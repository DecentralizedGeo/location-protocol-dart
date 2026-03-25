# `location_protocol` Dart Library — Implementation Plan (Part 2 of 3)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Continues from** [Part 1](2025-03-12_phase1-project-init-part1.md) (Tasks 1–6: scaffold, LP payload, serializer, schema layer)

---

## Task 7: EAS Protocol Constants

**Files:**
- Create: `lib/src/eas/constants.dart`
- Test: `test/eas/constants_test.dart`

### Step 1: Write the failing tests

Create `test/eas/constants_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:location_protocol/src/eas/constants.dart';

void main() {
  group('EAS Constants', () {
    test('ZERO_ADDRESS is 42-char hex string', () {
      expect(EASConstants.zeroAddress, equals('0x0000000000000000000000000000000000000000'));
      expect(EASConstants.zeroAddress.length, equals(42));
    });

    test('ZERO_BYTES32 is 66-char hex string', () {
      expect(
        EASConstants.zeroBytes32,
        equals('0x0000000000000000000000000000000000000000000000000000000000000000'),
      );
      expect(EASConstants.zeroBytes32.length, equals(66));
    });

    test('SALT_SIZE is 32', () {
      expect(EASConstants.saltSize, equals(32));
    });

    test('EAS_ATTESTATION_VERSION is 2', () {
      expect(EASConstants.attestationVersion, equals(2));
    });

    test('EIP712_DOMAIN_NAME is "EAS Attestation"', () {
      expect(EASConstants.eip712DomainName, equals('EAS Attestation'));
    });

    test('generateSalt produces 32-byte Uint8List', () {
      final salt = EASConstants.generateSalt();
      expect(salt.length, equals(32));
    });

    test('generateSalt produces different values each call', () {
      final salt1 = EASConstants.generateSalt();
      final salt2 = EASConstants.generateSalt();
      // Probability of collision is 2^-256, so this is safe
      expect(salt1, isNot(equals(salt2)));
    });

    test('saltToHex returns 0x-prefixed 64-char hex string', () {
      final salt = EASConstants.generateSalt();
      final hex = EASConstants.saltToHex(salt);
      expect(hex, startsWith('0x'));
      expect(hex.length, equals(66));
    });
  });
}
```

### Step 2: Run tests to verify they fail

```bash
dart test test/eas/constants_test.dart
```

Expected: FAIL — `constants.dart` doesn't exist yet.

### Step 3: Write minimal implementation

Create `lib/src/eas/constants.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';

/// EAS protocol constants.
///
/// References:
/// - [EAS SDK utils.ts](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/utils.ts#L4-L6)
/// - [EAS SDK offchain.ts](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain.ts#L133)
class EASConstants {
  /// The Ethereum zero address.
  static const String zeroAddress =
      '0x0000000000000000000000000000000000000000';

  /// A 32-byte zero value.
  static const String zeroBytes32 =
      '0x0000000000000000000000000000000000000000000000000000000000000000';

  /// Salt size in bytes for offchain attestation UID uniqueness.
  static const int saltSize = 32;

  /// The offchain attestation version we implement (Version 2 includes salt).
  static const int attestationVersion = 2;

  /// The EIP-712 domain name used by EAS.
  static const String eip712DomainName = 'EAS Attestation';

  /// Generates a cryptographically secure random salt.
  ///
  /// Uses [Random.secure] (CSPRNG) to generate [saltSize] random bytes.
  /// Reference: [EAS SDK](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain.ts#L201-L203)
  static Uint8List generateSalt() {
    final random = Random.secure();
    final salt = Uint8List(saltSize);
    for (var i = 0; i < saltSize; i++) {
      salt[i] = random.nextInt(256);
    }
    return salt;
  }

  /// Converts a salt [Uint8List] to a `0x`-prefixed hex string.
  static String saltToHex(Uint8List salt) {
    final hex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '0x$hex';
  }
}
```

### Step 4: Run tests to verify they pass

```bash
dart test test/eas/constants_test.dart
```

Expected: All tests PASS.

