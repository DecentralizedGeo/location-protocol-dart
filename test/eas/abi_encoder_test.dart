import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/abi_encoder.dart';

void main() {
  group('AbiEncoder', () {
    late SchemaDefinition schema;

    setUp(() {
      schema = SchemaDefinition(
        fields: [
          SchemaField(type: 'uint256', name: 'timestamp'),
          SchemaField(type: 'string', name: 'memo'),
        ],
      );
    });

    test('encodes LP payload + user data into non-empty bytes', () {
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {'type': 'Point', 'coordinates': [-103.771556, 44.967243]},
      );

      final encoded = AbiEncoder.encode(
        schema: schema,
        lpPayload: lpPayload,
        userData: {
          'timestamp': BigInt.from(1710000000),
          'memo': 'Test memo',
        },
      );

      expect(encoded, isNotEmpty);
      // ABI encoding always produces output whose length is a multiple of 32
      expect(encoded.length % 32, equals(0));
    });

    test('encodes LP-only schema (no user fields)', () {
      final lpOnlySchema = SchemaDefinition(fields: []);
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'h3',
        location: '8928308280fffff',
      );

      final encoded = AbiEncoder.encode(
        schema: lpOnlySchema,
        lpPayload: lpPayload,
        userData: {},
      );

      expect(encoded, isNotEmpty);
      expect(encoded.length % 32, equals(0));
    });

    test('deterministic — same inputs produce same output', () {
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: '{"type":"Point","coordinates":[-103.771556,44.967243]}',
      );

      final data = {
        'timestamp': BigInt.from(1710000000),
        'memo': 'Test',
      };

      final encoded1 = AbiEncoder.encode(
        schema: schema, lpPayload: lpPayload, userData: data,
      );
      final encoded2 = AbiEncoder.encode(
        schema: schema, lpPayload: lpPayload, userData: data,
      );

      expect(encoded1, equals(encoded2));
    });

    test('throws if user data key does not match schema field', () {
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: 'test',
      );

      expect(
        () => AbiEncoder.encode(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'wrong_key': BigInt.from(1),
            'memo': 'test',
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws if user data is missing a required field', () {
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: 'test',
      );

      expect(
        () => AbiEncoder.encode(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1)},
          // missing 'memo'
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('serializes Map location to string before encoding', () {
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {'type': 'Point', 'coordinates': [-103.77, 44.96]},
      );

      // Should not throw — Map should be serialized to string
      final encoded = AbiEncoder.encode(
        schema: schema,
        lpPayload: lpPayload,
        userData: {
          'timestamp': BigInt.from(1710000000),
          'memo': 'test',
        },
      );
      expect(encoded, isNotEmpty);
    });
  });
}
