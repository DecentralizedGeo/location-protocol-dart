import 'dart:convert';

import 'package:geobase/geobase.dart';

/// Validates that a location value matches its declared location type.
///
/// Phase 6A: type-contract checks (known type + correct Dart shape).
/// Phase 6B: deep structural checks (regex, parser, bounds).
class LocationValidator {
  static final RegExp _h3Pattern = RegExp(r'^[89ab][0-9a-f]{14}$');
  static final RegExp _geohashPattern = RegExp(r'^[0-9b-hjkmnp-z]{1,12}$');

  /// The 9 canonical location types from the LP spec.
  static const Set<String> knownLocationTypes = {
    'coordinate-decimal+lon-lat',
    'geojson-point',
    'geojson-line',
    'geojson-polygon',
    'h3',
    'geohash',
    'wkt',
    'address',
    'scaledCoordinates',
  };

  /// Validators for built-in types.
  static final Map<String, void Function(dynamic)> _builtInValidators = {
    'coordinate-decimal+lon-lat': _validateCoordinateList,
    'geojson-point': _validateGeoJsonPoint,
    'geojson-line': _validateGeoJsonLine,
    'geojson-polygon': _validateGeoJsonPolygon,
    'h3': _validateH3,
    'geohash': _validateGeohash,
    'wkt': _validateWkt,
    'address': _validateAddress,
    'scaledCoordinates': _validateScaledCoordinatesMap,
  };

  /// Runtime-registered custom type validators.
  static final Map<String, void Function(dynamic)> _customValidators = {};

  /// Validates [location] against [locationType].
  ///
  /// Throws [ArgumentError] if the type is unknown or the location
  /// does not match the expected Dart shape.
  static void validate(String locationType, dynamic location) {
    final validator =
        _builtInValidators[locationType] ?? _customValidators[locationType];
    if (validator == null) {
      throw ArgumentError.value(
        locationType,
        'locationType',
        'Unknown location type. Registered types: '
            '${[...knownLocationTypes, ..._customValidators.keys].join(', ')}',
      );
    }
    validator(location);
  }

  /// Registers a custom location type with a validator function.
  ///
  /// The [validator] should throw [ArgumentError] on invalid input.
  /// Built-in types cannot be overridden.
  /// Duplicate registrations replace the previous validator.
  static void register(String locationType, void Function(dynamic) validator) {
    if (knownLocationTypes.contains(locationType)) {
      throw ArgumentError.value(
        locationType,
        'locationType',
        'Cannot override built-in location type.',
      );
    }
    _customValidators[locationType] = validator;
  }

  /// Clears all custom type registrations. For testing only.
  static void resetCustomTypes() {
    _customValidators.clear();
  }

  static void _validateCoordinateList(dynamic location) {
    if (location is! List) {
      throw ArgumentError(
        'coordinate-decimal+lon-lat requires a List. '
        'Got: ${location.runtimeType}',
      );
    }
    if (location.length != 2) {
      throw ArgumentError(
        'coordinate-decimal+lon-lat requires exactly 2 elements [lon, lat]. '
        'Got length: ${location.length}',
      );
    }
    if (location[0] is! num) {
      throw ArgumentError(
        'coordinate-decimal+lon-lat elements must be num. '
        'Got lon: ${location[0].runtimeType}',
      );
    }
    if (location[1] is! num) {
      throw ArgumentError(
        'coordinate-decimal+lon-lat elements must be num. '
        'Got lat: ${location[1].runtimeType}',
      );
    }
    final lon = (location[0] as num).toDouble();
    final lat = (location[1] as num).toDouble();
    if (lon < -180 || lon > 180) {
      throw ArgumentError('Longitude must be in [-180, 180]. Got: $lon');
    }
    if (lat < -90 || lat > 90) {
      throw ArgumentError('Latitude must be in [-90, 90]. Got: $lat');
    }
  }

  static void _validateGeoJsonPoint(dynamic location) {
    if (location is! Map) {
      throw ArgumentError(
        'GeoJSON location types requires a Map. '
        'Got: ${location.runtimeType}',
      );
    }
    try {
      Point.parse(jsonEncode(location), format: GeoJSON.geometry);
    } on FormatException catch (e) {
      throw ArgumentError('Invalid GeoJSON Point: ${e.message}');
    }
  }

  static void _validateGeoJsonLine(dynamic location) {
    if (location is! Map) {
      throw ArgumentError(
        'GeoJSON location types requires a Map. '
        'Got: ${location.runtimeType}',
      );
    }
    try {
      LineString.parse(jsonEncode(location), format: GeoJSON.geometry);
    } on FormatException catch (e) {
      throw ArgumentError('Invalid GeoJSON LineString: ${e.message}');
    }
  }

  static void _validateGeoJsonPolygon(dynamic location) {
    if (location is! Map) {
      throw ArgumentError(
        'GeoJSON location types requires a Map. '
        'Got: ${location.runtimeType}',
      );
    }
    try {
      Polygon.parse(jsonEncode(location), format: GeoJSON.geometry);
    } on FormatException catch (e) {
      throw ArgumentError('Invalid GeoJSON Polygon: ${e.message}');
    }
  }

  static void _validateH3(dynamic location) {
    if (location is! String) {
      throw ArgumentError(
        'This location type requires a String. '
        'Got: ${location.runtimeType}',
      );
    }
    if (!_h3Pattern.hasMatch(location)) {
      throw ArgumentError(
        'Invalid H3 index. Must match pattern ${_h3Pattern.pattern}. '
        'Got: "$location"',
      );
    }
  }

  static void _validateGeohash(dynamic location) {
    if (location is! String) {
      throw ArgumentError(
        'This location type requires a String. '
        'Got: ${location.runtimeType}',
      );
    }
    if (!_geohashPattern.hasMatch(location)) {
      throw ArgumentError(
        'Invalid geohash. Must be 1-12 chars from base-32 charset '
        '[0-9b-hjkmnp-z]. Got: "$location"',
      );
    }
  }

  static void _validateWkt(dynamic location) {
    if (location is! String) {
      throw ArgumentError(
        'This location type requires a String. '
        'Got: ${location.runtimeType}',
      );
    }
    if (location.isEmpty) {
      throw ArgumentError('Invalid WKT: string is empty.');
    }

    try {
      Point.parse(location, format: WKT.geometry);
      return;
    } on FormatException {
      // try next geometry type
    }

    try {
      LineString.parse(location, format: WKT.geometry);
      return;
    } on FormatException {
      // try next geometry type
    }

    try {
      Polygon.parse(location, format: WKT.geometry);
      return;
    } on FormatException {
      throw ArgumentError('Invalid WKT: unsupported or malformed geometry.');
    }
  }

  static void _validateAddress(dynamic location) {
    if (location is! String) {
      throw ArgumentError(
        'This location type requires a String. '
        'Got: ${location.runtimeType}',
      );
    }
    if (location.trim().isEmpty) {
      throw ArgumentError(
        'address requires a non-empty string (after trimming whitespace).',
      );
    }
  }

  static void _validateScaledCoordinatesMap(dynamic location) {
    if (location is! Map) {
      throw ArgumentError(
        'scaledCoordinates requires a Map. '
        'Got: ${location.runtimeType}',
      );
    }
    for (final key in ['x', 'y', 'scale']) {
      if (!location.containsKey(key)) {
        throw ArgumentError('scaledCoordinates requires key "$key".');
      }
      if (location[key] is! num) {
        throw ArgumentError(
          'scaledCoordinates "$key" must be num. '
          'Got: ${location[key].runtimeType}',
        );
      }
    }
  }
}
