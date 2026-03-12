# `location_protocol` Dart Library — Implementation Plan (Part 1 of 3)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a schema-agnostic Dart library implementing the Location Protocol base data model on EAS.

**Architecture:** Separated layers — LP payload validation → schema composition → ABI encoding → EIP-712 signing / onchain client. The library auto-prepends LP base fields to user-defined business schemas.

**Tech Stack:** Dart 3.x, `on_chain ^8.0.0`, `dart test`

**Reference PRD:** [location protocol dart implementation Design Doc](lp_dart_prd.md)

**Plan parts:**
- **Part 1** (this file): Project scaffold, LP Payload, Location Serializer, Schema Layer
- [Part 2](2025-03-12_phase1-project-init-part2.md): EAS Constants, ABI Encoder, Offchain Signer
- [Part 3](2025-03-12_phase1-project-init-part3.md): Onchain Client, Schema Registry, Chain Config, Integration Test, README

---

## Task 1: Project Scaffold

**Files:**
- Create: `pubspec.yaml`
- Create: `analysis_options.yaml`
- Create: `lib/location_protocol.dart`
- Create: `lib/src/lp/lp_payload.dart` (placeholder)
- Create: `test/lp/lp_payload_test.dart` (placeholder)

> [!NOTE]
> The working directory for all paths in this plan is wherever the `location-protocol-dart` repo is cloned. For now, we'll initialize the Dart package directly. The user will create the GitHub repo `DecentralizedGeo/location-protocol-dart` separately.

**Step 1: Create the Dart package**

Create `pubspec.yaml`:

```yaml
name: location_protocol
description: >-
  Schema-agnostic Dart library implementing the Location Protocol base data
  model on the Ethereum Attestation Service (EAS).
version: 0.1.0
repository: https://github.com/DecentralizedGeo/location-protocol-dart

environment:
  sdk: ^3.0.0

dependencies:
  on_chain: ^8.0.0

dev_dependencies:
  test: ^1.25.0
  lints: ^4.0.0
```

**Step 2: Create analysis options**

Create `analysis_options.yaml`:

```yaml
include: package:lints/recommended.yaml

linter:
  rules:
    prefer_single_quotes: true
    prefer_final_locals: true
    avoid_print: true
```

**Step 3: Create barrel export**

Create `lib/location_protocol.dart`:

```dart
/// Schema-agnostic Dart library implementing the Location Protocol
/// base data model on the Ethereum Attestation Service (EAS).
library location_protocol;

// LP layer
export 'src/lp/lp_payload.dart';
export 'src/lp/location_serializer.dart';

// Schema layer
export 'src/schema/schema_field.dart';
export 'src/schema/schema_definition.dart';
export 'src/schema/schema_uid.dart';

// EAS layer
export 'src/eas/constants.dart';
export 'src/eas/abi_encoder.dart';
export 'src/eas/offchain_signer.dart';
export 'src/eas/onchain_client.dart';
export 'src/eas/schema_registry.dart';

// Config
export 'src/config/chain_config.dart';

// Models
export 'src/models/attestation.dart';
export 'src/models/signature.dart';
export 'src/models/verification_result.dart';
```

> [!IMPORTANT]
> The barrel export references files that don't exist yet. This will cause analysis errors until all files are created. That's expected. We'll create placeholder files as we go, and the barrel export serves as our roadmap. For now, **comment out** all exports except `lp_payload.dart` and uncomment each line as the corresponding file is created.

**Step 4: Install dependencies**

```bash
dart pub get
```

Expected: Dependencies resolve successfully.

**Step 5: Commit**

```bash
git add .
git commit -m "chore: scaffold location_protocol Dart package"
```

---

## Task 2: LP Payload — Validation

The LP Payload class validates the 4 required Location Protocol base fields: `lp_version`, `srs`, `location_type`, `location`.

**Files:**
- Create: `lib/src/lp/lp_payload.dart`
- Create: `lib/src/lp/lp_version.dart`
- Test: `test/lp/lp_payload_test.dart`

### Step 1: Write the failing tests

Create `test/lp/lp_payload_test.dart`:

```dart
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
  });
}
```

### Step 2: Run tests to verify they fail

```bash
dart test test/lp/lp_payload_test.dart
```

Expected: FAIL — `lp_payload.dart` doesn't exist yet.

### Step 3: Create LP version constants

Create `lib/src/lp/lp_version.dart`:

