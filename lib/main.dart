// dart:async gives us StreamController and related async utilities.
// A "Stream" in Dart is like a pipe that can carry a sequence of events over
// time — we use one here to broadcast cancel signals to any open alert screen.
import 'dart:async';

// Flutter's material library provides the core UI building blocks:
// widgets, themes, navigation, etc. "Material" refers to Google's design system.
import 'package:flutter/material.dart';

// flutter_localizations ships the translated strings that Flutter's own widgets
// use (e.g. the "OK" button on a date picker). We need to include its delegates
// alongside our own so every part of the UI speaks the user's language.
import 'package:flutter_localizations/flutter_localizations.dart';

// Our own generated localization helper (lives in lib/l10n/).
// It reads the device locale and returns the matching translated strings.
import 'l10n/app_localizations.dart';

// The two main screens of the phone app.
import 'screens/home_screen.dart';
import 'screens/fall_alert_screen.dart';
import 'repositories/contacts_repository.dart';

// The service that talks to the native watch layer (Wear OS / watchOS).
import 'services/watch_communication_service.dart';
import 'services/alert_coordinator.dart';
import 'services/backend_api_service.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';

// ─── Entry point ─────────────────────────────────────────────────────────────
// Every Flutter app starts here. The `async` keyword allows us to `await`
// asynchronous work before the first frame is drawn.
void main() async {
  // Step 1 — Bind Flutter to the native platform.
  // Flutter's engine communicates with Android/iOS through "bindings". Before
  // calling any platform API (like notifications) we must tell Flutter that
  // the engine is ready. Without this line, any `await` before `runApp` would
  // silently hang.
  WidgetsFlutterBinding.ensureInitialized();

  // Step 2 — Initialise the notification plugin ONCE, at startup.
  // flutter_local_notifications registers its Android notification channel and
  // requests iOS permission here. It must happen before any notification can
  // be shown. We do it eagerly so the channel exists the moment a fall fires.
  await NotificationService().initialize();

  // Step 3 — Hand control to Flutter and draw the first widget.
  // `runApp` inflates the root widget and begins the render loop.
  runApp(const FallGuardianApp());
}

// ─── Root widget ─────────────────────────────────────────────────────────────
// Why StatefulWidget and not StatelessWidget?
// Because the root needs to own long-lived objects (_watchService,
// _navigatorKey, _cancelAlertController) that must survive rebuilds.
// A StatelessWidget is re-created from scratch on every rebuild, so it cannot
// safely hold service instances.
/// Root widget of the Fall Guardian phone app.
///
/// Responsibilities:
/// 1. Owns the [WatchCommunicationService] that listens for watch events.
/// 2. Holds the [GlobalKey<NavigatorState>] so fall events can push a new
///    screen even when no BuildContext is readily available.
/// 3. Broadcasts cancel signals to any open [FallAlertScreen] via a [Stream].
class FallGuardianApp extends StatefulWidget {
  const FallGuardianApp({super.key});

  @override
  State<FallGuardianApp> createState() => _FallGuardianAppState();
}

class _FallGuardianAppState extends State<FallGuardianApp> {
  // The watch service is instantiated here (at the app root) because it must
  // live for the entire lifetime of the app — fall events can arrive at any
  // time, including while the user is on a different screen.
  final _watchService = WatchCommunicationService();
  final _alertCoordinator = AlertCoordinator.live();
  final _locationService = LocationService();
  final _backendApi = BackendApiService();
  final _contactsRepository = ContactsRepository();

  // GlobalKey gives us a stable reference to the Navigator (the stack of
  // screens). We need it in _onFallDetected because that callback fires from
  // the native layer, outside the normal widget tree where a BuildContext
  // would give us `Navigator.of(context)`.
  final _navigatorKey = GlobalKey<NavigatorState>();

  bool _isAlertScreenShowing = false;

