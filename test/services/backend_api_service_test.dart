import 'dart:async';
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

  test('ensureReady rejects insecure backend URL in release mode', () async {
    final service = BackendApiService(
      store: store,
      baseUrl: 'http://api.example.test',
      releaseMode: true,
      client: MockClient((request) async {
        fail('Release configuration must be rejected before an HTTP request.');
      }),
    );

    await expectLater(
      service.ensureReady(),
      throwsA(isA<StateError>()),
    );
  });

  test('submitFallAlert posts alert without remote contact sync', () async {
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
    await service.submitFallAlert(
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

    expect(requests, [
      'POST /api/v1/devices/register',
      'POST /api/v1/fall-alerts',
    ]);
  });

  test('createInvite posts with stored bearer token', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/invites');
      expect(request.headers['authorization'], 'Bearer token-1');
      return http.Response(
        jsonEncode(
            {'code': 'ABC12345', 'expiresAt': '2026-05-16T10:00:00+00:00'}),
        201,
      );
    });

    final service = BackendApiService(store: store, client: client);

    final invite = await service.createInvite();

    expect(invite['code'], 'ABC12345');
  });

  test('createInvite throws typed exception on API failure', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async => http.Response('forbidden', 403)),
    );

    await expectLater(
      service.createInvite(),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.body, 'body', 'forbidden'),
      ),
    );
  });

  test('submitFallAlert throws typed exception on API failure', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async => http.Response('bad request', 400)),
    );

    await expectLater(
      service.submitFallAlert(
        clientAlertId: 'alert-1',
        fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
        locale: 'en',
        latitude: null,
        longitude: null,
        contacts: const [],
      ),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having((error) => error.body, 'body', 'bad request'),
      ),
    );
  });

  test('submitFallAlert throws typed exception when backend hangs', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      requestTimeout: const Duration(milliseconds: 1),
      client: MockClient((request) => Completer<http.Response>().future),
    );

    await expectLater(
      service.submitFallAlert(
        clientAlertId: 'alert-1',
        fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
        locale: 'en',
        latitude: null,
        longitude: null,
        contacts: const [],
      ),
      throwsA(
        isA<BackendApiException>().having(
          (error) => error.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test('cancelFallAlert skips API call when no token is stored', () async {
    var called = false;
    final service = BackendApiService(
      store: store,
      client: MockClient((request) async {
        called = true;
        return http.Response('', 204);
      }),
    );

    await service.cancelFallAlert(clientAlertId: 'alert-1');

    expect(called, isFalse);
  });

  test('cancelFallAlert ignores already missing backend alert', () async {
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/fall-alerts/alert-1/cancel');
        expect(request.headers['authorization'], 'Bearer token-1');
        return http.Response('missing', 404);
      }),
    );

    await service.cancelFallAlert(clientAlertId: 'alert-1');
  });

  test('cancelFallAlert throws typed exception on API failure', () async {
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async => http.Response('server error', 500)),
    );

    await expectLater(
      service.cancelFallAlert(clientAlertId: 'alert-1'),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 500)
            .having((error) => error.body, 'body', 'server error'),
      ),
    );
  });
}
