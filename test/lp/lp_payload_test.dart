import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';

void main() {
  group('LPPayload', () {
    group('valid payloads', () {
      test('accepts valid geojson-point payload with Map location', () {
        final payload = LPPayload(
          lpVersion: '1.0.0',
          srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
          locationType: 'geojson-point',
          location: {'type': 'Point', 'coordinates': [-103.771556, 44.967243]},
        );
        expect(payload.lpVersion, equals('1.0.0'));
        expect(payload.locationType, equals('geojson-point'));
      });

      test('accepts valid coordinate-decimal+lon-lat payload with List location', () {
        final payload = LPPayload(
          lpVersion: '2.1.0',
          srs: 'http://www.opengis.net/def/crs/EPSG/0/4326',
          locationType: 'coordinate-decimal+lon-lat',
          location: [-103.771556, 44.967243],
        );
        expect(payload.location, isA<List>());
      });

      test('accepts valid h3 payload with String location', () {
        final payload = LPPayload(
          lpVersion: '1.0.0',
          srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
          locationType: 'h3',
          location: '8928308280fffff',
        );
        expect(payload.location, isA<String>());
      });
    });

    group('lp_version validation', () {
      test('rejects empty lp_version', () {
        expect(
          () => LPPayload(
            lpVersion: '',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'geojson-point',
            location: 'test',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects non-semver lp_version', () {
        expect(
          () => LPPayload(
            lpVersion: '1.0',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'geojson-point',
            location: 'test',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects lp_version with text', () {
        expect(
          () => LPPayload(
            lpVersion: 'v1.0.0',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'geojson-point',
            location: 'test',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('srs validation', () {
      test('rejects empty srs', () {
        expect(
          () => LPPayload(
            lpVersion: '1.0.0',
            srs: '',
            locationType: 'geojson-point',
            location: 'test',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects non-URI srs', () {
        expect(
          () => LPPayload(
            lpVersion: '1.0.0',
            srs: 'not a uri',
            locationType: 'geojson-point',
            location: 'test',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('location_type validation', () {
      test('rejects empty location_type', () {
        expect(
          () => LPPayload(
            lpVersion: '1.0.0',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: '',
            location: 'test',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('location validation', () {
      test('rejects null location', () {
        expect(
          () => LPPayload(
            lpVersion: '1.0.0',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'geojson-point',
            location: null,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('location type validation (strict)', () {
      test('rejects unknown locationType by default', () {
        expect(
          () => LPPayload(
            lpVersion: '1.0.0',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'banana',
            location: 'some-data',
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Unknown location type'),
            ),
          ),
        );
      });

      test('rejects Dart-type mismatch (geojson-point with List)', () {
        expect(
          () => LPPayload(
            lpVersion: '1.0.0',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'geojson-point',
            location: [-103.77, 44.96],
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('requires a Map'),
            ),
          ),
        );
      });

      test('accepts valid geojson-point with Map', () {
        expect(
          () => LPPayload(
            lpVersion: '1.0.0',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'geojson-point',
            location: {'type': 'Point', 'coordinates': [-103.77, 44.96]},
          ),
          returnsNormally,
        );
      });
    });

    group('validateLocation bypass', () {
      test('bypasses location validation when false', () {
        expect(
          () => LPPayload(
            lpVersion: '1.0.0',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'banana',
            location: 'anything',
            validateLocation: false,
          ),
          returnsNormally,
        );
      });

      test('still validates lpVersion when bypass is set', () {
        expect(
          () => LPPayload(
            lpVersion: 'bad',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'banana',
            location: 'anything',
            validateLocation: false,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('still validates srs when bypass is set', () {
        expect(
          () => LPPayload(
            lpVersion: '1.0.0',
            srs: 'not-a-uri',
            locationType: 'banana',
            location: 'anything',
            validateLocation: false,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('still rejects null location when bypass is set', () {
        expect(
          () => LPPayload(
            lpVersion: '1.0.0',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'geojson-point',
            location: null,
            validateLocation: false,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
