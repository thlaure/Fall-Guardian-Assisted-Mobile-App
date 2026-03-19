import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_sms/flutter_sms.dart';
import '../models/contact.dart';

class SmsService {
  static DateTime? _lastSentAt;

  /// Resets the rate-limiting state. Only for use in tests.
  @visibleForTesting
  static void resetLastSentAt() => _lastSentAt = null;

  /// Overrides the last-sent timestamp. Only for use in tests.
  @visibleForTesting
  static void setLastSentAtForTesting(DateTime value) => _lastSentAt = value;

  /// Sends a fall alert SMS to all contacts.
  ///
  /// [message] is the fully localized message string, built by the caller
  /// using [AppLocalizations] (which has access to BuildContext).
  ///
  /// Returns the list of contact names to which the SMS was sent.
  /// Returns an empty list immediately if called within 60 seconds of the last send.
  Future<List<String>> sendFallAlert({
    required List<Contact> contacts,
    required String message,
  }) async {
    if (contacts.isEmpty) return [];

    final now = DateTime.now();
    if (_lastSentAt != null && now.difference(_lastSentAt!).inSeconds < 60) {
      return [];
    }

    final phones = contacts.map((c) => c.phone).toList();

    try {
      final result = await sendSMS(message: message, recipients: phones);
      if (result == 'sent') {
        _lastSentAt = DateTime.now();
        return contacts.map((c) => c.name).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
