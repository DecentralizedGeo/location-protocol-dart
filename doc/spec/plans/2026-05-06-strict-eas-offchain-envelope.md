# Strict EAS Offchain Envelope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor offchain attestation so `SignedOffchainAttestation` stores the exact EAS offchain JSON envelope (preserving `domain`, `primaryType`, `types`, `message`, `signature`, `uid`, and `signer`) instead of a flat derived record, and so `verifyOffchainAttestation` validates the preserved envelope fields directly rather than reconstructing them from scratch.

**Architecture:** Five sequential tasks, each leaving the codebase in a compilable, passing state before moving on. Tasks 1–2 are purely additive (new JSON helpers on `EIP712Signature`, new failure enum on `VerificationResult`); Task 3 redefines `SignedOffchainAttestation`; Task 4 refactors `OffchainSigner`; Task 5 updates integration tests and docs. Every task starts with failing tests (TDD).

**Tech Stack:** Dart 3.x, `test`, `blockchain_utils`, `on_chain`, `package:collection` (already a transitive dependency via `test`), existing `docs_snippet_extractor.dart` workflow.

---

## File Structure

**Modify (in order)**

- `lib/src/models/signature.dart` — add `toJson()` and `fromJson()` to `EIP712Signature`
- `lib/src/models/verification_result.dart` — add `VerificationFailure` enum and `code` field
- `lib/src/models/attestation.dart` — redefine `SignedOffchainAttestation` as the preserved EAS envelope; keep `UnsignedAttestation` and `Attestation` unchanged
- `lib/src/eas/offchain_signer.dart` — build canonical envelope maps during signing; replace `buildOffchainTypedDataJson` with `buildOffchainTypedDataJsonFromEnvelope`; validate the preserved envelope in `verifyOffchainAttestation`

**Modify (after core)**

- `test/models/attestation_test.dart` — add JSON round-trip and getter tests (Task 3)
- `test/eas/offchain_signer_test.dart` — add canonical-shape, tamper, and strict failure tests (Task 4)
- `test/integration/full_workflow_test.dart` — update assertions to use getters (Task 5)
- `README.md` — update offchain examples (Task 5)
- `doc/guides/reference-api.md` — update `SignedOffchainAttestation` docs (Task 5)
- `doc/guides/tutorial-first-attestation.md` — update snippets (Task 5)
- `doc/guides/tutorial-wallet-signer.md` — update snippets (Task 5)

**Do NOT modify**

- `lib/src/models/attestation.dart` `UnsignedAttestation` class — leave untouched
- `lib/src/models/attestation.dart` `Attestation` class — leave untouched
- `lib/src/eas/constants.dart` — read-only reference; no changes needed
- `lib/location_protocol.dart` — exports unchanged; all public types already exported
- `test/docs/docs_snippets_test.dart` — regenerate via script; never hand-edit

---

## Background: What Exists Today

Before touching any code, understand the current shape:

**`SignedOffchainAttestation`** (current flat model in `lib/src/models/attestation.dart`):
```dart
class SignedOffchainAttestation {
  final String uid;
  final String schemaUID;
  final String recipient;
  final BigInt time;
  final BigInt expirationTime;
  final bool revocable;
  final String refUID;
  final Uint8List data;   // ABI-encoded bytes
  final String salt;       // 0x-prefixed 32-byte hex
  final int version;
  final EIP712Signature signature;
  final String signer;
}
```

**Target `SignedOffchainAttestation`** (canonical envelope after this work):
```dart
class SignedOffchainAttestation {
  final String signer;
  final Map<String, dynamic> domain;    // EIP-712 domain
  final String primaryType;             // always 'Attest'
  final Map<String, dynamic> types;     // Attest field descriptors
  final Map<String, dynamic> message;   // the attestation payload
  final EIP712Signature signature;
  final String uid;
}
```

The target `toJson()` output must match the EAS SDK offchain package exactly:
```json
{
  "signer": "0x...",
  "sig": {
    "domain": { "name": "EAS Attestation", "version": "1.0.0", "chainId": 11155111, "verifyingContract": "0x..." },
    "primaryType": "Attest",
    "types": { "Attest": [...] },
    "message": { "version": 2, "schema": "0x...", "recipient": "0x...", "time": 1710000000, ... },
    "signature": { "v": 28, "r": "0x...", "s": "0x..." },
    "uid": "0x..."
  }
}
```

**Important notes:**
- `chainId` in `domain` is stored and serialized as an **integer**, not a string.
- `time` / `expirationTime` / `version` in `message` are stored as integers (Dart `int` / `BigInt`) — **not** as strings. The EAS SDK JSON uses plain numbers for these fields.
- `salt` in `message` is a `0x`-prefixed 64-char hex string (32 bytes).
- `data` in `message` is a `0x`-prefixed hex string of the ABI-encoded payload.
- `buildOffchainTypedDataJson` (the wallet signing helper) uses decimal **strings** for `time`/`expirationTime`/`chainId` because the `on_chain` package v8 requires it. This is a transient wallet-only concern and must NOT leak into the persisted canonical model.

---

## Task 1: Add JSON Helpers to `EIP712Signature`

**Files:**
- Modify: `lib/src/models/signature.dart`
- Modify: `test/models/attestation_test.dart`
- Test: `test/models/attestation_test.dart`

- [ ] **Step 1: Write the failing test**

Add a new `group` at the bottom of the existing `EIP712Signature` group in `test/models/attestation_test.dart`:

```dart
group('EIP712Signature JSON', () {
  const sig = EIP712Signature(
    v: 28,
    r: '0x1111111111111111111111111111111111111111111111111111111111111111',
    s: '0x2222222222222222222222222222222222222222222222222222222222222222',
  );

  test('toJson emits v, r, s', () {
    final json = sig.toJson();
    expect(json, equals({
      'v': 28,
      'r': '0x1111111111111111111111111111111111111111111111111111111111111111',
      's': '0x2222222222222222222222222222222222222222222222222222222222222222',
    }));
  });

  test('fromJson round-trips', () {
    final json = sig.toJson();
    final restored = EIP712Signature.fromJson(json);
    expect(restored.v, equals(28));
    expect(restored.r, equals(sig.r));
    expect(restored.s, equals(sig.s));
  });

  test('fromJson accepts num for v (JSON deserialization returns num)', () {
    final restored = EIP712Signature.fromJson({'v': 28, 'r': sig.r, 's': sig.s});
    expect(restored.v, equals(28));
  });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `dart test test/models/attestation_test.dart -r expanded`

Expected: FAIL — `EIP712Signature` has no `toJson` method and no `fromJson` factory.

- [ ] **Step 3: Implement `toJson` and `fromJson` on `EIP712Signature`**

Add the following two members to `lib/src/models/signature.dart` inside the `EIP712Signature` class, after the existing `fromHex` factory:

```dart
/// Serializes the signature to the EAS JSON shape.
Map<String, dynamic> toJson() => {
  'v': v,
  'r': r,
  's': s,
};

