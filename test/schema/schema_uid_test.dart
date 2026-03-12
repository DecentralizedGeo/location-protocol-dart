import 'package:test/test.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/schema/schema_uid.dart';

void main() {
  group('SchemaUID', () {
    test('computes a 32-byte hex string', () {
      final schema = SchemaDefinition(fields: [
        SchemaField(type: 'uint256', name: 'timestamp'),
      ]);

      final uid = SchemaUID.compute(schema);
      expect(uid, startsWith('0x'));
      expect(uid.length, equals(66)); // 0x + 64 hex chars
    });

    test('is deterministic — same inputs produce same UID', () {
      final schema1 = SchemaDefinition(fields: [
        SchemaField(type: 'uint256', name: 'timestamp'),
      ]);
      final schema2 = SchemaDefinition(fields: [
        SchemaField(type: 'uint256', name: 'timestamp'),
      ]);

      expect(SchemaUID.compute(schema1), equals(SchemaUID.compute(schema2)));
    });

    test('different schemas produce different UIDs', () {
      final schema1 = SchemaDefinition(fields: [
        SchemaField(type: 'uint256', name: 'timestamp'),
      ]);
      final schema2 = SchemaDefinition(fields: [
        SchemaField(type: 'string', name: 'memo'),
      ]);

      expect(
        SchemaUID.compute(schema1),
        isNot(equals(SchemaUID.compute(schema2))),
      );
    });

    test('revocable flag affects UID', () {
      final schema1 = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
        revocable: true,
      );
      final schema2 = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
        revocable: false,
      );

      expect(
        SchemaUID.compute(schema1),
        isNot(equals(SchemaUID.compute(schema2))),
      );
    });

    test('resolver address affects UID', () {
      final schema1 = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );
      final schema2 = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
        resolverAddress: '0x1234567890abcdef1234567890abcdef12345678',
      );

      expect(
        SchemaUID.compute(schema1),
        isNot(equals(SchemaUID.compute(schema2))),
      );
    });
  });
}