### Step 5: Commit

```bash
git add lib/src/eas/constants.dart test/eas/constants_test.dart
git commit -m "feat: add EAS protocol constants (ZERO_ADDRESS, salt, version)"
```

---

## Task 8: Attestation Data Models

Data classes for unsigned attestations, signed offchain attestations, EIP-712 signatures, and verification results.

**Files:**
- Create: `lib/src/models/attestation.dart`
- Create: `lib/src/models/signature.dart`
- Create: `lib/src/models/verification_result.dart`
- Test: `test/models/attestation_test.dart`

### Step 1: Write the failing tests

Create `test/models/attestation_test.dart`:

```dart
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:location_protocol/src/models/attestation.dart';
import 'package:location_protocol/src/models/signature.dart';
import 'package:location_protocol/src/models/verification_result.dart';

void main() {
  group('EIP712Signature', () {
    test('stores v, r, s components', () {
      final sig = EIP712Signature(v: 28, r: '0xabc', s: '0xdef');
      expect(sig.v, equals(28));
      expect(sig.r, equals('0xabc'));
      expect(sig.s, equals('0xdef'));
    });
  });

  group('UnsignedAttestation', () {
    test('stores all EAS attestation fields', () {
      final att = UnsignedAttestation(
        schemaUID: '0xschema',
        recipient: '0xrecip',
        time: BigInt.from(1710000000),
        expirationTime: BigInt.zero,
        revocable: true,
        refUID: '0x0000000000000000000000000000000000000000000000000000000000000000',
        data: Uint8List.fromList([1, 2, 3]),
      );
      expect(att.schemaUID, equals('0xschema'));
      expect(att.time, equals(BigInt.from(1710000000)));
      expect(att.revocable, isTrue);
    });
  });

  group('SignedOffchainAttestation', () {
    test('stores attestation data + signature + uid + salt', () {
      final signed = SignedOffchainAttestation(
        uid: '0xuid123',
        schemaUID: '0xschema',
        recipient: '0xrecip',
        time: BigInt.from(1710000000),
        expirationTime: BigInt.zero,
        revocable: true,
        refUID: '0x0000000000000000000000000000000000000000000000000000000000000000',
        data: Uint8List.fromList([1, 2, 3]),
        salt: '0xsalt',
        version: 2,
        signature: EIP712Signature(v: 28, r: '0xr', s: '0xs'),
        signer: '0xSignerAddress',
      );
      expect(signed.uid, equals('0xuid123'));
      expect(signed.signature.v, equals(28));
      expect(signed.signer, equals('0xSignerAddress'));
      expect(signed.version, equals(2));
    });
  });

  group('VerificationResult', () {
    test('valid result', () {
      final result = VerificationResult(
        isValid: true,
        recoveredAddress: '0xabc',
      );
      expect(result.isValid, isTrue);
      expect(result.recoveredAddress, equals('0xabc'));
      expect(result.reason, isNull);
    });

    test('invalid result with reason', () {
      final result = VerificationResult(
        isValid: false,
        recoveredAddress: '0xwrong',
        reason: 'UID mismatch',
      );
      expect(result.isValid, isFalse);
      expect(result.reason, equals('UID mismatch'));
    });
  });
}
```

### Step 2: Run tests to verify they fail

```bash
dart test test/models/attestation_test.dart
```

Expected: FAIL — model files don't exist yet.

### Step 3: Write minimal implementation

Create `lib/src/models/signature.dart`:

```dart
/// An EIP-712 ECDSA signature with v, r, s components.
class EIP712Signature {
  /// Recovery id (27 or 28).
  final int v;

  /// The r component as a hex string.
  final String r;

  /// The s component as a hex string.
  final String s;

  const EIP712Signature({
    required this.v,
    required this.r,
    required this.s,
  });
}
```

Create `lib/src/models/verification_result.dart`:

