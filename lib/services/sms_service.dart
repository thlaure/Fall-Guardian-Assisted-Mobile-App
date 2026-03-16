import 'package:flutter_sms/flutter_sms.dart';
import '../models/contact.dart';

class SmsService {
  /// Sends a fall alert SMS to all contacts.
  ///
  /// [message] is the fully localized message string, built by the caller
  /// using [AppLocalizations] (which has access to BuildContext).
  ///
  /// Returns the list of contact names to which the SMS was sent.
  Future<List<String>> sendFallAlert({
    required List<Contact> contacts,
    required String message,
  }) async {
    if (contacts.isEmpty) return [];

    final phones = contacts.map((c) => c.phone).toList();

    try {
      final result = await sendSMS(message: message, recipients: phones);
      if (result == 'sent') {
        return contacts.map((c) => c.name).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
