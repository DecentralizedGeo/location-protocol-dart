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

### [ID: PHASE3_CODEBASE_REVIEW_PLAN] -> Follows [PHASE2_BATCH2_EXEC]
- **Date**: 2026-03-13
- **Event**: Phase 3 Codebase Review — design decisions and implementation plan approved
- **Status**: COMPLETED (planning only; execution pending)
- **Context**: Reviewed the codebase for readability and maintainability improvements. Identified duplicated hex/byte logic, noisy inline ABIs, complex tuple decoding in clients, and tight coupling of RPC credentials in client constructors.
- **Design Decision**: Option A (DRY Refactoring) and Option B (Architectural Expansion). Clients will now require an `RpcProvider` interface via DI, removing raw `rpcUrl`/`privateKey` from their constructors (matching the "Astral" pattern). Tuple decoding moved to domain model factories (`Attestation.fromTuple`).
- **Technical Pivot**: Confirmed `OffchainSigner` intentionally does *not* take the new `RpcProvider`, as it is strictly for local cryptography, maintaining a clean boundary between transport and cryptography.
- **Key Insight**: Discovered `AbiEncoder` blindly trusts user-provided string inputs for `bytes/bytes32` schema fields. Added a requirement to use `HexUtils(.toBytes())` to intercept and safely convert these before handing them to `on_chain`'s tuple coder. Checked changelogs for `on_chain` v8 and `blockchain_utils` v6; confirmed the plan is 100% forward-compatible and inherits constant-time crypto safety automatically.
- **Artifacts**: `docs/spec/plans/2026-03-13_phase3-codebase-review.md` (8 tasks)
