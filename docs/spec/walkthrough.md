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

## Phase 6: Location Type Validation

`LPPayload` now validates that `location` structurally matches declared `locationType` during construction.

### Supported built-in location types

- `coordinate-decimal+lon-lat` → `List<num>` with exactly 2 elements `[lon, lat]` and bounds lon ∈ [-180, 180], lat ∈ [-90, 90]
- `geojson-point` / `geojson-line` / `geojson-polygon` → `Map` parsed as GeoJSON geometry
- `h3` → `String` matching `^[89ab][0-9a-f]{14}$`
- `geohash` → `String` matching `^[0-9b-hjkmnp-z]{1,12}$`
- `wkt` → `String` that parses as WKT geometry
- `address` → non-empty trimmed `String`
- `scaledCoordinates` → `Map` containing numeric `x`, `y`, `scale`

### Custom validators

You can register custom non-built-in location types:

```dart
LocationValidator.register('community.plus-code.v1', (location) {
	if (location is! String || location.trim().isEmpty) {
		throw ArgumentError('plus-code must be a non-empty String');
	}
});
```

Built-ins cannot be overridden. Duplicate custom registrations replace prior custom validators.

### Migration bypass

`LPPayload(validateLocation: false)` bypasses only location type dispatch while keeping semver, URI, and null checks active.
