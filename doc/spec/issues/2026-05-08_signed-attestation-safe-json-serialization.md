# Issue: `SignedOffchainAttestation.toJson()` Is Unsafe When Called on a Freshly-Signed Attestation

**Status:** Open  
**Date:** 2026-05-08  
**Priority:** Low  
**Area:** `lib/src/models/attestation.dart`

---

## Problem

`SignedOffchainAttestation.toJson()` is not safe to pass directly to `jsonEncode` when the attestation was produced by a signing session rather than deserialized from JSON.

During signing, `OffchainSigner.signOffchainAttestation` stores `message['time']` and `message['expirationTime']` as `BigInt` values, and `domain['chainId']` as `int`. Dart's `jsonEncode` will throw a `JsonUnsupportedObjectError` on any raw `BigInt` value:

```dart
final signed = await offchainSigner.signOffchainAttestation(...);
jsonEncode(signed.toJson()); // throws JsonUnsupportedObjectError
```

The `_serializableValue` workaround in `scripts/create_offchain_attestation.dart` handles this correctly, but it is a private script helper — not part of the public library surface. Downstream consumers who call `toJson()` and pass it to `jsonEncode` will hit this error with no helpful message pointing to the cause.

Attestations that are **deserialized from JSON** via `fromJson()` do not have this problem because JSON parsing always produces `int`, never `BigInt`.

---

## Affected API Surface

| Symbol | File | Behavior |
|---|---|---|
| `SignedOffchainAttestation.toJson()` | `lib/src/models/attestation.dart` | Returns a map that may contain `BigInt` values — unsafe for `jsonEncode` when freshly signed |
| `_serializableValue` | `scripts/create_offchain_attestation.dart` | Correct workaround, but private and undiscoverable |

---

## Proposed Fix

**Option A — Add `toJsonSafe()` method (preferred)**

Add a `toJsonSafe()` method to `SignedOffchainAttestation` that recursively converts all `BigInt` values to `int` before returning:

```dart
/// Returns a JSON-encodable map safe to pass directly to [jsonEncode].
///
/// Unlike [toJson], this converts all [BigInt] values to [int], making the
/// result safe for serialization. Use [toJson] only when you need the
/// raw map (e.g. for in-memory processing where BigInt precision matters).
Map<String, dynamic> toJsonSafe() => _toJsonSafeMap(toJson()) as Map<String, dynamic>;

static dynamic _toJsonSafeMap(dynamic value) {
  if (value is BigInt) return value.toInt();
  if (value is Map) return value.map((k, v) => MapEntry(k, _toJsonSafeMap(v)));
  if (value is List) return value.map(_toJsonSafeMap).toList();
  return value;
}
```

**Option B — Add a doc comment to `toJson()`**

Document the limitation directly on `toJson()` with a pointer to a safe serialization pattern. Lower implementation cost but does not prevent the runtime error.

---

## Notes

- `BigInt.toInt()` loses precision beyond `2^63 - 1` on 64-bit platforms. All EAS timestamp and chain ID values are well within safe range, so this is safe in practice.
- The `fromJson()` round-trip is unaffected — JSON parsing always deserializes numbers as `int`.
- The TypeScript SDK has the same issue (`bigint` → `JSON.stringify`) and addresses it via a replacer function. See `Verifying-Offchain-Attestations.md` § "JSON Serialization Pitfall: BigInt Fields".