```dart
/// Result of verifying an offchain attestation signature.
class VerificationResult {
  /// Whether the signature is valid and the UID matches.
  final bool isValid;

  /// The Ethereum address recovered from the signature.
  final String recoveredAddress;

  /// If invalid, the reason for failure.
  final String? reason;

  const VerificationResult({
    required this.isValid,
    required this.recoveredAddress,
    this.reason,
  });
}
```

Create `lib/src/models/attestation.dart`:

```dart
import 'dart:typed_data';

import 'signature.dart';

/// An unsigned EAS attestation — the data payload before signing.
class UnsignedAttestation {
  /// The schema UID this attestation conforms to.
  final String schemaUID;

  /// The recipient address (can be zero address for no recipient).
  final String recipient;

  /// The attestation creation time (Unix seconds).
  final BigInt time;

  /// When this attestation expires (0 = never).
  final BigInt expirationTime;

  /// Whether this attestation can be revoked.
  final bool revocable;

  /// Reference to another attestation UID (zero bytes32 for none).
  final String refUID;

  /// ABI-encoded data payload.
  final Uint8List data;

  const UnsignedAttestation({
    required this.schemaUID,
    required this.recipient,
    required this.time,
    required this.expirationTime,
    required this.revocable,
    required this.refUID,
    required this.data,
  });
}

/// A signed offchain EAS attestation with EIP-712 signature.
class SignedOffchainAttestation {
  /// The deterministic offchain UID.
  final String uid;

  /// Schema UID.
  final String schemaUID;

  /// Recipient address.
  final String recipient;

  /// Attestation creation time (Unix seconds).
  final BigInt time;

  /// Expiration time (0 = never).
  final BigInt expirationTime;

  /// Whether revocable.
  final bool revocable;

  /// Reference UID.
  final String refUID;

  /// ABI-encoded data payload.
  final Uint8List data;

  /// Random salt (32 bytes, hex string).
  final String salt;

  /// Offchain attestation version.
  final int version;

  /// The EIP-712 signature.
  final EIP712Signature signature;

  /// The signer's Ethereum address.
  final String signer;

  const SignedOffchainAttestation({
    required this.uid,
    required this.schemaUID,
    required this.recipient,
    required this.time,
    required this.expirationTime,
    required this.revocable,
    required this.refUID,
    required this.data,
    required this.salt,
    required this.version,
    required this.signature,
    required this.signer,
  });
}
```

### Step 4: Run tests to verify they pass

```bash
dart test test/models/attestation_test.dart
```

Expected: All tests PASS.

### Step 5: Commit

```bash
git add lib/src/models/ test/models/
git commit -m "feat: add attestation data models (unsigned, signed, signature, verification)"
```

---

## Task 9: ABI Encoder

Schema-aware encoder that merges LP payload + user data into ABI-encoded bytes. This is the bridge between the LP/schema layer and the EAS signing layer.

**Files:**
- Create: `lib/src/eas/abi_encoder.dart`
- Test: `test/eas/abi_encoder_test.dart`

> [!IMPORTANT]
> This task depends heavily on `on_chain`'s ABI encoding API. The `on_chain` package provides Solidity ABI encoding via its Ethereum utilities. During implementation, you'll need to:
> 1. Find the correct ABI encoding function (likely something like `AbiCoder.encode` or building `ContractABI` objects)
> 2. Map our `SchemaField.type` strings to `on_chain`'s ABI type representations
>
> The key operation is: given a list of Solidity types and a list of values, produce ABI-encoded bytes. If `on_chain`'s API doesn't provide a simple `encode(types, values)` function, you may need to construct `AbiFunctionFragment` objects or use lower-level encoding utilities.

### Step 1: Write the failing tests

