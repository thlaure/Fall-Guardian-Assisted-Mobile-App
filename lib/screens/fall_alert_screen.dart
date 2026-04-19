// dart:async provides Timer (for the countdown) and StreamSubscription
// (for listening to cancel events arriving from the watch).
import 'dart:async';

// Flutter's Material UI toolkit — widgets, animations, navigation, etc.
import 'package:flutter/material.dart';

// Our translated strings — all user-visible text comes from here so the app
// can display in English, French, etc. based on device language.
import '../l10n/app_localizations.dart';

// Services
import '../services/alert_coordinator.dart';

// ─── Why a StatefulWidget? ───────────────────────────────────────────────────
// The screen owns a live countdown (_remaining), a pulsing animation, and a
// StreamSubscription that can dismiss the screen externally. All of these are
// mutable state that must survive widget rebuilds. StatelessWidget cannot hold
// mutable state, so StatefulWidget is the right choice here.

/// Full-screen alert shown when the watch detects a fall.
///
/// The screen displays a 30-second countdown. The user has until zero to tap
/// "Cancel". Timeout, cancellation, and escalation are owned by [AlertCoordinator];
/// this widget only renders the alert state and forwards the local cancel action.
class FallAlertScreen extends StatefulWidget {
  /// The Unix epoch timestamp (milliseconds) at the exact moment the fall was
  /// detected on the watch. Both the watch and the phone derive their remaining
  /// seconds from this shared origin, keeping the two displays in sync even if
  /// the event message was delayed in transit.
  final int fallTimestamp;

  final AlertCoordinator alertCoordinator;

  const FallAlertScreen({
    super.key,
    required this.fallTimestamp,
    required this.alertCoordinator,
  });

  @override
  State<FallAlertScreen> createState() => _FallAlertScreenState();
}

