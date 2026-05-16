// flutter_local_notifications is a Flutter plugin that wraps the native
// notification APIs on each platform:
//   Android — NotificationManager + NotificationChannel (required since Android 8)
//   iOS     — UNUserNotificationCenter (UserNotifications framework)
//
// "Local" means the notification is generated on the device itself (by our app)
// rather than sent from a server (which would be a "push" / "remote" notification).
import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'alert_ports.dart';

// ─── Why this service exists ─────────────────────────────────────────────────
// We need to show the user an alert even when the app is in the background
// (screen locked, app not visible). The FallAlertScreen widget can only be
// shown when the app is in the foreground; an OS-level notification is the
// only way to reach the user when the screen is off or the app is hidden.
//
// This service centralises all notification logic so that:
//   • initialisation happens exactly once (guarded by _initialized).
//   • the rest of the app never touches the plugin directly.
//   • tests can stub this class without patching the plugin globally.

/// Manages OS-level local push notifications for Fall Guardian.
///
/// Usage order:
///   1. Call [initialize] once at app startup (in `main()`).
///   2. Call [showFallDetectedNotification] when a fall is detected and the
///      app is in the background.
///   3. Call [cancelAll] when the alert is resolved (cancelled or SMS sent)
///      to remove the notification from the notification shade.
class NotificationService implements AlertNotificationGateway {
  // ── Singleton plugin instance ─────────────────────────────────────────────
  // `static final` means there is exactly one plugin object for the entire
  // app lifetime, shared across all NotificationService instances.
  // This is important because the plugin registers itself with the OS during
  // initialization; creating multiple instances would cause conflicts.
  static final _plugin = FlutterLocalNotificationsPlugin();

  // A flag that prevents initialize() from registering the notification channel
  // with the OS more than once. Calling the underlying platform API twice is
  // harmless on iOS but can produce warnings on Android.
  static bool _initialized = false;

  // ── Android notification channel ──────────────────────────────────────────
  // Android 8+ requires every notification to belong to a "channel" — a named
  // category that users can independently enable/disable in Settings.
  // The channel ID is a stable identifier; the name is the human-readable label
  // shown in Android Settings → Notifications → Fall Guardian.
  static const _channelId = 'fall_guardian_alerts';
  static const _channelName = 'Fall Alerts';

  // ── Initialization ────────────────────────────────────────────────────────

  /// Initialises the notification plugin.
  ///
  /// On Android: registers the notification channel and sets up the plugin.
  /// On iOS:     intentionally skipped — see note below.
  ///
  /// Must be called once before any notification can be shown on Android.
  /// Subsequent calls are no-ops (guarded by [_initialized]).
  ///
  /// iOS note: flutter_local_notifications.initialize() sets itself as the
  /// UNUserNotificationCenterDelegate and then suppresses any notification it
  /// did not post itself (our native fall alert included).  To avoid this,
  /// we skip plugin initialisation on iOS entirely.  Notification permission
  /// is requested natively in AppDelegate, and fall notifications are posted
  /// via UNUserNotificationCenter directly by WatchSessionManager.
  /// cancelAll() still works on iOS without initialisation because it calls
  /// removeAllDeliveredNotifications() directly on UNUserNotificationCenter.
  Future<void> initialize() async {
    if (_initialized) return;

    // Android only — skip on iOS to avoid delegate conflict (see doc above).
    if (!Platform.isIOS) {
      // The icon name '@mipmap/ic_launcher' refers to the app launcher icon
      // in android/app/src/main/res/mipmap-*/. It appears in the notification shade.
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: const InitializationSettings(android: androidSettings),
      );

      // Android 13+ requires POST_NOTIFICATIONS at runtime.
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  // ── Showing a notification ─────────────────────────────────────────────────

  /// Shows the fall-detected notification with localized strings.
  ///
  /// This is shown only when the app is in the background (screen locked or
  /// app not visible). When the app is in the foreground, [FallAlertScreen]
  /// is pushed directly and no notification is needed.
  ///
  /// [title] and [body] are pre-built by the caller using [AppLocalizations]
  /// because this service class has no BuildContext.
  Future<void> showFallDetectedNotification({
    required String title,
    required String body,
  }) async {
    // ── Android notification details ──────────────────────────────────────
    const androidDetails = AndroidNotificationDetails(
      _channelId, // must match the channel registered in initialize()
      _channelName, // displayed in Android notification settings
      // Importance.max + Priority.high together produce a "heads-up" notification
      // — the banner that slides in from the top of the screen even when the
      // phone is unlocked. This is the highest-priority notification type on Android.
      importance: Importance.max,
      priority: Priority.high,
      // fullScreenIntent: true attempts to launch the full-screen notification
      // activity on Android when the device is locked. This is what makes the
      // phone "wake up" and show the alert on the lock screen, similar to an
      // incoming call. Requires the USE_FULL_SCREEN_INTENT permission in the
      // AndroidManifest, which Flutter's plugin adds automatically.
      fullScreenIntent: true,
    );

    // ── iOS notification details ──────────────────────────────────────────
    const iosDetails = DarwinNotificationDetails(
      // presentAlert: show the notification banner on iOS.
      presentAlert: true,
      // presentBanner: required on iOS 14+ to display the sliding banner even
      // when the app is in the foreground (presentAlert alone is not enough).
      presentBanner: true,
      // presentSound: play the default notification sound.
      presentSound: true,
      // presentBadge is intentionally omitted — we don't increment the app
      // icon badge for an alert that must be acted upon immediately.
    );

    // Send the notification to the OS. The `1` is the notification ID —
    // a stable integer that identifies this notification. Using the same ID
    // (1) for every fall notification means a new fall event replaces the
    // previous one instead of stacking multiple banners.
    await _plugin.show(
      id: 1, // notification ID
      title: title,
      body: body,
      notificationDetails:
          const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // ── Cancellation ──────────────────────────────────────────────────────────

  /// Removes all active Fall Guardian notifications from the notification shade.
  ///
  /// Called after the alert is resolved (either cancelled or SMS sent) so the
  /// user isn't left with a stale "Fall Detected" banner in their notification
  /// shade after the situation has already been handled.
  @override
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (error, stackTrace) {
      // Notification cleanup must never block the safety-critical alert state
      // transition. This can happen in widget tests before the plugin platform
      // is registered, and on devices if the OS notification service is absent.
      developer.log(
        'cancelAll failed',
        name: 'NotificationService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
