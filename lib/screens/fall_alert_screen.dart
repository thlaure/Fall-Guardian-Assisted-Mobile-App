import 'dart:async';
import 'package:flutter/material.dart';

import 'package:geolocator/geolocator.dart';
import '../l10n/app_localizations.dart';
import '../models/fall_event.dart';
import '../repositories/contacts_repository.dart';
import '../repositories/fall_events_repository.dart';
import '../services/location_service.dart';
import '../services/sms_service.dart';
import '../services/notification_service.dart';
import '../services/watch_communication_service.dart';
import 'package:uuid/uuid.dart';

class FallAlertScreen extends StatefulWidget {
  final int fallTimestamp;
  final Stream<void>? cancelStream;

  const FallAlertScreen({
    super.key,
    required this.fallTimestamp,
    this.cancelStream,
  });

  @override
  State<FallAlertScreen> createState() => _FallAlertScreenState();
}

class _FallAlertScreenState extends State<FallAlertScreen>
    with TickerProviderStateMixin {
  static const _countdownSeconds = 30;

  int _remaining = _countdownSeconds;
  Timer? _timer;
  StreamSubscription<void>? _cancelSub;
  bool _dismissed = false;
  bool _sending = false;
  String _statusMessage = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupPulse();
    _startCountdown();
    _cancelSub = widget.cancelStream?.listen((_) => _cancel());
  }

  void _setupPulse() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(_pulseController);
  }

  void _startCountdown() {
    // Poll at 500 ms so the display stays in sync with the watch countdown.
    // Compute remaining from the original fall timestamp so both devices
    // show the same number regardless of message delivery latency.
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) return;
      final elapsed =
          DateTime.now().millisecondsSinceEpoch - widget.fallTimestamp;
      final remaining =
          (_countdownSeconds - elapsed ~/ 1000).clamp(0, _countdownSeconds);
      setState(() => _remaining = remaining);
      if (_remaining <= 0) {
        timer.cancel();
        _sendAlert();
      }
    });
  }

  Future<void> _sendAlert() async {
    if (_dismissed || _sending) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);

    setState(() {
      _sending = true;
      _statusMessage = l10n.gettingLocation;
    });

    final Position? position = await LocationService().getCurrentPosition();
    if (_dismissed || !mounted) return;

    setState(() => _statusMessage = l10n.sendingSms);

    // Build the localized SMS message here, where we have context
    final locationLine = (position != null)
        ? l10n.smsLocationLine(position.latitude, position.longitude)
        : l10n.smsLocationUnavailable;
    final smsBody = l10n.smsMessage(locationLine);

    final contacts = await ContactsRepository().getAll();
    final notified = await SmsService().sendFallAlert(
      contacts: contacts,
      message: smsBody,
    );
    if (_dismissed || !mounted) return;

    final smsFailed = contacts.isNotEmpty && notified.isEmpty;
    final event = FallEvent(
      id: const Uuid().v4(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(widget.fallTimestamp),
      status:
          smsFailed ? FallEventStatus.alertFailed : FallEventStatus.alertSent,
      latitude: position?.latitude,
      longitude: position?.longitude,
      notifiedContacts: notified,
    );
    await FallEventsRepository().add(event);
    await NotificationService().cancelAll();
    if (!mounted) return;

    setState(
      () => _statusMessage =
          smsFailed ? l10n.smsFailed : l10n.alertSentCount(notified.length),
    );

    await Future.delayed(Duration(seconds: smsFailed ? 5 : 2));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    setState(() => _dismissed = true);
    unawaited(WatchCommunicationService.sendCancelAlert());

    final event = FallEvent(
      id: const Uuid().v4(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(widget.fallTimestamp),
      status: FallEventStatus.cancelled,
    );
    await FallEventsRepository().add(event);
    await NotificationService().cancelAll();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cancelSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = _remaining / _countdownSeconds;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A0000),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: const Icon(
                    Icons.warning_rounded,
                    size: 80,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.fallAlertTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.fallAlertBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 40),
                _sending
                    ? Column(
                        children: [
                          const CircularProgressIndicator(
                            color: Colors.redAccent,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 120,
                                height: 120,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 8,
                                  backgroundColor: Colors.white12,
                                  color: _remaining <= 10
                                      ? Colors.redAccent
                                      : const Color(0xFFE5694A),
                                ),
                              ),
                              Text(
                                '$_remaining',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 48),
                          SizedBox(
                            height: 60,
                            child: ElevatedButton.icon(
                              onPressed: _cancel,
                              icon: const Icon(Icons.check_circle, size: 28),
                              label: Text(
                                l10n.cancelAlert,
                                style: const TextStyle(fontSize: 18),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
