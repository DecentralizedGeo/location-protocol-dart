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

### 1. Domain version strictness in `verifyOffchainAttestation`

The method currently checks:
1. UID recomputation matches stored UID
2. `domain` map deep-equals `_expectedDomain()`
3. `primaryType == 'Attest'`
4. `types` map deep-equals `_canonicalTypes()`
5. ecRecover matches `attestation.signer`

This structure is **correct and matches the EAS TypeScript SDK**. The SDK's `verifyTypedDataRequestSignature` performs the same checks: domain deep-equal, primaryType match, types deep-equal, then ecRecover. For Version 2, `OFFCHAIN_ATTESTATION_TYPES[Version2]` has a single entry, so the SDK's `.some()` loop is functionally a single check — identical to ours.

The one behavioral difference is how the domain `version` field is handled. The SDK calls `verifyTypedDataRequestSignature` with `strict=false`, which replaces the expected domain version with whatever the attestation itself reports:

```ts
if (!strict) {
  expectedDomain = { ...expectedDomain, version: domain.version }; // accepts any version string
}
```

Our `_expectedDomain()` requires an exact match against the signer's configured `easVersion`. This means an attestation signed by the TS SDK with `version: '0.26'` would pass the SDK's own verifier but fail ours, even though the signature is cryptographically valid.

**Consequence:** `verifyOffchainAttestation` is correct for round-trip verification of attestations this library produced, but is stricter than the SDK on domain version for cross-tool attestations. The fix is narrow: relax the domain version check to match the attestation's own reported version (i.e. mirror `strict=false`), not to remove structural validation entirely.

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
| Domain version exact-match rejects cross-tool attestations | Low–Medium | An attestation signed with a different EAS SDK version string (e.g. `'0.26'`) passes the TS SDK's own verifier but fails ours; fix is one line (mirror `strict=false` by using the attestation's own domain version) |
| Hand-rolled `_mapsDeepEqual` | Low | Correct but unnecessary; owned code that could diverge from `collection`'s behavior |
| Dead `buildOffchainTypedDataJson` static | Low | Misleads API consumers; will accumulate confusion over time |
| `docs_snippet_extractor.dart` import fragility | Medium | Every new doc snippet using a non-barrel package requires a manual extractor update that is easy to miss |

---

## Recommended Simplifications (for next session)

### Priority 1 — Relax domain version check to mirror `strict=false`

The EAS SDK passes `strict=false` to `verifyTypedDataRequestSignature`, which replaces the expected domain version with the attestation's own reported version before comparing. This means any EAS-produced attestation passes regardless of which SDK version produced it.

Our fix is a single line in `verifyOffchainAttestation` — when building `expectedDomain` for comparison, use the attestation's own domain version rather than `easVersion`:

```dart
// Current (strict — rejects cross-tool attestations with different version strings)
final expectedDomain = _expectedDomain();

// Fixed (mirrors SDK strict=false — accepts any version string)
final expectedDomain = _expectedDomain()
  ..['version'] = attestation.domain['version'] as String;
```

The method name `verifyOffchainAttestation` should be kept — it mirrors the SDK's own top-level `verifyOffchainAttestationSignature`. The internal logic should be decomposed to match the SDK's two-layer structure:

- `verifyOffchainAttestation` — public entry point: UID check, then delegates to the two sub-checks below
- `_verifyTypedDataStructure` (private) — checks domain, primaryType, and types against expected values (mirrors `verifyTypedDataRequestSignature`'s structural half)
- `_verifySignature` (private) — ecRecover + signer address compare (mirrors `verifyTypedDataRequestSignature`'s cryptographic half)

This decomposition makes the verification logic easier to follow and easier to test in isolation, without changing the public API surface.

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
