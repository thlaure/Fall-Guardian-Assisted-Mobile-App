import 'package:flutter_test/flutter_test.dart';
import 'package:fall_guardian/models/fall_event.dart';

void main() {
  final timestamp = DateTime(2024, 1, 15, 10, 30);

  group('FallEvent', () {
    test('toJson / fromJson round-trip — alertSent with location', () {
      final event = FallEvent(
        id: 'abc',
        timestamp: timestamp,
        status: FallEventStatus.alertSent,
        latitude: 48.8566,
        longitude: 2.3522,
        notifiedContacts: ['Alice', 'Bob'],
      );

      final restored = FallEvent.fromJson(event.toJson());
      expect(restored.id, event.id);
      expect(restored.timestamp, event.timestamp);
      expect(restored.status, FallEventStatus.alertSent);
      expect(restored.latitude, 48.8566);
      expect(restored.longitude, 2.3522);
      expect(restored.notifiedContacts, ['Alice', 'Bob']);
    });

    test('toJson / fromJson round-trip — cancelled, no location', () {
      final event = FallEvent(
        id: 'xyz',
        timestamp: timestamp,
        status: FallEventStatus.cancelled,
      );

      final restored = FallEvent.fromJson(event.toJson());
      expect(restored.status, FallEventStatus.cancelled);
      expect(restored.latitude, isNull);
      expect(restored.longitude, isNull);
      expect(restored.notifiedContacts, isEmpty);
    });

    test('all status values round-trip', () {
      for (final status in FallEventStatus.values) {
        final event = FallEvent(id: 'x', timestamp: timestamp, status: status);
        final restored = FallEvent.fromJson(event.toJson());
        expect(restored.status, status);
      }
    });

    test('fromJson_missingNotifiedContacts_defaultsToEmpty', () {
      final json = {
        'id': 'abc',
        'timestamp': timestamp.toIso8601String(),
        'status': 'cancelled',
        'latitude': null,
        'longitude': null,
        // 'notifiedContacts' key intentionally omitted
      };
      final event = FallEvent.fromJson(json);
      expect(event.notifiedContacts, isEmpty);
    });

    test('fromJson_nullNotifiedContacts_defaultsToEmpty', () {
      final json = {
        'id': 'abc',
        'timestamp': timestamp.toIso8601String(),
        'status': 'alertSent',
        'latitude': null,
        'longitude': null,
        'notifiedContacts': null,
      };
      final event = FallEvent.fromJson(json);
      expect(event.notifiedContacts, isEmpty);
    });

    test('fromJson_invalidStatus_throwsError', () {
      final json = {
        'id': 'abc',
        'timestamp': timestamp.toIso8601String(),
        'status': 'bogusStatus',
        'latitude': null,
        'longitude': null,
        'notifiedContacts': <String>[],
      };
      expect(() => FallEvent.fromJson(json), throwsA(isA<ArgumentError>()));
    });
  });
}
