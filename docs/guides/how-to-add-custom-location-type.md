# How to register a custom location type

This guide shows how to extend `LocationValidator` with a custom location type
for application-specific formats not in the
[LP Location Types Registry](https://spec.decentralizedgeo.org/specification/location-types/).
It assumes basic familiarity with the library.

---

## Step 1 — Register a custom validator

```dart
import 'package:location_protocol/location_protocol.dart';

// Register a custom location type called 'plus-code'
// A Google Plus Code looks like '8FW4V75V+8Q'
LocationValidator.register('plus-code', (location) {
  if (location is! String) {
    throw ArgumentError('plus-code location must be a String, got ${location.runtimeType}');
  }
  // Plus codes: 8 chars + '+' + 2+ chars, base-20 charset
  final plusCodeRegex = RegExp(r'^[23456789CFGHJMPQRVWX]{8}\+[23456789CFGHJMPQRVWX]{2,}$');
  if (!plusCodeRegex.hasMatch(location.toUpperCase())) {
    throw ArgumentError('Invalid plus-code format: $location');
  }
});
```

The second argument to `register()` is a validator function. If the location
data is valid, return normally. If invalid, throw an `ArgumentError` with a
descriptive message. The library catches this and surfaces it from `LPPayload`
construction.

---

## Step 2 — Use the custom type in an LP payload

```dart
final lpPayload = LPPayload(
  lpVersion: '1.0.0',
  srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
  locationType: 'plus-code',
  location: '8FW4V75V+8Q',
);
// Succeeds — custom validator is called and passes
```

---

## Constraints

**Built-in types cannot be overridden.** Attempting to register a validator for
a built-in type (e.g., `'geojson-point'`, `'h3'`, `'address'`) throws an
`ArgumentError` immediately:

```dart
// Throws: Invalid argument (locationType): Cannot override built-in location type.: geojson-point
LocationValidator.register('geojson-point', (location) { ... });
```

The full list of protected built-in types:

- `geojson-point`, `geojson-line`, `geojson-polygon`
- `h3`, `geohash`, `wkt`
- `address`, `coordinate-decimal+lon-lat`, `scaledCoordinates`

**`resetCustomTypes()` is for tests only.** It clears all custom registrations
and should only be called in test `tearDown()` blocks. Calling it in application
code will silently remove validators that other parts of your app depend on.

```dart
// In your test file:
tearDown(() => LocationValidator.resetCustomTypes());
```

---

## What's next

- [API reference — LocationValidator](reference-api.md#locationvalidator)
- [Concepts: Location types and validation extensibility](explanation-concepts.md#6-location-types-and-validation-extensibility)
- [LP Location Types Registry](https://spec.decentralizedgeo.org/specification/location-types/)
