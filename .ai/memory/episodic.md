# Episodic Memory

### [ID: DESIGN_INCEPTION]
- **Date**: 2026-03-12
- **Event**: Design brainstorming for `location_protocol` Dart library
- **Previous ID**: N/A
- **Status**: COMPLETED
- **Context**: User proved out EAS-compatible offchain attestations in a [Flutter app](https://github.com/SethDocherty/location-protocol-flutter-app). Goal: extract into a standalone, schema-agnostic Dart library. Key decisions: separated layers architecture, LP base field auto-prepend, snake_case for LP fields, convert→serialize (no validation) for MVP location serialization.
- **Artifacts**: `design-document.md` created in conversation brain.

### [ID: PACKAGE_EVAL_PIVOT] -> Follows [DESIGN_INCEPTION]
- **Date**: 2026-03-12
- **Event**: Evaluated 5 Dart packages as alternatives to `web3dart`
- **Status**: COMPLETED
- **Context**: Compared `on_chain`, `blockchain_utils`, `web3_signers`, `eth-sig-util`, `eip1559`. Decision: **replace `web3dart` with `on_chain`** — built-in EIP-712 v1/v3/v4, EIP-1559, typed schema classes, contract interaction. `web3_signers` rejected (Flutter-only). `eth-sig-util` rejected (stale maintenance). `blockchain_utils` comes free as transitive dep of `on_chain`.
- **User Research**: User independently validated `on_chain` is superior for EAS-heavy apps with typed schema classes extending base EIP712 class.

### [ID: PLAN_APPROVED] -> Follows [PACKAGE_EVAL_PIVOT]
- **Date**: 2026-03-12
- **Event**: 3-part implementation plan approved (16 tasks, TDD)
- **Status**: COMPLETED
- **Context**: Plan split across 3 files. Part 1: scaffold + LP + schema. Part 2: EAS constants + models + ABI + signer. Part 3: chain config + onchain clients + integration + README. User chose to execute in a parallel session.

### [ID: PHASE1_PART1_INIT] -> Follows [PLAN_APPROVED]
- **Date**: 2026-03-12
- **Event**: Implementation of Phase 1 Part 1 (LP Core & Schema Layer)
- **Previous ID**: N/A
- **Status**: COMPLETED
- **Context**: Successfully scaffolded the project and built the core LP data model and schema definition logic.
- **Key Pivot**: Downgraded `on_chain` from `8.0.0` to `7.1.0` due to Dart SDK constraint (current: 3.6.2, required for 8.0.0: 3.7.0).
- **Technical Insight**: `on_chain` 7.1.0 exports are slightly different from 8.0.0; used `blockchain_utils` (a dependency of `on_chain`) for `QuickCrypto.keccack256Hash` and `BytesUtils`.

### [ID: PHASE1_PART2_EXEC] -> Follows [PHASE1_PART1_INIT]
- **Date**: 2026-03-12
- **Event**: Implementation of Phase 1 Part 2 (EAS Integration & Offchain Signing)
- **Status**: COMPLETED
- **Context**: Implemented EAS constants, attestation models, ABI encoder, and EIP-712 offchain signer.
- **Key Discovery**: `ABICoder.encode` in `on_chain` v7.1.0 is less reliable than using `TupleCoder` directly for multi-parameter schemas.
- **Verification**: All 27 tests passing, covering core LP validation through to EIP-712 signature recovery.

### [ID: PHASE1_PART3_FINAL] -> Follows [PHASE1_PART2_EXEC]
- **Date**: 2026-03-12
- **Event**: Implementation of Phase 1 Part 3 (Chain Config & Onchain Clients)
- **Status**: COMPLETED
- **Context**: Built `ChainConfig`, `SchemaRegistryClient`, and `EASClient`. Finalized barrel export and integration tests.
- **Key discovery**: `blockchain_utils` must be added as a direct dependency to `pubspec.yaml` to resolve versioning conflicts between `on_chain` requirements and our direct usage of crypto utilities.
- **Technical Pivot**: Fixed `EASClient.buildTimestampCallData` to explicitly convert hex UIDs to `Uint8List` before encoding, as `on_chain` fragments do not auto-coerce strings to `bytes32`.
- **Verification**: Total suite reached 86 tests with 100% pass rate.

### [ID: PHASE2_ONCHAIN_PLAN] -> Follows [PHASE1_PART3_FINAL]
- **Date**: 2026-03-13
- **Event**: Phase 2 Onchain Operations — design decisions and implementation plan approved
- **Status**: COMPLETED (planning only; execution pending)
- **Context**: Designed RPC layer for performing onchain EAS operations (`register`, `getSchema`, `attest`, `timestamp`). Deep-dived into `on_chain` v7.1.0 internals: `EthereumProvider`, `ETHTransaction`, `ETHTransactionBuilder`, `EthereumServiceProvider` mixin, all JSON-RPC method classes.
- **Design Decision**: Option A approved — built-in `dart:io` `HttpClient` wrapping `EthereumServiceProvider` mixin. User passes RPC URL + API token. Zero new dependencies.
- **Critical Bug Caught**: Self-review discovered that manual `keccak256(serialized)` + `sign(hash, hashMessage: false)` would double-hash. `on_chain`'s own `ETHTransactionBuilder.sign()` passes raw serialized bytes with `hashMessage: true` (default). Plan rewritten to use `ETHTransactionBuilder.autoFill()` → `.sign()` → `.sendTransaction()`.
- **Env Strategy**: User prefers `.env` + `.env.example` files (Astral SDK pattern) over bash-exported environment variables for Sepolia integration tests.
- **Artifacts**: `docs/spec/plans/2026-03-13_phase2-onchain-operations.md` (10 tasks, 14 files)

### [ID: PHASE2_BATCH1_EXEC] -> Follows [PHASE2_ONCHAIN_PLAN]
- **Date**: 2026-03-13
- **Event**: Implementation of Phase 2 Batch 1 (RPC Transport & Core Onchain Ops)
- **Status**: COMPLETED
- **Context**: Successfully implemented `HttpRpcService`, `RpcHelper`, `SchemaRegistryClient.register/getSchema`, and `EASClient.buildAttestCallData`.
- **Key Insight**: Discovered that `ETHTransactionBuilder` v7.1.0 in `on_chain` does not expose a public setter for the raw `data` field when using the base constructor. Developed a "manual auto-fill" pattern: `provider.request(nonce/gas/fees)` -> `ETHTransaction.legacy/eip1559(...)` -> `ETHTransaction.fillTransaction(...)` -> `sign(...)`. This ensures pre-encoded ABI payloads are correctly handled with EIP-1559.
- **Verification**: Total suite reached 95 tests with 100% pass rate.
### [ID: PHASE2_BATCH2_EXEC] -> Follows [PHASE2_BATCH1_EXEC]
- **Date**: 2026-03-13
- **Event**: Implementation of Phase 2 Batch 2 (EAS Client Onchain & Integration Verification)
- **Status**: COMPLETED
- **Context**: Implemented `EASClient.attest/timestamp/getAttestation`. Added `Attestation` model for parsing onchain records. Created a dry-run integration test `onchain_workflow_test.dart` that verifies the full RPC pipeline without needing a live network.
- **Key Insight**: ABI tuple encoding for nested structs (like `AttestationRequest`) in `on_chain` requires precise List-of-Lists structures that match the ABI fragment definition (e.g., nesting the `AttestationRequestData` struct inside the request tuple). ABI decoding from `eth_call` requires manual type checking and casting (`BigInt` vs `int`, `Uint8List` vs `List<int>`) to safely map tuple results to Dart models.
- **Verification**: Total suite reached 95 tests with 100% pass rate.

### [ID: SEPOLIA_RLP_BUG_FIX] -> Follows [PHASE3_CODEBASE_REVIEW_PLAN]
- **Date**: 2026-03-13
- **Event**: Debugged and fixed failing Sepolia integration tests (`register` and `timestamp`)
- **Status**: COMPLETED
- **Context**: Both tests failed with `rlp: non-canonical integer (leading zero bytes) for *big.Int, decoding into (types.DynamicFeeTx).Value`. Root cause: `blockchain_utils` v6.0.0's `BigintUtils.bitlengthInBytes(BigInt.zero)` returns `1` (not `0`) due to an explicit guard `if (bitlength == 0) return 1`, causing `toBytes(BigInt.zero)` = `[0x00]`. This RLP-encodes as `0x00` (single byte ≤ 0x7F → pass-through) rather than `0x80` (empty byte string = canonical zero), which Geth rejects for EIP-1559 `DynamicFeeTx.Value`.
- **Key Insight**: The project was already upgraded to `on_chain ^8.0.0` + `blockchain_utils ^6.0.0` (lock file confirmed), so the old v7.1.0/v5.4.0 procedural notes no longer apply. The SDK is now `^3.11.0`.
- **Fix**: Added `_canonicalBigIntBytes` helper (returns `[]` for zero) and `_buildEip1559Bytes` method to `RpcHelper`. For EIP-1559 txs, signing and serialization now bypass `ETHTransaction.serialized` entirely, using `RLPEncoder` directly. Legacy path is unchanged.
- **Verification**: Test 1 (register schema): TX `0x4c800fe269287501679c94fb9a28678f8623b437e1cfbca0ef98426ebfca2e38`. Test 2 (timestamp): TX `0x0f19ad65661d45f2bed9e706126d9599f0255a3e831e3e555368726e1809b24a`. Both confirmed on Sepolia.
- **Secondary Issue**: `FeeHistory.toFee()` throws `RangeError` on Infura Sepolia (empty `rewards` array). Fallback to manual EIP-1559 fees works correctly; both tests pass.

### [ID: PHASE3_CODEBASE_REVIEW_PLAN] -> Follows [PHASE2_BATCH2_EXEC]
- **Date**: 2026-03-13
- **Event**: Phase 3 Codebase Review — design decisions and implementation plan approved
- **Status**: COMPLETED (planning only; execution pending)
- **Context**: Reviewed the codebase for readability and maintainability improvements. Identified duplicated hex/byte logic, noisy inline ABIs, complex tuple decoding in clients, and tight coupling of RPC credentials in client constructors.
- **Design Decision**: Option A (DRY Refactoring) and Option B (Architectural Expansion). Clients will now require an `RpcProvider` interface via DI, removing raw `rpcUrl`/`privateKey` from their constructors (matching the "Astral" pattern). Tuple decoding moved to domain model factories (`Attestation.fromTuple`).
- **Technical Pivot**: Confirmed `OffchainSigner` intentionally does *not* take the new `RpcProvider`, as it is strictly for local cryptography, maintaining a clean boundary between transport and cryptography.
- **Key Insight**: Discovered `AbiEncoder` blindly trusts user-provided string inputs for `bytes/bytes32` schema fields. Added a requirement to use `HexUtils(.toBytes())` to intercept and safely convert these before handing them to `on_chain`'s tuple coder. Checked changelogs for `on_chain` v8 and `blockchain_utils` v6; confirmed the plan is 100% forward-compatible and inherits constant-time crypto safety automatically.
- **Artifacts**: `docs/spec/plans/2026-03-13_phase3-codebase-review.md` (8 tasks)

### [ID: PHASE3_CODEBASE_REVIEW_EXEC] -> Follows [PHASE3_CODEBASE_REVIEW_PLAN]
- **Date**: 2026-03-14
- **Event**: Implementation of Phase 3 (Codebase Review & DI Refactoring)
- **Status**: COMPLETED
- **Context**: Successfully extracted `HexUtils` and `ByteUtils` for readable type expansions. Migrated raw inline JSON ABIs to a central `EASAbis` registry. Moved raw tuple array index-parsing into domain model factories (`Attestation.fromTuple`, `SchemaRecord.fromTuple`).
- **Architectural Shift**: Implemented strict Dependency Injection via the `RpcProvider` interface. `EASClient` and `SchemaRegistryClient` no longer accept URL/keys, requiring a provider instance. Proved the viability of this pattern by creating `FakeRpcProvider` for instant, offline unit tests without network mocking.
- **Verification**: Cleaned up all static analysis warnings and achieved 100% test pass rate across 98 tests (including offline E2E mock tests).

### [ID: PHASE4_RECEIPT_ENHANCEMENT_EXEC] -> Follows [PHASE3_CODEBASE_REVIEW_EXEC]
- **Date**: 2026-03-14
- **Event**: Implementation of Phase 4 (Attestation Receipt Enhancement)
- **Status**: COMPLETED
- **Context**: Replaced bare tx-hash returns with `AttestResult`, `TimestampResult`, and `RegisterResult`; added `RpcProvider.waitForReceipt()` and production polling in `DefaultRpcProvider`; implemented `Attested` and `Timestamped` log parsing with address+topic filtering.
- **Verification**: Non-Sepolia suite reached 127 passing tests (`dart test --exclude-tags sepolia`). Sepolia tagged tests compile and run but depend on live RPC/network health.

### [ID: PHASE5_FIXED_SCHEMA_SEPOLIA_EXEC] -> Follows [PHASE4_RECEIPT_ENHANCEMENT_EXEC]
- **Date**: 2026-03-15
- **Event**: Implementation of Phase 5 (Fixed Schema Sepolia Attest)
- **Status**: COMPLETED
- **Context**: Replaced per-run Sepolia schema registration with fixed env-driven UID usage (`SEPOLIA_EXISTING_SCHEMA_UID`) in recurring integration tests. Added explicit skip guardrails for missing/invalid env values, schema existence check for configured UID, zero-bytes32 non-existence check, and onchain attest→fetch parity assertions using LP-only schema + ABI payload equivalence.
- **Workflow Adjustment (User-approved)**: Implemented one-time schema bootstrap as a script (`scripts/sepolia_schema_bootstrap.dart`) with concise script docs instead of a `sepolia-bootstrap` integration test file.
- **Verification**: `dart test test/integration/sepolia_onchain_test.dart --tags sepolia -r expanded` yields explicit skips without env; `dart test --exclude-tags sepolia --exclude-tags sepolia-bootstrap -r expanded` passes (127 tests).

### [ID: PHASE6_LOCATION_VALIDATION_EXEC] -> Follows [PHASE5_FIXED_SCHEMA_SEPOLIA_EXEC]
- **Date**: 2026-03-16
- **Event**: Implementation of Phase 6 (Location Type Structural Validation)
- **Status**: COMPLETED
- **Context**: Added `LocationValidator` with canonical type dispatch, shape/deep validators (coordinates, GeoJSON, H3, geohash, WKT, address, scaledCoordinates), custom registration with built-in override prevention, and `LPPayload(validateLocation: true|false)` wiring.
- **Migration + docs**: Migrated downstream LP fixtures to canonical valid types/shapes, exported validator in package barrel, removed geobase spike test after permanent coverage, and updated memory + walkthrough docs.
- **Verification**: Phase gates passed for LP, EAS, integration (including Sepolia-tag run), and full non-Sepolia regression; `dart analyze` still reports pre-existing unrelated workspace issues while touched Phase 6 files are diagnostics-clean.
