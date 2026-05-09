# Verifying Offchain EAS Attestations — Dart Implementation Reference

## File Map

| Concern | File | Symbol |
|---|---|---|
| Signing & UID computation | `lib/src/eas/offchain_signer.dart` | `OffchainSigner`, `computeOffchainUID` |
| Verification result | `lib/src/models/verification_result.dart` | `VerificationResult`, `VerificationFailure` |
| Attestation model + JSON | `lib/src/models/attestation.dart` | `SignedOffchainAttestation` |
| EIP-712 signing abstraction | `lib/src/eas/signer.dart` | `Signer.signTypedData` |
| Local key signing | `lib/src/eas/local_key_signer.dart` | `LocalKeySigner` |
| Schema UID computation | `lib/src/schema/schema_uid.dart` | `SchemaUID.compute` |
| ABI encoding | `lib/src/eas/abi_encoder.dart` | `AbiEncoder.encode` |
| EAS constants | `lib/src/eas/constants.dart` | `EASConstants` |
| Signing tests | `test/eas/offchain_signer_test.dart` | — |
| Example script | `scripts/create_offchain_attestation.dart` | `main` |

---

## Background

Offchain EAS attestations are signed using EIP-712 typed data. In this library, the `OffchainSigner` class in `lib/src/eas/offchain_signer.dart` handles both signing and verification without any RPC connection.

Verifying an attestation requires confirming two things independently:

1. **UID integrity** — the attestation's `uid` field was computed correctly from its contents via `computeOffchainUID`.
2. **Signature validity** — the EIP-712 signature was produced by the address stored in `attestation.signer`.

`verifyOffchainAttestation` enforces these in order — UID is checked first, then EIP-712 structure, then cryptographic signature recovery.

---

## Attestation JSON Format

The Dart library produces the canonical EAS wrapped envelope. `SignedOffchainAttestation.toJson()` always emits:

```json
{
  "signer": "0x3074C8732366cE5DB80986aBA8FB69897872DdB9",
  "sig": {
    "domain": {
      "name": "EAS Attestation",
      "version": "0.26",
      "chainId": 11155111,
      "verifyingContract": "0xC2679fBD37d54388Ce493F1DB75320D236e1815e"
    },
    "primaryType": "Attest",
    "types": {
      "EIP712Domain": [...],
      "Attest": [...]
    },
    "message": {
      "version": 2,
      "schema": "0x...",
      "recipient": "0x...",
      "time": 1778262429,
      "expirationTime": 0,
      "revocable": true,
      "refUID": "0x0000...0000",
      "data": "0x...",
      "salt": "0x..."
    },
    "signature": { "v": 27, "r": "0x...", "s": "0x..." },
    "uid": "0x..."
  }
}
```

`fromJson()` parses this same structure. Numeric fields (`time`, `expirationTime`, `version`) are stored as `int` after JSON deserialization and as `BigInt` during signing. The getters on `SignedOffchainAttestation` handle both forms transparently.

**Interop note:** This `{ signer, sig: { ... } }` shape is the canonical EAS offchain envelope format used by the TypeScript SDK as well. The TypeScript SDK's `verifyOffchainAttestationSignature` expects exactly this structure, called as `offchain.verifyOffchainAttestationSignature(attestation.signer, attestation.sig)`. The envelope shape is an EAS convention — it is not defined by EIP-712, which only specifies the inner `{ types, primaryType, domain, message }` signing payload.

---

## Dart BigInt Serialization Pitfall

Dart's `jsonEncode` will throw a `JsonUnsupportedObjectError` on raw `BigInt` values. During signing, `message['time']` and `message['expirationTime']` are stored as `BigInt`; `domain['chainId']` is stored as `int`.

The `_serializableValue` helper in `scripts/create_offchain_attestation.dart` handles this by recursing through the JSON tree and converting `BigInt` to `int` for the fields `time`, `expirationTime`, and `version`, and to `String` for all other `BigInt` values.

Any code that serializes a `SignedOffchainAttestation` built during a signing session (not deserialized from JSON) must apply the same conversion before calling `jsonEncode`.

---

## The Three-Check Verification Sequence

`OffchainSigner.verifyOffchainAttestation` runs four checks in order and returns a `VerificationResult` on the first failure:

