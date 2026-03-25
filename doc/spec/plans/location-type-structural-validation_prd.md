# Issue: Location Type Structural Validation in `LPPayload` and `LocationSerializer`

**Status:** Open  
**Date:** 2026-03-14  
**Priority:** Medium  
**Area:** `lib/src/lp/lp_payload.dart`, `lib/src/lp/location_serializer.dart`

---

## Problem

`LPPayload._validate()` currently performs only surface-level field checks:

- `locationType` must be a non-empty string — but *any* string is accepted (e.g. `"banana"`)
- `location` must be non-null — but its Dart type is unconstrained and never matched against `locationType`

This means two classes of invalid payload silently pass construction and only fail
later (or silently produce garbled ABI-encoded data):

1. **Unknown location type** — `locationType: 'banana'` is accepted; no guard against
   unregistered identifiers.
2. **Dart type mismatch** — `locationType: 'geojson-point'` with
   `location: [-103.77, 44.96]` (a `List`, not a `Map`) passes construction and
   produces a malformed JSON string downstream.

The LP spec defines 9 location types, each with a required Dart type for its
`location` field. Phase 2 of this feature adds deep structural correctness checks
(e.g. RFC 7946 GeoJSON, H3 index regex, coordinate bounds).

---

## Pipeline Context

```
User provides LPPayload.location as String | List<num> | Map<String, dynamic>
    ↓
Validate: LocationValidator.validate(locationType, location)   ← NEW (this issue)
    ↓
Convert:  normalize to String (jsonEncode for List/Map, passthrough for String)
    ↓
Serialize: the string gets ABI-encoded as the `location` field
```

Validation fires in `LPPayload._validate()` at **construction time**, consistent
with the existing `lpVersion` (semver) and `srs` (URI) checks. Invalid payloads
throw `ArgumentError` before any encoding work is done.

---

## Location Type Registry