// TickerProviderStateMixin is required by Flutter's animation system.
// An AnimationController needs a "vsync" source — an object that knows the
// current frame rate — to avoid wasting CPU when the screen is off.
// TickerProviderStateMixin makes this State class itself serve as that source.
class _FallAlertScreenState extends State<FallAlertScreen>
    with TickerProviderStateMixin {
  // The total countdown in seconds. This is the authoritative maximum; the
  // actual remaining time is always computed from the original timestamp.
  static const _countdownSeconds = 30;

  // ── Mutable state ─────────────────────────────────────────────────────────
  int _remaining =
      _countdownSeconds; // seconds left — drives the progress ring and number
  Timer? _timer; // periodic timer that re-computes _remaining
  StreamSubscription<AlertUiState>?
      _alertStateSub; // state updates from the coordinator
  StreamSubscription<void>?
      _dismissSub; // dismissal events from the coordinator
  bool _sending = false; // true while the SMS-send flow is in progress
  String _statusMessage = ''; // shown beneath the spinner while sending
  AlertPhase _phase = AlertPhase.countdown;

  // ── Animation ─────────────────────────────────────────────────────────────
  // AnimationController drives the pulse animation on the warning icon.
  // Animation<double> holds the interpolated scale value at each frame.
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // Order matters: set up animation first, then start the countdown, then
    // subscribe to external cancel events.
    _setupPulse();
    _startCountdown();
    final currentState = widget.alertCoordinator.currentState;
    if (currentState != null &&
        currentState.fallTimestamp == widget.fallTimestamp) {
      _applyAlertUiState(currentState);
    }
    _alertStateSub = widget.alertCoordinator.stateStream.listen(
      _applyAlertUiState,
    );
    _dismissSub = widget.alertCoordinator.dismissStream.listen((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ── Pulse animation setup ─────────────────────────────────────────────────
  void _setupPulse() {
    _pulseController = AnimationController(
      // One full pulse cycle takes 800 ms.
      duration: const Duration(milliseconds: 800),
      // `this` works here because of TickerProviderStateMixin — the State
      // itself acts as the vsync source.
      vsync: this,
      // `..repeat(reverse: true)` chains a method call on the controller
      // immediately after construction. `reverse: true` means the animation
      // goes 0→1→0 instead of restarting abruptly, giving a smooth in-out pulse.
    )..repeat(reverse: true);

    // Tween defines the start and end values; `.animate` binds them to the
    // controller. The icon will scale between 90 % and 110 % of its natural size.
    _pulseAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(_pulseController);
  }

  // ── Countdown logic ───────────────────────────────────────────────────────
  void _startCountdown() {
    // Poll at 500 ms so the display stays in sync with the watch countdown.
    // Compute remaining from the original fall timestamp so both devices
    // show the same number regardless of message delivery latency.
    //
    // Why compute from the original timestamp instead of decrementing a counter?
    // If we just did `_remaining--` every second, any clock drift or message
    // delay between the watch and the phone would cause the two displays to
    // diverge. By always subtracting from the shared `fallTimestamp`, both
    // devices are guaranteed to show the same number.
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      // Guard: if the widget has been removed from the tree (e.g. navigation
      // has already popped this screen), stop the timer and do nothing.
      // Calling setState on an unmounted widget throws an error.
      if (!mounted) return;

      final elapsed =
          DateTime.now().millisecondsSinceEpoch - widget.fallTimestamp;

      // `~/ 1000` is integer division — converts milliseconds to whole seconds.
      // `.clamp(0, _countdownSeconds)` ensures the value never goes negative
      // or above 30 (e.g. if the timestamp is slightly in the future).
      final remaining =
          (_countdownSeconds - elapsed ~/ 1000).clamp(0, _countdownSeconds);

      // setState tells Flutter to rebuild the widget with the new _remaining value.
      setState(() => _remaining = remaining);

      if (_remaining <= 0) {
        timer.cancel();
        // Guard: if the coordinator is still in countdown phase after the UI
        // timer expired, its own Dart Timer was likely lost while the app was
        // backgrounded (Android paused the Flutter engine). Kick it manually
        // so the post-countdown flow (location → SMS → dismiss) still runs.
        if (mounted && _phase == AlertPhase.countdown) {
          unawaited(
            widget.alertCoordinator
                .handleExpiredCountdown(widget.fallTimestamp),
          );
        }
      }
    });
  }

  void _applyAlertUiState(AlertUiState state) {
    if (!mounted || state.fallTimestamp != widget.fallTimestamp) return;
    setState(() {
      _phase = state.phase;
      _sending = state.isSending;
      _statusMessage = state.statusMessage ?? '';
    });
  }

  // ── Cancel flow (user tapped Cancel OR remote cancel from watch) ──────────
  //
  // Steps:
  //   1. Stop the countdown timer.
  //   2. Mark as dismissed so _sendAlert cannot start.
  //   3. Tell the watch to also dismiss its alert (fire-and-forget).
  //   4. Persist a "cancelled" FallEvent to history.
  //   5. Dismiss any lingering OS notification.
  //   6. Pop this screen.
  Future<void> _cancel() async {
    await widget.alertCoordinator.cancelFromPhone();
  }

  @override
  void dispose() {
    // Always cancel timers and subscriptions in dispose() to prevent them from
    // firing after the widget is gone, which would cause runtime errors.
    _timer?.cancel();
    _alertStateSub?.cancel();
    _dismissSub?.cancel();
    // AnimationControllers must also be disposed to release the vsync ticker.
    _pulseController.dispose();
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Progress goes from 1.0 (full, 30 s left) to 0.0 (empty, 0 s left).
    // The CircularProgressIndicator uses this to draw the shrinking arc.
    final progress = _remaining / _countdownSeconds;

    return PopScope(
      // canPop: false disables the system back gesture/button while the alert
      // is active. This prevents the user from accidentally swiping away the
      // screen and missing the countdown. The only way to leave is by tapping
      // "Cancel" (programmatic Navigator.pop) or letting the timer run out.
      canPop: false,
      child: Scaffold(
        // Deep red background — intentionally alarming to grab attention.
        // 0xFF = fully opaque; 0x1A0000 = very dark red.
        backgroundColor: const Color(0xFF1A0000),
        body: SafeArea(
          // SafeArea insets the content so it doesn't overlap the status bar
          // (top of screen) or home indicator (bottom of screen on notchless phones).
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Pulsing warning icon ──────────────────────────────────
                // ScaleTransition rebuilds every animation frame with a new
                // scale value derived from _pulseAnimation (0.9 ↔ 1.1).
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: const Icon(
                    Icons.warning_rounded,
                    size: 80,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Title & body text ─────────────────────────────────────
                Text(
                  l10n.fallAlertTitle, // e.g. "Fall Detected!"
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.fallAlertBody, // e.g. "Tap Cancel if you are OK"
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 40),

                // ── Conditional body: spinner OR countdown + cancel button ─
                // Once _sendAlert starts (_sending = true), replace the
                // interactive countdown with a progress spinner and status text.
                // The user can no longer cancel at this point — the SMS is already
                // on its way.
                _phase != AlertPhase.countdown
                    ? Column(
                        children: [
                          const CircularProgressIndicator(
                            color: Colors.redAccent,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage, // "Getting location…" or "Sending SMS…"
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
                          // ── Countdown ring ────────────────────────────────
                          // Stack layers widgets on top of each other.
                          // Layer 1 (bottom): the circular progress arc.
                          // Layer 2 (top):    the remaining-seconds number.
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 120,
                                height: 120,
                                child: CircularProgressIndicator(
                                  // `value` between 0.0 and 1.0: the filled fraction.
                                  value: progress,
                                  strokeWidth: 8,
                                  // Faint white background arc so the ring doesn't
                                  // look broken when almost empty.
                                  backgroundColor: Colors.white12,
                                  // Turn the ring bright red in the final 10 seconds
                                  // to signal increasing urgency.
                                  color: _remaining <= 10
                                      ? Colors.redAccent
                                      : const Color(0xFFE5694A), // brand orange
                                ),
                              ),
                              // Large digit centred inside the ring.
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

                          // ── Cancel button ─────────────────────────────────
                          // Green = safe / "I'm OK". Made deliberately large
                          // (60 px tall) so it's easy to tap in a stressful moment.
                          SizedBox(
                            height: 60,
                            child: ElevatedButton.icon(
                              onPressed: _sending ? null : _cancel,
                              icon: const Icon(Icons.check_circle, size: 28),
                              label: Text(
                                l10n.cancelAlert, // "I'm OK – Cancel"
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