```dart
/// Location Protocol version constants and validation.
class LPVersion {
  /// Current LP spec version.
  static const String current = '1.0.0';

  /// Regex pattern for valid semver: major.minor.patch (digits only).
  static final RegExp semverPattern = RegExp(r'^\d+\.\d+\.\d+$');

  /// Validates a version string matches semver format.
  static bool isValid(String version) => semverPattern.hasMatch(version);
}
```

### Step 4: Write minimal implementation

Create `lib/src/lp/lp_payload.dart`:

```dart
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

  /// Creates a validated LP payload.
  ///
  /// Throws [ArgumentError] if any field is invalid.
  LPPayload({
    required this.lpVersion,
    required this.srs,
    required this.locationType,
    required this.location,
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
  }
}
```

### Step 5: Run tests to verify they pass

```bash
dart test test/lp/lp_payload_test.dart
```

Expected: All tests PASS.

### Step 6: Commit

```bash
git add lib/src/lp/ test/lp/
git commit -m "feat: add LPPayload with base field validation"
```

---

## Task 3: Location Serializer

Converts flexible Dart types (`String`, `List<num>`, `Map<String, dynamic>`) to ABI-compatible strings. No location-type-specific validation in MVP — just convert → serialize.

**Files:**
- Create: `lib/src/lp/location_serializer.dart`
- Test: `test/lp/location_serializer_test.dart`

### Step 1: Write the failing tests

Create `test/lp/location_serializer_test.dart`:

```dart
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
```

### Step 2: Run tests to verify they fail

```bash
dart test test/lp/location_serializer_test.dart
```

Expected: FAIL — `location_serializer.dart` doesn't exist yet.

### Step 3: Write minimal implementation

Create `lib/src/lp/location_serializer.dart`:

```dart
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
```

### Step 4: Run tests to verify they pass

```bash
dart test test/lp/location_serializer_test.dart
```

Expected: All tests PASS.

### Step 5: Commit

```bash
git add lib/src/lp/location_serializer.dart test/lp/location_serializer_test.dart
git commit -m "feat: add LocationSerializer for convert-serialize flow"
```

---

## Task 4: Schema Field

Defines individual field entries for user-defined schemas.

**Files:**
- Create: `lib/src/schema/schema_field.dart`
- Test: `test/schema/schema_field_test.dart`

### Step 1: Write the failing tests

Create `test/schema/schema_field_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:location_protocol/src/schema/schema_field.dart';

void main() {
  group('SchemaField', () {
    test('creates a field with type and name', () {
      final field = SchemaField(type: 'uint256', name: 'timestamp');
      expect(field.type, equals('uint256'));
      expect(field.name, equals('timestamp'));
    });

    test('toString returns ABI-formatted string', () {
      final field = SchemaField(type: 'uint256', name: 'timestamp');
      expect(field.toString(), equals('uint256 timestamp'));
    });

    test('toString for string type', () {
      final field = SchemaField(type: 'string', name: 'memo');
      expect(field.toString(), equals('string memo'));
    });

    test('toString for bytes32 type', () {
      final field = SchemaField(type: 'bytes32', name: 'document_hash');
      expect(field.toString(), equals('bytes32 document_hash'));
    });

    test('toString for address type', () {
      final field = SchemaField(type: 'address', name: 'recipient');
      expect(field.toString(), equals('address recipient'));
    });

    test('toString for array type', () {
      final field = SchemaField(type: 'string[]', name: 'tags');
      expect(field.toString(), equals('string[] tags'));
    });

    test('equality works for identical fields', () {
      final a = SchemaField(type: 'uint256', name: 'timestamp');
      final b = SchemaField(type: 'uint256', name: 'timestamp');
      expect(a, equals(b));
    });

    test('rejects empty type', () {
      expect(
        () => SchemaField(type: '', name: 'timestamp'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects empty name', () {
      expect(
        () => SchemaField(type: 'uint256', name: ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
```

### Step 2: Run tests to verify they fail

```bash
dart test test/schema/schema_field_test.dart
```

Expected: FAIL — `schema_field.dart` doesn't exist yet.

### Step 3: Write minimal implementation

Create `lib/src/schema/schema_field.dart`:

```dart
/// A single field in an EAS schema definition.
///
/// Each field has a Solidity [type] (e.g. `uint256`, `string`, `address`)
/// and a [name] (e.g. `timestamp`, `memo`).
class SchemaField {
  final String type;
  final String name;

  /// Creates a schema field.
  ///
  /// Both [type] and [name] must be non-empty strings.
  SchemaField({required this.type, required this.name}) {
    if (type.isEmpty) {
      throw ArgumentError.value(type, 'type', 'Must be non-empty.');
    }
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must be non-empty.');
    }
  }

  /// Returns the ABI-formatted field string, e.g. `uint256 timestamp`.
  @override
  String toString() => '$type $name';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SchemaField && type == other.type && name == other.name;

  @override
  int get hashCode => Object.hash(type, name);
}
```

