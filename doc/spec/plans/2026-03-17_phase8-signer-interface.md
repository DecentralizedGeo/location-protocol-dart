# Phase 8: Signer Interface Design — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce an abstract `Signer` class that decouples `OffchainSigner` from raw private keys, enabling wallet-backed EIP-712 signing (Privy, MetaMask, WalletConnect), along with a wallet-friendly onchain transaction request helper.

**Architecture:** Single `Signer` abstract class with `address`, `signDigest()` (abstract), and `signTypedData()` (default: reconstruct `Eip712TypedData` from JSON → `encode()` → `signDigest()`). `OffchainSigner` calls `signer.signTypedData(jsonMap)` instead of using `ETHPrivateKey` directly. New public static methods expose typed-data JSON construction and UID computation. `EASClient.buildAttestTxRequest()` wraps ABI-encoded calldata into a standard `{to, data, value, from?}` transaction request map for wallet SDK consumption. Key technical insight: `on_chain` v8's `Eip712TypedData.fromJson()` correctly round-trips JSON-safe maps (decimal strings for integers, hex strings for bytes) through `_ensureCorrectValues()` coercion during `encode()`, producing identical digests — so we only need to build one JSON-safe map representation that serves both local signing and wallet SDK pass-through.

**Tech Stack:** Dart 3.11+, `on_chain` ^8.0.0 (`Eip712TypedData`, `ETHPrivateKey`), `blockchain_utils` ^6.0.0 (keccak256, `BytesUtils`)

**PRD:** `doc/spec/plans/prd-signer-interface.md`
**Research Report:** `doc/spec/artifacts/signer-interface-report.md`
**Wallet Tx Request Spec:** `doc/spec/artifacts/building-wallet-tx-requests.md`

---

## Table of Contents

