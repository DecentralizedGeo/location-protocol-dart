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
- **Artifacts**: `doc/spec/plans/2026-03-13_phase2-onchain-operations.md` (10 tasks, 14 files)

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
- **Artifacts**: `doc/spec/plans/2026-03-13_phase3-codebase-review.md` (8 tasks)

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

### [ID: PHASE7_DOC_SNIPPET_VALIDATION_EXEC] -> Follows [PHASE6_LOCATION_VALIDATION_EXEC]
- **Date**: 2026-03-16
- **Event**: Implementation of Phase 7 (Documentation Snippet Extraction & Validation)
- **Status**: COMPLETED
- **Context**: Added `scripts/docs_snippet_extractor.dart` to scan docs, extract fenced Dart snippets, classify step/error/standalone blocks, and generate `test/doc/docs_snippets_test.dart` as a derived artifact with `@Tags(['doc-snippets'])`.
- **Key Findings**:
	- Fixed CRLF fence parsing to avoid missing snippets in Windows-authored markdown files.
	- Added generation-time normalization for utility snippets that call `tearDown(...)` so they execute safely in runtime tests.
	- Stabilized Sepolia doc-snippet execution by skip-guarding duplicate mempool transaction errors (`already known`) while preserving core snippet execution.
- **Verification**: Offline doc-snippet suite passes, Sepolia doc-snippet suite passes in-session, full non-Sepolia suite passes, and generator output is idempotent across two consecutive runs.

### [ID: PHASE8_SIGNER_INTERFACE_EXEC] -> Follows [PHASE7_DOC_SNIPPET_VALIDATION_EXEC]
- **Date**: 2026-03-17
- **Event**: Implementation of Phase 8 (Signer Interface Design)
- **Status**: COMPLETED
- **Context**: Introduced abstract `Signer` class to decouple `OffchainSigner` from raw private keys, enabling wallet-backed EIP-712 signing.
- **Files Added**:
  - `lib/src/eas/signer.dart` — abstract `Signer` with `address`, `signDigest`, and default `signTypedData` (JSON→Eip712TypedData→encode→signDigest)
  - `lib/src/eas/local_key_signer.dart` — `LocalKeySigner` wrapping `ETHPrivateKey`  
  - `test/eas/signer_test.dart` — 6 tests for Signer contract + LocalKeySigner (including real-crypto ecRecover)
  - `test/models/signature_test.dart` — 7 tests for `EIP712Signature.fromHex()`
- **Files Modified**:
  - `lib/src/models/signature.dart` — added `EIP712Signature.fromHex()` factory (65-byte r||s||v layout, throws on wrong length)
  - `lib/src/eas/offchain_signer.dart` — refactored to accept `Signer`; added `fromPrivateKey` factory; replaced `_buildTypedData` with `buildOffchainTypedDataJson` (public static, JSON-safe map); `_computeOffchainUID` now delegates to `computeOffchainUID` (public static); `signOffchainAttestation` now uses `signer.signTypedData(jsonMap)` + v normalization (0/1 → 27/28); `verifyOffchainAttestation` uses `fromJson→encode` path
  - `lib/src/eas/onchain_client.dart` — added `buildAttestTxRequest({easAddress, callData, from?, value?})` static helper
  - `lib/location_protocol.dart` — added `signer.dart` and `local_key_signer.dart` exports
  - `test/eas/offchain_signer_test.dart` — updated setUp to `fromPrivateKey`; added Task 4 utility group (6 tests), Task 5 fromPrivateKey/parity/v-norm groups (3 tests), `_LowVSignerWrapper` helper
  - `test/integration/full_workflow_test.dart` — updated to `fromPrivateKey`; added Task 6 wallet-style signer integration test with `_WalletStyleSigner`
  - `test/eas/onchain_client_test.dart` — added Task 7 buildAttestTxRequest group (4 tests)
- **Key Design Constraints**:
  - `buildOffchainTypedDataJson`: uint values MUST be decimal strings (e.g. `'11155111'`), NOT hex — `on_chain` v8 calls `valueAsBigInt(allowHex: false)` for `uint*` types
  - `EIP712Signature.fromHex`: 65-byte layout is `r[32] || s[32] || v[1]` (NOT `v || r || s`)
  - v normalization: `if (v < 27) v += 27` (some wallets return 0/1)
  - `signTypedData` default impl: `Eip712TypedData.fromJson(map).encode()` → 32-byte digest → `signDigest`
  - `buildAttestTxRequest` value: always hex string (e.g. `'0x0'` for zero)
- **Verification**: 93/93 unit tests pass across all test directories (no regressions)
- **Commits**: 5 clean commits on `main` — `feat: add EIP712Signature.fromHex()`, `feat: add Signer abstract class and LocalKeySigner implementation`, `feat: expose buildOffchainTypedDataJson and computeOffchainUID as public utilities`, `feat: refactor OffchainSigner to accept Signer, add fromPrivateKey factory`, `feat: add EASClient.buildAttestTxRequest() wallet-friendly tx helper`, `feat: update barrel exports to include Signer and LocalKeySigner`

### [ID: PHASE8.1_DOC_REFRAMING] -> Follows [PHASE8_SIGNER_INTERFACE_EXEC]
- Date: 2026-03-18
- Event: Phase 8.1 Documentation Reframing
- Status: COMPLETED
- Context: Reframed the documentation to explicitly decouple the chain-agnostic Location Protocol payload from the Ethereum-specific EAS Reference Envelope. Clarified portability to non-EVM chains like Solana and Filecoin using native wrappers.
- Commits: 1 commit on `main` — `docs: Phase 8.1 documentation reframing (reference implementation and EAS envelope)`

### [ID: ISSUE4_UID_PARITY_TEST_REFINEMENT] -> Follows [PHASE8.1_DOC_REFRAMING]
- Date: 2026-03-25
- Event: Strengthened issue #4 cross-chain UID parity coverage
- Status: COMPLETED
- Context: Expanded `test/eas/offchain_signer_test.dart` so the multi-chain parity test now directly recomputes `OffchainSigner.computeOffchainUID(...)` from each signed attestation and rebuilds typed-data JSON for both chains. The test now proves identical UID-driving message fields and identical recomputed UIDs across chains while showing that `domain.chainId`, `domain.verifyingContract`, typed-data digests, and signatures differ.
- Verification: `dart test test/eas/offchain_signer_test.dart -r expanded` passed with 18/18 tests.