### Check 0: Offchain Envelope Version

The verifier only supports v2 attestations. If `attestation.message['version'] != 2`, it returns `VerificationFailure.unsupportedVersion` before any UID or salt logic runs.

### Check 1: UID Integrity

Recomputes the UID via `computeOffchainUID` from the attestation's fields and asserts it equals `attestation.uid`. Failure returns `VerificationFailure.uidMismatch`.

This is the **strictest gate** — any encoding divergence in how fields are packed (especially `schemaUID`, see below) will fail here before the signature is ever checked.

### Check 2: EIP-712 Typed Data Structure

`_verifyTypedDataStructure` checks:
- `attestation.domain` matches `_expectedDomain()` with the version field taken from the attestation itself (mirrors `strict=false` behavior)
- `attestation.primaryType == 'Attest'`
- `attestation.types` deep-equals `_canonicalTypes()`

Failure codes: `VerificationFailure.invalidDomain`, `VerificationFailure.invalidPrimaryType`, `VerificationFailure.invalidTypes`.

### Check 3: Cryptographic Signature Recovery

`_verifySignature` encodes the EIP-712 digest via `Eip712TypedData.fromJson(...).encode()`, ecRecovers the signer address from the `v/r/s` components, and compares it to `attestation.signer`.

Failure codes: `VerificationFailure.invalidSignature`, `VerificationFailure.signerMismatch`.

| UID valid | Signature recovers expected signer | Outcome |
|---|---|---|
| ✓ | ✓ | `isValid: true` |
| ✗ | — (not reached) | `VerificationFailure.uidMismatch` — encoding bug |
| ✓ | ✗ | `VerificationFailure.signerMismatch` — wrong key or tampered data |

---

## The Domain Version Problem

The `domain.version` field in the EIP-712 domain must match the version of the EAS contract deployment. It is not a free choice.

`OffchainSigner` defaults to `easVersion = '0.26'`, which is correct for Sepolia (`0xC2679fBD37d54388Ce493F1DB75320D236e1815e`). For other networks or future deployments, the version should be queried from the contract at runtime rather than hardcoded. **Unknown chains must supply `easVersion` explicitly** — the constructor throws an `ArgumentError` if an unsupported chain ID is provided without an explicit version.

```
// ABI: function version() view returns (string)
// Call this on the EAS contract address to get the canonical domain version.
```

No runtime version-query utility currently exists in this library. A future `EasClient.getVersion()` method would be the right place.

`verifyOffchainAttestation` uses `strict=false` behavior — it reads `domain.version` from the attestation itself, not from `easVersion`. This means verification does not fail due to a version mismatch, but an attestation signed with the wrong domain version will be rejected by standard EAS tooling (the TypeScript SDK checks the version against its hardcoded list).

**Known versions by network:**
- Sepolia (`0xC2679fBD37d54388Ce493F1DB75320D236e1815e`) → `"0.26"`
- Ethereum Mainnet → `"1.2.0"`

---

## The UID Encoding Problem (Cross-SDK)

This is the highest-priority known correctness issue in the library.

### Location

`OffchainSigner.computeOffchainUID` in `lib/src/eas/offchain_signer.dart`, step 2:

```dart
// CURRENT — encoding the schemaUID as UTF-8 bytes of the hex string:
packed.addAll(utf8.encode(schemaUID));  // 66 UTF-8 bytes of "0x3902cc7b..."
```

### What the EAS specification requires

The EAS TypeScript SDK's `solidityPackedKeccak256` call packs the `schema` parameter as `toUtf8Bytes(schema)` — that is, the UTF-8 encoding of each character of the hex string `"0x3902cc7b..."`. This produces 66 bytes (the `"0x"` prefix plus 64 hex characters, one byte per character), **not** the 32 raw decoded bytes of the hash.

The Dart code (`utf8.encode(schemaUID)`) matches this behavior **only if** `schemaUID` is always passed as the full 66-character `"0x..."` string. The comment in the source reading `"should be 32 bytes"` is misleading — per the canonical TypeScript SDK source (`offchain.js`, `static getOffchainUID`), 66 UTF-8 bytes is correct.

