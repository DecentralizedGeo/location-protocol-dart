# Offchain Envelope Implementation Review

**Branch:** `feat/strict-eas-offchain-envelope`
**Date:** 2026-05-07
**Status:** Implemented, all 301 offline tests + Sepolia integration tests passing

---

## What Was Built

The branch refactored `SignedOffchainAttestation` from a flat struct of derived fields into a preserved canonical EAS envelope matching the TypeScript SDK's `EIP712Response` shape:

```json
{
  "signer": "0x...",
  "sig": {
    "domain": { "name": "EAS Attestation", "version": "1.0.0", "chainId": 11155111, "verifyingContract": "0x..." },
    "primaryType": "Attest",
    "types": { "EIP712Domain": [...], "Attest": [...] },
    "message": { "version": 2, "schema": "0x...", "recipient": "0x...", "time": 1234567890, ... },
    "signature": { "v": 28, "r": "0x...", "s": "0x..." },
    "uid": "0x..."
  }
}
```

Additional changes delivered:
- `EIP712Signature.toJson()` / `fromJson()`
- `VerificationFailure` enum with 7 structured failure codes
- Convenience getters on `SignedOffchainAttestation` (`schemaUID`, `recipient`, `time`, `saltHex`, `dataBytes`, `offchainVersion`, etc.)
- `verifyOffchainAttestation` validates UID, domain, primaryType, types, then ecRecovers the signer address

---

## What Works Well

**Interoperability.** Storing the full envelope means `signed.toJson()` produces output that any EAS-compatible tool (the TS SDK, EAS Explorer, Ceramic) can consume directly. This is the primary value of the change and it is fully achieved.

**Structured failure codes.** `VerificationFailure` is genuinely useful for downstream apps that need to surface *why* verification failed (UID mismatch vs. domain mismatch vs. signer mismatch).

**`_buildTypedDataJsonForSigning` separation.** The transient wallet-signing conversion (BigInt/int → decimal strings for `on_chain` v8) is correctly isolated from the persisted canonical model. This is a subtle but important correctness distinction.

---

## What Is Overengineered

### 1. Structural envelope validation inside `verifyOffchainAttestation`

The method currently checks:
1. UID recomputation matches stored UID
2. `domain` map deep-equals `_expectedDomain()`
3. `primaryType == 'Attest'`
4. `types` map deep-equals `_canonicalTypes()`
5. ecRecover matches `attestation.signer`

Steps 2–4 are checking that the library's own output matches the library's own constants. `_canonicalTypes()` and `_expectedDomain()` are hardcoded — they will never diverge from a locally-produced attestation unless there is a bug in the library itself. More importantly, these checks will *reject a valid attestation produced by a different EAS-compatible tool* (e.g., the TS SDK on a frontend) if its domain version string or type ordering differs even slightly.

The TypeScript SDK only performs these structural checks to guard against cross-version ambiguity when `strict = false` is passed. For normal verification it just does ecRecover + address compare.

**Consequence:** `verifyOffchainAttestation` as currently written is stricter than the EAS protocol requires, and may produce false negatives for attestations produced outside this library.

### 2. Hand-rolled `_mapsDeepEqual`

`package:collection` (already a transitive dependency) provides `DeepCollectionEquality().equals(a, b)`. The hand-rolled helper is ~15 lines of extra owned logic with identical semantics.

### 3. `buildOffchainTypedDataJson` static method is dead code

The private `_buildTypedDataJsonForSigning` replaced it in Task 4. The static method remains in the public API with an incomplete `message` map (missing `expirationTime`, `revocable`, `refUID`, `data`, `salt` fields — they were never added). It should be removed; keeping it creates a misleading public surface.

### 4. `docs_snippet_extractor.dart` owns the import list, not the snippets

The extractor hardcodes `import 'package:location_protocol/location_protocol.dart'` in `generateFileHeader()`. Any doc snippet that uses a non-re-exported package currently breaks silently until the full test suite is run. The `dart:convert` issue encountered on this branch is a direct symptom. This is a fragility in the test generation pipeline, not in the feature itself, but it is tightly coupled to how doc examples are written.

---

## Long-Term Maintenance Concerns

| Concern | Risk | Notes |
|---|---|---|
| `_buildTypedDataJsonForSigning` int→string conversion | Medium | Works around `on_chain` v8 `valueAsBigInt(allowHex: false)`. If `on_chain` changes numeric handling, signing breaks with no compile error |
| Structural envelope validation rejects cross-tool attestations | High | A mobile app signing via MetaMask or the TS SDK may produce a valid EAS attestation that this library rejects as invalid |
| Hand-rolled `_mapsDeepEqual` | Low | Correct but unnecessary; owned code that could diverge from `collection`'s behavior |
| Dead `buildOffchainTypedDataJson` static | Low | Misleads API consumers; will accumulate confusion over time |
| `docs_snippet_extractor.dart` import fragility | Medium | Every new doc snippet using a non-barrel package requires a manual extractor update that is easy to miss |

---

## Recommended Simplifications (for next session)

### Priority 1 — Split verification into two methods

```dart
// Cryptographic only — matches what the EAS SDK actually does
VerificationResult verifySignature(SignedOffchainAttestation attestation);

// Optional structural check — use when you need to enforce this library's canonical format
VerificationResult validateEnvelope(SignedOffchainAttestation attestation);
```

`verifyOffchainAttestation` should become an alias for `verifySignature` (UID check + ecRecover only). `validateEnvelope` can call `verifySignature` and then layer the domain/type checks on top, for callers who explicitly want them.

### Priority 2 — Replace `_mapsDeepEqual` with `DeepCollectionEquality`

```dart
import 'package:collection/collection.dart';
const _eq = DeepCollectionEquality();

// Replace all _mapsDeepEqual(a, b) calls with:
_eq.equals(a, b)
```

### Priority 3 — Remove or fix `buildOffchainTypedDataJson`

Either delete it (it has no callers outside tests that test it directly) or complete the `message` map so it is actually usable. Keeping a half-implemented public static method is worse than removing it.

### Priority 4 — Fix the extractor's import handling

Either:
- Scan extracted snippets for `import` statements and pass unknown imports through to the generated file header, or
- Replace `import` stripping with a denylist (strip only `dart:io` and other incompatible imports, keep everything else)

---

## What Should Not Change

- The `SignedOffchainAttestation` envelope shape — this is correct and directly interoperable with the EAS SDK
- `VerificationFailure` enum — the structured codes are useful and the values are good
- The `_buildTypedDataJsonForSigning` / persisted-model separation — this is a subtle but correct design
- Convenience getters on `SignedOffchainAttestation` — these make the API pleasant without hiding the underlying maps