Create `test/eas/abi_encoder_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/abi_encoder.dart';

void main() {
  group('AbiEncoder', () {
    late SchemaDefinition schema;

    setUp(() {
      schema = SchemaDefinition(
        fields: [
          SchemaField(type: 'uint256', name: 'timestamp'),
          SchemaField(type: 'string', name: 'memo'),
        ],
      );
    });

    test('encodes LP payload + user data into non-empty bytes', () {
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {'type': 'Point', 'coordinates': [-103.771556, 44.967243]},
      );

      final encoded = AbiEncoder.encode(
        schema: schema,
        lpPayload: lpPayload,
        userData: {
          'timestamp': BigInt.from(1710000000),
          'memo': 'Test memo',
        },
      );

      expect(encoded, isNotEmpty);
      // ABI encoding always produces output whose length is a multiple of 32
      expect(encoded.length % 32, equals(0));
    });

    test('encodes LP-only schema (no user fields)', () {
      final lpOnlySchema = SchemaDefinition(fields: []);
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'h3',
        location: '8928308280fffff',
      );

      final encoded = AbiEncoder.encode(
        schema: lpOnlySchema,
        lpPayload: lpPayload,
        userData: {},
      );

      expect(encoded, isNotEmpty);
      expect(encoded.length % 32, equals(0));
    });

    test('deterministic — same inputs produce same output', () {
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: '{"type":"Point","coordinates":[-103.771556,44.967243]}',
      );

      final data = {
        'timestamp': BigInt.from(1710000000),
        'memo': 'Test',
      };

      final encoded1 = AbiEncoder.encode(
        schema: schema, lpPayload: lpPayload, userData: data,
      );
      final encoded2 = AbiEncoder.encode(
        schema: schema, lpPayload: lpPayload, userData: data,
      );

      expect(encoded1, equals(encoded2));
    });

    test('throws if user data key does not match schema field', () {
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: 'test',
      );

      expect(
        () => AbiEncoder.encode(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'wrong_key': BigInt.from(1),
            'memo': 'test',
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws if user data is missing a required field', () {
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: 'test',
      );

      expect(
        () => AbiEncoder.encode(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1)},
          // missing 'memo'
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('serializes Map location to string before encoding', () {
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {'type': 'Point', 'coordinates': [-103.77, 44.96]},
      );

      // Should not throw — Map should be serialized to string
      final encoded = AbiEncoder.encode(
        schema: schema,
        lpPayload: lpPayload,
        userData: {
          'timestamp': BigInt.from(1710000000),
          'memo': 'test',
        },
      );
      expect(encoded, isNotEmpty);
    });
  });
}
```

### Step 2: Run tests to verify they fail

```bash
dart test test/eas/abi_encoder_test.dart
```

Expected: FAIL — `abi_encoder.dart` doesn't exist yet.

### Step 3: Write minimal implementation

Create `lib/src/eas/abi_encoder.dart`:

```dart
import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';

import '../lp/lp_payload.dart';
import '../lp/location_serializer.dart';
import '../schema/schema_definition.dart';

/// Schema-aware ABI encoder for Location Protocol attestations.
///
/// Merges LP payload fields and user-defined business data into
/// ABI-encoded bytes matching the combined EAS schema.
class AbiEncoder {
  /// Encodes LP payload + user data according to the schema.
  ///
  /// The encoding order matches [SchemaDefinition.allFields]:
  /// LP fields first (lp_version, srs, location_type, location),
  /// then user fields in declaration order.
  ///
  /// The [lpPayload.location] is serialized to a string via
  /// [LocationSerializer] before encoding.
  ///
  /// Throws [ArgumentError] if [userData] keys don't match schema fields.
  static Uint8List encode({
    required SchemaDefinition schema,
    required LPPayload lpPayload,
    required Map<String, dynamic> userData,
  }) {
    // Validate user data keys match schema fields
    final userFieldNames = schema.fields.map((f) => f.name).toSet();
    final providedKeys = userData.keys.toSet();

    final missing = userFieldNames.difference(providedKeys);
    if (missing.isNotEmpty) {
      throw ArgumentError(
        'Missing user data fields: ${missing.join(", ")}',
      );
    }

    final extra = providedKeys.difference(userFieldNames);
    if (extra.isNotEmpty) {
      throw ArgumentError(
        'Unknown user data fields (not in schema): ${extra.join(", ")}',
      );
    }

    // Build ordered values list: LP fields first, then user fields
    final serializedLocation = LocationSerializer.serialize(lpPayload.location);

    final List<dynamic> values = [
      lpPayload.lpVersion,       // string lp_version
      lpPayload.srs,             // string srs
      lpPayload.locationType,    // string location_type
      serializedLocation,        // string location
    ];

    // Append user field values in schema declaration order
    for (final field in schema.fields) {
      values.add(userData[field.name]);
    }

    // Build ABI type list from all fields
    final allFields = schema.allFields;

    // Use on_chain's ABI encoding
    // Build parameter types for encoding
    final params = <AbiParameter>[];
    for (final field in allFields) {
      params.add(AbiParameter.fromJson({'type': field.type, 'name': field.name}));
    }

    // Encode using on_chain's ABI coder
    final encoded = ABICoder.encode(params, values);
    return Uint8List.fromList(encoded);
  }
}
```

