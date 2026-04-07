import 'dart:developer' as developer;

import 'package:geolocator/geolocator.dart';

import 'alert_ports.dart';

class LocationService implements AlertLocationProvider {
  /// Prompts for location permission early in the app lifecycle so the user
  /// does not first see the permission dialog during a live fall escalation.
  ///
  /// This method is intentionally best-effort: it should never crash startup or
  /// block the rest of the app if the platform rejects the request.
  Future<LocationPermission> requestPermissionIfNeeded() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        return Geolocator.requestPermission();
      }
      return permission;
    } catch (error, stackTrace) {
      developer.log(
        'requestPermissionIfNeeded failed',
        name: 'LocationService',
        error: error,
        stackTrace: stackTrace,
      );
      return LocationPermission.unableToDetermine;
    }
  }

  /// Returns the current position, or null if unavailable.
  @override
  Future<Position?> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await requestPermissionIfNeeded();
    if (permission == LocationPermission.denied) return null;
    if (permission == LocationPermission.deniedForever) return null;
    if (permission == LocationPermission.unableToDetermine) return null;

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (error, stackTrace) {
      developer.log(
        'getCurrentPosition failed',
        name: 'LocationService',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  String googleMapsUrl(double lat, double lng) =>
      'https://maps.google.com/?q=$lat,$lng';
}
