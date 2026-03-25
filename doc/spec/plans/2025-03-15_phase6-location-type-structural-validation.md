# Phase 6 Implementation Plan: Location Type Structural Validation

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic structural validation to `LPPayload` so `location` matches its declared `locationType`, while preserving migration safety and existing LP/EAS architecture.

**Architecture:** A new `LocationValidator` class validates `locationType` + `location` pairs at `LPPayload` construction time. It is built and tested in isolation first, then downstream test fixtures are migrated to canonical shapes, and finally the validator is wired into `LPPayload._validate()` behind a `validateLocation` flag. Deep structural checks (regex, parser, bounds) follow in Phase 6B using `geobase`.

**Tech Stack:** Dart 3.11+, `test` package, `geobase ^1.5.0` (Phase 6B only), existing `LPPayload`/`AbiEncoder`/`OffchainSigner`/`EASClient`.

---

## Table of Contents

- [Scope and Non-Goals](#scope-and-non-goals)
- [Locked Decisions](#locked-decisions)
- [File Plan](#file-plan)
- [Phase 6A — Contract Validation (9 tasks)](#phase-6a--contract-validation-9-tasks)
- [Phase 6C — Migration: Fix Downstream Fixtures (5 tasks)](#phase-6c--migration-fix-downstream-fixtures-5-tasks)
- [Phase 6A-Wire — Integrate into LPPayload (3 tasks)](#phase-6a-wire--integrate-into-lppayload-3-tasks)
- [Phase 6B — Deep Structural Validation (11 tasks)](#phase-6b--deep-structural-validation-11-tasks)
- [Phase 6D — Verification and Quality Gates (7 tasks)](#phase-6d--verification-and-quality-gates-7-tasks)
- [Phase 6E — Memory Consolidation and Walkthrough (4 tasks)](#phase-6e--memory-consolidation-and-walkthrough-4-tasks)
- [Compact Verification Commands](#compact-verification-commands)

**Total tasks:** 39

---

## Scope and Non-Goals

**In scope:**
- Registered location type validation (9 canonical types).
- Location Dart-type shape checks by `locationType`.
- Deep structural validation (regex, parser, bounds) for canonical types.
- Custom type registration with override prevention.
- `validateLocation` bypass flag as temporary migration aid.
- Normalize all validation failures to `ArgumentError`.

**Non-goals (explicit):**
- No changes to `LocationSerializer` behavior (`lib/src/lp/location_serializer.dart`).
- No ABI format changes in `lib/src/eas/abi_encoder.dart`.
- No schema-model expansion in `lib/src/schema/`.
- No onchain protocol changes.

---

## Locked Decisions

- PRD source: `doc/spec/plans/location-type-structural-validation_prd.md`.
- Task order: build validator in isolation → migrate fixtures → wire into `LPPayload` → deep checks. This prevents cascade breakage.
- Built-in types cannot be overridden via `register()`.
- Duplicate custom registration replaces the prior validator (last-write-wins).
- `validateLocation` is a temporary migration escape hatch, not a permanent API.
- Phase 6B is gated behind a `geobase` API spike.

---

## File Plan

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/src/lp/location_validator.dart` | Validator class with registry, dispatch, shape checks |
| Create | `test/lp/location_validator_test.dart` | All validator unit tests |
| Modify | `lib/src/lp/lp_payload.dart` | Add `validateLocation` param, call validator |
| Modify | `lib/location_protocol.dart` | Export `LocationValidator` |
| Modify | `test/lp/lp_payload_test.dart` | Add integration tests for wired validation |
| Modify | `test/eas/abi_encoder_test.dart` | Fix invalid fixtures |
| Modify | `test/eas/onchain_client_test.dart` | Fix invalid fixtures |
| Modify | `test/integration/sepolia_onchain_test.dart` | Fix invalid fixture |
| Modify | `pubspec.yaml` | Add `geobase` dependency (Phase 6B) |
| Modify | `.ai/memory/semantic.md` | Record learnings |
| Modify | `.ai/memory/procedural.md` | Record patterns |
| Modify | `doc/walkthrough.md` | Document validation behavior |

---

## Phase 6A — Contract Validation (9 tasks)

### Task 6A.1: Write failing tests for unknown type rejection

**Files:**
- Create: `test/lp/location_validator_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
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
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL — `location_validator.dart` does not exist yet.

- [ ] **Step 3: Commit**

```powershell
git add test/lp/location_validator_test.dart
git commit -m "test(lp): add failing tests for unknown location type rejection"
```

---

### Task 6A.2: Implement `LocationValidator` skeleton with unknown-type rejection

**Files:**
- Create: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write minimal implementation**

```dart
/// Validates that a location value matches its declared location type.
///
/// Phase 6A: type-contract checks (known type + correct Dart shape).
/// Phase 6B: deep structural checks (regex, parser, bounds).
class LocationValidator {
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

  /// Validators for built-in types. Populated in later tasks.
  static final Map<String, void Function(dynamic)> _builtInValidators = {};

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
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: PASS — both unknown-type tests pass.

- [ ] **Step 3: Commit**

```powershell
git add lib/src/lp/location_validator.dart
git commit -m "feat(lp): add LocationValidator skeleton with unknown-type rejection"
```

---

### Task 6A.3: Write failing shape-mismatch tests + implement shape validators

**Files:**
- Modify: `test/lp/location_validator_test.dart`
- Modify: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write the failing tests**

Add these groups after the `unknown type rejection` group in `test/lp/location_validator_test.dart`:

```dart
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
    });

    group('type-shape contract: Map types', () {
      test('geojson-point accepts Map', () {
        expect(
          () => LocationValidator.validate('geojson-point',
              {'type': 'Point', 'coordinates': [-103.77, 44.96]}),
          returnsNormally,
        );
      });

      test('geojson-point rejects List', () {
        expect(
          () => LocationValidator.validate(
              'geojson-point', [-103.77, 44.96]),
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
            'coordinates': [[-103.77, 44.96], [-103.78, 44.97]],
          }),
          returnsNormally,
        );
      });

      test('geojson-polygon accepts Map', () {
        expect(
          () => LocationValidator.validate('geojson-polygon', {
            'type': 'Polygon',
            'coordinates': [[
              [-104.0, 45.0], [-103.0, 45.0],
              [-103.0, 44.0], [-104.0, 45.0],
            ]],
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL — built-in validators map is empty, so known types throw `Unknown location type`.

- [ ] **Step 3: Write minimal implementation**

Replace the `_builtInValidators` initialization in `lib/src/lp/location_validator.dart`:

```dart
  static final Map<String, void Function(dynamic)> _builtInValidators = {
    'coordinate-decimal+lon-lat': _validateCoordinateList,
    'geojson-point': _validateGeoJsonMap,
    'geojson-line': _validateGeoJsonMap,
    'geojson-polygon': _validateGeoJsonMap,
    'h3': _validateString,
    'geohash': _validateString,
    'wkt': _validateString,
    'address': _validateString,
    'scaledCoordinates': _validateMap,
  };
```

Add these private helpers at the bottom of the class:

```dart
  static void _validateCoordinateList(dynamic location) {
    if (location is! List) {
      throw ArgumentError(
        'coordinate-decimal+lon-lat requires a List. '
        'Got: ${location.runtimeType}',
      );
    }
  }

  static void _validateGeoJsonMap(dynamic location) {
    if (location is! Map) {
      throw ArgumentError(
        'GeoJSON location types require a Map. '
        'Got: ${location.runtimeType}',
      );
    }
  }

  static void _validateString(dynamic location) {
    if (location is! String) {
      throw ArgumentError(
        'This location type requires a String. '
        'Got: ${location.runtimeType}',
      );
    }
  }

  static void _validateMap(dynamic location) {
    if (location is! Map) {
      throw ArgumentError(
        'scaledCoordinates requires a Map. '
        'Got: ${location.runtimeType}',
      );
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/lp/location_validator.dart test/lp/location_validator_test.dart
git commit -m "feat(lp): add shape validators for all canonical location types"
```

---

### Task 6A.4: Add coordinate list arity check

**Files:**
- Modify: `test/lp/location_validator_test.dart`
- Modify: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write the failing test**

Add inside the `type-shape contract: List types` group:

```dart
      test('coordinate-decimal+lon-lat rejects empty list', () {
        expect(
          () => LocationValidator.validate('coordinate-decimal+lon-lat', []),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message, 'message', contains('exactly 2 elements'),
            ),
          ),
        );
      });

      test('coordinate-decimal+lon-lat rejects 1-element list', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', [-103.77]),
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL — arity not checked yet, empty/short/long lists pass.

- [ ] **Step 3: Write minimal implementation**

Update `_validateCoordinateList` in `lib/src/lp/location_validator.dart`:

```dart
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
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/lp/location_validator.dart test/lp/location_validator_test.dart
git commit -m "feat(lp): enforce coordinate list arity (exactly 2)"
```

---

### Task 6A.5: Add `scaledCoordinates` required key check

**Files:**
- Modify: `test/lp/location_validator_test.dart`
- Modify: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write the failing test**

Add inside the `type-shape contract: Map types` group:

```dart
      test('scaledCoordinates rejects Map missing x', () {
        expect(
          () => LocationValidator.validate(
              'scaledCoordinates', {'y': 200, 'scale': 1000}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message, 'message', contains('requires key "x"'),
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
          () => LocationValidator.validate(
              'scaledCoordinates', {'x': 100, 'y': 200}),
          throwsA(isA<ArgumentError>()),
        );
      });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL — key checks not implemented.

- [ ] **Step 3: Write minimal implementation**

Replace `_validateMap` with `_validateScaledCoordinatesMap` in `lib/src/lp/location_validator.dart`:

```dart
  static void _validateScaledCoordinatesMap(dynamic location) {
    if (location is! Map) {
      throw ArgumentError(
        'scaledCoordinates requires a Map. '
        'Got: ${location.runtimeType}',
      );
    }
    for (final key in ['x', 'y', 'scale']) {
      if (!location.containsKey(key)) {
        throw ArgumentError(
          'scaledCoordinates requires key "$key".',
        );
      }
    }
  }
```

Update the dispatch table entry to reference the renamed method:

```dart
    'scaledCoordinates': _validateScaledCoordinatesMap,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/lp/location_validator.dart test/lp/location_validator_test.dart
git commit -m "feat(lp): enforce scaledCoordinates required key presence"
```

---

### Task 6A.6: Add custom type registration + override prevention + test reset

**Files:**
- Modify: `test/lp/location_validator_test.dart`
- Modify: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write the failing tests**

Add a new top-level group in `test/lp/location_validator_test.dart`:

```dart
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
          () => LocationValidator.validate(
              'community.plus-code.v1', '849VCWC8+R9'),
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL — `register()` and `resetCustomTypes()` do not exist.

- [ ] **Step 3: Write minimal implementation**

Add these methods to `LocationValidator` in `lib/src/lp/location_validator.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/lp/location_validator.dart test/lp/location_validator_test.dart
git commit -m "feat(lp): add custom type registration with override prevention and test reset"
```

---

### Task 6A.7: Export `LocationValidator` from package barrel

**Files:**
- Modify: `lib/location_protocol.dart`

- [ ] **Step 1: Add the export**

Add after the existing LP layer exports:

```dart
export 'src/lp/location_validator.dart';
```

- [ ] **Step 2: Run test to verify nothing is broken**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 3: Commit**

```powershell
git add lib/location_protocol.dart
git commit -m "chore(api): export LocationValidator from package barrel"
```

---

## Phase 6C — Migration: Fix Downstream Fixtures (5 tasks)

> **Why this comes before wiring:** Once `LocationValidator` is called from `LPPayload._validate()`, every test that constructs an `LPPayload` with non-canonical fixtures will break. Fix fixtures first so the wiring step is clean.

### Task 6C.1: Inventory broken fixtures

The following tests construct `LPPayload` with invalid location type/shape combinations under strict rules:

| File | Location Type | Location Value | Problem |
|------|--------------|----------------|---------|
| `test/eas/abi_encoder_test.dart` (deterministic test) | `geojson-point` | `'{"type":"Point",...}'` (String) | String, not Map |
| `test/eas/abi_encoder_test.dart` (missing field test) | `geojson-point` | `'test'` (String) | String, not Map |
| `test/eas/abi_encoder_test.dart` (wrong key test) | `geojson-point` | `'test'` (String) | String, not Map |
| `test/eas/abi_encoder_test.dart` (hex test) | `point` | `'0,0'` | Unknown type |
| `test/eas/onchain_client_test.dart` (all 4 tests) | `geojson-point` | `'test-location'` (String) | String, not Map |
| `test/integration/sepolia_onchain_test.dart` (attest test) | `geojson-point` | `'test-location-...'` (String) | String, not Map |

Tests NOT broken (already valid):
- `test/eas/offchain_signer_test.dart` — uses Map location with `geojson-point` ✓
- `test/integration/full_workflow_test.dart` — uses Map location or valid String types ✓
- `test/lp/lp_payload_test.dart` — existing tests will need additions, not fixture fixes ✓

- [ ] **Commit intent:** not needed, this is a reference inventory.

---

### Task 6C.2: Fix `abi_encoder_test.dart` fixtures

**Files:**
- Modify: `test/eas/abi_encoder_test.dart`

- [ ] **Step 1: Update fixtures**

In the `deterministic` test (~line 69), the location is a pre-serialized JSON string. This test is verifying ABI encoding determinism, not LP validation. Change to use a valid Map:

```dart
    test('deterministic — same inputs produce same output', () {
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {'type': 'Point', 'coordinates': [-103.771556, 44.967243]},
      );
```

In the `throws if user data key does not match` test (~line 89), change location to a valid type/shape:

```dart
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'h3',
        location: '8928308280fffff',
      );
```

In the `throws if user data is missing` test (~line 106), same fix:

```dart
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'h3',
        location: '8928308280fffff',
      );
```

In the `hex strings` test (~line 143), change from unknown type `point` to valid `address`:

```dart
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'address',
        location: '0,0',
      );
```

- [ ] **Step 2: Run tests to verify nothing is broken yet** (validator not wired)

Run: `dart test test/eas/abi_encoder_test.dart -r expanded`
Expected: ALL PASS — fixtures are valid and validator is not yet called.

- [ ] **Step 3: Commit**

```powershell
git add test/eas/abi_encoder_test.dart
git commit -m "test(eas): update abi encoder fixtures to canonical location types"
```

---

### Task 6C.3: Fix `onchain_client_test.dart` fixtures

**Files:**
- Modify: `test/eas/onchain_client_test.dart`

- [ ] **Step 1: Update fixtures**

All four `LPPayload` constructions in this file use `locationType: 'geojson-point'` with `location: 'test-location'`. These tests are testing EAS client behavior, not LP validation. Change all to use `address` type (which accepts strings):

Every occurrence of:
```dart
        locationType: 'geojson-point',
        location: 'test-location',
```

Replace with:
```dart
        locationType: 'address',
        location: 'test-location',
```

- [ ] **Step 2: Run tests**

Run: `dart test test/eas/onchain_client_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 3: Commit**

```powershell
git add test/eas/onchain_client_test.dart
git commit -m "test(eas): update onchain client fixtures to canonical location types"
```

---

### Task 6C.4: Fix `sepolia_onchain_test.dart` fixture

**Files:**
- Modify: `test/integration/sepolia_onchain_test.dart`

- [ ] **Step 1: Update fixture**

The attest test (~line 69) uses `locationType: 'geojson-point'` with a dynamically generated string location. Change to `address` to preserve the dynamic uniqueness while being type-valid:

```dart
      final submittedPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'address',
        location: 'test-location-${DateTime.now().millisecondsSinceEpoch}',
      );
```

- [ ] **Step 2: Run non-network tests to verify compile**

Run: `dart test test/integration/sepolia_onchain_test.dart -r expanded`
Expected: Tests skip (no env vars in CI) or PASS if env configured.

- [ ] **Step 3: Commit**

```powershell
git add test/integration/sepolia_onchain_test.dart
git commit -m "test(integration): update sepolia fixture to canonical address type"
```

---

### Task 6C.5: Verify serializer tests remain unaffected

**Files:**
- Check: `test/lp/location_serializer_test.dart`

- [ ] **Step 1: Run serializer tests to confirm no drift**

Run: `dart test test/lp/location_serializer_test.dart -r expanded`
Expected: ALL PASS — serializer is not touched by Phase 6.

- [ ] **Step 2: Commit** (no changes expected — verification only)

---

## Phase 6A-Wire — Integrate into LPPayload (3 tasks)

### Task 6A-Wire.1: Write failing `LPPayload` integration tests

**Files:**
- Modify: `test/lp/lp_payload_test.dart`

- [ ] **Step 1: Write the failing tests**

Add these new groups inside the `LPPayload` group in `test/lp/lp_payload_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/lp_payload_test.dart -r expanded`
Expected: FAIL — `validateLocation` parameter does not exist; unknown type `banana` is currently accepted.

- [ ] **Step 3: Commit**

```powershell
git add test/lp/lp_payload_test.dart
git commit -m "test(lp): add failing LPPayload strict validation + bypass tests"
```

---

### Task 6A-Wire.2: Wire `LocationValidator` into `LPPayload`

**Files:**
- Modify: `lib/src/lp/lp_payload.dart`

- [ ] **Step 1: Write minimal implementation**

Add import at top of `lib/src/lp/lp_payload.dart`:

```dart
import 'package:location_protocol/src/lp/location_validator.dart';
```

Update the constructor to accept `validateLocation`:

```dart
  /// Whether to validate location type and shape at construction.
  ///
  /// Defaults to `true`. Set to `false` only as a temporary migration aid
  /// for callers that guarantee their own data correctness.
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
```

Add the validator call at the end of `_validate()`, after the existing `location == null` check:

```dart
    // location type + shape: must match registered type contract
    if (validateLocation) {
      LocationValidator.validate(locationType, location);
    }
```

- [ ] **Step 2: Run test to verify it passes**

Run: `dart test test/lp/lp_payload_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 3: Commit**

```powershell
git add lib/src/lp/lp_payload.dart
git commit -m "feat(lp): wire LocationValidator into LPPayload with validateLocation flag"
```

---

### Task 6A-Wire.3: Run full regression to verify no cascade breakage

- [ ] **Step 1: Run all non-Sepolia tests**

Run: `dart test --exclude-tags sepolia --exclude-tags sepolia-bootstrap -r expanded`
Expected: ALL PASS — fixtures were migrated in Phase 6C, validator is wired.

- [ ] **Step 2: Run static analysis**

Run: `dart analyze`
Expected: No new warnings or errors.

- [ ] **Step 3: Commit** (no changes — verification gate)

---

## Phase 6B — Deep Structural Validation (11 tasks)

### Task 6B.1: Geobase API spike (blocking gate)

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add geobase dependency**

Add to `dependencies` in `pubspec.yaml`:

```yaml
  geobase: ^1.5.0
```

- [ ] **Step 2: Install**

Run: `dart pub get`
Expected: Resolves without conflict.

- [ ] **Step 3: Write spike test to verify parser APIs**

Create `test/lp/location_validator_geobase_spike_test.dart`:

```dart
import 'dart:convert';
import 'package:test/test.dart';
import 'package:geobase/geobase.dart';

void main() {
  group('geobase API spike', () {
    test('parses valid GeoJSON Point', () {
      final json = {'type': 'Point', 'coordinates': [-103.77, 44.96]};
      final point = Point.parse(jsonEncode(json), format: GeoJSON.geometry);
      expect(point, isNotNull);
    });

    test('rejects invalid GeoJSON Point', () {
      final json = {'type': 'Point', 'coordinates': 'not-a-list'};
      expect(
        () => Point.parse(jsonEncode(json), format: GeoJSON.geometry),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses valid GeoJSON LineString', () {
      final json = {
        'type': 'LineString',
        'coordinates': [[-103.77, 44.96], [-103.78, 44.97]],
      };
      final line =
          LineString.parse(jsonEncode(json), format: GeoJSON.geometry);
      expect(line, isNotNull);
    });

    test('parses valid GeoJSON Polygon', () {
      final json = {
        'type': 'Polygon',
        'coordinates': [[
          [-104.0, 45.0], [-103.0, 45.0],
          [-103.0, 44.0], [-104.0, 45.0],
        ]],
      };
      final polygon =
          Polygon.parse(jsonEncode(json), format: GeoJSON.geometry);
      expect(polygon, isNotNull);
    });

    test('parses valid WKT', () {
      final geom = Geometry.parse('POINT(-103.77 44.96)', format: WKT.geometry);
      expect(geom, isNotNull);
    });

    test('rejects invalid WKT', () {
      expect(
        () => Geometry.parse('NOT_WKT()', format: WKT.geometry),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
```

- [ ] **Step 4: Run spike tests**

Run: `dart test test/lp/location_validator_geobase_spike_test.dart -r expanded`
Expected: ALL PASS. If any fail, **STOP** — update parser API assumptions before proceeding.

- [ ] **Step 5: Commit**

```powershell
git add pubspec.yaml pubspec.lock test/lp/location_validator_geobase_spike_test.dart
git commit -m "chore(lp): add geobase dependency and validate parser API assumptions"
```

---

### Task 6B.2: Add coordinate bounds validation

**Files:**
- Modify: `test/lp/location_validator_test.dart`
- Modify: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write the failing tests**

Add a new group in `test/lp/location_validator_test.dart`:

```dart
    group('deep: coordinate-decimal+lon-lat bounds', () {
      test('rejects lon < -180', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', [-181.0, 44.96]),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message, 'message', contains('Longitude'),
            ),
          ),
        );
      });

      test('rejects lon > 180', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', [181.0, 44.96]),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects lat < -90', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', [-103.77, -91.0]),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message, 'message', contains('Latitude'),
            ),
          ),
        );
      });

      test('rejects lat > 90', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', [-103.77, 91.0]),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects non-numeric elements', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', ['abc', 44.96]),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('accepts boundary values (-180, -90)', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', [-180.0, -90.0]),
          returnsNormally,
        );
      });

      test('accepts boundary values (180, 90)', () {
        expect(
          () => LocationValidator.validate(
              'coordinate-decimal+lon-lat', [180.0, 90.0]),
          returnsNormally,
        );
      });
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL — bounds not checked yet.

- [ ] **Step 3: Write minimal implementation**

Update `_validateCoordinateList` in `lib/src/lp/location_validator.dart`:

```dart
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
      throw ArgumentError(
        'Longitude must be in [-180, 180]. Got: $lon',
      );
    }
    if (lat < -90 || lat > 90) {
      throw ArgumentError(
        'Latitude must be in [-90, 90]. Got: $lat',
      );
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/lp/location_validator.dart test/lp/location_validator_test.dart
git commit -m "feat(lp): add coordinate lon-lat bounds and numeric validation"
```

---

### Task 6B.3: Add GeoJSON point structural validation

**Files:**
- Modify: `test/lp/location_validator_test.dart`
- Modify: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write the failing tests**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL — currently only checks `is Map`.

- [ ] **Step 3: Write minimal implementation**

Add import at top of `lib/src/lp/location_validator.dart`:

```dart
import 'dart:convert';
import 'package:geobase/geobase.dart';
```

Replace `_validateGeoJsonMap` and add per-geometry validators:

```dart
  static void _validateGeoJsonPoint(dynamic location) {
    if (location is! Map) {
      throw ArgumentError(
        'GeoJSON location types require a Map. '
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
        'GeoJSON location types require a Map. '
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
        'GeoJSON location types require a Map. '
        'Got: ${location.runtimeType}',
      );
    }
    try {
      Polygon.parse(jsonEncode(location), format: GeoJSON.geometry);
    } on FormatException catch (e) {
      throw ArgumentError('Invalid GeoJSON Polygon: ${e.message}');
    }
  }
```

Update the dispatch table:

```dart
    'geojson-point': _validateGeoJsonPoint,
    'geojson-line': _validateGeoJsonLine,
    'geojson-polygon': _validateGeoJsonPolygon,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/lp/location_validator.dart test/lp/location_validator_test.dart
git commit -m "feat(lp): add GeoJSON point structural validation via geobase"
```

---

### Task 6B.4: Add GeoJSON line + polygon structural tests

**Files:**
- Modify: `test/lp/location_validator_test.dart`

- [ ] **Step 1: Write the tests**

```dart
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
            'coordinates': [[-103.77, 44.96], [-103.78, 44.97]],
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
            'coordinates': [[
              [-104.0, 45.0], [-103.0, 45.0],
              [-103.0, 44.0], [-104.0, 45.0],
            ]],
          }),
          returnsNormally,
        );
      });
    });
```

- [ ] **Step 2: Run test to verify it passes** (implementation already done in 6B.3)

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 3: Commit**

```powershell
git add test/lp/location_validator_test.dart
git commit -m "test(lp): add GeoJSON line and polygon structural tests"
```

---

### Task 6B.5: Add H3 regex validation

**Files:**
- Modify: `test/lp/location_validator_test.dart`
- Modify: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write the failing tests**

```dart
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
              (e) => e.message, 'message', contains('Invalid H3'),
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL — H3 currently only checks `is String`.

- [ ] **Step 3: Write minimal implementation**

Add regex constant and update validator in `lib/src/lp/location_validator.dart`:

```dart
  static final RegExp _h3Pattern = RegExp(r'^[89ab][0-9a-f]{14}$');

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
```

Update dispatch table: `'h3': _validateH3,`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/lp/location_validator.dart test/lp/location_validator_test.dart
git commit -m "feat(lp): add H3 regex validation"
```

---

### Task 6B.6: Add geohash regex validation

**Files:**
- Modify: `test/lp/location_validator_test.dart`
- Modify: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write the failing tests**

```dart
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
              (e) => e.message, 'message', contains('Invalid geohash'),
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

```dart
  static final RegExp _geohashPattern = RegExp(r'^[0-9b-hjkmnp-z]{1,12}$');

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
```

Update dispatch table: `'geohash': _validateGeohash,`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/lp/location_validator.dart test/lp/location_validator_test.dart
git commit -m "feat(lp): add geohash regex validation"
```

---

### Task 6B.7: Add WKT parser validation

**Files:**
- Modify: `test/lp/location_validator_test.dart`
- Modify: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write the failing tests**

```dart
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
              (e) => e.message, 'message', contains('Invalid WKT'),
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

```dart
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
      Geometry.parse(location, format: WKT.geometry);
    } on FormatException catch (e) {
      throw ArgumentError('Invalid WKT: ${e.message}');
    }
  }
```

Update dispatch table: `'wkt': _validateWkt,`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/lp/location_validator.dart test/lp/location_validator_test.dart
git commit -m "feat(lp): add WKT parser validation via geobase"
```

---

### Task 6B.8: Add address deep validation (trimmed non-empty)

**Files:**
- Modify: `test/lp/location_validator_test.dart`
- Modify: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write the failing tests**

```dart
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
              (e) => e.message, 'message', contains('non-empty'),
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL — whitespace/empty not rejected.

- [ ] **Step 3: Write minimal implementation**

```dart
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
```

Update dispatch table: `'address': _validateAddress,`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/lp/location_validator.dart test/lp/location_validator_test.dart
git commit -m "feat(lp): add address trimmed non-empty validation"
```

---

### Task 6B.9: Add `scaledCoordinates` numeric value validation

**Files:**
- Modify: `test/lp/location_validator_test.dart`
- Modify: `lib/src/lp/location_validator.dart`

- [ ] **Step 1: Write the failing tests**

```dart
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
              (e) => e.message, 'message', contains('must be num'),
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: FAIL — numeric checks not implemented.

- [ ] **Step 3: Write minimal implementation**

Update `_validateScaledCoordinatesMap`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/lp/location_validator_test.dart -r expanded`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/lp/location_validator.dart test/lp/location_validator_test.dart
git commit -m "feat(lp): add scaledCoordinates numeric value validation"
```

---

### Task 6B.10: Remove temporary geobase spike file

**Files:**
- Delete: `test/lp/location_validator_geobase_spike_test.dart`

- [ ] **Step 1: Verify all spike coverage is in permanent tests**

The GeoJSON and WKT parsing paths are now covered by Tasks 6B.3-6B.7. The spike file is redundant.

- [ ] **Step 2: Delete spike file**

Run: `Remove-Item test/lp/location_validator_geobase_spike_test.dart`

- [ ] **Step 3: Run all LP tests**

Run: `dart test test/lp/ -r expanded`
Expected: ALL PASS.

- [ ] **Step 4: Commit**

```powershell
git add -A
git commit -m "test(lp): remove redundant geobase spike tests"
```

---

### Task 6B.11: Full regression after deep validation

- [ ] **Step 1: Run all non-Sepolia tests**

Run: `dart test --exclude-tags sepolia --exclude-tags sepolia-bootstrap -r expanded`
Expected: ALL PASS.

- [ ] **Step 2: Run static analysis**

Run: `dart analyze`
Expected: No new warnings.

- [ ] **Step 3: Commit** (verification gate — no changes)

---

## Phase 6D — Verification and Quality Gates (7 tasks)

### Task 6D.1: LP unit test gate

- [ ] Run: `dart test test/lp/lp_payload_test.dart test/lp/location_serializer_test.dart test/lp/location_validator_test.dart -r expanded`
- [ ] Confirm: all pass, no flaky ordering from registry state.

### Task 6D.2: EAS unit test gate

- [ ] Run: `dart test test/eas/abi_encoder_test.dart test/eas/offchain_signer_test.dart test/eas/onchain_client_test.dart -r expanded`
- [ ] Confirm: all pass with migrated fixtures.

### Task 6D.3: Integration gate (non-Sepolia)

- [ ] Run: `dart test test/integration/full_workflow_test.dart test/integration/onchain_workflow_test.dart -r expanded`
- [ ] Confirm: pass.

### Task 6D.4: Integration gate (Sepolia)

- [ ] Run: `dart test test/integration/sepolia_onchain_test.dart --tags sepolia -r expanded`
- [ ] Confirm: pass with migrated `address` fixture.

### Task 6D.5: Full regression (no network tags)

- [ ] Run: `dart test --exclude-tags sepolia --exclude-tags sepolia-bootstrap -r expanded`
- [ ] Confirm: zero warnings introduced by Phase 6.

### Task 6D.6: Static analysis gate

- [ ] Run: `dart analyze`
- [ ] Confirm: no new warnings or errors.

### Task 6D.7: Root-cause assurance

- [ ] Verify: invalid payloads fail at `LPPayload` constructor, not in serializer or encoder.
- [ ] Verify: all validation errors are `ArgumentError`.
- [ ] Verify: no global-state leakage in tests (use `resetCustomTypes()` in tearDown).

---

## Phase 6E — Memory Consolidation and Walkthrough (4 tasks)

### Task 6E.1: Update semantic memory

**Files:**
- Modify: `.ai/memory/semantic.md`

- [ ] **Step 1: Append to semantic.md**

```markdown
### Phase 6 Location Type Structural Validation
- **LocationValidator**: Static class in `lib/src/lp/location_validator.dart` that validates `location` against `locationType` at `LPPayload` construction time.
- **Canonical types**: 9 built-in types — `coordinate-decimal+lon-lat` (List[2]), `geojson-point`/`geojson-line`/`geojson-polygon` (Map, parsed via geobase), `h3` (String, regex `^[89ab][0-9a-f]{14}$`), `geohash` (String, regex `^[0-9b-hjkmnp-z]{1,12}$`), `wkt` (String, parsed via geobase), `address` (String, trimmed non-empty), `scaledCoordinates` (Map with numeric `x`, `y`, `scale`).
- **Error contract**: All validation failures throw `ArgumentError`. Custom validators that throw other types get their errors passed through as-is.
- **Registration rules**: Built-in types cannot be overridden. Custom types registered via `LocationValidator.register()` use last-write-wins for duplicates.
- **validateLocation flag**: Temporary migration aid on `LPPayload` constructor, defaults to `true`. Skips only location dispatch; semver/URI/null checks still run.
```

- [ ] **Step 2: Commit**

```powershell
git add .ai/memory/semantic.md
git commit -m "docs(memory): record phase 6 validation semantics"
```

---

### Task 6E.2: Update procedural memory

**Files:**
- Modify: `.ai/memory/procedural.md`

- [ ] **Step 1: Append to procedural.md**

```markdown
### Phase 6 Validation Patterns
- **Build-then-wire strategy**: Build and test `LocationValidator` in isolation → migrate downstream fixtures → wire into `LPPayload`. This prevents cascade failures from strict validation breaking existing tests.
- **Test isolation for static registries**: Always use `tearDown(() => LocationValidator.resetCustomTypes())` in test groups that call `register()`.
- **Parser exception normalization**: `geobase` throws `FormatException`; catch and re-throw as `ArgumentError` to keep LP error surface consistent.
- **Fixture migration pattern**: When tests are testing encoding/signing/network behavior (not LP validation), use the simplest valid type (`address` for String values, `h3` for hex-like strings) rather than `validateLocation: false`.
```

- [ ] **Step 2: Commit**

```powershell
git add .ai/memory/procedural.md
git commit -m "docs(memory): record phase 6 procedural patterns"
```

---

### Task 6E.3: Update walkthrough

**Files:**
- Modify: `doc/walkthrough.md`

- [ ] **Step 1: Add validation section to walkthrough**

```markdown
## Location Type Validation (Phase 6)

`LPPayload` now validates that `location` matches its declared `locationType` at construction time.

### Supported Location Types

| Type | Expected Dart Type | Validation |
|------|-------------------|------------|
| `coordinate-decimal+lon-lat` | `List<num>` (length 2) | lon ∈ [-180, 180], lat ∈ [-90, 90] |
| `geojson-point` | `Map` | RFC 7946 Point via geobase |
| `geojson-line` | `Map` | RFC 7946 LineString via geobase |
| `geojson-polygon` | `Map` | RFC 7946 Polygon via geobase |
| `h3` | `String` | Regex `^[89ab][0-9a-f]{14}$` |
| `geohash` | `String` | Base-32 charset, 1-12 chars |
| `wkt` | `String` | WKT parse via geobase |
| `address` | `String` | Trimmed non-empty |
| `scaledCoordinates` | `Map` | Keys `x`, `y`, `scale` present and numeric |

### Custom Types

Register custom types before constructing payloads:

```dart
LocationValidator.register('community.plus-code.v1', (location) {
  if (location is! String || location.isEmpty) {
    throw ArgumentError('plus-code must be a non-empty String');
  }
});
```

### Migration Bypass

If you need to construct an `LPPayload` with a non-standard type temporarily:

```dart
LPPayload(
  lpVersion: '1.0.0',
  srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
  locationType: 'legacy-type',
  location: 'data',
  validateLocation: false, // Temporary — remove when compliant
);
```

This flag is a migration aid and will be removed in a future version.
```

- [ ] **Step 2: Commit**

```powershell
git add doc/walkthrough.md
git commit -m "docs: add location type validation walkthrough"
```

---

### Task 6E.4: Final acceptance report

- [ ] Produce completion summary listing all changed files and test/analyze outputs.
- [ ] Confirm: clean output, root-cause fixes at constructor boundary, memory updated, walkthrough updated.

---

## Compact Verification Commands

```powershell
# LP focus
dart test test/lp/lp_payload_test.dart test/lp/location_serializer_test.dart test/lp/location_validator_test.dart -r expanded

# EAS focus
dart test test/eas/abi_encoder_test.dart test/eas/offchain_signer_test.dart test/eas/onchain_client_test.dart -r expanded

# Integration (non-Sepolia)
dart test test/integration/full_workflow_test.dart test/integration/onchain_workflow_test.dart -r expanded

# Integration (Sepolia)
dart test test/integration/sepolia_onchain_test.dart --tags sepolia -r expanded

# Full regression (no network tags)
dart test --exclude-tags sepolia --exclude-tags sepolia-bootstrap -r expanded

# Static analysis
dart analyze
```