> [!IMPORTANT]
> The `on_chain` package's ABI encoding API may differ from the pseudo-code above. During implementation:
> 1. Check if `ABICoder.encode` is the correct method or if it's `AbiCoder.defaultAbiCoder().encode(...)` or similar
> 2. Check how `AbiParameter` objects are constructed from type strings
> 3. You may need to use `ContractABI` or `AbiFunctionFragment` for encoding
>
> The critical behavior is: take a list of Solidity types and values, produce standard ABI-encoded bytes. If the `on_chain` API is significantly different, adjust the implementation but keep the same public API and test behavior.

### Step 4: Run tests to verify they pass

```bash
dart test test/eas/abi_encoder_test.dart
```

Expected: All tests PASS.

### Step 5: Commit

```bash
git add lib/src/eas/abi_encoder.dart test/eas/abi_encoder_test.dart
git commit -m "feat: add schema-aware ABI encoder for LP attestations"
```

---

## Task 10: Offchain Signer

The core EIP-712 signing and verification engine. Uses `on_chain`'s built-in EIP-712 support. Generates CSPRNG salt, constructs the EIP-712 typed data structure, signs it, and computes the offchain UID.

**Files:**
- Create: `lib/src/eas/offchain_signer.dart`
- Test: `test/eas/offchain_signer_test.dart`

> [!IMPORTANT]
> This is the most complex task. It involves:
> 1. Constructing the EIP-712 domain (name="EAS Attestation", version=contractVersion, chainId, verifyingContract=easAddress)
> 2. Defining the Attest type (Version 2 with salt)
> 3. Building the message with the attestation data
> 4. Signing with `on_chain`'s EIP-712 v4 signing
> 5. Computing the offchain UID via `solidityPackedKeccak256`
> 6. Verifying signatures via `ecRecover`
>
> The `on_chain` package supports EIP-712 v4 natively. During implementation, explore how to construct `EIP712TypedData` objects and call the signing method.

### Step 1: Write the failing tests

Create `test/eas/offchain_signer_test.dart`:

