# `EASClient.attest()` + `EASClient.timestamp()` + `SchemaRegistryClient.register()` — Rich Return Types PRD

> **Repo:** `DecentralizedGeo/location-protocol-dart`
> **Issue Ref:** `doc/spec/issues/2026-03-13_attest-return-uid-from-receipt.md`
> **Date:** 2026-03-14
> **Priority:** High
> **Area:** `lib/src/eas/`, `lib/src/rpc/`, `lib/src/models/`

---

## Goal

Replace the bare `Future<String>` (tx hash) return type of `EASClient.attest()`,
`EASClient.timestamp()`, and `SchemaRegistryClient.register()` with rich result objects that
surface the attestation/schema UID and, where applicable, the on-chain confirmation timestamp.
This eliminates the need for callers to perform separate out-of-band queries after submission.

---

## Background

### Why `attest()` cannot compute the UID locally

For schema registration, the UID is deterministic and already computable offline via
`SchemaRegistryClient.computeSchemaUID()`. No receipt polling is needed.

For onchain attestations, the UID is derived by the EAS contract from fields that are only
known after mining:

```solidity
uid = keccak256(abi.encodePacked(
  schema, recipient, attester,
  time,       // block.timestamp — unknown until mined
  expirationTime, revocable, refUID, data,
  bump        // per-attester nonce stored in contract — unknown until mined
))
```

The UID **must** be extracted from the `Attested` event log in the transaction receipt.

### Source of truth: the `Attested` event

```solidity
event Attested(
  address indexed recipient,   // topics[1]
  address indexed attester,    // topics[2]
  bytes32 uid,                 // data (non-indexed, first 32 bytes)
  bytes32 indexed schema       // topics[3]
);
```

### Why `timestamp()` needs receipt polling

The UID passed into `timestamp()` is already known (the offchain attestation UID). However,
the **block timestamp** at which the anchoring occurred is only known after the transaction is
mined. Without it a caller cannot confirm *when* the offchain attestation was anchored
on-chain without a separate `EAS.getTimestamp(uid)` call.

### Source of truth: the `Timestamped` event

```solidity
event Timestamped(
  bytes32 indexed data,   // topics[1] — the offchain attestation UID
  uint64  indexed time    // topics[2] — block.timestamp at anchoring
);
```

Both fields are **indexed** — they live in `topics[1]` and `topics[2]`. There is no `data`
payload on this event.

The `on_chain` v8 package provides `EthereumRequestGetTransactionReceipt` which returns a
typed `TransactionReceipt?` (null while pending). Its `.logs` field is a `List<LogEntry>`,
where `LogEntry.topics[0]` is the keccak256 event signature hash.

---

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **`waitForReceipt()` placement** | Added to `RpcProvider` interface | Keeps all clients working purely through the abstraction; enables `FakeRpcProvider` to mock receipt responses for offline tests |
| **Receipt model** | Own thin `TransactionReceipt` + `TransactionLog` value objects | Insulates `RpcProvider` interface from `on_chain` internals; makes `FakeRpcProvider` construction trivial |
| **`attest()` UID source** | Parse `Attested` event log from receipt | Only reliable method; `eth_call` simulation is unreliable due to on-chain nonce (`bump`) divergence |
| **`timestamp()` time source** | Parse `Timestamped` event log from receipt | `block.timestamp` is only known post-mine; receipt is the canonical source |
| **`register()` UID source** | Computed locally via existing `SchemaUID.compute()` | Deterministic; no receipt polling needed |
| **Timeout configuration** | Constructor default on `DefaultRpcProvider` + per-call override on `waitForReceipt()` | Sensible default (2 min); per-call override for tests and time-sensitive contexts |
| **Scope** | `attest()`, `timestamp()`, and `register()` | Consistent rich return types across all three write methods |

---

## New Public API

### Result Types (models)

```dart
/// Returned by EASClient.attest() after the transaction is mined.
class AttestResult {
  final String txHash;       // "0x..." — the submitted transaction hash
  final String uid;          // "0x..." — keccak256 UID of the new onchain attestation
  final int blockNumber;     // block in which the tx was mined
}

/// Returned by EASClient.timestamp() after the transaction is mined.
class TimestampResult {
  final String txHash;       // "0x..." — the submitted transaction hash
  final String uid;          // "0x..." — the offchain attestation UID that was anchored
  final BigInt time;         // block.timestamp (uint64) at which anchoring occurred
}

/// Returned by SchemaRegistryClient.register() after the transaction is broadcast.
class RegisterResult {
  final String txHash;       // "0x..." — the submitted transaction hash
  final String uid;          // "0x..." — deterministic schema UID (locally computed)
}
```

### RPC Value Objects (rpc)

