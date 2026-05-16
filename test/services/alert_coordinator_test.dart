import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fall_guardian/models/contact.dart';
import 'package:fall_guardian/models/fall_event.dart';
import 'package:fall_guardian/services/alert_coordinator.dart';
import 'package:fall_guardian/services/alert_ports.dart';
import 'package:fall_guardian/services/alert_runtime.dart';

class _FakeContactsRepository implements EmergencyContactsStore {
  _FakeContactsRepository(this.contacts);

  final List<Contact> contacts;

  @override
  Future<List<Contact>> getAll() async => contacts;
}

class _FakeFallEventsRepository implements FallEventRecorder {
  final List<FallEvent> savedEvents = [];

  @override
  Future<void> add(FallEvent event) async {
    savedEvents.add(event);
  }
}

class _FakeLocationService implements AlertLocationProvider {
  @override
  Future<Position?> getCurrentPosition() async => null;
}

class _FakeNotificationService implements AlertNotificationGateway {
  int cancelCount = 0;

  @override
  Future<void> cancelAll() async {
    cancelCount++;
  }
}

class _FakeBackendGateway implements AlertBackendGateway {
  _FakeBackendGateway({this.shouldFail = false});

  final bool shouldFail;
  String? lastClientAlertId;
  String? lastLocale;
  List<Contact>? lastContacts;
  int? lastTimestamp;
  double? lastLatitude;
  double? lastLongitude;
  int cancelCount = 0;
  int callCount = 0;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<void> syncContacts(List<Contact> contacts) async {}

  @override
  Future<void> submitFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
    required List<Contact> contacts,
  }) async {
    callCount++;
    lastClientAlertId = clientAlertId;
    lastLocale = locale;
    lastTimestamp = fallTimestamp;
    lastLatitude = latitude;
    lastLongitude = longitude;
    lastContacts = contacts;
    if (shouldFail) {
      throw Exception('backend unavailable');
    }
  }

  @override
  Future<void> cancelFallAlert({required String clientAlertId}) async {
    cancelCount++;
  }
}

class _FakeWatchGateway implements WatchCommandGateway {
  int cancelCount = 0;

  @override
  Future<void> sendCancelAlert() async {
    cancelCount++;
  }
}

class _FakeClock implements Clock {
  _FakeClock([DateTime? initialNow]) : _now = initialNow ?? DateTime.now();

  DateTime _now;

  @override
  DateTime now() => _now;

  void setNow(DateTime value) {
    _now = value;
  }
}

class _FakeIdGenerator implements IdGenerator {
  int _next = 0;

  @override
  String newId() => 'id-${_next++}';
}