```dart
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/offchain_signer.dart';
import 'package:location_protocol/src/eas/constants.dart';

void main() {
  // A well-known test private key — NEVER use in production
  // Address: will be derived from the key during tests
  const testPrivateKeyHex =
      'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  late OffchainSigner signer;
  late SchemaDefinition schema;
  late LPPayload lpPayload;

  setUp(() {
    signer = OffchainSigner(
      privateKeyHex: testPrivateKeyHex,
      chainId: 11155111, // Sepolia
      easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      easVersion: '1.0.0',
    );

    schema = SchemaDefinition(
      fields: [
        SchemaField(type: 'uint256', name: 'timestamp'),
        SchemaField(type: 'string', name: 'memo'),
      ],
    );

    lpPayload = LPPayload(
      lpVersion: '1.0.0',
      srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
      locationType: 'geojson-point',
      location: {'type': 'Point', 'coordinates': [-103.771556, 44.967243]},
    );
  });

  group('OffchainSigner', () {
    group('signOffchainAttestation', () {
      test('returns a SignedOffchainAttestation with valid UID', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test attestation',
          },
        );

        expect(signed.uid, startsWith('0x'));
        expect(signed.uid.length, equals(66));
      });

      test('includes CSPRNG salt in result', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
        );

        expect(signed.salt, startsWith('0x'));
        expect(signed.salt.length, equals(66)); // 0x + 64 hex chars
      });

      test('sets version to 2', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
        );

        expect(signed.version, equals(EASConstants.attestationVersion));
      });

      test('signature has valid v, r, s components', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
        );

        expect(signed.signature.v, anyOf(equals(27), equals(28)));
        expect(signed.signature.r, startsWith('0x'));
        expect(signed.signature.s, startsWith('0x'));
      });

      test('produces different UIDs for different salts', () async {
        final signed1 = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
        );
        final signed2 = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
        );

        // Salt is random, so UIDs should differ
        expect(signed1.uid, isNot(equals(signed2.uid)));
      });
    });

    group('verifyOffchainAttestation', () {
      test('verifies a valid attestation', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test verif',
          },
        );

        final result = signer.verifyOffchainAttestation(signed);
        expect(result.isValid, isTrue);
      });

      test('recovered address matches signer', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
        );

        final result = signer.verifyOffchainAttestation(signed);
        expect(
          result.recoveredAddress.toLowerCase(),
          equals(signed.signer.toLowerCase()),
        );
      });
    });

    group('signerAddress', () {
      test('returns a valid Ethereum address', () {
        final addr = signer.signerAddress;
        expect(addr, startsWith('0x'));
        expect(addr.length, equals(42));
      });
    });
  });
}
```

### Step 2: Run tests to verify they fail

```bash
dart test test/eas/offchain_signer_test.dart
```

Expected: FAIL — `offchain_signer.dart` doesn't exist yet.

### Step 3: Write minimal implementation

Create `lib/src/eas/offchain_signer.dart`:

```dart
import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';

import '../lp/lp_payload.dart';
import '../schema/schema_definition.dart';
import '../schema/schema_uid.dart';
import '../models/attestation.dart';
import '../models/signature.dart';
import '../models/verification_result.dart';
import 'abi_encoder.dart';
import 'constants.dart';

/// EIP-712 offchain attestation signer and verifier.
///
/// Signs Location Protocol attestations using EIP-712 typed data (Version 2
/// with salt). No RPC connection required.
///
/// Reference: [EAS SDK offchain.ts](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain.ts)
class OffchainSigner {
  final String _privateKeyHex;
  final int chainId;
  final String easContractAddress;
  final String easVersion;

  /// Creates a signer with the given private key and chain configuration.
  OffchainSigner({
    required String privateKeyHex,
    required this.chainId,
    required this.easContractAddress,
    this.easVersion = '1.0.0',
  }) : _privateKeyHex = privateKeyHex;

  /// The Ethereum address derived from the private key.
  String get signerAddress {
    final privateKey = ETHPrivateKey.fromHex(_privateKeyHex);
    return privateKey.publicKey().toAddress().toString();
  }

  /// Signs an offchain attestation using EIP-712 typed data.
  ///
  /// Generates a CSPRNG salt, ABI-encodes the data, constructs the
  /// EIP-712 message, signs it, and computes the offchain UID.
  Future<SignedOffchainAttestation> signOffchainAttestation({
    required SchemaDefinition schema,
    required LPPayload lpPayload,
    required Map<String, dynamic> userData,
    String recipient = '0x0000000000000000000000000000000000000000',
    BigInt? time,
    BigInt? expirationTime,
    String? refUID,
    Uint8List? salt,
  }) async {
    final now = time ?? BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final expTime = expirationTime ?? BigInt.zero;
    final ref = refUID ?? EASConstants.zeroBytes32;
    final saltBytes = salt ?? EASConstants.generateSalt();
    final saltHex = EASConstants.saltToHex(saltBytes);

    // ABI-encode the data payload
    final encodedData = AbiEncoder.encode(
      schema: schema,
      lpPayload: lpPayload,
      userData: userData,
    );

    // Compute schema UID
    final schemaUID = SchemaUID.compute(schema);

    // Build EIP-712 typed data for Attest (Version 2)
    // Domain: { name: "EAS Attestation", version: easVersion, chainId, verifyingContract }
    // Type: Attest(uint16 version, bytes32 schema, address recipient, uint64 time,
    //             uint64 expirationTime, bool revocable, bytes32 refUID,
    //             bytes data, bytes32 salt)

    final privateKey = ETHPrivateKey.fromHex(_privateKeyHex);

    // Construct the EIP-712 typed data and sign
    // Note: The exact on_chain API for EIP-712 signing will need exploration.
    // This implementation builds the EIP-712 hash manually and signs the digest.
    final domainSeparator = _computeDomainSeparator();
    final structHash = _computeStructHash(
      schemaUID: schemaUID,
      recipient: recipient,
      time: now,
      expirationTime: expTime,
      revocable: schema.revocable,
      refUID: ref,
      data: encodedData,
      salt: saltBytes,
    );

    // EIP-712 hash: keccak256(0x19 || 0x01 || domainSeparator || structHash)
    final digest = _computeEIP712Digest(domainSeparator, structHash);

    // Sign the digest
    final sig = privateKey.sign(digest);

    // Compute offchain UID
    final uid = _computeOffchainUID(
      schemaUID: schemaUID,
      recipient: recipient,
      time: now,
      expirationTime: expTime,
      revocable: schema.revocable,
      refUID: ref,
      data: encodedData,
      salt: saltBytes,
    );

    return SignedOffchainAttestation(
      uid: uid,
      schemaUID: schemaUID,
      recipient: recipient,
      time: now,
      expirationTime: expTime,
      revocable: schema.revocable,
      refUID: ref,
      data: encodedData,
      salt: saltHex,
      version: EASConstants.attestationVersion,
      signature: EIP712Signature(
        v: sig.v,
        r: '0x${sig.r.toRadixString(16).padLeft(64, '0')}',
        s: '0x${sig.s.toRadixString(16).padLeft(64, '0')}',
      ),
      signer: signerAddress,
    );
  }

  /// Verifies a signed offchain attestation.
  ///
  /// Recomputes the UID and recovers the signer from the signature.
  VerificationResult verifyOffchainAttestation(SignedOffchainAttestation attestation) {
    // Recompute the UID
    final saltBytes = _hexToBytes(attestation.salt);
    final expectedUID = _computeOffchainUID(
      schemaUID: attestation.schemaUID,
      recipient: attestation.recipient,
      time: attestation.time,
      expirationTime: attestation.expirationTime,
      revocable: attestation.revocable,
      refUID: attestation.refUID,
      data: attestation.data,
      salt: saltBytes,
    );

    if (expectedUID != attestation.uid) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        reason: 'UID mismatch: expected $expectedUID, got ${attestation.uid}',
      );
    }

    // Recover signer from signature
    final domainSeparator = _computeDomainSeparator();
    final structHash = _computeStructHash(
      schemaUID: attestation.schemaUID,
      recipient: attestation.recipient,
      time: attestation.time,
      expirationTime: attestation.expirationTime,
      revocable: attestation.revocable,
      refUID: attestation.refUID,
      data: attestation.data,
      salt: saltBytes,
    );
    final digest = _computeEIP712Digest(domainSeparator, structHash);

    // Recover address using on_chain's ecRecover
    final recovered = _recoverAddress(digest, attestation.signature);

    return VerificationResult(
      isValid: recovered.toLowerCase() == attestation.signer.toLowerCase(),
      recoveredAddress: recovered,
      reason: recovered.toLowerCase() != attestation.signer.toLowerCase()
          ? 'Signer mismatch: recovered $recovered, expected ${attestation.signer}'
          : null,
    );
  }

  // — Private helpers —

  Uint8List _computeDomainSeparator() {
    // keccak256(abi.encode(
    //   keccak256("EAS Attestation"),
    //   keccak256(easVersion),
    //   chainId,
    //   easContractAddress
    // ))
    // Implementation uses on_chain's keccak256 and ABI encoding
    throw UnimplementedError('TODO: implement with on_chain API');
  }

  Uint8List _computeStructHash({
    required String schemaUID,
    required String recipient,
    required BigInt time,
    required BigInt expirationTime,
    required bool revocable,
    required String refUID,
    required Uint8List data,
    required Uint8List salt,
  }) {
    // keccak256(abi.encode(
    //   ATTEST_TYPEHASH,
    //   version, schema, recipient, time, expirationTime, revocable, refUID,
    //   keccak256(data), salt
    // ))
    throw UnimplementedError('TODO: implement with on_chain API');
  }

  Uint8List _computeEIP712Digest(Uint8List domainSeparator, Uint8List structHash) {
    // keccak256(0x19 || 0x01 || domainSeparator || structHash)
    final bytes = Uint8List(2 + 32 + 32);
    bytes[0] = 0x19;
    bytes[1] = 0x01;
    bytes.setAll(2, domainSeparator);
    bytes.setAll(34, structHash);
    // return keccak256(bytes);
    throw UnimplementedError('TODO: implement with on_chain API');
  }

  String _computeOffchainUID({
    required String schemaUID,
    required String recipient,
    required BigInt time,
    required BigInt expirationTime,
    required bool revocable,
    required String refUID,
    required Uint8List data,
    required Uint8List salt,
  }) {
    // solidityPackedKeccak256(
    //   ['uint16','bytes','address','address','uint64','uint64','bool',
    //    'bytes32','bytes','bytes32','uint32'],
    //   [version, schema, recipient, ZERO_ADDRESS, time, expirationTime,
    //    revocable, refUID, data, salt, 0]
    // )
    throw UnimplementedError('TODO: implement with on_chain API');
  }

  String _recoverAddress(Uint8List digest, EIP712Signature sig) {
    // Use on_chain's ecRecover to recover the address from the signature
    throw UnimplementedError('TODO: implement with on_chain API');
  }

  static Uint8List _hexToBytes(String hex) {
    final cleanHex = hex.startsWith('0x') ? hex.substring(2) : hex;
    final result = Uint8List(cleanHex.length ~/ 2);
    for (var i = 0; i < cleanHex.length; i += 2) {
      result[i ~/ 2] = int.parse(cleanHex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
```