/// Deserializes from the EAS JSON shape.
///
/// JSON numbers deserialize as [num] in Dart, so [v] is cast safely.
factory EIP712Signature.fromJson(Map<String, dynamic> json) {
  return EIP712Signature(
    v: (json['v'] as num).toInt(),
    r: json['r'] as String,
    s: json['s'] as String,
  );
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `dart test test/models/attestation_test.dart -r expanded`

Expected: PASS — all tests including the new JSON group should be green.

- [ ] **Step 5: Commit**

```bash
git add lib/src/models/signature.dart test/models/attestation_test.dart
git commit -m "feat: add toJson/fromJson to EIP712Signature"
```

---

## Task 2: Add Structured Failure Codes to `VerificationResult`

**Files:**
- Modify: `lib/src/models/verification_result.dart`
- Modify: `test/models/attestation_test.dart`
- Test: `test/models/attestation_test.dart`

- [ ] **Step 1: Write the failing test**

Add a new group at the bottom of `test/models/attestation_test.dart`:

```dart
group('VerificationFailure', () {
  test('all expected codes exist', () {
    const codes = VerificationFailure.values;
    expect(codes, containsAll([
      VerificationFailure.uidMismatch,
      VerificationFailure.invalidDomain,
      VerificationFailure.invalidPrimaryType,
      VerificationFailure.invalidTypes,
      VerificationFailure.missingSalt,
      VerificationFailure.invalidSignature,
      VerificationFailure.signerMismatch,
    ]));
  });
});

group('VerificationResult with code', () {
  test('valid result has null code', () {
    const result = VerificationResult(
      isValid: true,
      recoveredAddress: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    );
    expect(result.code, isNull);
  });

  test('invalid result can carry a code', () {
    const result = VerificationResult(
      isValid: false,
      recoveredAddress: '',
      code: VerificationFailure.uidMismatch,
      reason: 'UID does not match',
    );
    expect(result.isValid, isFalse);
    expect(result.code, equals(VerificationFailure.uidMismatch));
    expect(result.reason, contains('UID'));
  });
});
```

You will need to add `VerificationFailure` to the import in `test/models/attestation_test.dart`. The file already imports from `package:location_protocol/location_protocol.dart`, so no new import is needed once the enum is exported through the barrel.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `dart test test/models/attestation_test.dart -r expanded`

Expected: FAIL — `VerificationFailure` does not exist.

- [ ] **Step 3: Add the `VerificationFailure` enum and `code` field**

Replace the entire contents of `lib/src/models/verification_result.dart` with:

```dart
/// Structured failure category for offchain attestation verification.
enum VerificationFailure {
  /// The recomputed UID does not match the stored UID.
  uidMismatch,

  /// The preserved EIP-712 domain does not match the signer's configuration.
  invalidDomain,

  /// The `primaryType` is not `'Attest'`.
  invalidPrimaryType,

  /// The `types` map does not match the canonical Attest field list.
  invalidTypes,

  /// The v2 `salt` field is absent from the `message` map.
  missingSalt,

  /// The signer address cannot be recovered from the signature.
  invalidSignature,

  /// The recovered signer address does not match `attestation.signer`.
  signerMismatch,
}

/// Result of verifying an offchain attestation signature.
class VerificationResult {
  /// Whether the signature is valid and the UID matches.
  final bool isValid;

  /// The Ethereum address recovered from the signature.
  ///
  /// Empty string (`''`) for failures that occur before signature recovery
  /// (e.g. [VerificationFailure.uidMismatch], [VerificationFailure.invalidDomain]).
  /// Always check [isValid] before using this value.
  final String recoveredAddress;

  /// Structured failure category. `null` when [isValid] is `true`.
  final VerificationFailure? code;

  /// Human-readable reason for failure. `null` when [isValid] is `true`.
  final String? reason;

  const VerificationResult({
    required this.isValid,
    required this.recoveredAddress,
    this.code,
    this.reason,
  });
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `dart test test/models/attestation_test.dart -r expanded`

Expected: PASS — all tests including the new `VerificationFailure` groups should be green.

- [ ] **Step 5: Confirm no other tests broke**

Run: `dart test --exclude-tags sepolia --exclude-tags sepolia-bootstrap -r expanded`

Expected: PASS across the full offline suite. `VerificationResult` is additive — the new `code` field is optional so existing call sites that omit it still compile.

- [ ] **Step 6: Commit**

```bash
git add lib/src/models/verification_result.dart test/models/attestation_test.dart
git commit -m "feat: add VerificationFailure enum and code field to VerificationResult"
```

---

## Task 3: Redefine `SignedOffchainAttestation` as a Canonical Envelope

**Files:**
- Modify: `lib/src/models/attestation.dart`
- Modify: `test/models/attestation_test.dart`
- Test: `test/models/attestation_test.dart`

> **Context:** This task changes the stored fields on `SignedOffchainAttestation` from flat derived values to preserved EAS envelope maps. `OffchainSigner` calls that construct `SignedOffchainAttestation` WILL break after this step — that is expected and is fixed in Task 4. The verification tests in `test/eas/offchain_signer_test.dart` WILL also fail — also expected. This task only concerns the model shape and `test/models/attestation_test.dart`.

- [ ] **Step 1: Write the failing model tests**

Replace the entire `group('SignedOffchainAttestation', ...)` block in `test/models/attestation_test.dart` with:

```dart
group('SignedOffchainAttestation', () {
  // This is the canonical fixture used across all sub-tests in this group.
  // The shape mirrors what the EAS offchain SDK produces.
  final canonicalJson = {
    'signer': '0x1111111111111111111111111111111111111111',
    'sig': {
      'domain': {
        'name': 'EAS Attestation',
        'version': '1.0.0',
        'chainId': 11155111,
        'verifyingContract': '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      },
      'primaryType': 'Attest',
      'types': {
        'Attest': [
          {'name': 'version', 'type': 'uint16'},
          {'name': 'schema', 'type': 'bytes32'},
          {'name': 'recipient', 'type': 'address'},
          {'name': 'time', 'type': 'uint64'},
          {'name': 'expirationTime', 'type': 'uint64'},
          {'name': 'revocable', 'type': 'bool'},
          {'name': 'refUID', 'type': 'bytes32'},
          {'name': 'data', 'type': 'bytes'},
          {'name': 'salt', 'type': 'bytes32'},
        ],
      },
      'message': {
        'version': 2,
        'schema': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'recipient': '0x0000000000000000000000000000000000000000',
        'time': 1710000000,
        'expirationTime': 0,
        'revocable': true,
        'refUID': '0x0000000000000000000000000000000000000000000000000000000000000000',
        'data': '0x010203',
        'salt': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      },
      'signature': {
        'v': 28,
        'r': '0x1111111111111111111111111111111111111111111111111111111111111111',
        's': '0x2222222222222222222222222222222222222222222222222222222222222222',
      },
      'uid': '0x3333333333333333333333333333333333333333333333333333333333333333',
    },
  };

  late SignedOffchainAttestation canonical;

  setUp(() {
    canonical = SignedOffchainAttestation.fromJson(canonicalJson);
  });

  test('fromJson parses signer', () {
    expect(canonical.signer,
        equals('0x1111111111111111111111111111111111111111'));
  });

  test('fromJson parses uid', () {
    expect(canonical.uid,
        equals('0x3333333333333333333333333333333333333333333333333333333333333333'));
  });

  test('toJson emits exactly signer and sig at the top level', () {
    final json = canonical.toJson();
    expect(json.keys.toList(), equals(['signer', 'sig']));
  });

  test('toJson sig contains exactly the six canonical keys', () {
    final sig = canonical.toJson()['sig'] as Map<String, dynamic>;
    expect(sig.keys.toList(),
        equals(['domain', 'primaryType', 'types', 'message', 'signature', 'uid']));
  });

  test('toJson round-trips correctly', () {
    final json = canonical.toJson();
    final restored = SignedOffchainAttestation.fromJson(json);
    expect(restored.signer, equals(canonical.signer));
    expect(restored.uid, equals(canonical.uid));
    expect(restored.primaryType, equals(canonical.primaryType));
  });

  group('derived getters', () {
    test('schemaUID', () {
      expect(canonical.schemaUID,
          equals('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'));
    });

    test('recipient', () {
      expect(canonical.recipient,
          equals('0x0000000000000000000000000000000000000000'));
    });

    test('time returns BigInt', () {
      expect(canonical.time, equals(BigInt.from(1710000000)));
    });

    test('expirationTime', () {
      expect(canonical.expirationTime, equals(BigInt.zero));
    });

    test('revocable', () {
      expect(canonical.revocable, isTrue);
    });

    test('refUID', () {
      expect(canonical.refUID,
          equals('0x0000000000000000000000000000000000000000000000000000000000000000'));
    });

    test('offchainVersion', () {
      expect(canonical.offchainVersion, equals(2));
    });

    test('saltHex', () {
      expect(canonical.saltHex,
          equals('0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'));
    });

    test('dataHex', () {
      expect(canonical.dataHex, equals('0x010203'));
    });

    test('dataBytes converts hex to Uint8List', () {
      expect(canonical.dataBytes, equals(Uint8List.fromList([0x01, 0x02, 0x03])));
    });

    test('saltBytes converts hex to Uint8List of length 32', () {
      expect(canonical.saltBytes, hasLength(32));
    });

    test('saltBytes is null when message has no salt key', () {
      final noSalt = Map<String, dynamic>.from(canonicalJson['sig']!['message'] as Map);
      noSalt.remove('salt');
      final withoutSalt = SignedOffchainAttestation.fromJson({
        'signer': canonicalJson['signer'],
        'sig': {
          ...(canonicalJson['sig'] as Map<String, dynamic>),
          'message': noSalt,
        },
      });
      expect(withoutSalt.saltHex, isNull);
      expect(withoutSalt.saltBytes, isNull);
    });
  });
});
```

You will need `import 'dart:typed_data';` at the top of the test file if not already present.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `dart test test/models/attestation_test.dart -r expanded`

Expected: FAIL — `SignedOffchainAttestation.fromJson` does not exist; the constructor shape changed.

- [ ] **Step 3: Redefine `SignedOffchainAttestation` in `lib/src/models/attestation.dart`**

Replace the entire `SignedOffchainAttestation` class (lines ~42–95) with the implementation below. Leave `UnsignedAttestation` and `Attestation` exactly as they are.

You will need to add at the top of the file:
```dart
import 'package:blockchain_utils/blockchain_utils.dart';
```
(It may already be imported.)

Also add:
```dart
import '../utils/hex_utils.dart';
```

Then replace the `SignedOffchainAttestation` class:

```dart
/// A signed offchain EAS attestation in the canonical EAS envelope format.
///
/// This is the exact JSON shape produced by the EAS offchain SDK:
/// ```json
/// {
///   "signer": "0x...",
///   "sig": {
///     "domain": {...},
///     "primaryType": "Attest",
///     "types": {"Attest": [...]},
///     "message": {...},
///     "signature": {"v": 28, "r": "0x...", "s": "0x..."},
///     "uid": "0x..."
///   }
/// }
/// ```
///
/// Use the convenience getters ([schemaUID], [time], [saltHex], etc.) to
/// access common fields without navigating the nested map directly.
class SignedOffchainAttestation {
  /// The Ethereum address of the signer.
  final String signer;

  /// The EIP-712 domain — contains name, version, chainId, verifyingContract.
  ///
  /// [chainId] is stored as an [int] (not a string).
  final Map<String, dynamic> domain;

  /// The EIP-712 primary type. Always `'Attest'`.
  final String primaryType;

  /// The EIP-712 types map — contains the Attest field descriptor list.
  final Map<String, dynamic> types;

  /// The EIP-712 message — the full attestation payload.
  ///
  /// Numeric fields ([time], [expirationTime], [version]) are stored as [int]
  /// when deserialized from JSON, and as [BigInt] when built during signing.
  /// The getters handle both forms automatically.
  final Map<String, dynamic> message;

  /// The EIP-712 signature components.
  final EIP712Signature signature;

  /// The deterministic offchain attestation UID.
  final String uid;

  const SignedOffchainAttestation({
    required this.signer,
    required this.domain,
    required this.primaryType,
    required this.types,
    required this.message,
    required this.signature,
    required this.uid,
  });

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Deserializes from the canonical EAS offchain JSON envelope.
  factory SignedOffchainAttestation.fromJson(Map<String, dynamic> json) {
    final sig = json['sig'] as Map<String, dynamic>;
    return SignedOffchainAttestation(
      signer: json['signer'] as String,
      domain: Map<String, dynamic>.from(sig['domain'] as Map),
      primaryType: sig['primaryType'] as String,
      types: Map<String, dynamic>.from(sig['types'] as Map),
      message: Map<String, dynamic>.from(sig['message'] as Map),
      signature: EIP712Signature.fromJson(
          Map<String, dynamic>.from(sig['signature'] as Map)),
      uid: sig['uid'] as String,
    );
  }

  /// Serializes to the canonical EAS offchain JSON envelope.
  Map<String, dynamic> toJson() => {
        'signer': signer,
        'sig': {
          'domain': domain,
          'primaryType': primaryType,
          'types': types,
          'message': message,
          'signature': signature.toJson(),
          'uid': uid,
        },
      };

  // ---------------------------------------------------------------------------
  // Derived getters (projections from the preserved message map)
  // ---------------------------------------------------------------------------

  /// The schema UID. From `message['schema']`.
  String get schemaUID => message['schema'] as String;

  /// The recipient address. From `message['recipient']`.
  String get recipient => message['recipient'] as String;

  /// The attestation creation time (Unix seconds). From `message['time']`.
  ///
  /// Works whether the value was stored as [int] (from JSON) or [BigInt]
  /// (from signing).
  BigInt get time => _toBigInt(message['time']);

  /// The attestation expiration time (0 = never). From `message['expirationTime']`.
  BigInt get expirationTime => _toBigInt(message['expirationTime']);

  /// Whether this attestation is revocable. From `message['revocable']`.
  bool get revocable => message['revocable'] as bool;

  /// The reference UID. From `message['refUID']`.
  String get refUID => message['refUID'] as String;

  /// The offchain attestation version (2 for v2 with salt). From `message['version']`.
  int get offchainVersion => (message['version'] as num).toInt();

  /// The salt as a `0x`-prefixed hex string, or `null` if absent (v1 attestations).
  String? get saltHex => message['salt'] as String?;

  /// The salt as raw bytes, or `null` if absent.
  Uint8List? get saltBytes {
    final hex = saltHex;
    if (hex == null) return null;
    return hex.toBytes();
  }

  /// The ABI-encoded data as a `0x`-prefixed hex string. From `message['data']`.
  String get dataHex => message['data'] as String;

  /// The ABI-encoded data as raw bytes.
  Uint8List get dataBytes => dataHex.toBytes();

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static BigInt _toBigInt(dynamic value) {
    if (value is BigInt) return value;
    if (value is int) return BigInt.from(value);
    return BigInt.parse(value.toString());
  }
}
```

- [ ] **Step 4: Run the model tests and confirm they pass**

Run: `dart test test/models/attestation_test.dart -r expanded`

Expected: PASS — all `SignedOffchainAttestation` shape and getter tests should be green.

- [ ] **Step 5: Note expected failures in other test files**

Run: `dart test --exclude-tags sepolia --exclude-tags sepolia-bootstrap -r expanded`

Expected: FAIL in `test/eas/offchain_signer_test.dart` and `test/integration/full_workflow_test.dart` because `OffchainSigner.signOffchainAttestation()` still constructs `SignedOffchainAttestation` with the old flat-field constructor, which no longer compiles. These failures are expected and are resolved in Task 4.

Do NOT proceed to Task 4 unless `test/models/attestation_test.dart` is fully green.

- [ ] **Step 6: Commit**

```bash
git add lib/src/models/attestation.dart test/models/attestation_test.dart
git commit -m "feat: redefine SignedOffchainAttestation as canonical EAS envelope"
```

---

## Task 4: Refactor `OffchainSigner` to Build and Verify the Preserved Envelope

**Files:**
- Modify: `lib/src/eas/offchain_signer.dart`
- Modify: `test/eas/offchain_signer_test.dart`
- Test: `test/eas/offchain_signer_test.dart`

> **Context:** After Task 3 the build is broken because `OffchainSigner` still uses the old `SignedOffchainAttestation` constructor. This task fixes the signing implementation first (restoring compile), then extends the tests, then implements strict verification.

### Step 1: Fix Compilation — Update `signOffchainAttestation` to Build the Canonical Envelope

In `lib/src/eas/offchain_signer.dart`, change `signOffchainAttestation()` to:

1. Build `domain`, `message`, and `types` maps first as local variables.
2. Derive the transient wallet signing request (`buildOffchainTypedDataJson`) from those local maps.
3. Return `SignedOffchainAttestation` using the new constructor.

Replace the existing method body (from the `final now = ...` line through the current `return SignedOffchainAttestation(...)` call) with:

```dart
  Future<SignedOffchainAttestation> signOffchainAttestation({
    required SchemaDefinition schema,
    required LPPayload lpPayload,
    required Map<String, dynamic> userData,
    String recipient = EASConstants.zeroAddress,
    BigInt? time,
    BigInt? expirationTime,
    String? refUID,
    Uint8List? salt,
  }) async {
    final now =
        time ?? BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final expTime = expirationTime ?? BigInt.zero;
    final ref = refUID ?? EASConstants.zeroBytes32;
    final saltBytes = salt ?? EASConstants.generateSalt();
    final saltHex = EASConstants.saltToHex(saltBytes);

    // 1. ABI-encode the data payload.
    final encodedData = AbiEncoder.encode(
      schema: schema,
      lpPayload: lpPayload,
      userData: userData,
    );
    final dataHex = '0x${BytesUtils.toHexString(encodedData)}';

    // 2. Compute schema UID.
    final schemaUID = SchemaUID.compute(schema);

    // 3. Build the canonical envelope maps.
    //    These are the values that will be preserved in SignedOffchainAttestation.
    //    Note: chainId and time are stored as integers here, matching EAS SDK JSON.
    final domainMap = <String, dynamic>{
      'name': EASConstants.eip712DomainName,
      'version': easVersion,
      'chainId': chainId,                 // int — NOT a string
      'verifyingContract': easContractAddress,
    };

    final messageMap = <String, dynamic>{
      'version': EASConstants.attestationVersion, // int 2
      'schema': schemaUID,
      'recipient': recipient,
      'time': now,               // BigInt from signing; getters handle this
      'expirationTime': expTime, // BigInt
      'revocable': schema.revocable,
      'refUID': ref,
      'data': dataHex,
      'salt': saltHex,
    };

    final typesMap = <String, dynamic>{
      'Attest': [
        {'name': 'version', 'type': 'uint16'},
        {'name': 'schema', 'type': 'bytes32'},
        {'name': 'recipient', 'type': 'address'},
        {'name': 'time', 'type': 'uint64'},
        {'name': 'expirationTime', 'type': 'uint64'},
        {'name': 'revocable', 'type': 'bool'},
        {'name': 'refUID', 'type': 'bytes32'},
        {'name': 'data', 'type': 'bytes'},
        {'name': 'salt', 'type': 'bytes32'},
      ],
    };

    // 4. Derive the transient wallet-signing request from the canonical maps.
    //    This is the ONLY place where integers are converted to strings for
    //    the on_chain package. These strings never enter the canonical model.
    final typedDataJson = _buildTypedDataJsonForSigning(
      domainMap: domainMap,
      typesMap: typesMap,
      messageMap: messageMap,
    );

    // 5. Sign via the Signer interface (supports local keys and wallets).
    final rawSig = await signer.signTypedData(typedDataJson);
    final normalizedV = rawSig.v < 27 ? rawSig.v + 27 : rawSig.v;

    // 6. Compute the deterministic offchain UID.
    final uid = computeOffchainUID(
      schemaUID: schemaUID,
      recipient: recipient,
      time: now,
      expirationTime: expTime,
      revocable: schema.revocable,
      refUID: ref,
      data: encodedData,
      salt: saltBytes,
    );

    // 7. Return the canonical preserved envelope.
    return SignedOffchainAttestation(
      signer: signerAddress,
      domain: domainMap,
      primaryType: 'Attest',
      types: typesMap,
      message: messageMap,
      signature: EIP712Signature(v: normalizedV, r: rawSig.r, s: rawSig.s),
      uid: uid,
    );
  }
```

Note: `signOffchainWithData` is a forwarding alias to `signOffchainAttestation` — **no changes are needed there**. It will automatically benefit from the refactored method.

- [ ] **Step 2: Add the `_buildTypedDataJsonForSigning` private helper**

This replaces the current `buildOffchainTypedDataJson` static method as the internal signing helper. Add it as a private instance method on `OffchainSigner`. **Keep** the existing `static buildOffchainTypedDataJson(...)` method in place for now (marked deprecated below) for backward compatibility; Task 4 Step 5 will confirm whether it can be removed.

Add this private method anywhere in the class body (e.g., just before `computeOffchainUID`):

```dart
  /// Builds the transient EIP-712 JSON request for wallet signing.
  ///
  /// This is derived from the canonical envelope maps and converts integer
  /// fields to decimal strings as required by the `on_chain` v8 package.
  /// It is a signing helper only — the returned map is NOT the canonical
  /// model and must never be serialized or stored.
  Map<String, dynamic> _buildTypedDataJsonForSigning({
    required Map<String, dynamic> domainMap,
    required Map<String, dynamic> typesMap,
    required Map<String, dynamic> messageMap,
  }) {
    return {
      'types': {
        'EIP712Domain': [
          {'name': 'name', 'type': 'string'},
          {'name': 'version', 'type': 'string'},
          {'name': 'chainId', 'type': 'uint256'},
          {'name': 'verifyingContract', 'type': 'address'},
        ],
        ...typesMap,
      },
      'primaryType': 'Attest',
      'domain': {
        ...domainMap,
        'chainId': domainMap['chainId'].toString(), // on_chain needs string
      },
      'message': {
        ...messageMap,
        'version': messageMap['version'].toString(),
        'time': messageMap['time'].toString(),
        'expirationTime': messageMap['expirationTime'].toString(),
      },
    };
  }
```

- [ ] **Step 3: Compile-check and confirm existing tests pass**

Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

Expected: The current signing tests should PASS (UID format, salt entropy, v∈{27,28}, etc.). The existing verification test ("valid attestation passes") will also pass — verification still works because `signOffchainAttestation` now returns a canonical envelope that the refactored verification in Step 4 will also handle. At this point the old `verifyOffchainAttestation` references `attestation.salt` which no longer exists, so it will FAIL to compile. That is resolved in Step 4.

---

### Step 4: Update `verifyOffchainAttestation` to Validate the Preserved Envelope

Replace the entire `verifyOffchainAttestation` method in `lib/src/eas/offchain_signer.dart` with:

```dart
  /// Verifies a signed offchain attestation against the preserved envelope.
  ///
  /// Validation steps (in order):
  /// 1. Recompute UID from the message fields → compare to [attestation.uid].
  /// 2. Compare the preserved domain to the current signer configuration.
  /// 3. Confirm [primaryType] is `'Attest'`.
  /// 4. Confirm the types map matches the canonical field list.
  /// 5. Confirm v2 [salt] is present in the message.
  /// 6. Recover the signer address from the preserved signed payload.
  /// 7. Compare the recovered address to [attestation.signer].
  VerificationResult verifyOffchainAttestation(
    SignedOffchainAttestation attestation,
  ) {
    // 1. Verify UID.
    final saltBytes = attestation.saltBytes;
    if (saltBytes == null) {
      return const VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.missingSalt,
        reason: 'v2 salt is absent from message',
      );
    }

    final expectedUID = computeOffchainUID(
      schemaUID: attestation.schemaUID,
      recipient: attestation.recipient,
      time: attestation.time,
      expirationTime: attestation.expirationTime,
      revocable: attestation.revocable,
      refUID: attestation.refUID,
      data: attestation.dataBytes,
      salt: saltBytes,
    );

    if (expectedUID != attestation.uid) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.uidMismatch,
        reason: 'UID mismatch: expected $expectedUID, got ${attestation.uid}',
      );
    }

    // 2. Verify the preserved domain matches this signer's configuration.
    //    chainId must match as an integer on both sides.
    final expected = _expectedDomain();
    if (!_mapsDeepEqual(attestation.domain, expected)) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidDomain,
        reason:
            'Preserved EIP-712 domain does not match signer configuration. '
            'Got: ${attestation.domain}, expected: $expected',
      );
    }

    // 3. Verify primaryType.
    if (attestation.primaryType != 'Attest') {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidPrimaryType,
        reason:
            'primaryType must be "Attest", got "${attestation.primaryType}"',
      );
    }

    // 4. Verify types map.
    if (!_mapsDeepEqual(attestation.types, _canonicalTypes())) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidTypes,
        reason: 'types map does not match the canonical Attest field list',
      );
    }

    // 5. Recover signer from the preserved signed payload.
    final typedDataJson = _buildTypedDataJsonForSigning(
      domainMap: attestation.domain,
      typesMap: attestation.types,
      messageMap: attestation.message,
    );

    final hash = Eip712TypedData.fromJson(typedDataJson).encode();
    final r = BytesUtils.fromHexString(attestation.signature.r.substring(2));
    final s = BytesUtils.fromHexString(attestation.signature.s.substring(2));
    final v = attestation.signature.v;

    final sigBytes = <int>[
      ...List<int>.filled(32 - r.length, 0),
      ...r,
      ...List<int>.filled(32 - s.length, 0),
      ...s,
      v,
    ];

    final recoveredPubKey = ETHPublicKey.getPublicKey(
      hash,
      sigBytes,
      hashMessage: false,
    );

    if (recoveredPubKey == null) {
      return const VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidSignature,
        reason: 'Could not recover public key from signature',
      );
    }

    final recoveredAddress =
        EthereumAddress.fromPublicKey(recoveredPubKey).address;

    // 6. Compare recovered address to the preserved signer.
    if (recoveredAddress.toLowerCase() != attestation.signer.toLowerCase()) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: recoveredAddress,
        code: VerificationFailure.signerMismatch,
        reason:
            'Recovered address $recoveredAddress does not match signer '
            '${attestation.signer}',
      );
    }

    return VerificationResult(
      isValid: true,
      recoveredAddress: recoveredAddress,
    );
  }
