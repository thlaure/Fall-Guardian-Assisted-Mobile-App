import 'package:flutter/material.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

/// Usage in widgets: AppLocalizations.of(context).someString
abstract class AppLocalizations {
  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static AppLocalizations forLocale(Locale locale) {
    return switch (locale.languageCode) {
      'fr' => AppLocalizationsFr(),
      _ => AppLocalizationsEn(),
    };
  }

  static const delegate = _AppLocalizationsDelegate();

  static const supportedLocales = [Locale('en'), Locale('fr')];

  // ── Generic ──────────────────────────────────────────────────────────────
  String get appTitle;
  String get cancel;
  String get save;
  String get remove;
  String get required_;
  String get unitG;
  String get unitMs;
  String get unitDeg;

  // ── Home ─────────────────────────────────────────────────────────────────
  String get homeStatusTitle;
  String get homeStatusBody;
  String get homeContactsTitle;
  String get homeContactsSubtitle;
  String get homeHistoryTitle;
  String get homeHistorySubtitle;
  String get homeFootnote;

  // ── Contacts ─────────────────────────────────────────────────────────────
  String get contactsScreenTitle;
  String contactsRemoveTitle(String name);
  String get contactsEmpty;
  String get contactsEmptyHint;
  String get addContact;
  String get editContact;
  String get contactNameLabel;
  String get contactPhoneLabel;
  String get contactsSyncFailedBanner;
  String get contactsSyncFailedHint;
  String get contactsSavedLocallyOnly;

  // ── Fall Alert ────────────────────────────────────────────────────────────
  String get fallAlertTitle;
  String get fallAlertBody;
  String get gettingLocation;
  String get sendingSms;
  String get smsFailed;
  String alertSentCount(int count);
  String get cancelAlert;

  // ── History ──────────────────────────────────────────────────────────────
  String get historyTitle;
  String get clearHistoryTitle;
  String get clearHistoryBody;
  String get clear;
  String get historyEmpty;
  String get statusAlertSent;
  String get statusAlertFailed;
  String get statusCancelled;
  String get statusTimedOut;
  String notifiedLabel(String names);
  String locationLabel(String coords);

  // ── Settings ─────────────────────────────────────────────────────────────
  String get settingsTitle;
  String get settingsSaved;
  String get thresholdsSection;
  String get thresholdsInfo;
  String get freeFallLabel;
  String get freeFallDesc;
  String get impactLabel;
  String get impactDesc;
  String get tiltLabel;
  String get tiltDesc;
  String get freeFallDurationLabel;
  String get freeFallDurationDesc;
  String get resetDefaults;

  // ── Notifications ─────────────────────────────────────────────────────────
  String get notifTitle;
  String get notifBody;

  // ── SMS ───────────────────────────────────────────────────────────────────
  String smsMessage(String locationLine);
  String get smsLocationUnavailable;
  String smsLocationLine(double lat, double lng);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
        (l) => l.languageCode == locale.languageCode,
      );

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations.forLocale(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