> [!CAUTION]
> The `OffchainSigner` implementation above has several `throw UnimplementedError` placeholders. This is intentional. During execution, you MUST:
> 1. Explore `on_chain`'s API for keccak256, ABI encoding, signing, and ecRecover
> 2. Replace each `throw UnimplementedError` with the actual implementation
> 3. The tests will guide you — they specify the expected behavior
>
> The structure and public API are correct. Only the internal crypto calls need to be wired up to `on_chain`'s specific methods.

### Step 4: Run tests to verify they pass

```bash
dart test test/eas/offchain_signer_test.dart
```

Expected: All tests PASS (after implementing the `UnimplementedError` methods).

### Step 5: Commit

```bash
git add lib/src/eas/offchain_signer.dart test/eas/offchain_signer_test.dart
git commit -m "feat: add OffchainSigner with EIP-712 signing and verification"
```

---

## Part 2 Summary

After completing Tasks 7–10, you have:

| Component | File | Tests |
|---|---|---|
| EAS Constants | `lib/src/eas/constants.dart` | `test/eas/constants_test.dart` |
| Attestation Models | `lib/src/models/attestation.dart` | `test/models/attestation_test.dart` |
| Signature Model | `lib/src/models/signature.dart` | (covered by attestation tests) |
| Verification Result | `lib/src/models/verification_result.dart` | (covered by attestation tests) |
| ABI Encoder | `lib/src/eas/abi_encoder.dart` | `test/eas/abi_encoder_test.dart` |
| Offchain Signer | `lib/src/eas/offchain_signer.dart` | `test/eas/offchain_signer_test.dart` |

**Proceed to** [Part 3](2025-03-12_phase1-project-init-part3.md) for Onchain Client, Schema Registry, Chain Config, Integration Test, and README.
