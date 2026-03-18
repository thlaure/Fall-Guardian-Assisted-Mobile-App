import 'package:flutter_test/flutter_test.dart';
import 'package:fall_guardian/models/contact.dart';

void main() {
  const contact = Contact(id: '1', name: 'Alice', phone: '+33600000000');

  group('Contact', () {
    test('toJson / fromJson round-trip', () {
      final json = contact.toJson();
      final restored = Contact.fromJson(json);
      expect(restored.id, contact.id);
      expect(restored.name, contact.name);
      expect(restored.phone, contact.phone);
    });

    test('toJson contains all fields', () {
      final json = contact.toJson();
      expect(json['id'], '1');
      expect(json['name'], 'Alice');
      expect(json['phone'], '+33600000000');
    });

    test('copyWith replaces given fields', () {
      final updated = contact.copyWith(name: 'Bob');
      expect(updated.id, contact.id);
      expect(updated.name, 'Bob');
      expect(updated.phone, contact.phone);
    });

    test('copyWith with no args returns equal values', () {
      final copy = contact.copyWith();
      expect(copy.id, contact.id);
      expect(copy.name, contact.name);
      expect(copy.phone, contact.phone);
    });
  });
}
