import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/contact.dart';
import '../models/fall_event.dart';
import 'alert_ports.dart';
import 'alert_runtime.dart';
import 'backend_api_service.dart';
import 'location_service.dart';
import 'notification_service.dart';
import '../repositories/contacts_repository.dart';
import '../repositories/fall_events_repository.dart';

enum AlertPhase {
  countdown,
  gettingLocation,
  sendingAlert,
  alertSent,
  alertFailed,
  timedOutNoSms,
  cancelled,
}

class AlertUiState {
  final int fallTimestamp;
  final AlertPhase phase;
  final String? statusMessage;

  const AlertUiState({
    required this.fallTimestamp,
    required this.phase,
    this.statusMessage,
  });

  bool get isSending =>
      phase == AlertPhase.gettingLocation ||
      phase == AlertPhase.sendingAlert ||
      phase == AlertPhase.alertSent ||
      phase == AlertPhase.alertFailed ||
      phase == AlertPhase.timedOutNoSms;
}

class AlertCoordinator {
  /// The alert workflow is intentionally written in terms of ports instead of
  /// concrete repositories/plugins. That keeps this class focused on
  /// "what should happen next?" rather than "how do we talk to storage/SMS?".
  AlertCoordinator({
    required EmergencyContactsStore contactsStore,
    required FallEventRecorder eventRecorder,
    required AlertLocationProvider locationProvider,
    required AlertNotificationGateway notificationGateway,
    required AlertBackendGateway backendGateway,
    required WatchCommandGateway watchGateway,
    required AlertLocaleResolver localeResolver,
    required Clock clock,
    required IdGenerator idGenerator,
  })  : _contactsStore = contactsStore,
        _eventRecorder = eventRecorder,
        _locationProvider = locationProvider,
        _notificationGateway = notificationGateway,
        _backendGateway = backendGateway,
        _watchGateway = watchGateway,
        _localeResolver = localeResolver,
        _clock = clock,
        _idGenerator = idGenerator;

  factory AlertCoordinator.live() {
    return AlertCoordinator(
      contactsStore: ContactsRepository(),
      eventRecorder: FallEventsRepository(),
      locationProvider: LocationService(),
      notificationGateway: NotificationService(),
      backendGateway: BackendApiService(),
      watchGateway: const MethodChannelWatchGateway(),
      localeResolver: const DeviceLocaleResolver(),
      clock: SystemClock(),
      idGenerator: const UuidGenerator(),
    );
  }

  static const _countdownSeconds = 30;

  final EmergencyContactsStore _contactsStore;
  final FallEventRecorder _eventRecorder;
  final AlertLocationProvider _locationProvider;
  final AlertNotificationGateway _notificationGateway;
  final AlertBackendGateway _backendGateway;
  final WatchCommandGateway _watchGateway;
  final AlertLocaleResolver _localeResolver;
  final Clock _clock;
  final IdGenerator _idGenerator;

  final _stateController = StreamController<AlertUiState>.broadcast();
  final _dismissController = StreamController<void>.broadcast();

  Timer? _timeoutTimer;
  Timer? _dismissTimer;
  AlertUiState? _currentState;
  int? _activeTimestamp;
  String? _activeClientAlertId;
  bool _submittedToBackend = false;

  Stream<AlertUiState> get stateStream => _stateController.stream;
  Stream<void> get dismissStream => _dismissController.stream;
  AlertUiState? get currentState => _currentState;

  Future<void> startAlert(int timestamp) async {
    if (_activeTimestamp == timestamp) return;

    _cancelTimers();
    _activeTimestamp = timestamp;
    _activeClientAlertId = _idGenerator.newId();
    _submittedToBackend = false;
    _transition(timestamp, AlertPhase.countdown);

    final elapsedMs = _clock.now().millisecondsSinceEpoch - timestamp;
    final remainingMs = (_countdownSeconds * 1000 - elapsedMs)
        .clamp(0, _countdownSeconds * 1000);

    _timeoutTimer = Timer(
      Duration(milliseconds: remainingMs),
      () => unawaited(_handleTimeout(timestamp)),
    );
  }

  Future<void> cancelFromPhone() => _cancel(notifyWatch: true);

  Future<void> cancelFromWatch() => _cancel(notifyWatch: false);

  /// Called by [FallAlertScreen] when the UI countdown reaches zero but the
  /// coordinator is still in [AlertPhase.countdown]. This happens when the
  /// Android OS paused the Flutter engine while the app was backgrounded,
  /// preventing the internal [_timeoutTimer] callback from running on time.
  /// Re-entrant calls are safe: the [_isCurrentAlert] and phase guards inside
  /// [_handleTimeout] make them no-ops for any timestamp that no longer matches.
  Future<void> handleExpiredCountdown(int timestamp) async {
    if (!_isCurrentAlert(timestamp)) return;
    if (_currentState?.phase != AlertPhase.countdown) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await _handleTimeout(timestamp);
  }