```

- [ ] **Step 5: Add the `_expectedDomain`, `_canonicalTypes`, and `_mapsDeepEqual` helpers**

Add these three private helpers to the `OffchainSigner` class body:

```dart
  /// Builds the expected EIP-712 domain for this signer's configuration.
  ///
  /// [chainId] is stored as [int] in the canonical domain map — never a string.
  Map<String, dynamic> _expectedDomain() => {
        'name': EASConstants.eip712DomainName,
        'version': easVersion,
        'chainId': chainId,
        'verifyingContract': easContractAddress,
      };

  /// The canonical Attest EIP-712 types map.
  Map<String, dynamic> _canonicalTypes() => {
        'Attest': [
          {'name': 'version', 'type': 'uint16'},
          {'name': 'schema', 'type': 'bytes32'},
          {'name': 'recipient', 'type': 'address'},
          {'name': 'time', 'type': 'uint64'},
          {'name': 'expirationTime', 'type': 'uint64'},
          {'name': 'revocable', 'type': 'bool'},
          {'name': 'refUID', 'type': 'bytes32'},
          {'name': 'data', 'type': 'bytes'},
          {'name': 'salt', 'type': 'bytes32'},
        ],
      };

  /// Deep-equality comparison for [Map<String, dynamic>] values.
  ///
  /// Uses [DeepCollectionEquality] from `package:collection`, which is already
  /// a transitive dependency via the `test` package.
  bool _mapsDeepEqual(Map<String, dynamic> a, Map<String, dynamic> b) =>
      const DeepCollectionEquality().equals(a, b);