  @override
  void initState() {
    super.initState();
    // Register our two callback functions with the watch service.
    // The service will call these whenever it receives an event from the
    // native platform layer (Kotlin/Swift code on the watch side).
    _watchService.setFallDetectedCallback(_onFallDetected);
    _watchService.setCancelAlertCallback(_onAlertCancelled);

    // Ask for location permission early so a real alert is not the first time
    // the user sees the GPS authorization sheet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_locationService.requestPermissionIfNeeded());
      unawaited(_bootstrapBackend());
    });
  }

  Future<void> _bootstrapBackend() async {
    try {
      await _backendApi.ensureReady();
      final contacts = await _contactsRepository.getAll();
      await _backendApi.syncContacts(contacts);
    } catch (_) {
      // Best effort only: the app must still function locally if the backend is
      // unavailable, and alert submission will surface the failure later.
    }
  }

  // Called by WatchCommunicationService when the watch (or native layer)
  // signals that an in-progress alert has been cancelled.
  // We push `null` into the broadcast stream — the value itself doesn't matter,
  // the event ("something was cancelled") is what listeners care about.
  void _onAlertCancelled() {
    unawaited(_alertCoordinator.cancelFromWatch());
  }

  // Called by WatchCommunicationService when the watch detects a fall.
  // [timestamp] is the Unix epoch in milliseconds of the moment the fall
  // was detected — it is the shared "origin" that keeps both countdowns in sync.
  Future<void> _onFallDetected(int timestamp) async {
    // Retrieve the current localization bundle so we can build translated
    // notification strings. We use the navigator's context rather than the
    // widget's own context because this method can be called at any time,
    // including after the widget has been rebuilt.
    await _alertCoordinator.startAlert(timestamp);

    // Android background alerts are owned by WearDataListenerService's native
    // full-screen notification. iOS background alerts are owned by
    // WatchSessionManager's native notification. Flutter only presents the
    // full-screen in-app alert when the phone UI is actually visible.
    // Push FallAlertScreen on top of the current screen.
    // MaterialPageRoute describes the transition animation and the widget to show.
    // fullscreenDialog: true gives it a slide-up-from-bottom animation (modal
    // style) rather than the default slide-in-from-right.
    //
    // The `?.` null-safe call means: do nothing if the navigator hasn't been
    // created yet (should never happen in practice, but safe to guard).
    if (_isAlertScreenShowing) return;

    _isAlertScreenShowing = true;
    _navigatorKey.currentState
        ?.push(
      MaterialPageRoute(
        builder: (_) => FallAlertScreen(
          // Pass the original fall timestamp so FallAlertScreen can compute
          // its remaining seconds relative to the same clock origin as the watch.
          fallTimestamp: timestamp,
          alertCoordinator: _alertCoordinator,
        ),
        fullscreenDialog: true,
      ),
    )
        .whenComplete(() {
      _isAlertScreenShowing = false;
    });
  }

  // dispose() is called when the widget is permanently removed from the tree
  // (e.g. the app is killed). We clean up resources to avoid memory leaks:
  // - Closing the StreamController stops the underlying broadcast stream.
  // - Disposing the watch service clears the MethodChannel handler.
  @override
  void dispose() {
    _alertCoordinator.dispose();
    _watchService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // MaterialApp is the top-level Flutter widget. It sets up:
    //   • the Navigator (screen stack)
    //   • theming (colours, typography)
    //   • localization (translated strings)
    //   • the debug banner (we hide it)
    return MaterialApp(
      // Give the Navigator a stable key so _onFallDetected can reach it from
      // outside the widget tree (see _navigatorKey above).
      navigatorKey: _navigatorKey,
      title: 'Fall Guardian',
      // Hide the red "DEBUG" banner that Flutter shows in the top-right corner
      // during development builds.
      debugShowCheckedModeBanner: false,

      // ── Localization ──────────────────────────────────────────────────────
      // "Delegates" are factories: Flutter asks each delegate to produce the
      // translated strings for a given locale. We need four delegates:
      //   1. AppLocalizations.delegate — our own strings (lib/l10n/)
      //   2. GlobalMaterialLocalizations.delegate — strings for Material widgets
      //      (e.g. "Cancel", "OK", month names in date pickers)
      //   3. GlobalWidgetsLocalizations.delegate — text direction (LTR vs RTL)
      //   4. GlobalCupertinoLocalizations.delegate — strings for iOS-style widgets
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Tell Flutter which locales the app supports. If the device is set to a
      // language not in this list, Flutter picks the closest match or the first
      // entry as the fallback.
      supportedLocales: AppLocalizations.supportedLocales,
      // English is the fallback when the device locale is not supported
      // null = let Flutter automatically pick based on the device's language setting.
      locale: null, // null = follow device locale automatically
      // ─────────────────────────────────────────────────────────────────────

      // ── Theming ───────────────────────────────────────────────────────────
      // We define both a light and a dark theme so the app respects the user's
      // OS-level dark mode preference automatically.
      //
      // ColorScheme.fromSeed generates a complete, harmonious colour palette
      // from a single "seed" colour. 0xFFE5694A is the brand orange.
      // useMaterial3 opts into Material Design 3 (the latest version of
      // Google's design system, with rounded shapes and tonal colours).
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE5694A)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE5694A),
          // brightness: Brightness.dark tells the seed algorithm to produce
          // dark-mode-appropriate shades of the same colour family.
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // ThemeMode.system = automatically switch between light and dark theme
      // based on the device's system setting (Settings → Display → Dark mode).
      themeMode: ThemeMode.system,
      // ─────────────────────────────────────────────────────────────────────

      // The first screen shown when the app launches.
      // We pass _onFallDetected so the HomeScreen can trigger a simulated fall
      // (useful for testing the full alert flow without a real watch).
      home: HomeScreen(onSimulateFall: _onFallDetected),
    );
  }
}