### Step 4: Run tests to verify they pass

```bash
dart test test/schema/schema_field_test.dart
```

Expected: All tests PASS.

### Step 5: Commit

```bash
git add lib/src/schema/schema_field.dart test/schema/schema_field_test.dart
git commit -m "feat: add SchemaField for EAS schema field definitions"
```

---

## Task 5: Schema Definition

The core schema composition class: user defines business fields, library auto-prepends LP base fields, detects conflicts, generates the EAS schema string, and computes the deterministic schema UID.

**Files:**
- Create: `lib/src/schema/schema_definition.dart`
- Create: `lib/src/schema/schema_uid.dart`
- Test: `test/schema/schema_definition_test.dart`
- Test: `test/schema/schema_uid_test.dart`

### Step 1: Write the failing tests for SchemaDefinition

Create `test/schema/schema_definition_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';

void main() {
  group('SchemaDefinition', () {
    group('LP field auto-prepend', () {
      test('generates EAS schema string with LP fields prepended', () {
        final schema = SchemaDefinition(
          fields: [
            SchemaField(type: 'uint256', name: 'timestamp'),
            SchemaField(type: 'string', name: 'memo'),
          ],
        );

        expect(
          schema.toEASSchemaString(),
          equals(
            'string lp_version,string srs,string location_type,'
            'string location,uint256 timestamp,string memo',
          ),
        );
      });

      test('generates EAS schema string with LP fields only (no user fields)', () {
        final schema = SchemaDefinition(fields: []);

        expect(
          schema.toEASSchemaString(),
          equals('string lp_version,string srs,string location_type,string location'),
        );
      });

      test('lpFields returns the 4 LP base fields', () {
        expect(
          SchemaDefinition.lpFields.map((f) => f.name).toList(),
          equals(['lp_version', 'srs', 'location_type', 'location']),
        );
      });

      test('allFields includes LP fields + user fields', () {
        final schema = SchemaDefinition(
          fields: [SchemaField(type: 'uint256', name: 'timestamp')],
        );
        final names = schema.allFields.map((f) => f.name).toList();
        expect(names, equals(['lp_version', 'srs', 'location_type', 'location', 'timestamp']));
      });
    });

    group('field conflict detection', () {
      test('throws if user field name collides with lp_version', () {
        expect(
          () => SchemaDefinition(
            fields: [SchemaField(type: 'string', name: 'lp_version')],
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws if user field name collides with srs', () {
        expect(
          () => SchemaDefinition(
            fields: [SchemaField(type: 'string', name: 'srs')],
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws if user field name collides with location_type', () {
        expect(
          () => SchemaDefinition(
            fields: [SchemaField(type: 'string', name: 'location_type')],
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws if user field name collides with location', () {
        expect(
          () => SchemaDefinition(
            fields: [SchemaField(type: 'string', name: 'location')],
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('revocable flag', () {
      test('defaults to true', () {
        final schema = SchemaDefinition(fields: []);
        expect(schema.revocable, isTrue);
      });

      test('can be set to false', () {
        final schema = SchemaDefinition(fields: [], revocable: false);
        expect(schema.revocable, isFalse);
      });
    });

    group('resolver address', () {
      test('defaults to ZERO_ADDRESS', () {
        final schema = SchemaDefinition(fields: []);
        expect(
          schema.resolverAddress,
          equals('0x0000000000000000000000000000000000000000'),
        );
      });

      test('can be set to a custom address', () {
        const addr = '0x1234567890abcdef1234567890abcdef12345678';
        final schema = SchemaDefinition(fields: [], resolverAddress: addr);
        expect(schema.resolverAddress, equals(addr));
      });
    });
  });
}
```

### Step 2: Run tests to verify they fail

```bash
dart test test/schema/schema_definition_test.dart
```

Expected: FAIL — `schema_definition.dart` doesn't exist yet.

### Step 3: Write minimal implementation for SchemaDefinition

Create `lib/src/schema/schema_definition.dart`:

