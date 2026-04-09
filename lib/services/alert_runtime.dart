import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import 'alert_ports.dart';
import 'watch_communication_service.dart';

class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

class UuidGenerator implements IdGenerator {
  const UuidGenerator();

  @override
  String newId() => const Uuid().v4();
}

class DeviceLocaleResolver implements AlertLocaleResolver {
  const DeviceLocaleResolver();

  @override
  AppLocalizations resolve() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final supportedLocale = AppLocalizations.supportedLocales.firstWhere(
      (supported) => supported.languageCode == locale.languageCode,
      orElse: () => const Locale('en'),
    );
    return AppLocalizations.forLocale(supportedLocale);
  }

  @override
  String languageCode() {
    return WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  }
}

class MethodChannelWatchGateway implements WatchCommandGateway {
  const MethodChannelWatchGateway();

  @override
  Future<void> sendCancelAlert() => WatchCommunicationService.sendCancelAlert();
}
