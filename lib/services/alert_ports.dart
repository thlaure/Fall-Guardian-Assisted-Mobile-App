import 'package:geolocator/geolocator.dart';

import '../l10n/app_localizations.dart';
import '../models/contact.dart';
import '../models/fall_event.dart';

/// Small ports that keep the alert workflow independent from storage,
/// platform APIs, and concrete plugins.
abstract class EmergencyContactsStore {
  Future<List<Contact>> getAll();
}

abstract class FallEventRecorder {
  Future<void> add(FallEvent event);
}

abstract class AlertLocationProvider {
  Future<Position?> getCurrentPosition();
}

abstract class AlertNotificationGateway {
  Future<void> cancelAll();
}

abstract class AlertBackendGateway {
  Future<void> ensureReady();

  Future<void> syncContacts(List<Contact> contacts);

  Future<List<String>> submitFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
    required List<Contact> contacts,
  });

  Future<void> cancelFallAlert({required String clientAlertId});
}

abstract class WatchCommandGateway {
  Future<void> sendCancelAlert();
}

abstract class AlertLocaleResolver {
  AppLocalizations resolve();

  String languageCode();
}

abstract class Clock {
  DateTime now();
}

abstract class IdGenerator {
  String newId();
}