```

Add the import at the top of `lib/src/eas/offchain_signer.dart`:

```dart
import 'package:collection/collection.dart';
```

- [ ] **Step 6: Add `package:collection` to `pubspec.yaml` if not already present**

Run: `dart pub deps | grep collection`

If `collection` appears as a transitive dependency only (not a direct one), add it explicitly to `pubspec.yaml` under `dependencies`:

```yaml
dependencies:
  collection: ^1.18.0
```

Then run: `dart pub get`

- [ ] **Step 7: Write the new strict signer tests**

Add the following groups to `test/eas/offchain_signer_test.dart`. Place them after the existing `'signOffchainAttestation'` group:

```dart
group('canonical envelope shape', () {
  test('signOffchainAttestation returns correct JSON top-level keys', () async {
    final signed = await signer.signOffchainAttestation(
      schema: schema,
      lpPayload: lpPayload,
      userData: {'timestamp': BigInt.from(1710000000), 'memo': 'shape test'},
    );
    final json = signed.toJson();
    expect(json.keys.toList(), equals(['signer', 'sig']));
    final sig = json['sig'] as Map<String, dynamic>;
    expect(sig.keys.toList(),
        equals(['domain', 'primaryType', 'types', 'message', 'signature', 'uid']));
  });

  test('returned envelope has primaryType Attest', () async {
    final signed = await signer.signOffchainAttestation(
      schema: schema,
      lpPayload: lpPayload,
      userData: {'timestamp': BigInt.from(1710000000), 'memo': 'type test'},
    );
    expect(signed.primaryType, equals('Attest'));
  });

  test('returned envelope has v2 salt in message', () async {
    final signed = await signer.signOffchainAttestation(
      schema: schema,
      lpPayload: lpPayload,
      userData: {'timestamp': BigInt.from(1710000000), 'memo': 'salt test'},
    );
    expect(signed.saltHex, isNotNull);
    expect(signed.saltHex, startsWith('0x'));
    expect(signed.saltBytes, hasLength(32));
  });

  test('domain chainId is stored as int not string', () async {
    final signed = await signer.signOffchainAttestation(
      schema: schema,
      lpPayload: lpPayload,
      userData: {'timestamp': BigInt.from(1710000000), 'memo': 'domain test'},
    );
    expect(signed.domain['chainId'], isA<int>());
  });
});