```dart
import 'schema_field.dart';

/// Defines an EAS schema with automatic LP base field prepending.
///
/// Users provide only their business-specific fields. The LP base fields
/// (`lp_version`, `srs`, `location_type`, `location`) are automatically
/// prepended when generating the EAS schema string.
///
/// Field names that collide with LP reserved names will throw [ArgumentError].
class SchemaDefinition {
  /// LP base fields — always prepended to the EAS schema. All typed as `string`
  /// since the LP payload is serialized before ABI encoding.
  static final List<SchemaField> lpFields = [
    SchemaField(type: 'string', name: 'lp_version'),
    SchemaField(type: 'string', name: 'srs'),
    SchemaField(type: 'string', name: 'location_type'),
    SchemaField(type: 'string', name: 'location'),
  ];

  /// The reserved LP field names that user fields cannot use.
  static final Set<String> _reservedNames =
      lpFields.map((f) => f.name).toSet();

  /// User-defined business fields.
  final List<SchemaField> fields;

  /// Whether attestations made against this schema can be revoked.
  final bool revocable;

  /// Optional resolver contract address. Defaults to the zero address.
  final String resolverAddress;

  /// Creates a schema definition.
  ///
  /// Throws [ArgumentError] if any user field name collides with an LP
  /// reserved field name.
  SchemaDefinition({
    required this.fields,
    this.revocable = true,
    this.resolverAddress = '0x0000000000000000000000000000000000000000',
  }) {
    _validateNoConflicts();
  }

  void _validateNoConflicts() {
    for (final field in fields) {
      if (_reservedNames.contains(field.name)) {
        throw ArgumentError.value(
          field.name,
          'field.name',
          'Conflicts with LP reserved field name "${field.name}". '
              'LP fields are auto-prepended and cannot be redefined.',
        );
      }
    }
  }

  /// All fields in schema order: LP fields first, then user fields.
  List<SchemaField> get allFields => [...lpFields, ...fields];

  /// Generates the EAS-compatible schema string.
  ///
  /// Format: `type1 name1,type2 name2,...`
  /// LP fields are always first:
  /// `string lp_version,string srs,string location_type,string location,...`
  String toEASSchemaString() {
    return allFields.map((f) => f.toString()).join(',');
  }
}
```

### Step 4: Run tests to verify they pass

```bash
dart test test/schema/schema_definition_test.dart
```

Expected: All tests PASS.

### Step 5: Commit

```bash
git add lib/src/schema/schema_definition.dart test/schema/schema_definition_test.dart
git commit -m "feat: add SchemaDefinition with LP auto-prepend and conflict detection"
```

---

## Task 6: Schema UID Computation

Deterministic UID computation: `keccak256(abi.encodePacked(schemaString, resolverAddress, revocable))`.

**Files:**
- Create: `lib/src/schema/schema_uid.dart`
- Test: `test/schema/schema_uid_test.dart`

> [!IMPORTANT]
> This task uses `on_chain`'s keccak256 and ABI encoding. The exact import paths and API calls depend on `on_chain`'s public API. During implementation, you may need to explore the package's exports. The key functions needed are:
> - `keccak256` hash
> - `solidityPackedKeccak256` or equivalent packed encoding
>
> If `on_chain` doesn't expose a convenient `solidityPackedKeccak256` equivalent, you can construct it manually: concatenate the packed bytes (UTF-8 of schema string + zero-padded address bytes + bool byte) and keccak256 the result.

### Step 1: Write the failing tests

Create `test/schema/schema_uid_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/schema/schema_uid.dart';

void main() {
  group('SchemaUID', () {
    test('computes a 32-byte hex string', () {
      final schema = SchemaDefinition(fields: [
        SchemaField(type: 'uint256', name: 'timestamp'),
      ]);

      final uid = SchemaUID.compute(schema);
      expect(uid, startsWith('0x'));
      expect(uid.length, equals(66)); // 0x + 64 hex chars
    });

    test('is deterministic — same inputs produce same UID', () {
      final schema1 = SchemaDefinition(fields: [
        SchemaField(type: 'uint256', name: 'timestamp'),
      ]);
      final schema2 = SchemaDefinition(fields: [
        SchemaField(type: 'uint256', name: 'timestamp'),
      ]);

      expect(SchemaUID.compute(schema1), equals(SchemaUID.compute(schema2)));
    });

    test('different schemas produce different UIDs', () {
      final schema1 = SchemaDefinition(fields: [
        SchemaField(type: 'uint256', name: 'timestamp'),
      ]);
      final schema2 = SchemaDefinition(fields: [
        SchemaField(type: 'string', name: 'memo'),
      ]);

      expect(
        SchemaUID.compute(schema1),
        isNot(equals(SchemaUID.compute(schema2))),
      );
    });

    test('revocable flag affects UID', () {
      final schema1 = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
        revocable: true,
      );
      final schema2 = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
        revocable: false,
      );

      expect(
        SchemaUID.compute(schema1),
        isNot(equals(SchemaUID.compute(schema2))),
      );
    });

    test('resolver address affects UID', () {
      final schema1 = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );
      final schema2 = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
        resolverAddress: '0x1234567890abcdef1234567890abcdef12345678',
      );

      expect(
        SchemaUID.compute(schema1),
        isNot(equals(SchemaUID.compute(schema2))),
      );
    });
  });
}
```