**The most likely divergence:** if `schemaUID` arrives at `computeOffchainUID` without its `0x` prefix (64 characters instead of 66), the resulting hash will differ from the TypeScript SDK. Confirm the prefix is always present.

### How to diagnose

Generate an attestation with the TypeScript SDK for identical inputs (same schema string, same recipient, same time, same data, same salt). Compare the `uid` fields directly. A mismatch always means an encoding divergence in `computeOffchainUID`. Print `schemaUID.length` and confirm it is 66.

### Impact

If UID computation diverges from the TypeScript SDK:
- `verifyOffchainAttestation` will return `VerificationFailure.uidMismatch` for attestations whose `uid` was computed by the TypeScript SDK.
- Cross-SDK consumers using `offchain.verifyOffchainAttestationSignature` from the TypeScript SDK will reject attestations produced by this library, even though the cryptographic signature is valid.

---

## The EIP-712 Type Hash

The canonical Attest type string, as defined in `_canonicalTypes()` in `offchain_signer.dart`:

```
Attest(uint16 version,bytes32 schema,address recipient,uint64 time,uint64 expirationTime,bool revocable,bytes32 refUID,bytes data,bytes32 salt)
```

The `keccak256` of this string is the EIP-712 type hash. If a cross-SDK implementation produces a different hash, it indicates incompatible field ordering, type names, or missing fields.

Common cross-SDK mistakes:
- Using `uint256` instead of `uint64` for `time` / `expirationTime`.
- Omitting `salt` (present only in v2 envelopes; v1 used `nonce`).
- Different field ordering.

To verify, compute `keccak256(utf8.encode(typeString))` in Dart:

```dart
final typeString = "Attest(uint16 version,bytes32 schema,address recipient,"
    "uint64 time,uint64 expirationTime,bool revocable,"
    "bytes32 refUID,bytes data,bytes32 salt)";
final hash = QuickCrypto.keccack256Hash(utf8.encode(typeString));
```

Assert this matches the TypeScript SDK's `getAttestTypeHash()` for the same contract.

---

## Known Issues and Required Fixes

- [ ] **Confirm `schemaUID` byte encoding matches TypeScript SDK.** The current code uses `utf8.encode(schemaUID)` which is correct per EAS spec only if `schemaUID` always includes the `0x` prefix (66 chars). The inline comment says "should be 32 bytes", creating confusion. Write a cross-SDK test: produce an attestation in the TypeScript SDK with known inputs, hardcode the expected UID, assert `computeOffchainUID` in Dart produces the same value. (`offchain_signer.dart`, `computeOffchainUID`, step 2)

- [ ] **Remove debug `print` in `_verifySignature`.** The line `print('EIP-712 hash (Dart): 0x${BytesUtils.toHexString(eipHash)}');` is in the production verification path and should be removed. (`offchain_signer.dart`, `_verifySignature`)

- [ ] **Remove redundant `Eip712TypedData.encode()` call in `_verifySignature`.** Both `hash` and `eipHash` are computed from identical inputs — only one call is needed. (`offchain_signer.dart`, `_verifySignature`)

- [ ] **Add runtime domain version query.** No utility exists to fetch `domain.version` from the EAS contract via RPC. Hardcoding `'0.26'` works for Sepolia but will silently produce cross-SDK-incompatible attestations on any other network.

- [ ] **Add cross-SDK UID test.** `computeOffchainUID` is tested for determinism in `test/eas/offchain_signer_test.dart` but not validated against TypeScript SDK output for the same inputs. This is the only reliable way to catch encoding divergence.

- [ ] **Confirm `refUID` packing always yields exactly 32 bytes.** `refUID.toBytes()` via `HexUtils` strips `0x` and hex-decodes; for the zero bytes32 this is 32 bytes. Confirm this always yields exactly 32 bytes regardless of input string length. (`offchain_signer.dart`, `computeOffchainUID`, step 8)

- [ ] **Enforce safe `jsonEncode` pattern for `BigInt` fields.** The `_serializableValue` helper in `scripts/create_offchain_attestation.dart` is not part of the library. If downstream code calls `toJson()` on a freshly-signed attestation and passes it directly to `jsonEncode`, it will throw. Consider adding a `toJsonSafe()` method or documenting the requirement clearly on `toJson()`.
