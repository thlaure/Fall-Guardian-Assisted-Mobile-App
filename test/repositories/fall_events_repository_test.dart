import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fall_guardian/models/fall_event.dart';
import 'package:fall_guardian/repositories/fall_events_repository.dart';

void main() {
  late FallEventsRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FallEventsRepository();
  });

  group('FallEventsRepository', () {
    test('getAll returns empty list initially', () async {
      expect(await repo.getAll(), isEmpty);
    });

    test('add persists an event', () async {
      final event = FallEvent(
        id: '1',
        timestamp: DateTime(2024, 1, 1),
        status: FallEventStatus.alertSent,
        notifiedContacts: ['Alice'],
      );
      await repo.add(event);
      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.first.id, '1');
    });

    test('getAll returns events sorted newest first', () async {
      final older = FallEvent(
        id: 'old',
        timestamp: DateTime(2024, 1, 1),
        status: FallEventStatus.cancelled,
      );
      final newer = FallEvent(
        id: 'new',
        timestamp: DateTime(2024, 6, 1),
        status: FallEventStatus.alertSent,
      );
      await repo.add(older);
      await repo.add(newer);
      final all = await repo.getAll();
      expect(all.first.id, 'new');
      expect(all.last.id, 'old');
    });

    test('clear removes all events', () async {
      await repo.add(FallEvent(
        id: '1',
        timestamp: DateTime(2024, 1, 1),
        status: FallEventStatus.cancelled,
      ));
      await repo.clear();
      expect(await repo.getAll(), isEmpty);
    });

    test('add preserves location and contacts', () async {
      final event = FallEvent(
        id: '1',
        timestamp: DateTime(2024, 1, 1),
        status: FallEventStatus.alertSent,
        latitude: 48.8566,
        longitude: 2.3522,
        notifiedContacts: ['Alice', 'Bob'],
      );
      await repo.add(event);
      final restored = (await repo.getAll()).first;
      expect(restored.latitude, 48.8566);
      expect(restored.longitude, 2.3522);
      expect(restored.notifiedContacts, ['Alice', 'Bob']);
    });
  });
}
