import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fall_guardian/services/location_service.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The geolocator platform-interface package uses this channel name.
  const geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geolocatorChannel, null);
  });

  group('LocationService', () {
    // ------------------------------------------------------------------
    // googleMapsUrl — pure string formatting, no platform channel needed
    // ------------------------------------------------------------------
    test('googleMapsUrl_formatsCorrectly', () {
      final service = LocationService();
      expect(
        service.googleMapsUrl(48.8566, 2.3522),
        'https://maps.google.com/?q=48.8566,2.3522',
      );
    });

    test('googleMapsUrl_withNegativeCoords', () {
      final service = LocationService();
      expect(
        service.googleMapsUrl(-33.8688, 151.2093),
        'https://maps.google.com/?q=-33.8688,151.2093',
      );
    });

    // ------------------------------------------------------------------
    // getCurrentPosition — mock the geolocator channel.
    //
    // Note: geolocator's isLocationServiceEnabled is called before the
    // try/catch in LocationService.  We mock ALL relevant methods so the
    // channel never falls through to "no implementation".
    // ------------------------------------------------------------------
    test('getCurrentPosition_returnsNull_whenServiceDisabled', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(geolocatorChannel, (call) async {
        if (call.method == 'isLocationServiceEnabled') return false;
        return null;
      });

      final service = LocationService();
      final position = await service.getCurrentPosition();
      expect(
        position,
        isNull,
        reason: 'Should return null when location service is disabled',
      );
    });

    test(
      'getCurrentPosition_returnsNull_whenPermissionDeniedForever',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(geolocatorChannel, (call) async {
          if (call.method == 'isLocationServiceEnabled') return true;
          // LocationPermission.deniedForever has index 3 in geolocator v10.
          if (call.method == 'checkPermission') return 3;
          return null;
        });

        final service = LocationService();
        final position = await service.getCurrentPosition();
        expect(
          position,
          isNull,
          reason: 'Should return null when permission is denied forever',
        );
      },
    );

    test('getCurrentPosition_returnsNull_whenGetPositionThrows', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(geolocatorChannel, (call) async {
        if (call.method == 'isLocationServiceEnabled') return true;
        // LocationPermission.whileInUse has index 2 in geolocator v10.
        if (call.method == 'checkPermission') return 2;
        // Simulate getCurrentPosition throwing (e.g. timeout).
        throw PlatformException(
          code: 'TIMEOUT',
          message: 'Position request timed out.',
        );
      });

      final service = LocationService();
      final position = await service.getCurrentPosition();
      expect(
        position,
        isNull,
        reason: 'Should return null when getCurrentPosition throws',
      );
    });

    test('requestPermissionIfNeeded_requestsWhenDenied', () async {
      var requestCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(geolocatorChannel, (call) async {
        if (call.method == 'checkPermission') return 0;
        if (call.method == 'requestPermission') {
          requestCalled = true;
          return 2;
        }
        return null;
      });

      final service = LocationService();
      final permission = await service.requestPermissionIfNeeded();

      expect(requestCalled, isTrue);
      expect(permission, isNot(LocationPermission.denied));
    });

    test('requestPermissionIfNeeded_doesNotRequestWhenAlreadyGranted',
        () async {
      var requestCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(geolocatorChannel, (call) async {
        if (call.method == 'checkPermission') return 2;
        if (call.method == 'requestPermission') {
          requestCalled = true;
        }
        return null;
      });

      final service = LocationService();
      final permission = await service.requestPermissionIfNeeded();

      expect(requestCalled, isFalse);
      expect(permission, LocationPermission.whileInUse);
    });
  });
}
