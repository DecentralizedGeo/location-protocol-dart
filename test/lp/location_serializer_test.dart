import 'package:test/test.dart';
import 'package:location_protocol/src/lp/location_serializer.dart';

void main() {
  group('LocationSerializer', () {
    group('serialize', () {
      test('passes through String values unchanged', () {
        const input = '8928308280fffff';
        expect(LocationSerializer.serialize(input), equals('8928308280fffff'));
      });

      test('serializes a GeoJSON Point map to JSON string', () {
        final input = {
          'type': 'Point',
          'coordinates': [-103.771556, 44.967243],
        };
        final result = LocationSerializer.serialize(input);
        expect(result, contains('"type":"Point"'));
        expect(result, contains('"coordinates"'));
        expect(result, contains('-103.771556'));
      });

      test('serializes a coordinate List to JSON string', () {
        final input = [-103.771556, 44.967243];
        final result = LocationSerializer.serialize(input);
        expect(result, equals('[-103.771556,44.967243]'));
      });

      test('serializes a GeoJSON Polygon map', () {
        final input = {
          'type': 'Polygon',
          'coordinates': [
            [
              [-104.0, 45.0],
              [-103.0, 45.0],
              [-103.0, 44.0],
              [-104.0, 44.0],
              [-104.0, 45.0],
            ]
          ],
        };
        final result = LocationSerializer.serialize(input);
        expect(result, contains('"type":"Polygon"'));
      });

      test('serializes a scaledCoordinates map', () {
        final input = {'x': -103771556, 'y': 44967243, 'scale': 1000000};
        final result = LocationSerializer.serialize(input);
        expect(result, contains('"x":-103771556'));
        expect(result, contains('"scale":1000000'));
      });

      test('throws on unsupported type (int)', () {
        expect(
          () => LocationSerializer.serialize(42),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on unsupported type (bool)', () {
        expect(
          () => LocationSerializer.serialize(true),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
