# Issue: `EASClient.attest()` Should Return Attestation UID and Metadata from Transaction Receipt

**Status:** Open  
**Date:** 2026-03-13  
**Priority:** High  
**Area:** `lib/src/eas/onchain_client.dart`

---

## Problem

`EASClient.attest()` currently returns only the raw transaction hash (`String`):

```dart
Future<String> attest({...}) async {
  ...
  return await helper.sendTransaction(to: easAddress, data: callData);
  // ↑ returns e.g. "0xabc123..." — the tx hash only
}
```

This leaves a critical gap: **callers have no way to obtain the onchain attestation UID** without a separate, out-of-band query. The UID is the primary identifier for an EAS attestation and is required for any follow-on operation — querying, revocation, timestamping a reference, or linking attestations.

The same gap applies to `SchemaRegistryClient.register()` — it returns a tx hash, but the caller may want the resulting schema UID as a first-class return value alongside the tx hash (even though the UID can be computed locally with `computeSchemaUID()`).

---

## Why the UID Cannot Be Computed Locally (for `attest()`)

For **schema registration**, the UID is deterministic and can be computed offline via `SchemaUID.compute(schema)`. This is already exposed as `SchemaRegistryClient.computeSchemaUID()`.

For **onchain attestations**, the UID is derived by the EAS contract from:

```
uid = keccak256(abi.encodePacked(
  schema,
  recipient,
  attester,   // ← msg.sender (our wallet address)
  time,       // ← block.timestamp (set by the node, unknown until mined)
  expirationTime,
  revocable,
  refUID,
  data,
  bump        // ← an incrementing counter stored in the contract
))
```

`block.timestamp` and `bump` (the per-attester nonce) are only known after the transaction is mined. The UID **cannot be pre-computed locally** and must be extracted from the transaction receipt.

---

## Source of Truth: The `Attested` Event

The EAS contract emits the `Attested` event on every successful `attest()` call:

```solidity
event Attested(
    address indexed recipient,
    address indexed attester,
    bytes32 uid,           // ← the attestation UID
    bytes32 indexed schema
);
```

The attestation UID is available in the event log of the transaction receipt. The metadata (block, timestamp, attester address) is also available from the receipt and the returned `Attestation` struct via `getAttestation(uid)`.

---

## Proposed Solution

### Option A — Parse the `Attested` Event Log from the Receipt *(Recommended)*

After broadcasting, call `eth_getTransactionReceipt` and decode the `Attested` log:

```dart
// Proposed return type
class AttestResult {
  final String txHash;
  final String uid;         // keccak256 UID of the new onchain attestation
  final BigInt blockNumber;
  final BigInt timestamp;   // block.timestamp at time of attestation
  final String attester;    // address that submitted the tx (msg.sender)
}
```

Implementation sketch in `RpcHelper`:

```dart
/// Waits for a transaction to be mined and returns its receipt.
Future<Map<String, dynamic>> waitForReceipt(String txHash) async {
  // Poll eth_getTransactionReceipt until non-null (mined)
}

/// Decodes the Attested(address,address,bytes32,bytes32) event from logs.
/// Topic[0] = keccak256("Attested(address,address,bytes32,bytes32)")
/// Topic[1] = recipient (indexed, padded address)
/// Topic[2] = attester  (indexed, padded address)
/// Topic[3] = schema    (indexed, bytes32)
/// data     = uid (bytes32, non-indexed)
String parseAttestedUID(List<dynamic> logs) { ... }
```

`EASClient.attest()` signature becomes:

```dart
Future<AttestResult> attest({
  required SchemaDefinition schema,
  required LPPayload lpPayload,
  required Map<String, dynamic> userData,
  String recipient = '0x000...0',
  BigInt? expirationTime,
  String? refUID,
}) async { ... }
```

### Option B — `eth_call` Simulation Before Broadcast *(Partial)*

`eth_call` can simulate the `attest()` call and return the raw ABI-encoded `bytes32` return value. This gives the UID *if* the simulated state matches the real execution. However, `bump` (the on-chain nonce) may differ between simulation and the actual mined block, making this **unreliable** for production use.

### Recommendation

**Option A** is the correct approach. It requires:

1. Adding `eth_getTransactionReceipt` polling to `RpcHelper` (with timeout)
2. Decoding the `Attested` log from the receipt
3. Changing `EASClient.attest()` return type to `AttestResult`

The polling adds latency (~12s per Sepolia block), but it is the only reliable method. A `timeout` parameter on `attest()` allows callers to control this.

---

## Impact on Existing Code

| Method | Current Return | Proposed Return | Breaking? |
|---|---|---|---|
| `EASClient.attest()` | `Future<String>` (tx hash) | `Future<AttestResult>` | ✅ Yes — public API change |
| `EASClient.timestamp()` | `Future<String>` (tx hash) | No change needed | ❌ No |
| `SchemaRegistryClient.register()` | `Future<String>` (tx hash) | Optional: `Future<RegisterResult>` with `{txHash, uid}` | ⚠️ Optional |
| `RpcHelper.sendTransaction()` | `Future<String>` (tx hash) | Extend with `waitForReceipt()` helper | Internal |

---

## Related

- [EAS Contract source — `attest()` and `Attested` event](https://github.com/ethereum-attestation-service/eas-contracts/blob/master/contracts/EAS.sol)
- `lib/src/eas/onchain_client.dart` — `EASClient.attest()`
- `lib/src/rpc/rpc_helper.dart` — `RpcHelper.sendTransaction()`
- Sepolia integration test: `test/integration/sepolia_onchain_test.dart`
