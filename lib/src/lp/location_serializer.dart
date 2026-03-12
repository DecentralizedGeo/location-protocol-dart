import 'dart:convert';

/// Serializes location values to ABI-compatible strings.
///
/// The Location Protocol `location` field accepts flexible Dart types:
/// - [String]: passed through unchanged (e.g. H3 index, WKT, address)
/// - [List]: JSON-encoded (e.g. coordinate-decimal+lon-lat `[-103.77, 44.96]`)
/// - [Map]: JSON-encoded (e.g. GeoJSON `{"type":"Point","coordinates":[...]}`)
///
/// No location-type-specific validation is performed.
/// Validation is a Phase 2 feature.
class LocationSerializer {
  /// Serializes a location value to a string for ABI encoding.
  ///
  /// Throws [ArgumentError] if [location] is not a String, List, or Map.
  static String serialize(dynamic location) {
    if (location is String) return location;
    if (location is List) return jsonEncode(location);
    if (location is Map) return jsonEncode(location);
    throw ArgumentError(
      'Unsupported location type: ${location.runtimeType}. '
      'Expected String, List, or Map.',
    );
  }
}