| # | Task | Steps | Dependencies |
|---|------|-------|-------------|
| 1 | [`EIP712Signature.fromHex()` Factory](#task-1-eip712signaturefromhex-factory) | 7 | None |
| 2 | [`Signer` Abstract Class](#task-2-signer-abstract-class) | 7 | None |
| 3 | [`LocalKeySigner` Implementation](#task-3-localkeysigner-implementation) | 9 | Task 2 |
| 4 | [Public Typed-Data and UID Utilities](#task-4-public-typed-data-and-uid-utilities-on-offchainsigner) | 10 | None |
| 5 | [Refactor `OffchainSigner` to Accept `Signer`](#task-5-refactor-offchainsigner-to-accept-signer) | 13 | Tasks 1–4 |
| 6 | [Wallet-Style Signer Integration Test](#task-6-wallet-style-signer-integration-test) | 3 | Task 5 |
| 7 | [`EASClient.buildAttestTxRequest()` Helper](#task-7-easclientbuildattesttxrequest-helper) | 9 | None |
| 8 | [Barrel Export Updates](#task-8-barrel-export-updates) | 4 | Tasks 2, 3 |
| 9 | [Documentation Updates](#task-9-documentation-updates) | 4 | Tasks 5, 7 |
| 10 | [Verification & Memory Consolidation](#task-10-verification--memory-consolidation) | 8 | All |

**Total: 10 tasks, ~74 TDD steps**

**Parallelization:** Tasks 1, 2, 4, 7 have no interdependencies and can be executed concurrently. Task 3 depends only on Task 2. Task 5 is the main convergence point. Tasks 6, 8–10 are sequential after Task 5.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `lib/src/eas/signer.dart` | `Signer` abstract class |
| Create | `lib/src/eas/local_key_signer.dart` | `LocalKeySigner` implementation |
| Modify | `lib/src/models/signature.dart` | Add `EIP712Signature.fromHex()` factory |
| Modify | `lib/src/eas/offchain_signer.dart` | Refactor to accept `Signer`, expose public utilities |
| Modify | `lib/src/eas/onchain_client.dart` | Add `buildAttestTxRequest()` static helper |
| Modify | `lib/location_protocol.dart` | Export `signer.dart`, `local_key_signer.dart` |
| Create | `test/models/signature_test.dart` | `EIP712Signature.fromHex()` tests |
| Create | `test/eas/signer_test.dart` | `Signer` + `LocalKeySigner` tests |
| Modify | `test/eas/offchain_signer_test.dart` | `fromPrivateKey` parity + public utility tests |
| Modify | `test/eas/onchain_client_test.dart` | `buildAttestTxRequest` tests |
| Modify | `test/integration/full_workflow_test.dart` | Add wallet-signer integration scenario |

---

## Dependency Graph

```
Task 1: EIP712Signature.fromHex()  ──┐
                                      ├── Task 5: OffchainSigner refactor (convergence)
Task 2: Signer abstract class ───┐   │
                                  ├───┤
Task 3: LocalKeySigner ──────────┘   │
                                      │
Task 4: Public typed-data/UID utils ──┘
                                      │
Task 7: buildAttestTxRequest ─────── (independent)
                                      │
                                      ├── Task 6: Wallet signer integration test
                                      ├── Task 8: Barrel exports
                                      ├── Task 9: Documentation
                                      └── Task 10: Verification & memory
```

---

## Chunk 1: Foundation Layer

### Task 1: `EIP712Signature.fromHex()` Factory

**Files:**
- Modify: `lib/src/models/signature.dart`
- Create: `test/models/signature_test.dart`

**Context:** `eth_signTypedData_v4` returns a single `0x`-prefixed 65-byte hex string (`r[32] || s[32] || v[1]`). Every wallet-backed `Signer` implementation will need to split this into `v/r/s`. Providing a `fromHex` factory eliminates that duplication.

- [ ] **Step 1: Write failing test — valid 65-byte hex**

  In `test/models/signature_test.dart`, create a test that constructs `EIP712Signature.fromHex()` with a known 65-byte hex string (0x-prefixed, 132 chars) and asserts the `v`, `r`, `s` fields are correctly extracted. Use a deterministic test signature from Hardhat key #0.

- [ ] **Step 2: Run test, verify it fails**

  Run: `dart test test/models/signature_test.dart -r expanded`

  Expected: Compilation error — `fromHex` factory does not exist on `EIP712Signature`.

- [ ] **Step 3: Implement `fromHex` factory**

  In `lib/src/models/signature.dart`, add a `factory EIP712Signature.fromHex(String rawSig)` that:
  - Imports `package:blockchain_utils/blockchain_utils.dart` for `BytesUtils`.
  - Strips `0x` prefix, converts to bytes via `BytesUtils.fromHexString`.
  - Validates length is 65 bytes; throws `ArgumentError` otherwise.
  - Extracts `r = bytes[0..31]`, `s = bytes[32..63]`, `v = bytes[64]`.
  - Returns `EIP712Signature(v: v, r: '0x' + hex(r).padLeft(64, '0'), s: '0x' + hex(s).padLeft(64, '0'))`.

- [ ] **Step 4: Run test, verify it passes**

  Run: `dart test test/models/signature_test.dart -r expanded`

  Expected: PASS.

- [ ] **Step 5: Write edge-case tests**

  Add tests for:
  - Hex without `0x` prefix — still works.
  - Wrong length (64 bytes, 66 bytes) — throws `ArgumentError`.
  - Empty string — throws `ArgumentError`.

- [ ] **Step 6: Run full test, verify all pass**

  Run: `dart test test/models/signature_test.dart -r expanded`

  Expected: All PASS.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/src/models/signature.dart test/models/signature_test.dart
  git commit -m "feat: add EIP712Signature.fromHex() factory for wallet signature parsing"
  ```

---

### Task 2: `Signer` Abstract Class

**Files:**
- Create: `lib/src/eas/signer.dart`
- Create: `test/eas/signer_test.dart`

**Context:** `Signer` is the abstract base that all signing implementations extend. It owns one abstract method (`signDigest`) and one default method (`signTypedData` that reconstructs `Eip712TypedData` from JSON and delegates to `signDigest`). Consumer wallet adapters override `signTypedData` to call their wallet SDK directly.

- [ ] **Step 1: Write failing test — `Signer` contract**

  In `test/eas/signer_test.dart`, create a minimal concrete subclass `_TestSigner extends Signer` that implements `address` (returns a hardcoded address) and `signDigest()` (returns a hardcoded `EIP712Signature`). Write a test that:
  - Instantiates `_TestSigner`.
  - Asserts `signer.address` returns the expected string.
  - Calls `signer.signDigest(Uint8List(32))` and asserts it returns the canned signature.

- [ ] **Step 2: Run test, verify it fails**

  Run: `dart test test/eas/signer_test.dart -r expanded`

  Expected: Compilation error — `Signer` class does not exist.

- [ ] **Step 3: Implement `Signer` abstract class**

  In `lib/src/eas/signer.dart`:
  - Import `dart:typed_data`, `package:on_chain/on_chain.dart` (for `Eip712TypedData`), and `../models/signature.dart`.
  - Declare `abstract class Signer` with:
    - `String get address` — abstract getter.
    - `Future<EIP712Signature> signDigest(Uint8List digest)` — abstract.
    - `Future<EIP712Signature> signTypedData(Map<String, dynamic> typedData) async` — default implementation: construct `Eip712TypedData.fromJson(typedData)`, call `.encode()` to get the `List<int>` digest, then `return signDigest(Uint8List.fromList(digest))`.

- [ ] **Step 4: Run test, verify it passes**

  Run: `dart test test/eas/signer_test.dart -r expanded`

  Expected: PASS.

- [ ] **Step 5: Write test for default `signTypedData` behavior**

  Add a test that:
  - Creates a `_TestSigner` whose `signDigest()` captures the received `Uint8List digest` and returns a canned `EIP712Signature`.
  - Builds a minimal EIP-712 typed data JSON map (using the EAS `Attest` structure with known values — decimal strings for ints, hex strings for bytes).
  - Calls `signer.signTypedData(jsonMap)`.
  - Asserts: (a) `signDigest` was called with the correct 32-byte digest (computed independently via `Eip712TypedData.fromJson(jsonMap).encode()`), and (b) the returned signature matches the canned value.

  This tests the default delegation path — real `Eip712TypedData` encoding, not mocked behavior.

- [ ] **Step 6: Run test, verify it passes**

  Run: `dart test test/eas/signer_test.dart -r expanded`

  Expected: All PASS.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/src/eas/signer.dart test/eas/signer_test.dart
  git commit -m "feat: add Signer abstract class with signDigest and signTypedData"
  ```

---

### Task 3: `LocalKeySigner` Implementation

**Files:**
- Create: `lib/src/eas/local_key_signer.dart`
- Modify: `test/eas/signer_test.dart`

**Context:** `LocalKeySigner` wraps `ETHPrivateKey` — the exact same signing logic that `OffchainSigner` uses today. It extends `Signer`, implements `signDigest()` via `ETHPrivateKey.sign(digest, hashMessage: false)`, and inherits the default `signTypedData()`.

**Important:** `LocalKeySigner` must use `extends Signer` (not `implements`) to inherit the default `signTypedData()` body.

- [ ] **Step 1: Write failing test — `LocalKeySigner.address`**

  In `test/eas/signer_test.dart`, add a `LocalKeySigner` group. Use Hardhat key #0 (`ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`). Test that `signer.address` returns the known address `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` (case-insensitive comparison since checksumming may differ).

- [ ] **Step 2: Run test, verify it fails**

  Run: `dart test test/eas/signer_test.dart -r expanded`

  Expected: Compilation error — `LocalKeySigner` does not exist.

- [ ] **Step 3: Implement `LocalKeySigner`**

  In `lib/src/eas/local_key_signer.dart`:
  - Import `dart:typed_data`, `package:on_chain/on_chain.dart`, `package:blockchain_utils/blockchain_utils.dart`, `../models/signature.dart`, `signer.dart`.
  - `class LocalKeySigner extends Signer`:
    - `final ETHPrivateKey _privateKey;`
    - Constructor: `LocalKeySigner({required String privateKeyHex}) : _privateKey = ETHPrivateKey(privateKeyHex);`
    - `@override String get address => _privateKey.publicKey().toAddress().address;`
    - `@override Future<EIP712Signature> signDigest(Uint8List digest) async`: Call `_privateKey.sign(digest, hashMessage: false)`, extract `v`, `rBytes`, `sBytes`, return `EIP712Signature(v: sig.v, r: '0x${BytesUtils.toHexString(sig.rBytes).padLeft(64, "0")}', s: '0x${BytesUtils.toHexString(sig.sBytes).padLeft(64, "0")}')`.

- [ ] **Step 4: Run test, verify it passes**

  Run: `dart test test/eas/signer_test.dart -r expanded`

  Expected: PASS.

- [ ] **Step 5: Write test — `signDigest` produces valid signature**

  Build a known EIP-712 typed data digest (use the same parameters as existing `offchain_signer_test.dart`), sign with `LocalKeySigner.signDigest(digest)`, then recover the signer address using `ETHPublicKey.getPublicKey()`. Assert the recovered address matches `signer.address`.

  This tests real cryptographic behavior — NOT mocked behavior.

- [ ] **Step 6: Run test, verify it passes**

  Run: `dart test test/eas/signer_test.dart -r expanded`

  Expected: PASS.

- [ ] **Step 7: Write test — `signTypedData` (inherited default) produces parity with `signDigest`**

  Build a JSON-safe typed data map using EAS `Attest` structure with known values. Call `signer.signTypedData(jsonMap)`. Independently compute the digest via `Eip712TypedData.fromJson(jsonMap).encode()`, call `signer.signDigest(Uint8List.fromList(digest))`. Assert both signatures are byte-identical (`v`, `r`, `s` match).

- [ ] **Step 8: Run test, verify it passes**

  Run: `dart test test/eas/signer_test.dart -r expanded`

  Expected: PASS.

- [ ] **Step 9: Commit**

  ```bash
  git add lib/src/eas/local_key_signer.dart test/eas/signer_test.dart
  git commit -m "feat: add LocalKeySigner wrapping ETHPrivateKey for Signer interface"
  ```

---

### Task 4: Public Typed-Data and UID Utilities on `OffchainSigner`

**Files:**
- Modify: `lib/src/eas/offchain_signer.dart`
- Modify: `test/eas/offchain_signer_test.dart`

**Context:** The current `_buildTypedData()` and `_computeOffchainUID()` are private. Making them public statics enables external integrations to inspect typed data and compute UIDs independently (PRD FR-6, FR-7). The typed data utility returns a JSON-safe map (decimal strings for ints, hex strings for bytes) suitable for both `Eip712TypedData.fromJson()` and wallet `eth_signTypedData_v4`.

**Critical technical detail:** Integer values in the JSON map MUST be decimal strings (e.g., `'11155111'`), NOT hex. `on_chain` v8's `_ensureCorrectValues()` calls `valueAsBigInt(allowHex: false)` for `uint*` types, which rejects hex-formatted integers.

- [ ] **Step 1: Write failing test — `buildOffchainTypedDataJson` returns correct structure**

  In `test/eas/offchain_signer_test.dart`, add a new group `'public utilities'`. Test that `OffchainSigner.buildOffchainTypedDataJson(...)` returns a `Map<String, dynamic>` with keys `types`, `primaryType`, `domain`, `message`. Assert:
  - `primaryType == 'Attest'`
  - `domain['name'] == 'EAS Attestation'`
  - `domain['chainId']` is a decimal string of the passed chainId
  - `message['schema']` is the passed schema UID (hex)
  - `message['version']` is `EASConstants.attestationVersion` (int `2`)
  - `types['Attest']` has 9 entries matching the EAS V2 offchain structure
  - `types['EIP712Domain']` has 4 entries

- [ ] **Step 2: Run test, verify it fails**

  Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

  Expected: Compilation error — `buildOffchainTypedDataJson` not defined.

- [ ] **Step 3: Implement `buildOffchainTypedDataJson`**

  In `lib/src/eas/offchain_signer.dart`, add a public static method:

  ```dart
  static Map<String, dynamic> buildOffchainTypedDataJson({
    required int chainId,
    required String easContractAddress,
    required String schemaUID,
    required String recipient,
    required BigInt time,
    required BigInt expirationTime,
    required bool revocable,
    required String refUID,
    required Uint8List data,
    required Uint8List salt,
    String easVersion = '1.0.0',
  })
  ```

  Returns a map with:
  - `types`: Map with `EIP712Domain` (4 fields) and `Attest` (9 fields), each as `List<Map<String, String>>` with `name` and `type` keys.
  - `primaryType`: `'Attest'`.
  - `domain`: `{ 'name': 'EAS Attestation', 'version': easVersion, 'chainId': chainId.toString(), 'verifyingContract': easContractAddress }`.
  - `message`: all values JSON-safe — BigInt → `.toString()` (decimal), Uint8List → `'0x' + BytesUtils.toHexString(...)`, int/bool/String as-is.

  The `Attest` type fields in order: `version` (uint16), `schema` (bytes32), `recipient` (address), `time` (uint64), `expirationTime` (uint64), `revocable` (bool), `refUID` (bytes32), `data` (bytes), `salt` (bytes32).

- [ ] **Step 4: Run test, verify it passes**

  Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

  Expected: PASS.

- [ ] **Step 5: Write digest parity test**

  Build typed data JSON via the new public utility. Independently build `Eip712TypedData` with native Dart types (matching the current `_buildTypedData` implementation — `BigInt` for chainId/time, `Uint8List` for data/salt). Assert that `Eip712TypedData.fromJson(jsonMap).encode()` produces the identical digest as the natively-built `Eip712TypedData(...).encode()`.

  This is the critical round-trip test proving the JSON representation works.

- [ ] **Step 6: Run test, verify it passes**

  Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

  Expected: PASS.

- [ ] **Step 7: Write failing test — `computeOffchainUID` matches existing behavior**

  Call `OffchainSigner.computeOffchainUID(...)` with the same parameters used in an existing test's `signOffchainAttestation()` call (inject a deterministic salt). Assert the returned UID matches the `SignedOffchainAttestation.uid` from the signed result.

- [ ] **Step 8: Implement `computeOffchainUID`**

  Extract the current `_computeOffchainUID()` body into a public static method on `OffchainSigner`:

  ```dart
  static String computeOffchainUID({
    required String schemaUID,
    required String recipient,
    required BigInt time,
    required BigInt expirationTime,
    required bool revocable,
    required String refUID,
    required Uint8List data,
    required Uint8List salt,
  })
  ```

  Logic is identical to the existing private method. The private `_computeOffchainUID` call sites are replaced with calls to the public static.

- [ ] **Step 9: Run test, verify it passes**

  Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

  Expected: PASS. ALL existing tests also pass (no behavioral change).

- [ ] **Step 10: Commit**

  ```bash
  git add lib/src/eas/offchain_signer.dart test/eas/offchain_signer_test.dart
  git commit -m "feat: expose buildOffchainTypedDataJson and computeOffchainUID as public utilities"
  ```

---

## Chunk 2: Core Refactor

### Task 5: Refactor `OffchainSigner` to Accept `Signer`

**Files:**
- Modify: `lib/src/eas/offchain_signer.dart`
- Modify: `test/eas/offchain_signer_test.dart`

**Context:** This is the core refactoring. The primary constructor changes from `privateKeyHex` to `Signer signer`. A `fromPrivateKey` factory wraps in `LocalKeySigner` for backward compatibility. `signOffchainAttestation()` uses `signer.signTypedData(jsonMap)` instead of `ETHPrivateKey` directly. `v` normalization is added. `verifyOffchainAttestation()` switches from the private `_buildTypedData` to `buildOffchainTypedDataJson` → `Eip712TypedData.fromJson().encode()`.

**v normalization rule:** Normalize to 27/28 (`v < 27 ? v + 27 : v`). This matches the existing `EIP712Signature.v` convention used throughout the codebase, existing test assertions, and what `verifyOffchainAttestation()` expects. Zero changes needed in verification logic.

- [ ] **Step 1: Write failing test — `fromPrivateKey` factory**

  In `test/eas/offchain_signer_test.dart`, add a test that constructs `OffchainSigner.fromPrivateKey(privateKeyHex: testKey, chainId: 11155111, easContractAddress: '0xC2679...')` and asserts `signerAddress` matches the known Hardhat #0 address.

- [ ] **Step 2: Run test, verify it fails**

  Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

  Expected: Compilation error — `fromPrivateKey` factory does not exist.

- [ ] **Step 3: Refactor `OffchainSigner` constructor**

  In `lib/src/eas/offchain_signer.dart`:

  - Add imports: `import 'signer.dart';` and `import 'local_key_signer.dart';`.
  - Change field from `final String _privateKeyHex;` to `final Signer signer;`.
  - Change primary constructor:
    ```dart
    OffchainSigner({
      required this.signer,
      required this.chainId,
      required this.easContractAddress,
      this.easVersion = '1.0.0',
    });
    ```
  - Add factory:
    ```dart
    factory OffchainSigner.fromPrivateKey({
      required String privateKeyHex,
      required int chainId,
      required String easContractAddress,
      String easVersion = '1.0.0',
    }) {
      return OffchainSigner(
        signer: LocalKeySigner(privateKeyHex: privateKeyHex),
        chainId: chainId,
        easContractAddress: easContractAddress,
        easVersion: easVersion,
      );
    }
    ```
  - Change `signerAddress` getter: `String get signerAddress => signer.address;`.
  - Remove the `import 'package:on_chain/on_chain.dart'` usage for `ETHPrivateKey` in the class fields (but keep it if still needed for `Eip712TypedData` in verification or `ETHPublicKey` in recovery).

- [ ] **Step 4: Run test, verify `fromPrivateKey` passes**

  Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

  Expected: `fromPrivateKey` test PASS. Other tests may fail due to constructor change — that's expected; we fix them next.

- [ ] **Step 5: Update existing tests to use `fromPrivateKey`**

  In `test/eas/offchain_signer_test.dart`, change the `setUp()` from:
  ```dart
  signer = OffchainSigner(
    privateKeyHex: testPrivateKeyHex,
    chainId: 11155111,
    easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
    easVersion: '1.0.0',
  );
  ```
  to:
  ```dart
  signer = OffchainSigner.fromPrivateKey(
    privateKeyHex: testPrivateKeyHex,
    chainId: 11155111,
    easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
  );
  ```

  This is the ONLY change to existing test setup. All assertions remain identical.

- [ ] **Step 6: Refactor `signOffchainAttestation()`**

  Replace the signing body:
  - Remove: `final privateKey = ETHPrivateKey(_privateKeyHex);`, `final hash = typedData.encode();`, `final sig = privateKey.sign(hash, hashMessage: false);`, and the `_buildTypedData(...)` call.
  - Add: `final typedDataJson = buildOffchainTypedDataJson(...)` with all parameters.
  - Add: `final rawSig = await signer.signTypedData(typedDataJson);`
  - Add `v` normalization: `final normalizedV = rawSig.v < 27 ? rawSig.v + 27 : rawSig.v;`
  - Construct `EIP712Signature(v: normalizedV, r: rawSig.r, s: rawSig.s)`.
  - Keep UID computation via `computeOffchainUID(...)` (the now-public static).
  - Return `SignedOffchainAttestation` as before.

- [ ] **Step 7: Refactor `verifyOffchainAttestation()`**

  Replace `_buildTypedData(...)` call with:
  - `final typedDataJson = buildOffchainTypedDataJson(...)` with the attestation's stored parameters.
  - `final hash = Eip712TypedData.fromJson(typedDataJson).encode();`.
  - Rest of verification (sigBytes construction, `ETHPublicKey.getPublicKey(hash, sigBytes, hashMessage: false)`) remains identical.

- [ ] **Step 8: Run ALL existing offchain_signer tests**

  Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

  Expected: ALL PASS. Every existing test works via `fromPrivateKey` factory → `LocalKeySigner` → same signing path.

- [ ] **Step 9: Write parity test — primary constructor vs `fromPrivateKey`**

  Create two `OffchainSigner` instances: one via primary constructor (`signer: LocalKeySigner(privateKeyHex: testKey)`) and one via `fromPrivateKey(privateKeyHex: testKey)`. Sign the same attestation with a deterministic salt (inject via the `salt:` parameter). Assert `uid`, `signature.v`, `signature.r`, `signature.s` are identical.

- [ ] **Step 10: Run test, verify parity**

  Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

  Expected: PASS.

- [ ] **Step 11: Write `v` normalization test**

  Create a `_LowVSigner extends Signer` test helper that:
  - Returns `address` matching Hardhat #0 key.
  - Implements `signDigest()`: signs with the real `ETHPrivateKey`, then returns the signature with `v` shifted to 0/1 range (`v - 27`).
  - Does NOT override `signTypedData()` (inherits default, which delegates to `signDigest`).

  Sign with this signer via `OffchainSigner(signer: _LowVSigner(...))`. Assert:
  - The resulting `SignedOffchainAttestation.signature.v` is 27 or 28 (normalized).
  - The attestation passes `verifyOffchainAttestation()`.

- [ ] **Step 12: Run test, verify normalization works**

  Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

  Expected: PASS.

- [ ] **Step 13: Commit**

  ```bash
  git add lib/src/eas/offchain_signer.dart test/eas/offchain_signer_test.dart
  git commit -m "feat: refactor OffchainSigner to accept Signer, add fromPrivateKey factory"
  ```

---

## Chunk 3: Integration & Onchain Helper

### Task 6: Wallet-Style Signer Integration Test

**Files:**
- Modify: `test/integration/full_workflow_test.dart`

**Context:** Prove end-to-end that a non-`LocalKeySigner` can produce valid attestations. This simulates a wallet integration without an actual wallet — the test `Signer` overrides `signTypedData()` to manually compute the digest and sign with a known key, mimicking what `eth_signTypedData_v4` would do.

- [ ] **Step 1: Write integration test — wallet-style signer produces verifiable attestation**

  In `test/integration/full_workflow_test.dart`, add a new test `'wallet-style signer produces valid attestation'`:

  1. Define `_WalletStyleSigner extends Signer` that:
     - Stores a known `ETHPrivateKey` internally (simulating what a wallet holds).
     - Overrides `signTypedData(Map<String, dynamic> typedData)` to: compute digest via `Eip712TypedData.fromJson(typedData).encode()`, sign with `_privateKey.sign(digest, hashMessage: false)`, return `EIP712Signature(v, r, s)`.
     - Implements `signDigest()` as `throw UnsupportedError('wallet signers use signTypedData')` — to prove it's never called.
     - `address` returns the known Hardhat #0 address.
  2. Create `OffchainSigner(signer: _WalletStyleSigner(...), chainId: 11155111, easContractAddress: '0xC2679...')`.
  3. Define a `SchemaDefinition`, `LPPayload`, and `userData`.
  4. Call `signOffchainAttestation(...)`.
  5. Call `verifyOffchainAttestation(signed)`.
  6. Assert `isValid: true` and recovered address matches `signer.address`.

- [ ] **Step 2: Run test, verify it passes**

  Run: `dart test test/integration/full_workflow_test.dart -r expanded`

  Expected: ALL PASS (new test + all existing tests).

- [ ] **Step 3: Commit**

  ```bash
  git add test/integration/full_workflow_test.dart
  git commit -m "test: add wallet-style signer integration test"
  ```

---

### Task 7: `EASClient.buildAttestTxRequest()` Helper

**Files:**
- Modify: `lib/src/eas/onchain_client.dart`
- Modify: `test/eas/onchain_client_test.dart`

**Context:** Per `doc/spec/artifacts/building-wallet-tx-requests.md`, provide a static helper that wraps ABI-encoded calldata into a standard Ethereum transaction request map `{to, data, value, from?}`. This enables wallet-backed onchain attestations without any `DefaultRpcProvider` changes. The map is JSON-serializable and can be passed to any wallet SDK implementing `eth_sendTransaction`.

- [ ] **Step 1: Write failing test — builds correct transaction request map**

  In `test/eas/onchain_client_test.dart`, add a group `'buildAttestTxRequest'`. Build calldata via `EASClient.buildAttestCallData(...)` (existing static method). Call `EASClient.buildAttestTxRequest(easAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e', callData: callData)`. Assert:
  - Result contains key `to` with the EAS address.
  - Result contains key `data` as a `0x`-prefixed hex string.
  - Result contains key `value` as `'0x0'`.
  - Result does NOT contain key `from` (not provided).

- [ ] **Step 2: Run test, verify it fails**

  Run: `dart test test/eas/onchain_client_test.dart -r expanded`

  Expected: Compilation error — `buildAttestTxRequest` not defined.

- [ ] **Step 3: Implement `buildAttestTxRequest`**

  In `lib/src/eas/onchain_client.dart`, add a static method:

  ```dart
  /// Build a wallet-friendly transaction request for EAS.attest().
  ///
  /// Does NOT send or sign the transaction. Packages the ABI-encoded
  /// call data into a standard Ethereum transaction map that can be
  /// serialized and passed to an external wallet for eth_sendTransaction.
  static Map<String, dynamic> buildAttestTxRequest({
    required String easAddress,
    required Uint8List callData,
    String? from,
    BigInt? value,
  }) {
    return {
      if (from != null) 'from': from,
      'to': easAddress,
      'data': '0x${BytesUtils.toHexString(callData)}',
      'value': value != null
          ? '0x${value.toRadixString(16)}'
          : '0x0',
    };
  }
  ```

  Add the necessary import for `BytesUtils` — follow the existing import pattern in this file (check whether `blockchain_utils` is already imported or whether `hex_utils.dart` is used).

- [ ] **Step 4: Run test, verify it passes**

  Run: `dart test test/eas/onchain_client_test.dart -r expanded`

  Expected: PASS.

- [ ] **Step 5: Write test — `from` included when provided**

  Call `buildAttestTxRequest(easAddress: ..., callData: ..., from: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266')`. Assert result contains `from` key with the expected address.

- [ ] **Step 6: Write test — custom `value` renders as hex**

  Call with `value: BigInt.from(1000000000000000000)` (1 ETH). Assert `result['value']` is `'0xde0b6b3a7640000'`.

- [ ] **Step 7: Write test — `data` hex matches `buildAttestCallData` output**

  Assert that `result['data']` starts with `'0x'` and that the bytes match the original `callData` when decoded back. Alternatively, assert the first 4 bytes (function selector) match the expected `attest(...)` selector.

- [ ] **Step 8: Run all tests, verify they pass**

  Run: `dart test test/eas/onchain_client_test.dart -r expanded`

  Expected: ALL PASS.

- [ ] **Step 9: Commit**

  ```bash
  git add lib/src/eas/onchain_client.dart test/eas/onchain_client_test.dart
  git commit -m "feat: add EASClient.buildAttestTxRequest() for wallet-backed onchain attestations"
  ```

---

## Chunk 4: Exports, Documentation & Verification

### Task 8: Barrel Export Updates

**Files:**
- Modify: `lib/location_protocol.dart`

- [ ] **Step 1: Add exports**

  Add to the EAS layer section of `lib/location_protocol.dart`:
  ```dart
  export 'src/eas/signer.dart';
  export 'src/eas/local_key_signer.dart';
  ```

  These files have no transitive exports that would leak `on_chain` types — `Signer` and `LocalKeySigner` use library-owned types (`EIP712Signature`, `Uint8List`) at their public API surface.

- [ ] **Step 2: Run `dart analyze`**

  Run: `dart analyze lib/location_protocol.dart`

  Expected: No issues. No name collisions.

- [ ] **Step 3: Run full test suite**

  Run: `dart test --exclude-tags sepolia -r expanded`

  Expected: ALL PASS. Exports didn't break anything.

- [ ] **Step 4: Commit**

  ```bash
  git add lib/location_protocol.dart
  git commit -m "feat: export Signer and LocalKeySigner from barrel"
  ```

---

### Task 9: Documentation Updates

**Files:**
- Modify: `doc/guides/reference-api.md`
- Modify: `doc/guides/tutorial-first-attestation.md`

- [ ] **Step 1: Update reference-api.md**

  Add sections for:
  - **`Signer`** abstract class: description, `address` getter, `signDigest(Uint8List)` abstract, `signTypedData(Map<String, dynamic>)` default behavior.
  - **`LocalKeySigner`**: constructor (`privateKeyHex`), inherits `signTypedData` default.
  - **`OffchainSigner.fromPrivateKey()`**: factory for backward compatibility, parameters.
  - **`OffchainSigner.buildOffchainTypedDataJson()`**: return type, parameter list, JSON structure notes (decimal strings for integers, hex for bytes).
  - **`OffchainSigner.computeOffchainUID()`**: parameter list, return type.
  - **`EASClient.buildAttestTxRequest()`**: parameter list, return map structure (`{to, data, value, from?}`), usage with wallet SDKs.
  - **`EIP712Signature.fromHex()`**: parameter, byte layout (`r[32] || s[32] || v[1]`), error conditions.

- [ ] **Step 2: Update tutorial-first-attestation.md**

  - Update the offchain signing example to use `OffchainSigner.fromPrivateKey(...)`.
  - Add a new subsection **"Using a Wallet Signer"** showing the pattern: implement `Signer`, override `signTypedData()`, pass to `OffchainSigner`.
  - Add a new subsection **"Onchain Attestation with External Wallets"** showing the `buildAttestCallData` → `buildAttestTxRequest` → wallet SDK flow (reference the pattern from `building-wallet-tx-requests.md`).

- [ ] **Step 3: Regenerate doc snippets**

  Run: `dart run scripts/docs_snippet_extractor.dart`
  Run: `dart test test/doc/docs_snippets_test.dart --tags doc-snippets -r expanded`

  Expected: Generated tests pass or have known Sepolia-skip guards.

- [ ] **Step 4: Commit**

  ```bash
  git add doc/guides/reference-api.md doc/guides/tutorial-first-attestation.md
  git add test/doc/docs_snippets_test.dart
  git commit -m "docs: update API reference and tutorial for Signer interface"
  ```

---

### Task 10: Verification & Memory Consolidation

- [ ] **Step 1: Run `dart analyze`**

  Run: `dart analyze`

  Expected: Zero issues on all files touched in this phase.

- [ ] **Step 2: Run full non-Sepolia test suite**

  Run: `dart test --exclude-tags sepolia -r expanded`

  Expected: ALL PASS. Clean output. No warnings in test execution.

- [ ] **Step 3: Run Sepolia integration tests (if env available)**

  Run: `dart test test/integration/sepolia_onchain_test.dart --tags sepolia -r expanded`

  Expected: PASS or explicit env-skip messages.

- [ ] **Step 4: Update `.ai/memory/episodic.md`**

  Add entry:
  ```
  ### [ID: PHASE8_SIGNER_INTERFACE_EXEC] -> Follows [PHASE7_DOC_SNIPPET_VALIDATION_EXEC]
  - Date: 2026-03-17
  - Event: Implementation of Phase 8 (Signer Interface Design)
  - Status: COMPLETED
  - Context: Introduced abstract Signer class with signDigest/signTypedData,
    LocalKeySigner wrapping ETHPrivateKey, OffchainSigner refactored to accept Signer
    with fromPrivateKey factory, public buildOffchainTypedDataJson and computeOffchainUID
    utilities, EIP712Signature.fromHex factory, EASClient.buildAttestTxRequest helper
    for wallet-backed onchain attestations.
  - Key Insight: on_chain v8 Eip712TypedData.fromJson() round-trips JSON-safe maps
    via _ensureCorrectValues() coercion — decimal strings for uint types
    (allowHex: false), hex strings for bytes types (allowHex: true).
  ```

- [ ] **Step 5: Update `.ai/memory/semantic.md`**

  Add entries for:
  - `Signer` interface contract: `address` getter, `signDigest(Uint8List)` abstract, `signTypedData(Map)` default via `Eip712TypedData.fromJson().encode()` → `signDigest()`.
  - `LocalKeySigner`: wraps `ETHPrivateKey`, `extends Signer` for default `signTypedData` inheritance.
  - `buildOffchainTypedDataJson`: JSON-safe map contract — decimal strings for `uint*` values, `0x`-hex for `bytes*`/`address`.
  - `Eip712TypedData.fromJson()` round-trip: works with JSON-safe maps; `_ensureCorrectValues(uint*)` calls `valueAsBigInt(allowHex: false)` — hex strings THROW.
  - `buildAttestTxRequest`: output format `{to, data, value, from?}` for `eth_sendTransaction`.
  - `EIP712Signature.fromHex`: parses 65-byte `r[32]||s[32]||v[1]` hex; used by wallet Signer adapters.

- [ ] **Step 6: Update `.ai/memory/procedural.md`**

  Add entries for:
  - `v` normalization pattern: normalize to 27/28 in `OffchainSigner.signOffchainAttestation()`, never in `Signer`. Rule: `v < 27 ? v + 27 : v`.
  - JSON typed data construction: use decimal strings for `uint` values, `0x`-hex for `bytes`/`address`. Never use hex for integers — `_ensureCorrectValues(uint*, ...)` calls `valueAsBigInt(allowHex: false)`.
  - `Signer` subclass pattern: use `extends Signer` (not `implements`) to inherit default `signTypedData()`.
  - Wallet adapter pattern: override `signTypedData()` to call `eth_signTypedData_v4`, use `EIP712Signature.fromHex()` to parse result.

- [ ] **Step 7: Generate walkthrough**

  Create or update `doc/spec/walkthrough.md` with Phase 8 results:
  - What was built: Signer interface, LocalKeySigner, OffchainSigner refactor, public utilities, buildAttestTxRequest.
  - API surface: new classes, methods, factories.
  - Test count: before vs after.
  - Migration path from `OffchainSigner(privateKeyHex:)` to `OffchainSigner.fromPrivateKey(...)` or `OffchainSigner(signer: ...)`.

- [ ] **Step 8: Final commit**

  ```bash
  git add .ai/memory/ doc/spec/walkthrough.md
  git commit -m "docs: Phase 8 verification, memory consolidation, walkthrough"
  ```

---

## Verification Checklist

| Check | Command | Expected |
|-------|---------|----------|
| Static analysis | `dart analyze` | Zero issues on touched files |
| Non-Sepolia tests | `dart test --exclude-tags sepolia -r expanded` | ALL PASS |
| Sepolia tests | `dart test --tags sepolia -r expanded` | PASS or env-skip |
| Doc snippets | `dart test --tags doc-snippets -r expanded` | PASS |
| Backward compat | All existing `offchain_signer_test.dart` tests unchanged (only setUp lines) | PASS |
| Digest parity | `buildOffchainTypedDataJson` → `fromJson().encode()` = native `Eip712TypedData` digest | Tested in Task 4 Step 5 |
| v normalization | Low-v signer produces valid attestation with v ∈ {27, 28} | Tested in Task 5 Step 11 |
| Wallet integration | Wallet-style signer produces verifiable attestation | Tested in Task 6 Step 1 |

---

## Decisions Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| DefaultRpcProvider signer | Deferred; added `buildAttestTxRequest` instead | Offchain is the core value; onchain wallet story via tx request helper without touching provider |
| Class hierarchy | Single `Signer`, no `CustomSigner` | YAGNI — no second consumer yet |
| Delegated attestations | Deferred | No immediate consumer; explicitly future work |
| `v` normalization location | `OffchainSigner.signOffchainAttestation()` | Centralizes assumption; Signer contract stays simple |
| `v` normalization direction | Normalize to 27/28 (not 0/1) | Matches existing `EIP712Signature.v` convention; zero changes to verification or tests |
| Typed data representation | Single JSON-safe map via `buildOffchainTypedDataJson()` | `Eip712TypedData.fromJson()` round-trips correctly; one representation serves local and wallet paths |
| Integer serialization | Decimal strings (not hex) | `on_chain` v8 `_ensureCorrectValues(uint*)` calls `valueAsBigInt(allowHex: false)` — hex throws |
| `Signer` inheritance | `extends Signer` (not `implements`) | Inherits default `signTypedData()` body |
| Wallet onchain flow | `buildAttestCallData` → `buildAttestTxRequest` → wallet `eth_sendTransaction` | Clean boundary: library owns ABI encoding, wallet owns tx lifecycle |
