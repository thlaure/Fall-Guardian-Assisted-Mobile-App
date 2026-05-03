import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/contact.dart';
import 'alert_ports.dart';
import 'secure_store.dart';

class BackendApiService implements AlertBackendGateway {
  BackendApiService({
    KeyValueStore? store,
    http.Client? client,
  })  : _store = store ?? SecureKeyValueStore(),
        _client = client ?? http.Client();

  static const _deviceIdKey = 'backend_device_id';
  static const _deviceTokenKey = 'backend_device_token';

  final KeyValueStore _store;
  final http.Client _client;

  // On a physical iOS device 127.0.0.1 resolves to the phone, not the Mac.
  // Update this to your dev machine's LAN IP when testing on a real device,
  // or pass --dart-define=BACKEND_BASE_URL=http://<lan-ip>:8002 at build time.
  static const _devMachineLanIp = '192.168.1.20';

  String get _baseUrl {
    const defined = String.fromEnvironment('BACKEND_BASE_URL');
    if (defined.isNotEmpty) {
      return defined;
    }

    return 'http://$_devMachineLanIp:8002';
  }

  @override
  Future<void> ensureReady() async {
    await _credentials();
  }

  @override
  Future<void> syncContacts(List<Contact> contacts) async {
    final credentials = await _credentials();
    final response = await _client.put(
      Uri.parse('$_baseUrl/api/v1/emergency-contacts'),
      headers: _jsonHeaders(token: credentials.deviceToken),
      body: jsonEncode({
        'contacts': contacts
            .map((contact) => {
                  'id': contact.id,
                  'name': contact.name,
                  'phone': contact.phone,
                })
            .toList(),
      }),
    );

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to sync contacts',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  @override
  Future<List<String>> submitFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
    required List<Contact> contacts,
  }) async {
    final credentials = await _credentials();
    await syncContacts(contacts);

    final response = await _client.post(
      Uri.parse('$_baseUrl/api/v1/fall-alerts'),
      headers: _jsonHeaders(token: credentials.deviceToken),
      body: jsonEncode({
        'clientAlertId': clientAlertId,
        'fallTimestamp':
            DateTime.fromMillisecondsSinceEpoch(fallTimestamp, isUtc: true)
                .toIso8601String(),
        'locale': locale,
        'latitude': latitude,
        'longitude': longitude,
      }),
    );

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to submit fall alert',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    return contacts.map((contact) => contact.name).toList(growable: false);
  }

  Future<Map<String, dynamic>> createInvite() async {
    final credentials = await _credentials();
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/v1/invites'),
      headers: _jsonHeaders(token: credentials.deviceToken),
    );

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to create caregiver invite',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<void> cancelFallAlert({required String clientAlertId}) async {
    final token = await _store.read(_deviceTokenKey);
    if (token == null || token.isEmpty) {
      return;
    }

    final response = await _client.post(
      Uri.parse('$_baseUrl/api/v1/fall-alerts/$clientAlertId/cancel'),
      headers: _jsonHeaders(token: token),
    );

    if (response.statusCode == 404) {
      return;
    }

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to cancel fall alert',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<_BackendCredentials> _credentials() async {
    final deviceId = await _store.read(_deviceIdKey);
    final deviceToken = await _store.read(_deviceTokenKey);
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceToken != null &&
        deviceToken.isNotEmpty) {
      return _BackendCredentials(deviceId: deviceId, deviceToken: deviceToken);
    }

    final response = await _client.post(
      Uri.parse('$_baseUrl/api/v1/devices/register'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'appVersion': '1.0.0',
      }),
    );

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to register device',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final credentials = _BackendCredentials(
      deviceId: payload['deviceId'] as String,
      deviceToken: payload['deviceToken'] as String,
    );

    await _store.write(_deviceIdKey, credentials.deviceId);
    await _store.write(_deviceTokenKey, credentials.deviceToken);
    developer.log(
      'Registered device with backend ${credentials.deviceId}',
      name: 'BackendApiService',
    );
    return credentials;
  }

  Map<String, String> _jsonHeaders({String? token}) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  bool _isSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;
}

class BackendApiException implements Exception {
  BackendApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => 'BackendApiException($message, $statusCode, $body)';
}

class _BackendCredentials {
  const _BackendCredentials({
    required this.deviceId,
    required this.deviceToken,
  });

  final String deviceId;
  final String deviceToken;
}
