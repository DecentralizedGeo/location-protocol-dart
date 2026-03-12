import 'package:test/test.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';

void main() {
  group('SchemaDefinition', () {
    group('LP field auto-prepend', () {
      test('generates EAS schema string with LP fields prepended', () {
        final schema = SchemaDefinition(
          fields: [
            SchemaField(type: 'uint256', name: 'timestamp'),
            SchemaField(type: 'string', name: 'memo'),
          ],
        );

        expect(
          schema.toEASSchemaString(),
          equals(
            'string lp_version,string srs,string location_type,'
            'string location,uint256 timestamp,string memo',
          ),
        );
      });

      test('generates EAS schema string with LP fields only (no user fields)', () {
        final schema = SchemaDefinition(fields: []);

        expect(
          schema.toEASSchemaString(),
          equals('string lp_version,string srs,string location_type,string location'),
        );
      });

      test('lpFields returns the 4 LP base fields', () {
        expect(
          SchemaDefinition.lpFields.map((f) => f.name).toList(),
          equals(['lp_version', 'srs', 'location_type', 'location']),
        );
      });

      test('allFields includes LP fields + user fields', () {
        final schema = SchemaDefinition(
          fields: [SchemaField(type: 'uint256', name: 'timestamp')],
        );
        final names = schema.allFields.map((f) => f.name).toList();
        expect(names, equals(['lp_version', 'srs', 'location_type', 'location', 'timestamp']));
      });
    });

    group('field conflict detection', () {
      test('throws if user field name collides with lp_version', () {
        expect(
          () => SchemaDefinition(
            fields: [SchemaField(type: 'string', name: 'lp_version')],
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws if user field name collides with srs', () {
        expect(
          () => SchemaDefinition(
            fields: [SchemaField(type: 'string', name: 'srs')],
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws if user field name collides with location_type', () {
        expect(
          () => SchemaDefinition(
            fields: [SchemaField(type: 'string', name: 'location_type')],
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws if user field name collides with location', () {
        expect(
          () => SchemaDefinition(
            fields: [SchemaField(type: 'string', name: 'location')],
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('revocable flag', () {
      test('defaults to true', () {
        final schema = SchemaDefinition(fields: []);
        expect(schema.revocable, isTrue);
      });

      test('can be set to false', () {
        final schema = SchemaDefinition(fields: [], revocable: false);
        expect(schema.revocable, isFalse);
      });
    });

    group('resolver address', () {
      test('defaults to ZERO_ADDRESS', () {
        final schema = SchemaDefinition(fields: []);
        expect(
          schema.resolverAddress,
          equals('0x0000000000000000000000000000000000000000'),
        );
      });

      test('can be set to a custom address', () {
        const addr = '0x1234567890abcdef1234567890abcdef12345678';
        final schema = SchemaDefinition(fields: [], resolverAddress: addr);
        expect(schema.resolverAddress, equals(addr));
      });
    });
  });
}
