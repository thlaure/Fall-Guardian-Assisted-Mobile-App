import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fall_guardian/l10n/app_localizations.dart';
import 'package:fall_guardian/screens/fall_alert_screen.dart';

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Silence platform calls from flutter_local_notifications in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      null,
    );
  });

  group('FallAlertScreen', () {
    testWidgets('shows 30-second countdown on launch', (tester) async {
      await tester.pumpWidget(_app(
        const FallAlertScreen(fallTimestamp: 0),
      ));
      await tester.pump();
      expect(find.text('30'), findsOneWidget);
    });

    testWidgets('shows warning icon and cancel button', (tester) async {
      await tester.pumpWidget(_app(
        const FallAlertScreen(fallTimestamp: 0),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('countdown decrements by 1 each second', (tester) async {
      await tester.pumpWidget(_app(
        const FallAlertScreen(fallTimestamp: 0),
      ));
      await tester.pump();
      expect(find.text('30'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('29'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('28'), findsOneWidget);
    });

    testWidgets('tapping cancel pops the screen', (tester) async {
      // Push FallAlertScreen on top of a home screen so we can verify the pop.
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const FallAlertScreen(fallTimestamp: 0),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));

      // Pump twice: once for the initial frame, once to load localizations.
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('open'));
      await tester.pump(); // trigger navigation
      await tester.pump(); // complete transition

      expect(find.byType(FallAlertScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pump(); // trigger async cancel + pop
      await tester.pump(const Duration(milliseconds: 100)); // complete pop

      expect(find.byType(FallAlertScreen), findsNothing);
    });
  });
}
