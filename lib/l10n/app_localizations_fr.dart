import 'app_localizations.dart';

class AppLocalizationsFr extends AppLocalizations {
  // ── Generic ──────────────────────────────────────────────────────────────
  @override String get appTitle => 'Fall Guardian';
  @override String get cancel => 'Annuler';
  @override String get save => 'Enregistrer';
  @override String get remove => 'Supprimer';
  @override String get required_ => 'Obligatoire';
  @override String get unitG => 'g';
  @override String get unitMs => 'ms';
  @override String get unitDeg => '°';

  // ── Home ─────────────────────────────────────────────────────────────────
  @override String get homeStatusTitle => 'Protégé';
  @override String get homeStatusBody =>
      'La détection de chutes PSP est active.\n'
      'Une alerte de 30 secondes apparaîtra si une chute est détectée.';
  @override String get homeContactsTitle => 'Contacts d\'urgence';
  @override String get homeContactsSubtitle => 'Gérer qui est alerté';
  @override String get homeHistoryTitle => 'Historique des chutes';
  @override String get homeHistorySubtitle => 'Consulter les chutes passées';
  @override String get homeFootnote =>
      'Surveillance active sur votre montre.\n'
      'Gardez l\'application montre ouverte en arrière-plan.';

  // ── Contacts ─────────────────────────────────────────────────────────────
  @override String get contactsScreenTitle => 'Contacts d\'urgence';
  @override String contactsRemoveTitle(String name) =>
      'Retirer $name des contacts d\'urgence ?';
  @override String get contactsEmpty => 'Aucun contact';
  @override String get contactsEmptyHint =>
      'Ajoutez des proches à prévenir en cas de chute détectée.';
  @override String get addContact => 'Ajouter un contact';
  @override String get editContact => 'Modifier le contact';
  @override String get contactNameLabel => 'Nom';
  @override String get contactPhoneLabel => 'Numéro de téléphone';

  // ── Fall Alert ────────────────────────────────────────────────────────────
  @override String get fallAlertTitle => 'Chute détectée !';
  @override String get fallAlertBody =>
      'Vos contacts d\'urgence seront prévenus sauf si vous annulez.';
  @override String get gettingLocation => 'Récupération de votre position…';
  @override String get sendingSms => 'Envoi des alertes SMS…';
  @override String get smsFailed =>
      '⚠️ Échec de l\'envoi du SMS. Appelez vos contacts manuellement !';
  @override String alertSentCount(int count) =>
      'Alerte envoyée à $count contact${count == 1 ? '' : 's'}.';
  @override String get cancelAlert => 'Je vais bien — Annuler l\'alerte';

  // ── History ──────────────────────────────────────────────────────────────
  @override String get historyTitle => 'Historique des chutes';
  @override String get clearHistoryTitle => 'Effacer l\'historique ?';
  @override String get clearHistoryBody =>
      'Cela supprimera définitivement tous les enregistrements de chutes.';
  @override String get clear => 'Effacer';
  @override String get historyEmpty => 'Aucune chute enregistrée';
  @override String get statusAlertSent => 'Alerte envoyée';
  @override String get statusAlertFailed => 'SMS échoué';
  @override String get statusCancelled => 'Annulée';
  @override String get statusTimedOut => 'Délai expiré';
  @override String notifiedLabel(String names) => 'Prévenus : $names';
  @override String locationLabel(String coords) => 'Position : $coords';

  // ── Settings ─────────────────────────────────────────────────────────────
  @override String get settingsTitle => 'Paramètres';
  @override String get settingsSaved => 'Paramètres enregistrés';
  @override String get thresholdsSection => 'Seuils de détection PSP';
  @override String get thresholdsInfo =>
      'Ces seuils contrôlent la sensibilité. Des seuils de chute libre plus bas '
      'et d\'impact plus élevés réduisent les fausses alertes. Les chutes PSP '
      'manquent souvent de phase de chute libre — impact + inclinaison seuls '
      'déclencheront une alerte.';
  @override String get freeFallLabel => 'Seuil de chute libre';
  @override String get freeFallDesc =>
      '‖accel‖ doit descendre en dessous pour détecter la chute libre';
  @override String get impactLabel => 'Seuil d\'impact';
  @override String get impactDesc =>
      'Le pic ‖accel‖ doit dépasser ce seuil pour détecter l\'impact';
  @override String get tiltLabel => 'Seuil d\'inclinaison';
  @override String get tiltDesc =>
      'L\'angle par rapport à la verticale doit dépasser ce seuil après l\'impact';
  @override String get freeFallDurationLabel => 'Durée min. de chute libre';
  @override String get freeFallDurationDesc =>
      'Durée minimale de la phase de chute libre';
  @override String get resetDefaults => 'Réinitialiser les valeurs par défaut';

  // ── Notifications ─────────────────────────────────────────────────────────
  @override String get notifTitle => '⚠️ Chute détectée';
  @override String get notifBody =>
      'Ouvrez l\'app pour annuler ou envoyer une alerte dans 30 secondes';

  // ── SMS ───────────────────────────────────────────────────────────────────
  @override String smsMessage(String locationLine) =>
      '🚨 ALERTE CHUTE : Votre proche a peut-être fait une chute et a besoin d\'aide.\n'
      '$locationLine\n'
      'Appelez-le ou rendez-vous auprès de lui immédiatement.\n'
      '– Application Fall Guardian';
  @override String get smsLocationUnavailable => 'Position : indisponible';
  @override String smsLocationLine(double lat, double lng) =>
      'Position : https://maps.google.com/?q=$lat,$lng';
}