```dart
/// A minimal receipt representation, insulated from on_chain internals.
class TransactionReceipt {
  final String txHash;
  final int blockNumber;
  final bool? status;           // true = success, false = reverted, null = pre-Byzantium
  final List<TransactionLog> logs;
}

/// A single event log entry from a transaction receipt.
class TransactionLog {
  final String address;         // contract that emitted the event
  final List<String> topics;    // topics[0] = event signature hash
  final String data;            // hex-encoded non-indexed parameters
}
```

### `RpcProvider` Interface addition (rpc_provider.dart)

```dart
abstract class RpcProvider {
  // ... existing methods unchanged ...

  /// Polls eth_getTransactionReceipt until the transaction is mined,
  /// then returns a typed receipt.
  ///
  /// Throws [TimeoutException] if [timeout] elapses before the tx is mined.
  Future<TransactionReceipt> waitForReceipt(
    String txHash, {
    Duration? timeout,
    Duration pollInterval,
  });
}
```

### Updated method signatures

```dart
// lib/src/eas/onchain_client.dart
Future<AttestResult>   attest({ ... });              // was Future<String>
Future<TimestampResult> timestamp(String offchainUID); // was Future<String>

// lib/src/eas/schema_registry.dart
Future<RegisterResult> register(SchemaDefinition schema);  // was Future<String>
```

---

## Architecture

```
EASClient.attest()
  │
  ├─ buildAttestCallData(...)          (unchanged)
  ├─ provider.sendTransaction(...)     → txHash
  ├─ provider.waitForReceipt(txHash)  → TransactionReceipt
  │    └─ [DefaultRpcProvider] polls eth_getTransactionReceipt until non-null
  │       maps on_chain TransactionReceipt → our TransactionReceipt
  ├─ _parseAttestedUID(receipt.logs)  → uid
  │    └─ filter logs by topics[0] == EASConstants.attestedEventTopic
  │       extract uid from log.data (first 32 bytes, non-indexed)
  └─ return AttestResult(txHash, uid, blockNumber)


EASClient.timestamp()
  │
  ├─ buildTimestampCallData(...)       (unchanged)
  ├─ provider.sendTransaction(...)     → txHash
  ├─ provider.waitForReceipt(txHash)  → TransactionReceipt
  ├─ _parseTimestampedEvent(receipt.logs) → (uid, time)
  │    └─ filter logs by topics[0] == EASConstants.timestampedEventTopic
  │       uid  = topics[1] (indexed bytes32 — the anchored UID)
  │       time = topics[2] decoded as uint64 BigInt
  └─ return TimestampResult(txHash, uid, time)


SchemaRegistryClient.register()
  │
  ├─ buildRegisterCallData(...)        (unchanged)
  ├─ provider.sendTransaction(...)     → txHash
  ├─ SchemaUID.compute(schema)         → uid (local, no polling)
  └─ return RegisterResult(txHash, uid)
```

---

## Key Components

### 1. `AttestResult` + `TimestampResult` + `RegisterResult` (models)

Simple immutable value objects. No logic beyond field access. Provide `toString()` for logging.

### 2. `TransactionReceipt` + `TransactionLog` (rpc)

Thin value objects constructed by `DefaultRpcProvider.waitForReceipt()` by mapping
from `on_chain`'s `TransactionReceipt` and `LogEntry` types. The `on_chain` types
are **not** exposed through the interface.

### 3. `RpcProvider.waitForReceipt()` (interface addition)

One new method on the abstract interface. Default parameters:
- `timeout`: falls back to constructor-level default on `DefaultRpcProvider` (2 minutes)
- `pollInterval`: defaults to 4 seconds (half a Sepolia block time)

### 4. `DefaultRpcProvider.waitForReceipt()` (implementation)

- Uses existing `_provider.request(EthereumRequestGetTransactionReceipt(...))` from `on_chain`
- Loops with `Future.delayed(pollInterval)` until result is non-null
- Throws `TimeoutException` on expiry
- Checks `receipt.status == false` and throws a descriptive error for reverted transactions
- Maps `on_chain` receipt → our `TransactionReceipt`

### 5. `FakeRpcProvider.waitForReceipt()` (fake_rpc_provider.dart)

New field: `Map<String, TransactionReceipt> receiptMocks`

```dart
@override
Future<TransactionReceipt> waitForReceipt(String txHash, {...}) async {
  return receiptMocks[txHash] ?? TransactionReceipt(
    txHash: txHash,
    blockNumber: 1,
    status: true,
    logs: [],
  );
}
```

### 6. `EASConstants.attestedEventTopic`

New constant: the keccak256 of `"Attested(address,address,bytes32,bytes32)"`.
Used in `_parseAttestedUID()` to filter logs by event signature.

```dart
// Precomputed value — verify against EAS contract ABI at implementation time
static const String attestedEventTopic =
    '0x8bf46bf4cfd674fa735a3d63ec1c9ad4153f033c290341f3a588b75685141b35';
```

### 7. `EASConstants.timestampedEventTopic`

New constant: the keccak256 of `"Timestamped(bytes32,uint64)"`.
Used in `_parseTimestampedEvent()` to filter logs.