group('verifyOffchainAttestation strict failures', () {
  late SignedOffchainAttestation signed;

  setUp(() async {
    signed = await signer.signOffchainAttestation(
      schema: schema,
      lpPayload: lpPayload,
      userData: {'timestamp': BigInt.from(1710000000), 'memo': 'tamper base'},
    );
  });

  test('passes with unmodified envelope', () {
    final result = signer.verifyOffchainAttestation(signed);
    expect(result.isValid, isTrue, reason: result.reason);
  });

  test('fails with uidMismatch when uid is tampered', () {
    final tampered = SignedOffchainAttestation(
      signer: signed.signer,
      domain: signed.domain,
      primaryType: signed.primaryType,
      types: signed.types,
      message: signed.message,
      signature: signed.signature,
      uid: '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    );
    final result = signer.verifyOffchainAttestation(tampered);
    expect(result.isValid, isFalse);
    expect(result.code, equals(VerificationFailure.uidMismatch));
  });

  test('fails with invalidDomain when chainId is changed', () {
    final badDomain = {...signed.domain, 'chainId': 1}; // mainnet chainId
    final tampered = SignedOffchainAttestation(
      signer: signed.signer,
      domain: badDomain,
      primaryType: signed.primaryType,
      types: signed.types,
      message: signed.message,
      signature: signed.signature,
      uid: signed.uid,
    );
    final result = signer.verifyOffchainAttestation(tampered);
    expect(result.isValid, isFalse);
    expect(result.code, equals(VerificationFailure.invalidDomain));
  });

  test('fails with invalidPrimaryType when primaryType is changed', () {
    final tampered = SignedOffchainAttestation(
      signer: signed.signer,
      domain: signed.domain,
      primaryType: 'Revoke', // wrong type
      types: signed.types,
      message: signed.message,
      signature: signed.signature,
      uid: signed.uid,
    );
    final result = signer.verifyOffchainAttestation(tampered);
    expect(result.isValid, isFalse);
    expect(result.code, equals(VerificationFailure.invalidPrimaryType));
  });

  test('fails with invalidTypes when types are tampered', () {
    final badTypes = {
      'Attest': [
        {'name': 'version', 'type': 'uint16'},
        // removed all other fields
      ],
    };
    final tampered = SignedOffchainAttestation(
      signer: signed.signer,
      domain: signed.domain,
      primaryType: signed.primaryType,
      types: badTypes,
      message: signed.message,
      signature: signed.signature,
      uid: signed.uid,
    );
    final result = signer.verifyOffchainAttestation(tampered);
    expect(result.isValid, isFalse);
    expect(result.code, equals(VerificationFailure.invalidTypes));
  });

  test('fails with missingSalt when salt is removed from message', () {
    final messageWithoutSalt = Map<String, dynamic>.from(signed.message)
      ..remove('salt');
    final tampered = SignedOffchainAttestation(
      signer: signed.signer,
      domain: signed.domain,
      primaryType: signed.primaryType,
      types: signed.types,
      message: messageWithoutSalt,
      signature: signed.signature,
      uid: signed.uid,
    );
    final result = signer.verifyOffchainAttestation(tampered);
    expect(result.isValid, isFalse);
    expect(result.code, equals(VerificationFailure.missingSalt));
  });

  test('fails with signerMismatch when signer field is changed', () {
    final tampered = SignedOffchainAttestation(
      signer: '0x0000000000000000000000000000000000000001', // wrong signer
      domain: signed.domain,
      primaryType: signed.primaryType,
      types: signed.types,
      message: signed.message,
      signature: signed.signature,
      uid: signed.uid,
    );
    final result = signer.verifyOffchainAttestation(tampered);
    expect(result.isValid, isFalse);
    expect(result.code, equals(VerificationFailure.signerMismatch));
  });
});
```

- [ ] **Step 8: Run the full offchain signer test suite**

Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

Expected: PASS — all existing signing tests, the new canonical-shape tests, and the new tamper tests should be green.

- [ ] **Step 9: Confirm old `buildOffchainTypedDataJson` static method**

Check whether any existing tests in `test/eas/offchain_signer_test.dart` call `OffchainSigner.buildOffchainTypedDataJson(...)` directly. If they do, those tests should still pass because the static method remains. If no tests call it directly, add a `@Deprecated` annotation to the static method to communicate that `_buildTypedDataJsonForSigning` is the preferred internal path going forward:

```dart
@Deprecated(
  'Use _buildTypedDataJsonForSigning (internal) or buildOffchainTypedDataJsonFromEnvelope. '
  'This static method will be removed in the next major version.',
)
static Map<String, dynamic> buildOffchainTypedDataJson({...}) { ... }
```

- [ ] **Step 10: Commit**

```bash
git add lib/src/eas/offchain_signer.dart test/eas/offchain_signer_test.dart pubspec.yaml pubspec.lock
git commit -m "feat: sign and verify preserved EAS offchain envelopes"
```

---

## Task 5: Update Integration Tests and Public Documentation

**Files:**
- Modify: `test/integration/full_workflow_test.dart`
- Modify: `README.md`
- Modify: `doc/guides/reference-api.md`
- Modify: `doc/guides/tutorial-first-attestation.md`
- Modify: `doc/guides/tutorial-wallet-signer.md`
- Test: `test/integration/full_workflow_test.dart`
- Test: `test/docs/docs_snippets_test.dart`

> **Context on docs snippets:** The script `scripts/docs_snippet_extractor.dart` scans `doc/guides/*.md` for fenced Dart code blocks tagged with `// snippet: <name>` and emits them as test fixtures. Those fixtures are compiled and run by `test/docs/docs_snippets_test.dart`. Any Dart code block you update in the docs must be valid, importable Dart that uses the updated API. Run the extractor after each docs change to regenerate the fixtures, then run the snippet test to confirm.

- [ ] **Step 1: Update integration test assertions to use envelope getters**

In `test/integration/full_workflow_test.dart`, replace the assertions that access old flat fields (`signed.version`, `signed.data`, `signed.salt`, `signed.schemaUID` via old direct field) with getter-based access. The existing getters on the new model have the same names, so this is mostly about fields that no longer exist as direct fields:

Old assertions to look for and replace:
- `signed.version` → `signed.offchainVersion`
- `signed.data` (as `Uint8List`) → `signed.dataBytes`
- `signed.salt` (as hex string) → `signed.saltHex`
- Any assertion checking `signed.schemaUID`, `signed.recipient`, etc. — these getters exist and should already work

Specifically, the primary happy-path test should read:

```dart
expect(signed.uid, startsWith('0x'));
expect(signed.signer, startsWith('0x'));
expect(signed.offchainVersion, equals(2));
expect(signed.saltHex, isNotNull);
expect(signed.saltHex, startsWith('0x'));
expect(signed.schemaUID, startsWith('0x'));
expect(signed.dataBytes, isNotEmpty);

final result = signer.verifyOffchainAttestation(signed);
expect(result.isValid, isTrue, reason: result.reason);
```

- [ ] **Step 2: Run the integration test**

Run: `dart test test/integration/full_workflow_test.dart -r expanded`

Expected: PASS — the `_WalletStyleSigner` test (proves no `signDigest` call occurs) and the different-locations test should both be green.

- [ ] **Step 3: Update `README.md` offchain example block**

Find the offchain attestation usage example in `README.md` and replace it with:

```dart
// snippet: offchain_sign_and_verify
final signed = await signer.signOffchainAttestation(
  schema: schema,
  lpPayload: payload,
  userData: {
    'observedAt': BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    'memo': 'Rooftop sensor reading',
    'observer': signer.signerAddress,
  },
);

// Serialize to EAS-compatible JSON (matches the EAS offchain SDK shape exactly)
print(jsonEncode(signed.toJson()));

// Access common fields via getters
print('UID:        ${signed.uid}');
print('Schema UID: ${signed.schemaUID}');
print('Signer:     ${signed.signer}');
print('Version:    ${signed.offchainVersion}');   // 2
print('Salt:       ${signed.saltHex}');

// Verify
final result = signer.verifyOffchainAttestation(signed);
assert(result.isValid, 'Verification failed: ${result.reason}');
```

- [ ] **Step 4: Update `doc/guides/reference-api.md`**

Locate the `SignedOffchainAttestation` section and replace the class description with:

```markdown
### `SignedOffchainAttestation`

The canonical preserved EAS offchain attestation envelope. Serializes to the exact shape produced by the EAS offchain SDK:

```json
{
  "signer": "0x...",
  "sig": {
    "domain": { "name": "EAS Attestation", "version": "1.0.0", "chainId": 11155111, "verifyingContract": "0x..." },
    "primaryType": "Attest",
    "types": { "Attest": [...] },
    "message": { "version": 2, "schema": "0x...", "recipient": "0x...", "time": 1710000000, ... },
    "signature": { "v": 28, "r": "0x...", "s": "0x..." },
    "uid": "0x..."
  }
}
```

**Convenience getters** project the most-used fields from the preserved `message` map without flattening the envelope:

| Getter | Type | Source |
|--------|------|--------|
| `schemaUID` | `String` | `message['schema']` |
| `recipient` | `String` | `message['recipient']` |
| `time` | `BigInt` | `message['time']` |
| `expirationTime` | `BigInt` | `message['expirationTime']` |
| `revocable` | `bool` | `message['revocable']` |
| `refUID` | `String` | `message['refUID']` |
| `offchainVersion` | `int` | `message['version']` |
| `saltHex` | `String?` | `message['salt']` |
| `saltBytes` | `Uint8List?` | parsed from `saltHex` |
| `dataHex` | `String` | `message['data']` |
| `dataBytes` | `Uint8List` | parsed from `dataHex` |
```

- [ ] **Step 5: Update tutorial doc snippets**

In `doc/guides/tutorial-first-attestation.md` and `doc/guides/tutorial-wallet-signer.md`, find any code blocks that reference:
- `signed.version` → replace with `signed.offchainVersion`
- `signed.data` (as bytes) → replace with `signed.dataBytes`
- `signed.salt` → replace with `signed.saltHex`

Where these tutorials print or inspect the attestation result, update to use `signed.toJson()` for JSON output and the getter API for field access (matching the README example above).

- [ ] **Step 6: Regenerate documentation snippet fixtures**

Run:
```bash
dart run scripts/docs_snippet_extractor.dart
```

Expected: completes without error. If it reports a diff (new snippets added or old ones changed), that is expected. Run it a second time to confirm it is idempotent (no further diff on the second run).

- [ ] **Step 7: Run the docs snippet test**

Run: `dart test test/docs/docs_snippets_test.dart -r expanded`

Expected: PASS — all extracted snippets compile and execute successfully.

- [ ] **Step 8: Commit**

```bash
git add test/integration/full_workflow_test.dart README.md \
  doc/guides/reference-api.md doc/guides/tutorial-first-attestation.md \
  doc/guides/tutorial-wallet-signer.md test/docs/docs_snippets_test.dart
git commit -m "docs: adopt canonical EAS offchain envelope examples and getters"
```

---

## Task 6: Final Regression and Completion Checkpoint

**Files:**
- Modify: `docs/superpowers/plans/2026-05-06-strict-eas-offchain-envelope.md` (check off completed items)

- [ ] **Step 1: Run the focused regression suite**

```bash
dart test \
  test/models/attestation_test.dart \
  test/eas/offchain_signer_test.dart \
  test/integration/full_workflow_test.dart \
  test/docs/docs_snippets_test.dart \
  -r expanded
```

Expected: PASS with zero failures.

- [ ] **Step 2: Run the full offline suite**

```bash
dart test --exclude-tags sepolia --exclude-tags sepolia-bootstrap -r expanded
```

Expected: PASS across the entire offline test suite.

- [ ] **Step 3: Run static analysis**

```bash
dart analyze
```

Expected: zero new diagnostics in any file touched by this plan. If pre-existing diagnostics appear in unrelated files, list them here for tracking but do not fix them in this PR.

- [ ] **Step 4: Commit the completed plan**

```bash
git add docs/superpowers/plans/2026-05-06-strict-eas-offchain-envelope.md
git commit -m "chore: mark strict EAS offchain envelope plan complete"
```

---

## Self-Review Checklist

- **Spec coverage:** Canonical envelope shape ✓ · `toJson`/`fromJson` round-trip ✓ · derived getters ✓ · `VerificationFailure` enum ✓ · tamper failures for `uid`, `domain`, `primaryType`, `types`, `message.salt`, `signer` ✓ · v2 salt enforcement ✓ · `buildOffchainTypedDataJson` deprecated / replaced ✓ · integration updated ✓ · docs updated ✓ · snippet test ✓
- **Placeholder scan:** No `TBD`, `TODO`, "similar to Task N", or "add appropriate" language.
- **Task ordering:** Each task leaves the codebase in a compilable, test-passing state before the next task begins. Tasks 1 and 2 are additive—they cannot break existing tests. Task 3 intentionally breaks `offchain_signer_test.dart` but `attestation_test.dart` passes. Task 4 restores full green. Task 5 updates surface concerns only.
- **Type consistency:** `SignedOffchainAttestation` constructor, `fromJson`, `toJson`, and all seven getters use the same field names throughout every task and all code snippets. `VerificationFailure` enum values are identical in Task 2 definition, Task 4 test assertions, and Task 4 implementation returns.
- **`chainId` int/string consistency:** stored as `int` in canonical `domain` map everywhere; converted to string only inside `_buildTypedDataJsonForSigning` for `on_chain` compat.
- **`signOffchainWithData` alias:** explicitly noted in Task 4 Step 1 as a no-op forward; no separate changes required.
- **`recoveredAddress: ''`:** explained in `VerificationResult` field doc in Task 2 and used consistently in all early-return failure paths in Task 4.