The 9 currently registered types from the
[LP spec](https://spec.decentralizedgeo.org/specification/location-types/), with
their expected Dart type and Phase 2 validation rules:

| `locationType`              | Expected Dart type     | Phase 2 validation rule                                                                 |
|-----------------------------|------------------------|------------------------------------------------------------------------------------------|
| `coordinate-decimal+lon-lat`| `List<num>` (length 2) | lon ∈ [−180, 180]; lat ∈ [−90, 90] via `geobase` `Geographic`                          |
| `geojson-point`             | `Map<String, dynamic>` | `type == "Point"`; `coordinates` is a 2–3 element `List<num>` (RFC 7946 §3.1.2)        |
| `geojson-line`              | `Map<String, dynamic>` | `type == "LineString"`; `coordinates` is a `List` of ≥2 positions (RFC 7946 §3.1.4)    |
| `geojson-polygon`           | `Map<String, dynamic>` | `type == "Polygon"`; each ring closes (first == last position) (RFC 7946 §3.1.6)       |
| `h3`                        | `String`               | regex `^[89ab][0-9a-f]{14}$`                                                             |
| `geohash`                   | `String`               | base-32 charset `[0-9b-hjkmnp-z]`; length 1–12                                          |
| `wkt`                       | `String`               | attempt parse via `geobase` `WKT.geometry`; throw on `FormatException`                  |
| `address`                   | `String`               | non-empty string *(deeper validation deferred)*                                          |
| `scaledCoordinates`         | `Map<String, dynamic>` | required keys `x`, `y`, `scale` present *(deeper validation deferred)*                  |

> **Note:** All `geojson-*` types must conform to
> [RFC 7946](https://datatracker.ietf.org/doc/html/rfc7946).

---

## Proposed Solution

### New class: `LocationValidator` (`lib/src/lp/location_validator.dart`)

```dart
class LocationValidator {
  /// The 9 types officially registered in the LP spec.
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

  // Internal dispatch table: locationType → validator function.
  // Phase 1: type-contract checks only.
  // Phase 2: deep structural checks (see below).
  static final Map<String, void Function(dynamic)> _validators = {
    'coordinate-decimal+lon-lat': _validateCoordinateList,
    'geojson-point':              _validateGeoJsonMap,
    'geojson-line':               _validateGeoJsonMap,
    'geojson-polygon':            _validateGeoJsonMap,
    'h3':                         _validateString,
    'geohash':                    _validateString,
    'wkt':                        _validateString,
    'address':                    _validateString,
    'scaledCoordinates':          _validateMap,
  };

  /// Validates [location] against [locationType].
  ///
  /// Phase 1: checks [locationType] is known and [location] has the correct
  /// Dart type. Throws [ArgumentError] on failure.
  static void validate(String locationType, dynamic location) {
    if (!knownLocationTypes.contains(locationType)) {
      final registered = knownLocationTypes.join(', ');
      throw ArgumentError.value(
        locationType,
        'locationType',
        'Unknown location type. Registered types: $registered. '
        'Use LocationValidator.register() to add custom types.',
      );
    }
    _validators[locationType]!(location);
  }

  /// Registers a custom or community location type.
  ///
  /// The [validator] function should throw [ArgumentError] if [location] is
  /// invalid for the given type. Callers are responsible for ensuring
  /// format and value correctness when using custom types.
  ///
  /// Example:
  /// ```dart
  /// LocationValidator.register(
  ///   'community.plus-code.v1',
  ///   (location) {
  ///     if (location is! String || location.isEmpty) {
  ///       throw ArgumentError('plus-code location must be a non-empty String');
  ///     }
  ///   },
  /// );
  /// ```
  static void register(String locationType, void Function(dynamic) validator) {
    _validators[locationType] = validator;
  }

  // --- Phase 1 type-contract helpers ---

  static void _validateCoordinateList(dynamic location) {
    if (location is! List) {
      throw ArgumentError(
        'coordinate-decimal+lon-lat requires a List. Got: ${location.runtimeType}',
      );
    }
  }

  static void _validateGeoJsonMap(dynamic location) {
    if (location is! Map) {
      throw ArgumentError(
        'GeoJSON location types require a Map. Got: ${location.runtimeType}',
      );
    }
  }

  static void _validateString(dynamic location) {
    if (location is! String) {
      throw ArgumentError(
        'This location type requires a String. Got: ${location.runtimeType}',
      );
    }
  }

  static void _validateMap(dynamic location) {
    if (location is! Map) {
      throw ArgumentError(
        'scaledCoordinates requires a Map. Got: ${location.runtimeType}',
      );
    }
  }
}
```

### Changes to `LPPayload._validate()`

Add a call to `LocationValidator.validate()` after the existing `locationType` and
`location` null checks:

```dart
// After the existing checks for locationType and location...
if (validateLocation) {
  LocationValidator.validate(locationType, location);
}
```

`LPPayload` gains an optional flag:

```dart
LPPayload({
  required this.lpVersion,
  required this.srs,
  required this.locationType,
  required this.location,
  this.validateLocation = true,   // ← NEW: set false to bypass location checks
}) { _validate(); }
```

When `validateLocation: false`, all existing field checks (semver, URI) still run;
only the location-type dispatch is skipped. This is intended for callers who own
their data and can guarantee correctness without the overhead.

---

## Phase 2: Deep Structural Validation

Deep structural validation is **deferred** to a follow-on implementation. The
dispatch table architecture means Phase 2 validators slot in as replacements for the
Phase 1 type-contract stubs — no changes to `LPPayload` or the public API.

### External dependency: `geobase ^1.5.0`

[`geobase`](https://pub.dev/packages/geobase) (BSD-3-Clause, pure Dart, actively
maintained) provides RFC 7946-compliant GeoJSON parsing and WKT parsing. Parsing
throws `FormatException` on invalid input, making it directly usable as a
validator.

```yaml
# pubspec.yaml
dependencies:
  geobase: ^1.5.0
```

**No additional dependency is needed** for H3 or geohash — those are simple
regex / character-set checks.

### Phase 2 validator stubs (per type)

| Type | Implementation approach |
|------|------------------------|
| `coordinate-decimal+lon-lat` | Length == 2; cast to `List<num>`; lon ∈ [−180, 180]; lat ∈ [−90, 90] using `geobase` `Geographic(lon, lat)` bounds check |
| `geojson-point` | `Point.parse(jsonEncode(location), format: GeoJSON.geometry)` — throws `FormatException` on failure |
| `geojson-line` | `LineString.parse(jsonEncode(location), format: GeoJSON.geometry)` |
| `geojson-polygon` | `Polygon.parse(jsonEncode(location), format: GeoJSON.geometry)` |
| `h3` | Regex `^[89ab][0-9a-f]{14}$` |
| `geohash` | Regex `^[0-9b-hjkmnp-z]{1,12}$` |
| `wkt` | Attempt `WKT.geometry` parse via `geobase`; catch `FormatException` |
| `address` | Non-empty string; no deeper spec defined yet |
| `scaledCoordinates` | Required keys `x`, `y`, `scale` present and numeric |

`FormatException` from `geobase` parsers should be caught and re-thrown as
`ArgumentError` to keep the library's error surface consistent.

---

## Impact on Existing Code

| Component | Change | Breaking? |
|-----------|--------|-----------|
| `LPPayload` | New `validateLocation` param (default `true`) | ❌ No — additive |
| `LPPayload._validate()` | Calls `LocationValidator.validate()` | ⚠️ Yes — previously accepted unknown types |
| `LocationSerializer` | No change | ❌ No |
| pubspec.yaml (Phase 2) | Add `geobase ^1.5.0` | ❌ No |

The breaking change is intentional: payloads constructed with unrecognised
`locationType` values will now throw. Callers using valid registered types are
unaffected. Callers using custom types must call `LocationValidator.register()`
before constructing payloads.

---

## Test Plan

### New file: `test/lp/location_validator_test.dart`

- **Known types accepted**: all 9 known types with correct Dart types construct without error
- **Unknown type rejected**: `'banana'`, `'community.foo.v1'` (before registration) throw `ArgumentError`
- **Type contract violations**: `geojson-point` + `List` throws; `h3` + `Map` throws; `coordinate-decimal+lon-lat` + `String` throws
- **Custom registration**: `register('community.plus-code.v1', ...)` then construct succeeds
- **Phase 2** (after `geobase` integration): GeoJSON geometry parse failures, H3 regex, coordinate bounds

### Additions to lp_payload_test.dart

- `LPPayload(locationType: 'banana', ...)` throws `ArgumentError`
- `LPPayload(locationType: 'geojson-point', location: [-103.77, 44.96], ...)` throws (List, not Map)
- `LPPayload(..., validateLocation: false)` with unknown type constructs without error

---

## Related

- [LP Spec — Location Types](https://spec.decentralizedgeo.org/specification/location-types/)
- [RFC 7946 — GeoJSON](https://datatracker.ietf.org/doc/html/rfc7946)
- [`geobase` on pub.dev](https://pub.dev/packages/geobase)
- lp_payload.dart — `LPPayload._validate()`
- location_serializer.dart — `LocationSerializer.serialize()`
- lp_payload_test.dart
- location_serializer_test.dart