### Step 2: Run tests to verify they fail

```bash
dart test test/schema/schema_uid_test.dart
```

Expected: FAIL — `schema_uid.dart` doesn't exist yet.

### Step 3: Write minimal implementation

Create `lib/src/schema/schema_uid.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';

import 'schema_definition.dart';

/// Computes deterministic schema UIDs matching the EAS SchemaRegistry.
///
/// Formula: `keccak256(abi.encodePacked(schemaString, resolverAddress, revocable))`
///
/// Reference: [EAS SDK schema-registry.ts](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/schema-registry.ts#L50-L54)
class SchemaUID {
  /// Computes the deterministic UID for a [SchemaDefinition].
  ///
  /// Returns a `0x`-prefixed 64-character hex string (32 bytes).
  static String compute(SchemaDefinition schema) {
    final schemaString = schema.toEASSchemaString();
    final resolverAddress = schema.resolverAddress;
    final revocable = schema.revocable;

    // Build packed encoding:
    // - schema string as UTF-8 bytes (no padding)
    // - resolver address as 20 bytes (no padding)
    // - revocable as 1 byte (0x01 or 0x00)
    final schemaBytes = utf8.encode(schemaString);

    // Parse address: strip 0x prefix, decode 20 hex bytes
    final addrHex = resolverAddress.startsWith('0x')
        ? resolverAddress.substring(2)
        : resolverAddress;
    final addrBytes = _hexToBytes(addrHex);

    final revocableByte = revocable ? 1 : 0;

    // Concatenate packed: schema + address + revocable
    final packed = Uint8List(schemaBytes.length + addrBytes.length + 1);
    packed.setAll(0, schemaBytes);
    packed.setAll(schemaBytes.length, addrBytes);
    packed[packed.length - 1] = revocableByte;

    // keccak256 hash
    final hash = ETHAddress.toKeccak256(packed);
    return '0x${_bytesToHex(hash)}';
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
```

> [!IMPORTANT]
> The `ETHAddress.toKeccak256` call above is a placeholder for the `on_chain` package's keccak256 function. During implementation, you'll need to find the correct import path and function name. The `on_chain` package provides keccak256 via its Ethereum utilities. If the exact API differs, replace with the correct call. The key requirement is: input `Uint8List`, output `Uint8List` (32 bytes).
>
> **Fallback:** If `on_chain`'s keccak256 is not easily accessible as a standalone function, you can use `blockchain_utils` (a dependency of `on_chain`) which provides `QuickCrypto.keccack256Hash(bytes)`.

### Step 4: Run tests to verify they pass

```bash
dart test test/schema/schema_uid_test.dart
```

Expected: All tests PASS.

### Step 5: Commit

```bash
git add lib/src/schema/schema_uid.dart test/schema/schema_uid_test.dart
git commit -m "feat: add deterministic SchemaUID computation"
```

---

## Part 1 Summary

After completing Tasks 1–6, you have:

| Component | File | Tests |
|---|---|---|
| Package scaffold | `pubspec.yaml`, `analysis_options.yaml`, barrel export | — |
| LP Payload | `lib/src/lp/lp_payload.dart` | `test/lp/lp_payload_test.dart` |
| LP Version | `lib/src/lp/lp_version.dart` | (covered by LP Payload tests) |
| Location Serializer | `lib/src/lp/location_serializer.dart` | `test/lp/location_serializer_test.dart` |
| Schema Field | `lib/src/schema/schema_field.dart` | `test/schema/schema_field_test.dart` |
| Schema Definition | `lib/src/schema/schema_definition.dart` | `test/schema/schema_definition_test.dart` |
| Schema UID | `lib/src/schema/schema_uid.dart` | `test/schema/schema_uid_test.dart` |

**Proceed to** [Part 2](2025-03-12_phase1-project-init-part2.md) for EAS Constants, ABI Encoder, and Offchain Signer.
