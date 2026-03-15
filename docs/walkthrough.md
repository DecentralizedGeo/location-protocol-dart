# Phase 4 Walkthrough: Attestation Receipt Enhancement

## Overview

Phase 4 upgrades write-method outputs from bare transaction hashes to rich result objects that include receipt-derived metadata.

- `EASClient.attest()` now returns `AttestResult` with `txHash`, `uid`, and `blockNumber`.
- `EASClient.timestamp()` now returns `TimestampResult` with `txHash`, `uid`, and anchored `time`.
- `SchemaRegistryClient.register()` now returns `RegisterResult` with `txHash` and deterministic schema `uid`.

## Receipt Polling Model

A new `RpcProvider.waitForReceipt(...)` contract was introduced and implemented across provider implementations:

- `DefaultRpcProvider.waitForReceipt()` polls `eth_getTransactionReceipt` until mined.
- Polling uses a configurable timeout (`receiptTimeout`, default 2 minutes) and poll interval override.
- Reverted transactions (`status == false`) throw `StateError`.
- Mapped return type is library-owned (`TransactionReceipt` and `TransactionLog`) to keep `on_chain` internals out of public contracts.

## Event Parsing Flow

Receipt logs are filtered with **topic + contract address** checks:

- `Attested(address,address,bytes32,bytes32)` → extracts UID from `log.data`.
- `Timestamped(bytes32,uint64)` → extracts UID from `topics[1]` and timestamp from `topics[2]`.

Constants now include verified topic hashes:

- `EASConstants.attestedEventTopic`
- `EASConstants.timestampedEventTopic`

## Testing and Mocking

Offline tests now use `FakeRpcProvider.receiptMocks` to inject deterministic mined receipts:

- Unit coverage added for `TransactionReceipt`/`TransactionLog`.
- Unit coverage added for `AttestResult`, `TimestampResult`, `RegisterResult`.
- Offline client tests cover success + failure paths for missing/wrong logs.

## Verification Snapshot

- `dart test --exclude-tags sepolia`: **127 passed**
- `dart analyze`: reports pre-existing issues in `test_tx.dart` (outside this phase scope)
- `dart test --tags sepolia`: executes but depends on live RPC/network state

## Phase 5: Sepolia Fixed Schema Workflow

Recurring Sepolia integration tests now use a fixed pre-registered LP-only schema UID instead of registering a new schema every run.

### One-time bootstrap

Run the bootstrap script once to register the LP-only schema and print an env-ready UID line:

- `dart run scripts/sepolia_schema_bootstrap.dart`

Copy the printed value into `.env`:

- `SEPOLIA_EXISTING_SCHEMA_UID=<uid>`

### Required `.env` keys

- `SEPOLIA_RPC_URL`
- `SEPOLIA_PRIVATE_KEY`
- `SEPOLIA_EXISTING_SCHEMA_UID`

The recurring Sepolia suite validates that the configured UID has `0x` prefix and bytes32 length (66 chars), and explicitly skips tests if values are missing or invalid.

### Recurring Sepolia command

- `dart test --tags sepolia -r expanded`

### Why registration is excluded from recurring runs

- Keeps recurring integration deterministic.
- Avoids creating per-run schemas and duplicate onchain writes.
- Ensures onchain verification focuses on schema existence/non-existence and attest→fetch parity against the fixed UID.
