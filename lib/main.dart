import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'screens/fall_alert_screen.dart';
import 'services/watch_communication_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().initialize();
  runApp(const FallGuardianApp());
}

class FallGuardianApp extends StatefulWidget {
  const FallGuardianApp({super.key});

  @override
  State<FallGuardianApp> createState() => _FallGuardianAppState();
}

class _FallGuardianAppState extends State<FallGuardianApp> {
  final _watchService = WatchCommunicationService();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _cancelAlertController = StreamController<void>.broadcast();

  @override
  void initState() {
    super.initState();
    _watchService.setFallDetectedCallback(_onFallDetected);
    _watchService.setCancelAlertCallback(_onAlertCancelled);
  }

  void _onAlertCancelled() {
    _cancelAlertController.add(null);
  }

  Future<void> _onFallDetected(int timestamp) async {
    // Get localized notification strings from current context
    final context = _navigatorKey.currentContext;
    final l10n = context != null ? AppLocalizations.of(context) : null;

    // Only show the notification when the app is backgrounded (e.g. screen locked).
    // When the app is in the foreground FallAlertScreen is pushed directly, so
    // showing a heads-up banner would require a second tap to dismiss it before
    // the user can interact with the cancel button.
    final isInForeground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!isInForeground) {
      await NotificationService().showFallDetectedNotification(
        title: l10n?.notifTitle ?? '⚠️ Fall Detected',
        body:
            l10n?.notifBody ?? 'Open app to cancel or send alert in 30 seconds',
      );
    }

    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => FallAlertScreen(
          fallTimestamp: timestamp,
          cancelStream: _cancelAlertController.stream,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  void dispose() {
    _cancelAlertController.close();
    _watchService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Fall Guardian',
      debugShowCheckedModeBanner: false,
      // ── Localization ──────────────────────────────────────────────────────
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // English is the fallback when the device locale is not supported
      locale: null, // null = follow device locale automatically
      // ─────────────────────────────────────────────────────────────────────
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE5694A)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE5694A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: HomeScreen(onSimulateFall: _onFallDetected),
    );
  }
}
