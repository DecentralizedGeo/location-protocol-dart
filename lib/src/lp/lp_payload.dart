import 'package:location_protocol/src/lp/location_validator.dart';

/// A validated Location Protocol base data model payload.
///
/// Contains the 4 required fields per the LP specification:
/// - [lpVersion]: semver string (e.g. "1.0.0")
/// - [srs]: Spatial Reference System URI
/// - [locationType]: location format identifier (e.g. "geojson-point")
/// - [location]: the location data (String, List, or Map)
///
/// Validation is performed on construction. Invalid payloads throw
/// [ArgumentError].
class LPPayload {
  final String lpVersion;
  final String srs;
  final String locationType;
  final dynamic location;
  final bool validateLocation;

  /// Creates a validated LP payload.
  ///
  /// Throws [ArgumentError] if any field is invalid.
  LPPayload({
    required this.lpVersion,
    required this.srs,
    required this.locationType,
    required this.location,
    this.validateLocation = true,
  }) {
    _validate();
  }

  void _validate() {
    // lp_version: must match major.minor.patch
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(lpVersion)) {
      throw ArgumentError.value(
        lpVersion,
        'lpVersion',
        'Must match semver pattern (major.minor.patch). Got: "$lpVersion"',
      );
    }

    // srs: must be a valid URI
    if (srs.isEmpty) {
      throw ArgumentError.value(srs, 'srs', 'Must be a non-empty URI.');
    }
    final uri = Uri.tryParse(srs);
    if (uri == null || !uri.hasScheme) {
      throw ArgumentError.value(
        srs,
        'srs',
        'Must be a valid URI with a scheme. Got: "$srs"',
      );
    }

    // location_type: must be non-empty
    if (locationType.isEmpty) {
      throw ArgumentError.value(
        locationType,
        'locationType',
        'Must be a non-empty string.',
      );
    }

    // location: must be non-null
    if (location == null) {
      throw ArgumentError.notNull('location');
    }

    if (validateLocation) {
      LocationValidator.validate(locationType, location);
    }
  }
}
