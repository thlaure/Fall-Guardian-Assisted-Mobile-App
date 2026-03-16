import 'app_localizations.dart';

class AppLocalizationsEn extends AppLocalizations {
  // ── Generic ──────────────────────────────────────────────────────────────
  @override String get appTitle => 'Fall Guardian';
  @override String get cancel => 'Cancel';
  @override String get save => 'Save';
  @override String get remove => 'Remove';
  @override String get required_ => 'Required';
  @override String get unitG => 'g';
  @override String get unitMs => 'ms';
  @override String get unitDeg => '°';

  // ── Home ─────────────────────────────────────────────────────────────────
  @override String get homeStatusTitle => 'Protected';
  @override String get homeStatusBody =>
      'PSP fall detection is active.\nA 30-second alert will appear if a fall is detected.';
  @override String get homeContactsTitle => 'Emergency Contacts';
  @override String get homeContactsSubtitle => 'Manage who gets alerted';
  @override String get homeHistoryTitle => 'Fall History';
  @override String get homeHistorySubtitle => 'Review past fall events';
  @override String get homeFootnote =>
      'Monitoring active on your watch.\nKeep the watch app running in the background.';

  // ── Contacts ─────────────────────────────────────────────────────────────
  @override String get contactsScreenTitle => 'Emergency Contacts';
  @override String contactsRemoveTitle(String name) =>
      'Remove $name from emergency contacts?';
  @override String get contactsEmpty => 'No contacts yet';
  @override String get contactsEmptyHint =>
      'Add family members to notify on fall detection.';
  @override String get addContact => 'Add Contact';
  @override String get editContact => 'Edit Contact';
  @override String get contactNameLabel => 'Name';
  @override String get contactPhoneLabel => 'Phone Number';

  // ── Fall Alert ────────────────────────────────────────────────────────────
  @override String get fallAlertTitle => 'Fall Detected!';
  @override String get fallAlertBody =>
      'Your emergency contacts will be notified unless you cancel.';
  @override String get gettingLocation => 'Getting your location…';
  @override String get sendingSms => 'Sending SMS alerts…';
  @override String get smsFailed =>
      '⚠️ SMS failed to send. Call your contacts manually!';
  @override String alertSentCount(int count) =>
      'Alert sent to $count contact${count == 1 ? '' : 's'}.';
  @override String get cancelAlert => "I'm OK — Cancel Alert";

  // ── History ──────────────────────────────────────────────────────────────
  @override String get historyTitle => 'Fall History';
  @override String get clearHistoryTitle => 'Clear history?';
  @override String get clearHistoryBody =>
      'This will permanently delete all fall event records.';
  @override String get clear => 'Clear';
  @override String get historyEmpty => 'No fall events recorded';
  @override String get statusAlertSent => 'Alert Sent';
  @override String get statusAlertFailed => 'SMS Failed';
  @override String get statusCancelled => 'Cancelled';
  @override String get statusTimedOut => 'Timed Out';
  @override String notifiedLabel(String names) => 'Notified: $names';
  @override String locationLabel(String coords) => 'Location: $coords';

  // ── Settings ─────────────────────────────────────────────────────────────
  @override String get settingsTitle => 'Settings';
  @override String get settingsSaved => 'Settings saved';
  @override String get thresholdsSection => 'PSP Fall Detection Thresholds';
  @override String get thresholdsInfo =>
      'These thresholds control sensitivity. Lower free-fall and higher impact '
      'thresholds reduce false positives. PSP falls often lack a free-fall '
      'phase — impact + tilt alone will trigger an alert.';
  @override String get freeFallLabel => 'Free-fall threshold';
  @override String get freeFallDesc =>
      '‖accel‖ must drop below this to detect free-fall phase';
  @override String get impactLabel => 'Impact threshold';
  @override String get impactDesc =>
      '‖accel‖ spike must exceed this to detect impact';
  @override String get tiltLabel => 'Tilt threshold';
  @override String get tiltDesc =>
      'Angle from upright must exceed this after impact';
  @override String get freeFallDurationLabel => 'Min free-fall duration';
  @override String get freeFallDurationDesc =>
      'Minimum duration of free-fall phase';
  @override String get resetDefaults => 'Reset to defaults';

  // ── Notifications ─────────────────────────────────────────────────────────
  @override String get notifTitle => '⚠️ Fall Detected';
  @override String get notifBody =>
      'Open app to cancel or send alert in 30 seconds';

  // ── SMS ───────────────────────────────────────────────────────────────────
  @override String smsMessage(String locationLine) =>
      '🚨 FALL ALERT: Your loved one may have fallen and needs help.\n'
      '$locationLine\n'
      'Please call or go check on them immediately.\n'
      '– Fall Guardian App';
  @override String get smsLocationUnavailable => 'Location: unavailable';
  @override String smsLocationLine(double lat, double lng) =>
      'Location: https://maps.google.com/?q=$lat,$lng';
}
