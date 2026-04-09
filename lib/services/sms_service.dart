import 'dart:developer' as developer;

// flutter/foundation.dart gives us @visibleForTesting — an annotation that
// documents that a method/field should only be called from test code.
// It does NOT enforce this at runtime, but Dart's linter will warn if
// production code accidentally uses a test-only helper.
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, visibleForTesting, TargetPlatform;
import 'package:flutter/services.dart';

// flutter_sms is a Flutter plugin that wraps the native SMS APIs.
//   Android: uses SmsManager to fire an intent-based SMS send.
//   iOS:    opens the Messages app via MFMessageComposeViewController.
// The package exposes a single top-level `sendSMS` function.
import 'package:flutter_sms/flutter_sms.dart';

// shared_preferences is a Flutter plugin for key-value persistent storage.
// On Android it uses SharedPreferences; on iOS it uses NSUserDefaults.
// We use it to remember the last time we sent an SMS so the rate-limiting
// logic survives app restarts (an in-memory variable would reset to null
// each time the user force-quits the app).
import 'package:shared_preferences/shared_preferences.dart';

// Our Contact model — a plain Dart class with `name` and `phone` fields.
import '../models/contact.dart';

// ─── Why a service class? ────────────────────────────────────────────────────
// Isolating SMS logic in its own class means:
//   • the rest of the app can call `SmsService().sendFallAlert(...)` without
//     knowing which plugin is used under the hood.
//   • tests can exercise the rate-limiting logic without sending real SMSes
//     (the plugin itself can be stubbed at the platform layer).
//   • if the SMS plugin changes, only this file needs to be updated.

/// Handles sending fall-alert SMS messages to emergency contacts.
///
/// Includes a 60-second rate limit to prevent accidental repeated sends
/// (e.g. if the watch fires multiple fall events in quick succession).
class SmsService {
  // Reuses the existing watch MethodChannel — no need for a separate channel.
  static const _smsChannel = MethodChannel('fall_guardian/watch');

  // ── Rate-limiting state ───────────────────────────────────────────────────
  // `static` means this field belongs to the *class*, not to any individual
  // instance. All `SmsService()` instances share the same `_lastSentAt`.
  // This is intentional — no matter where in the app `sendFallAlert` is called,
  // we check the same timestamp.
  static DateTime? _lastSentAt;

  // The SharedPreferences key used to persist the last-sent timestamp across
  // app restarts. Must be a unique string that doesn't collide with other keys.
  static const _kLastSentAtMs = 'sms_last_sent_at_ms';

  // ── Test helpers ──────────────────────────────────────────────────────────
  // @visibleForTesting documents that these methods are only meant for tests.
  // Production code should never call them.

  /// Resets the in-memory rate-limiting state. Only for use in tests.
  @visibleForTesting
  static void resetLastSentAt() => _lastSentAt = null;

  /// Overrides the last-sent timestamp. Only for use in tests.
  @visibleForTesting
  static void setLastSentAtForTesting(DateTime value) => _lastSentAt = value;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Sends a fall alert SMS to all contacts.
  ///
  /// [message] is the fully localized message string, built by the caller
  /// using [AppLocalizations] (which has access to BuildContext).
  /// This service class has no BuildContext, so it cannot build the string
  /// itself — the screen layer is responsible for composing the message and
  /// passing it in.
  ///
  /// Returns the list of contact names to which the SMS was sent.
  /// Returns an empty list immediately if called within 60 seconds of the last send.
  ///
  /// Workflow:
  ///   1. Bail out early if there are no contacts to send to.
  ///   2. Load the persisted last-sent timestamp (once, after app restart).
  ///   3. Enforce the 60-second rate limit.
  ///   4. Extract phone numbers from the Contact objects.
  ///   5. Call the flutter_sms plugin to send the message.
  ///   6. On success, persist the new timestamp and return the notified names.
  Future<List<String>> sendFallAlert({
    required List<Contact> contacts,
    required String message,
  }) async {
    // Step 1 — Nothing to do if there are no contacts saved yet.
    if (contacts.isEmpty) {
      developer.log('No contacts configured; skipping send',
          name: 'SmsService');
      return [];
    }

    final now = DateTime.now();

    // Step 2 — Hydrate the in-memory timestamp from persistent storage.
    // `_lastSentAt` is null when the app starts fresh (or in a test that called
    // resetLastSentAt). We check SharedPreferences once to restore the value
    // that was saved during a previous session. Subsequent calls skip this block
    // because `_lastSentAt` will already be non-null.
    // Load persisted timestamp on first call after app restart
    if (_lastSentAt == null) {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kLastSentAtMs); // null if never saved
      if (ms != null) _lastSentAt = DateTime.fromMillisecondsSinceEpoch(ms);
    }

    // Step 3 — Rate limit: refuse to send if we sent an SMS less than 60 s ago.
    // This guards against two scenarios:
    //   a) A fall detection false positive that fires multiple events in a row.
    //   b) The user repeatedly force-opening the alert in quick succession.
    // The check survives app restarts because the timestamp is persisted above.
    if (_lastSentAt != null && now.difference(_lastSentAt!).inSeconds < 60) {
      developer.log('Rate limited; skipping duplicate send',
          name: 'SmsService');
      return []; // silently skip — the caller treats an empty list as "not sent"
    }

    // Step 4 — Extract only the phone number strings from the Contact objects.
    // flutter_sms expects a plain List<String> of phone numbers.
    final phones = contacts.map((c) => c.phone).toList();

    // Step 5 — Send the SMS.
    //
    // We use two different paths depending on the platform:
    //
    //   Android → native SmsManager via MethodChannel ('fall_guardian/watch').
    //     SmsManager.sendMultipartTextMessage() sends silently in the background
    //     with no UI required. This requires SEND_SMS permission in
    //     AndroidManifest.xml (already declared). The flutter_sms plugin cannot
    //     do this — it always opens the SMS app in v3.0.1.
    //
    //   iOS → flutter_sms opens the Messages compose sheet.
    //     Apple does not allow apps to send SMS silently; the user must confirm.
    try {
      final String result;
      developer.log(
        'Attempting send to ${phones.length} recipient(s)',
        name: 'SmsService',
      );
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Invoke the native sendSms handler registered in MainActivity.kt.
        // Returns 'sent' on success, throws on failure.
        await _smsChannel.invokeMethod<void>('sendSms', {
          'message': message,
          'recipients': phones,
        });
        result = 'sent';
      } else {
        result = await sendSMS(message: message, recipients: phones);
      }
      if (result == 'sent') {
        developer.log('Send reported success', name: 'SmsService');
        // Step 6 — Record the send time in memory AND in SharedPreferences so
        // the rate limit persists across restarts.
        _lastSentAt = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_kLastSentAtMs, _lastSentAt!.millisecondsSinceEpoch);

        // Return the *names* (not phone numbers) of the contacts that were
        // notified. The caller uses this list to display a confirmation message
        // ("Alert sent to Alice, Bob") and to store in the event history.
        return contacts.map((c) => c.name).toList();
      }
      // The plugin returned something other than 'sent' — treat as failure.
      developer.log('Plugin returned non-sent result: $result',
          name: 'SmsService');
      return [];
    } catch (_) {
      developer.log('Send failed with exception', name: 'SmsService');
      // Any exception (plugin not available in the simulator, permission denied,
      // network error) results in a graceful empty-list return rather than a crash.
      // The caller checks `notified.isEmpty` to decide whether to show an error.
      return [];
    }
  }
}
