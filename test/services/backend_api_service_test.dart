import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fall_guardian/models/contact.dart';
import 'package:fall_guardian/services/backend_api_service.dart';
import 'package:fall_guardian/services/secure_store.dart';

class _FakeStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }
}

void main() {
  late _FakeStore store;

  setUp(() {
    store = _FakeStore();
  });

  test('ensureReady registers device once and stores credentials', () async {
    var registerCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/devices/register') {
        registerCalls++;
        return http.Response(
          jsonEncode({
            'deviceId': 'device-1',
            'deviceToken': 'token-1',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final service = BackendApiService(store: store, client: client);

    await service.ensureReady();
    await service.ensureReady();

    expect(registerCalls, 1);
    expect(store.data['backend_device_id'], 'device-1');
    expect(store.data['backend_device_token'], 'token-1');
  });

  test('submitFallAlert syncs contacts before posting alert', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');

      if (request.url.path == '/api/v1/devices/register') {
        return http.Response(
          jsonEncode({
            'deviceId': 'device-1',
            'deviceToken': 'token-1',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/api/v1/emergency-contacts') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect((payload['contacts'] as List<dynamic>).length, 2);
        expect(request.headers['authorization'], 'Bearer token-1');
        return http.Response(
          jsonEncode({'storedContacts': 2}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/api/v1/fall-alerts') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['clientAlertId'], 'alert-1');
        expect(payload['locale'], 'en');
        expect(request.headers['authorization'], 'Bearer token-1');
        return http.Response(
          jsonEncode({
            'id': 'server-alert-1',
            'clientAlertId': 'alert-1',
            'status': 'received',
            'fallTimestamp': '2026-04-09T10:00:00+00:00',
            'cancelledAt': null,
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final service = BackendApiService(store: store, client: client);
    final notified = await service.submitFallAlert(
      clientAlertId: 'alert-1',
      fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
      locale: 'en',
      latitude: 48.8566,
      longitude: 2.3522,
      contacts: const [
        Contact(id: '1', name: 'Alice', phone: '+33600000001'),
        Contact(id: '2', name: 'Bob', phone: '+33600000002'),
      ],
    );

    expect(notified, ['Alice', 'Bob']);
    expect(requests, [
      'POST /api/v1/devices/register',
      'PUT /api/v1/emergency-contacts',
      'POST /api/v1/fall-alerts',
    ]);
  });
}
