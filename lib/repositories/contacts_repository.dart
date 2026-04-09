import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import '../models/contact.dart';
import '../services/alert_ports.dart';
import '../services/backend_api_service.dart';
import '../services/secure_store.dart';
import 'shared_preferences_migration.dart';

enum ContactsSyncState { unknown, synced, failed }

class ContactsRepository implements EmergencyContactsStore {
  ContactsRepository({
    KeyValueStore? store,
    AlertBackendGateway? backendGateway,
  })  : _store = store ?? SecureKeyValueStore(),
        _backendGateway = backendGateway ?? BackendApiService();

  static const _key = 'contacts';
  final KeyValueStore _store;
  final AlertBackendGateway _backendGateway;
  final ValueNotifier<ContactsSyncState> syncState =
      ValueNotifier<ContactsSyncState>(ContactsSyncState.unknown);

  @override
  Future<List<Contact>> getAll() async {
    final raw = await _readRaw();
    final contacts = <Contact>[];
    for (final s in raw) {
      try {
        contacts.add(Contact.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // skip corrupted entry
      }
    }
    return contacts;
  }

  Future<bool> save(List<Contact> contacts) async {
    await _store.write(
      _key,
      jsonEncode(contacts.map((c) => jsonEncode(c.toJson())).toList()),
    );
    await deleteLegacyKey(_key);
    return _syncBackend(contacts);
  }

  Future<bool> add(Contact contact) async {
    final contacts = await getAll();
    contacts.add(contact);
    return save(contacts);
  }

  Future<bool> remove(String id) async {
    final contacts = await getAll();
    contacts.removeWhere((c) => c.id == id);
    return save(contacts);
  }

  Future<bool> update(Contact updated) async {
    final contacts = await getAll();
    final idx = contacts.indexWhere((c) => c.id == updated.id);
    if (idx != -1) {
      contacts[idx] = updated;
      return save(contacts);
    }

    return syncState.value == ContactsSyncState.synced;
  }

  Future<List<String>> _readRaw() async {
    final secureRaw = await _store.read(_key);
    if (secureRaw != null) {
      try {
        final decoded = jsonDecode(secureRaw) as List<dynamic>;
        return List<String>.from(decoded);
      } catch (_) {
        await _store.delete(_key);
      }
    }

    final legacyRaw = await readLegacyStringList(_key);
    if (legacyRaw.isNotEmpty) {
      await _store.write(_key, jsonEncode(legacyRaw));
      await deleteLegacyKey(_key);
    }
    return legacyRaw;
  }

  Future<bool> _syncBackend(List<Contact> contacts) async {
    try {
      await _backendGateway.ensureReady();
      await _backendGateway.syncContacts(contacts);
      syncState.value = ContactsSyncState.synced;
      return true;
    } catch (error, stackTrace) {
      developer.log(
        'Contact sync failed; keeping local copy',
        name: 'ContactsRepository',
        error: error,
        stackTrace: stackTrace,
      );
      syncState.value = ContactsSyncState.failed;
      return false;
    }
  }
}