  Future<void> _cancel({required bool notifyWatch}) async {
    final timestamp = _activeTimestamp;
    _cancelTimers();

    if (timestamp == null) {
      await _notificationGateway.cancelAll();
      _dismissController.add(null);
      return;
    }

    if (notifyWatch) {
      unawaited(_watchGateway.sendCancelAlert());
    }

    final clientAlertId = _activeClientAlertId;
    if (_submittedToBackend && clientAlertId != null) {
      unawaited(_backendGateway.cancelFallAlert(clientAlertId: clientAlertId));
    }

    _transition(timestamp, AlertPhase.cancelled);

    final event = FallEvent(
      id: _idGenerator.newId(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
      status: FallEventStatus.cancelled,
    );
    await _eventRecorder.add(event);
    await _notificationGateway.cancelAll();
    _activeTimestamp = null;
    _activeClientAlertId = null;
    _submittedToBackend = false;
    _currentState = null;
    _dismissController.add(null);
  }

  Future<void> _handleTimeout(int timestamp) async {
    if (!_isCurrentAlert(timestamp) ||
        _currentState?.phase != AlertPhase.countdown) {
      return;
    }

    final l10n = _localeResolver.resolve();
    final clientAlertId = _activeClientAlertId;
    _transition(
      timestamp,
      AlertPhase.gettingLocation,
      statusMessage: l10n.gettingLocation,
    );

    final Position? position = await _locationProvider.getCurrentPosition();
    if (!_isCurrentAlert(timestamp)) return;

    _transition(
      timestamp,
      AlertPhase.sendingAlert,
      statusMessage: l10n.sendingAlert,
    );

    final contacts = await _contactsStore.getAll();
    if (!_isCurrentAlert(timestamp)) return;

    // Always submit to the backend regardless of contacts: recording the fall
    // and notifying contacts are two separate backend responsibilities.
    // With no contacts the backend stores the event without sending any SMS.
    final outcome = await _backendEscalationOutcome(
      clientAlertId: clientAlertId,
      timestamp: timestamp,
      position: position,
      contacts: contacts,
      locale: _localeResolver.languageCode(),
      smsFailedMessage: l10n.smsFailed,
      alertSentMessageBuilder: l10n.alertSentCount,
    );
    if (outcome == null || !_isCurrentAlert(timestamp)) return;

    await _eventRecorder.add(outcome.event);
    await _notificationGateway.cancelAll();
    if (!_isCurrentAlert(timestamp)) return;

    _transition(timestamp, outcome.phase, statusMessage: outcome.message);

    _dismissTimer = Timer(outcome.dismissDelay, () {
      if (!_isCurrentAlert(timestamp)) return;
      _activeTimestamp = null;
      _activeClientAlertId = null;
      _submittedToBackend = false;
      _currentState = null;
      _dismissController.add(null);
    });
  }

  Future<_AlertOutcome?> _backendEscalationOutcome({
    required String? clientAlertId,
    required int timestamp,
    required Position? position,
    required List<Contact> contacts,
    required String locale,
    required String smsFailedMessage,
    required String Function(int notifiedCount) alertSentMessageBuilder,
  }) async {
    if (clientAlertId == null) {
      return null;
    }

    List<String> notified;
    try {
      notified = await _backendGateway.submitFallAlert(
        clientAlertId: clientAlertId,
        fallTimestamp: timestamp,
        locale: locale,
        latitude: position?.latitude,
        longitude: position?.longitude,
        contacts: contacts,
      );
    } catch (_) {
      notified = const [];
    }
    if (!_isCurrentAlert(timestamp)) return null;
    _submittedToBackend = notified.isNotEmpty;

    return _smsOutcome(
      timestamp: timestamp,
      position: position,
      notifiedContacts: notified,
      smsFailedMessage: smsFailedMessage,
      smsSuccessMessage: alertSentMessageBuilder(notified.length),
    );
  }

  _AlertOutcome _smsOutcome({
    required int timestamp,
    required Position? position,
    required List<String> notifiedContacts,
    required String smsFailedMessage,
    required String smsSuccessMessage,
  }) {
    final smsFailed = notifiedContacts.isEmpty;
    return _AlertOutcome(
      event: FallEvent(
        id: _idGenerator.newId(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
        status:
            smsFailed ? FallEventStatus.alertFailed : FallEventStatus.alertSent,
        latitude: position?.latitude,
        longitude: position?.longitude,
        notifiedContacts: notifiedContacts,
      ),
      phase: smsFailed ? AlertPhase.alertFailed : AlertPhase.alertSent,
      message: smsFailed ? smsFailedMessage : smsSuccessMessage,
      dismissDelay: Duration(seconds: smsFailed ? 5 : 2),
    );
  }

  void _cancelTimers() {
    _timeoutTimer?.cancel();
    _dismissTimer?.cancel();
  }

  bool _isCurrentAlert(int timestamp) => _activeTimestamp == timestamp;

  void _transition(
    int timestamp,
    AlertPhase phase, {
    String? statusMessage,
  }) {
    _emit(
      AlertUiState(
        fallTimestamp: timestamp,
        phase: phase,
        statusMessage: statusMessage,
      ),
    );
  }

  void _emit(AlertUiState state) {
    _currentState = state;
    _stateController.add(state);
  }

  void dispose() {
    _timeoutTimer?.cancel();
    _dismissTimer?.cancel();
    _stateController.close();
    _dismissController.close();
  }
}

class _AlertOutcome {
  const _AlertOutcome({
    required this.event,
    required this.phase,
    required this.message,
    required this.dismissDelay,
  });

  final FallEvent event;
  final AlertPhase phase;
  final String message;
  final Duration dismissDelay;
}