```dart
// Compute at implementation time using: keccak256("Timestamped(bytes32,uint64)")
static const String timestampedEventTopic = '0x...';
```

### 8. `_parseAttestedUID()` (private, in `onchain_client.dart`)

```
Input:  List<TransactionLog> logs
Output: String uid ("0x..." bytes32 hex)

Algorithm:
  1. Filter logs where topics[0] == EASConstants.attestedEventTopic
  2. Take the first matching log
  3. Extract log.data (hex string, 66 chars with 0x prefix = 32 bytes, non-indexed)
  4. Return as-is (already a valid bytes32 hex string)
  5. Throw StateError if no matching log found
```

### 9. `_parseTimestampedEvent()` (private, in `onchain_client.dart`)

```
Input:  List<TransactionLog> logs, String inputUID
Output: (String uid, BigInt time)

Algorithm:
  1. Filter logs where topics[0] == EASConstants.timestampedEventTopic
  2. Take the first matching log
  3. uid  = log.topics[1] (indexed bytes32 — the anchored UID)
  4. time = log.topics[2] decoded as uint64 BigInt (indexed uint64, zero-padded to 32 bytes)
  5. Throw StateError if no matching log found
```

Note: `uid` from the event can be cross-checked against the `inputUID` argument as a
sanity assertion during development.

---

## Affected Files

| File | Change |
|---|---|
| `lib/src/models/attest_result.dart` | **Create** — `AttestResult` |
| `lib/src/models/timestamp_result.dart` | **Create** — `TimestampResult` |
| `lib/src/models/register_result.dart` | **Create** — `RegisterResult` |
| `lib/src/rpc/transaction_receipt.dart` | **Create** — `TransactionReceipt` + `TransactionLog` |
| rpc_provider.dart | **Modify** — add `waitForReceipt()` |
| default_rpc_provider.dart | **Modify** — implement `waitForReceipt()`; add `receiptTimeout` constructor param |
| onchain_client.dart | **Modify** — `attest()` → `AttestResult`; `timestamp()` → `TimestampResult`; add `_parseAttestedUID()` and `_parseTimestampedEvent()` |
| constants.dart | **Modify** — add `attestedEventTopic` and `timestampedEventTopic` constants |
| schema_registry.dart | **Modify** — `register()` returns `RegisterResult` |
| location_protocol.dart | **Modify** — export new public types |
| fake_rpc_provider.dart | **Modify** — implement `waitForReceipt()`; add `receiptMocks` |
| eas_client_offline_test.dart | **Modify** — add offline tests for `attest()` and `timestamp()` via `FakeRpcProvider` |
| sepolia_onchain_test.dart | **Modify** — update all three call sites to use new return types |

---

## Breaking Changes

| Method | Before | After |
|---|---|---|
| `EASClient.attest()` | `Future<String>` | `Future<AttestResult>` |
| `EASClient.timestamp()` | `Future<String>` | `Future<TimestampResult>` |
| `SchemaRegistryClient.register()` | `Future<String>` | `Future<RegisterResult>` |
| `RpcProvider` (interface) | — | `waitForReceipt()` required |

Any custom `RpcProvider` implementation must add `waitForReceipt()`.

---

## Testing Requirements

### Unit tests (offline, instant)

- `AttestResult`, `TimestampResult`, and `RegisterResult` construction and field access
- `TransactionReceipt` and `TransactionLog` construction
- `_parseAttestedUID()` parses UID correctly from a well-formed mock log
- `_parseAttestedUID()` throws `StateError` when no `Attested` log is present
- `_parseTimestampedEvent()` parses UID and time correctly from a well-formed mock log
- `_parseTimestampedEvent()` throws `StateError` when no `Timestamped` log is present
- `EASClient.attest()` returns correct `AttestResult` using `FakeRpcProvider` with a mocked receipt containing an `Attested` log
- `EASClient.timestamp()` returns correct `TimestampResult` using `FakeRpcProvider` with a mocked receipt containing a `Timestamped` log
- `SchemaRegistryClient.register()` returns correct `RegisterResult` with locally-computed UID matching `computeSchemaUID()`

### Integration tests (Sepolia, tagged `@Tags(['sepolia'])`)

- `EASClient.attest()` returns an `AttestResult` with a valid 66-char `uid` and correct `txHash`
- `EASClient.timestamp()` returns a `TimestampResult` with a non-zero `time` and the expected `uid`
- `SchemaRegistryClient.register()` returns a `RegisterResult` whose `uid` matches `computeSchemaUID()`

---

## Out of Scope

- `SchemaRegistryClient.register()` receipt polling — UID is deterministic and computed locally; `RegisterResult.uid` is available immediately after `sendTransaction()` returns, before any block is mined
- Batch attestation (`multiAttest()`, `multiTimestamp()`) — separate feature
- `waitForReceipt()` retry-on-network-error logic — simple timeout + poll is sufficient for now
