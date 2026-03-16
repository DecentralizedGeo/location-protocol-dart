import 'package:test/test.dart';
import 'package:location_protocol/src/lp/location_validator.dart';

void main() {
  group('LocationValidator', () {
    group('unknown type rejection', () {
      test('rejects unknown locationType', () {
        expect(
          () => LocationValidator.validate('banana', 'some-location'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Unknown location type'),
            ),
          ),
        );
      });

      test('rejects empty locationType', () {
        expect(
          () => LocationValidator.validate('', 'some-location'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Unknown location type'),
            ),
          ),
        );
      });
    });

    group('type-shape contract: List types', () {
      test('coordinate-decimal+lon-lat accepts List', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', [-103.77, 44.96]),
          returnsNormally,
        );
      });

      test('coordinate-decimal+lon-lat rejects String', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', '-103.77,44.96'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('requires a List'),
            ),
          ),
        );
      });

      test('coordinate-decimal+lon-lat rejects Map', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', {'lon': -103.77}),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('coordinate-decimal+lon-lat rejects empty list', () {
        expect(
          () => LocationValidator.validate('coordinate-decimal+lon-lat', []),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('exactly 2 elements'),
            ),
          ),
        );
      });

      test('coordinate-decimal+lon-lat rejects 1-element list', () {
        expect(
          () => LocationValidator.validate('coordinate-decimal+lon-lat', [-103.77]),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('coordinate-decimal+lon-lat rejects 3-element list', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', [-103.77, 44.96, 100.0]),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('type-shape contract: Map types', () {
      test('geojson-point accepts Map', () {
        expect(
          () => LocationValidator.validate(
              'geojson-point', {'type': 'Point', 'coordinates': [-103.77, 44.96]}),
          returnsNormally,
        );
      });

      test('geojson-point rejects List', () {
        expect(
          () => LocationValidator.validate('geojson-point', [-103.77, 44.96]),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('requires a Map'),
            ),
          ),
        );
      });

      test('geojson-point rejects String', () {
        expect(
          () => LocationValidator.validate('geojson-point', 'not-a-map'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('geojson-line accepts Map', () {
        expect(
          () => LocationValidator.validate('geojson-line', {
            'type': 'LineString',
            'coordinates': [
              [-103.77, 44.96],
              [-103.78, 44.97],
            ],
          }),
          returnsNormally,
        );
      });

      test('geojson-polygon accepts Map', () {
        expect(
          () => LocationValidator.validate('geojson-polygon', {
            'type': 'Polygon',
            'coordinates': [
              [
                [-104.0, 45.0],
                [-103.0, 45.0],
                [-103.0, 44.0],
                [-104.0, 45.0],
              ],
            ],
          }),
          returnsNormally,
        );
      });

      test('scaledCoordinates accepts Map', () {
        expect(
          () => LocationValidator.validate(
              'scaledCoordinates', {'x': 100, 'y': 200, 'scale': 1000}),
          returnsNormally,
        );
      });

      test('scaledCoordinates rejects String', () {
        expect(
          () => LocationValidator.validate('scaledCoordinates', '100,200'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('requires a Map'),
            ),
          ),
        );
      });

      test('scaledCoordinates rejects Map missing x', () {
        expect(
          () => LocationValidator.validate(
              'scaledCoordinates', {'y': 200, 'scale': 1000}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('requires key "x"'),
            ),
          ),
        );
      });

      test('scaledCoordinates rejects Map missing y', () {
        expect(
          () => LocationValidator.validate(
              'scaledCoordinates', {'x': 100, 'scale': 1000}),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('scaledCoordinates rejects Map missing scale', () {
        expect(
          () => LocationValidator.validate('scaledCoordinates', {'x': 100, 'y': 200}),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('type-shape contract: String types', () {
      test('h3 accepts String', () {
        expect(
          () => LocationValidator.validate('h3', '8928308280fffff'),
          returnsNormally,
        );
      });

      test('h3 rejects Map', () {
        expect(
          () => LocationValidator.validate('h3', {'index': '89283'}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('requires a String'),
            ),
          ),
        );
      });

      test('geohash accepts String', () {
        expect(
          () => LocationValidator.validate('geohash', '9q8yyk'),
          returnsNormally,
        );
      });

      test('wkt accepts String', () {
        expect(
          () => LocationValidator.validate('wkt', 'POINT(-103.77 44.96)'),
          returnsNormally,
        );
      });

      test('address accepts String', () {
        expect(
          () => LocationValidator.validate('address', '123 Main St'),
          returnsNormally,
        );
      });
    });

    group('custom type registration', () {
      tearDown(() {
        LocationValidator.resetCustomTypes();
      });

      test('registered custom type is accepted', () {
        LocationValidator.register(
          'community.plus-code.v1',
          (location) {
            if (location is! String || location.isEmpty) {
              throw ArgumentError('plus-code must be a non-empty String');
            }
          },
        );

        expect(
          () => LocationValidator.validate('community.plus-code.v1', '849VCWC8+R9'),
          returnsNormally,
        );
      });

      test('registered custom type validator fires on invalid input', () {
        LocationValidator.register(
          'community.plus-code.v1',
          (location) {
            if (location is! String) {
              throw ArgumentError('plus-code must be a String');
            }
          },
        );

        expect(
          () => LocationValidator.validate('community.plus-code.v1', 42),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('cannot override built-in type', () {
        expect(
          () => LocationValidator.register('h3', (loc) {}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Cannot override built-in'),
            ),
          ),
        );
      });

      test('duplicate custom registration replaces previous', () {
        LocationValidator.register('custom.v1', (loc) {
          throw ArgumentError('first validator');
        });
        LocationValidator.register('custom.v1', (loc) {
          // second validator accepts everything
        });

        expect(
          () => LocationValidator.validate('custom.v1', 'anything'),
          returnsNormally,
        );
      });

      test('resetCustomTypes clears custom registrations', () {
        LocationValidator.register('custom.v1', (loc) {});
        LocationValidator.resetCustomTypes();

        expect(
          () => LocationValidator.validate('custom.v1', 'anything'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('deep: coordinate-decimal+lon-lat bounds', () {
      test('rejects lon < -180', () {
        expect(
          () => LocationValidator.validate('coordinate-decimal+lon-lat', [-181.0, 44.96]),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Longitude'),
            ),
          ),
        );
      });

      test('rejects lon > 180', () {
        expect(
          () => LocationValidator.validate('coordinate-decimal+lon-lat', [181.0, 44.96]),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects lat < -90', () {
        expect(
          () => LocationValidator.validate('coordinate-decimal+lon-lat', [-103.77, -91.0]),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Latitude'),
            ),
          ),
        );
      });

      test('rejects lat > 90', () {
        expect(
          () => LocationValidator.validate('coordinate-decimal+lon-lat', [-103.77, 91.0]),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects non-numeric elements', () {
        expect(
          () => LocationValidator.validate('coordinate-decimal+lon-lat', ['abc', 44.96]),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('accepts boundary values (-180, -90)', () {
        expect(
          () => LocationValidator.validate('coordinate-decimal+lon-lat', [-180.0, -90.0]),
          returnsNormally,
        );
      });

      test('accepts boundary values (180, 90)', () {
        expect(
          () => LocationValidator.validate('coordinate-decimal+lon-lat', [180.0, 90.0]),
          returnsNormally,
        );
      });
    });

    group('deep: geojson-point structure', () {
      test('rejects Map with wrong type field', () {
        expect(
          () => LocationValidator.validate('geojson-point', {
            'type': 'LineString',
            'coordinates': [-103.77, 44.96],
          }),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects Map with missing type field', () {
        expect(
          () => LocationValidator.validate('geojson-point', {
            'coordinates': [-103.77, 44.96],
          }),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects Map with invalid coordinates', () {
        expect(
          () => LocationValidator.validate('geojson-point', {
            'type': 'Point',
            'coordinates': 'not-a-list',
          }),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('accepts valid GeoJSON Point', () {
        expect(
          () => LocationValidator.validate('geojson-point', {
            'type': 'Point',
            'coordinates': [-103.77, 44.96],
          }),
          returnsNormally,
        );
      });
    });

    group('deep: geojson-line structure', () {
      test('rejects Map with wrong type field', () {
        expect(
          () => LocationValidator.validate('geojson-line', {
            'type': 'Point',
            'coordinates': [-103.77, 44.96],
          }),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('accepts valid LineString', () {
        expect(
          () => LocationValidator.validate('geojson-line', {
            'type': 'LineString',
            'coordinates': [
              [-103.77, 44.96],
              [-103.78, 44.97],
            ],
          }),
          returnsNormally,
        );
      });
    });

    group('deep: geojson-polygon structure', () {
      test('rejects Map with wrong type field', () {
        expect(
          () => LocationValidator.validate('geojson-polygon', {
            'type': 'Point',
            'coordinates': [-103.77, 44.96],
          }),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('accepts valid Polygon', () {
        expect(
          () => LocationValidator.validate('geojson-polygon', {
            'type': 'Polygon',
            'coordinates': [
              [
                [-104.0, 45.0],
                [-103.0, 45.0],
                [-103.0, 44.0],
                [-104.0, 45.0],
              ],
            ],
          }),
          returnsNormally,
        );
      });
    });

    group('deep: h3 format', () {
      test('accepts valid H3 index', () {
        expect(
          () => LocationValidator.validate('h3', '8928308280fffff'),
          returnsNormally,
        );
      });

      test('rejects H3 with wrong length', () {
        expect(
          () => LocationValidator.validate('h3', '8928'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Invalid H3'),
            ),
          ),
        );
      });

      test('rejects H3 with invalid prefix', () {
        expect(
          () => LocationValidator.validate('h3', '0028308280fffff'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects H3 with uppercase', () {
        expect(
          () => LocationValidator.validate('h3', '8928308280FFFFF'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects empty H3 string', () {
        expect(
          () => LocationValidator.validate('h3', ''),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('deep: geohash format', () {
      test('accepts valid geohash', () {
        expect(
          () => LocationValidator.validate('geohash', '9q8yyk'),
          returnsNormally,
        );
      });

      test('rejects geohash with invalid chars', () {
        expect(
          () => LocationValidator.validate('geohash', '9q8yAk'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Invalid geohash'),
            ),
          ),
        );
      });

      test('rejects geohash longer than 12', () {
        expect(
          () => LocationValidator.validate('geohash', '9q8yyk8q9q8yy'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects empty geohash', () {
        expect(
          () => LocationValidator.validate('geohash', ''),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('deep: wkt format', () {
      test('accepts valid WKT point', () {
        expect(
          () => LocationValidator.validate('wkt', 'POINT(-103.77 44.96)'),
          returnsNormally,
        );
      });

      test('accepts valid WKT linestring', () {
        expect(
          () => LocationValidator.validate(
              'wkt', 'LINESTRING(-103.77 44.96, -103.78 44.97)'),
          returnsNormally,
        );
      });

      test('rejects malformed WKT', () {
        expect(
          () => LocationValidator.validate('wkt', 'NOT_VALID_WKT()'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Invalid WKT'),
            ),
          ),
        );
      });

      test('rejects empty WKT string', () {
        expect(
          () => LocationValidator.validate('wkt', ''),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('deep: address format', () {
      test('accepts non-empty address', () {
        expect(
          () => LocationValidator.validate('address', '123 Main St'),
          returnsNormally,
        );
      });

      test('rejects empty address', () {
        expect(
          () => LocationValidator.validate('address', ''),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('non-empty'),
            ),
          ),
        );
      });

      test('rejects whitespace-only address', () {
        expect(
          () => LocationValidator.validate('address', '   '),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('deep: scaledCoordinates numeric values', () {
      test('accepts int values', () {
        expect(
          () => LocationValidator.validate(
              'scaledCoordinates', {'x': 100, 'y': 200, 'scale': 1000}),
          returnsNormally,
        );
      });

      test('accepts double values', () {
        expect(
          () => LocationValidator.validate(
              'scaledCoordinates', {'x': 1.5, 'y': 2.5, 'scale': 1000.0}),
          returnsNormally,
        );
      });

      test('rejects non-numeric x', () {
        expect(
          () => LocationValidator.validate(
              'scaledCoordinates', {'x': 'abc', 'y': 200, 'scale': 1000}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('must be num'),
            ),
          ),
        );
      });

      test('rejects non-numeric y', () {
        expect(
          () => LocationValidator.validate(
              'scaledCoordinates', {'x': 100, 'y': null, 'scale': 1000}),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects non-numeric scale', () {
        expect(
          () => LocationValidator.validate(
              'scaledCoordinates', {'x': 100, 'y': 200, 'scale': 'big'}),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