AlertCoordinator _coordinator({
  EmergencyContactsStore? contactsStore,
  FallEventRecorder? eventRecorder,
  AlertLocationProvider? locationProvider,
  AlertNotificationGateway? notificationGateway,
  AlertBackendGateway? backendGateway,
  WatchCommandGateway? watchGateway,
  AlertLocaleResolver? localeResolver,
  Clock? clock,
  IdGenerator? idGenerator,
}) {
  return AlertCoordinator(
    contactsStore: contactsStore ?? _FakeContactsRepository(const []),
    eventRecorder: eventRecorder ?? _FakeFallEventsRepository(),
    locationProvider: locationProvider ?? _FakeLocationService(),
    notificationGateway: notificationGateway ?? _FakeNotificationService(),
    backendGateway: backendGateway ?? _FakeBackendGateway(),
    watchGateway: watchGateway ?? _FakeWatchGateway(),
    localeResolver: localeResolver ?? const DeviceLocaleResolver(),
    clock: clock ?? _FakeClock(),
    idGenerator: idGenerator ?? _FakeIdGenerator(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/watch'),
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/watch'),
      null,
    );
  });

  test('startAlert enters countdown phase', () async {
    final coordinator = _coordinator();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await coordinator.startAlert(timestamp);

    expect(coordinator.currentState?.fallTimestamp, timestamp);
    expect(coordinator.currentState?.phase, AlertPhase.countdown);
    expect(coordinator.currentState?.isSending, isFalse);

    coordinator.dispose();
  });

  test('cancelFromWatch does not send cancel back to watch', () async {
    final watchCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/watch'),
      (call) async {
        watchCalls.add(call);
        return null;
      },
    );

    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
    );

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await coordinator.cancelFromWatch();

    expect(
      watchCalls.where((call) => call.method == 'sendCancelAlert'),
      isEmpty,
    );
    expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
    expect(coordinator.currentState, isNull);
    expect(notifications.cancelCount, 1);
    expect(backend.cancelCount, 0);

    coordinator.dispose();
  });

  test('cancelFromWatch emits cancelled phase before dismissal', () async {
    final states = <AlertUiState>[];
    final coordinator = _coordinator();
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await coordinator.cancelFromWatch();

    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.cancelled,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('cancelFromPhone sends cancel to watch and records cancellation',
      () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final watchGateway = _FakeWatchGateway();
    final backend = _FakeBackendGateway();
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      watchGateway: watchGateway,
      backendGateway: backend,
    );

    await coordinator.startAlert(DateTime.now().millisecondsSinceEpoch);
    await coordinator.cancelFromPhone();

    expect(watchGateway.cancelCount, 1);
    expect(repo.savedEvents.single.status, FallEventStatus.cancelled);
    expect(notifications.cancelCount, 1);
    expect(coordinator.currentState, isNull);
    expect(backend.cancelCount, 0);

    coordinator.dispose();
  });

  test(
      'timeout without contacts still submits to backend and records alertSent',
      () async {
    // Even with no emergency contacts the backend is always called so that
    // the fall event is persisted server-side and can be dispatched through
    // the linked caregiver workflow.
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.callCount, 1);
    expect(repo.savedEvents.single.status, FallEventStatus.alertSent);
    expect(notifications.cancelCount, 1);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingAlert,
      AlertPhase.alertSent,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('reconcileActiveAlert triggers timeout after lifecycle pause', () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final clock = _FakeClock(DateTime(2026, 4, 19, 12, 0, 0));
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
      clock: clock,
    );
    final sub = coordinator.stateStream.listen(states.add);

    final timestamp = clock.now().millisecondsSinceEpoch;
    await coordinator.startAlert(timestamp);

    clock.setNow(clock.now().add(const Duration(seconds: 31)));
    await coordinator.reconcileActiveAlert();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.callCount, 1);
    expect(repo.savedEvents.single.status, FallEventStatus.alertSent);
    expect(notifications.cancelCount, 1);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingAlert,
      AlertPhase.alertSent,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('timeout with contacts and backend submission records alertSent',
      () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final backend = _FakeBackendGateway();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      contactsStore: _FakeContactsRepository(const [
        Contact(id: '1', name: 'Alice', phone: '+33600000001'),
        Contact(id: '2', name: 'Bob', phone: '+33600000002'),
      ]),
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: backend,
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.savedEvents.single.status, FallEventStatus.alertSent);
    expect(repo.savedEvents.single.notifiedContacts, ['Alice', 'Bob']);
    expect(notifications.cancelCount, 1);
    expect(backend.lastContacts, hasLength(2));
    expect(backend.lastClientAlertId, isNotNull);
    expect(backend.lastLocale, isNotEmpty);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingAlert,
      AlertPhase.alertSent,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });

  test('timeout with contacts and backend failure records alertFailed',
      () async {
    final repo = _FakeFallEventsRepository();
    final notifications = _FakeNotificationService();
    final states = <AlertUiState>[];
    final coordinator = _coordinator(
      contactsStore: _FakeContactsRepository(const [
        Contact(id: '1', name: 'Alice', phone: '+33600000001'),
      ]),
      eventRecorder: repo,
      notificationGateway: notifications,
      backendGateway: _FakeBackendGateway(shouldFail: true),
    );
    final sub = coordinator.stateStream.listen(states.add);

    await coordinator.startAlert(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 31).inMilliseconds,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.savedEvents.single.status, FallEventStatus.alertFailed);
    expect(repo.savedEvents.single.notifiedContacts, isEmpty);
    expect(notifications.cancelCount, 1);
    expect(states.map((state) => state.phase), [
      AlertPhase.countdown,
      AlertPhase.gettingLocation,
      AlertPhase.sendingAlert,
      AlertPhase.alertFailed,
    ]);

    await sub.cancel();
    coordinator.dispose();
  });
}
