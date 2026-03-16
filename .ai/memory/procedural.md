# Procedural Memory

### Implementation Standards
- **TDD Rigor (Red-Green-Refactor)**: 
  - 1. Write failing test (ensure it fails for the right reason, e.g., Missing class or failing validation).
  - 2. Implement minimal code to pass.
  - 3. Refactor for Dart idiomatic patterns.
- **Dependency Management**:
  - Always verify `dart pub get` succeeds.
  - If SDK constraints conflict, downgrade library cautiously or request SDK upgrade.
- **KECCAK256 / Crypto**:
  - Use `QuickCrypto.keccack256Hash(Uint8List)` from `blockchain_utils` for pure Dart hashing.
  - Use `HexUtils` (`str.toBytes()`) for hex string to `Uint8List` conversions for maximum readability.
  - Use `ByteUtils` for explicit big-endian number-to-byte conversions (`uint16ToBytes`, `uint64ToBytes`).
  - **EIP-712 Signing**: Use `hashMessage: false` when signing a pre-computed EIP-712 digest (already hashed).
  - **Manual Transaction Construction**: When using pre-encoded ABI payloads with `on_chain` v7.1.0, bypass the high-level `ETHTransactionBuilder` for `autoFill` if you need to set the raw `data` field. Instead:
    - 1. Fetch `nonce`, `gasPrice`/`maxFeePerGas`, and `gasLimit` using `EthereumProvider`.
    - 2. Construct `ETHTransaction.legacy()` or `ETHTransaction.eip1559()`.
    - 3. Use `tx.fillTransaction(...)` with the fetched parameters.
    - 4. Use `builder.sign(key)` ensuring `builder.transaction` is the manually filled instance.
  - **Prefer `ETHTransactionBuilder` for High-level**: Use `builder.autoFill(provider)` ONLY when calling standard methods that the builder supports (like contract calls with `AbiFunctionFragment` where parameters are passed, not raw data).
  - **Encoding**: Use `ByteData` with `Endian.big` for explicit `uint16`, `uint32`, or `uint64` byte conversions.
  - **Nested Tuple Encoding**: For structs composed of other structs (like `AttestationRequest` containing `AttestationRequestData`), `on_chain`'s ABI encoder requires passing nested `List` structures that exactly align with the fragment's `components` array.
  - **ABI Output Parsing**: Results from `eth_call` via `AbiFunctionFragment.decodeOutput` return dynamic types. For nested or complex structs, manually cast components (e.g., check `if (value is BigInt) value else BigInt.from(value)`, cast `List<int>` to `Uint8List`) before hydrating Dart models.

### Pitfalls to Avoid
- **ABI Encoding Location**: Do not try to ABI encode a `Map` or `List` directly for the `location` field; serialize to a JSON string first.
- **Reserved Names**: User-defined fields must not collide with `lp_version`, `srs`, `location_type`, or `location`.

### Offchain UID (v2) Packed Encoding Layout
- **Order**: `version(uint16) | schemaUID(bytes32) | recipient(address) | attester(0x0 address) | time(uint64) | expirationTime(uint64) | revocable(bool) | refUID(bytes32) | data(bytes) | salt(bytes32) | zero(uint32)`.
- **Note**: Ensure `time` and `expirationTime` are big-endian 8-byte arrays. `revocable` is a single byte (0 or 1).
- **Zero Padding**: Signature `r` and `s` components MUST be zero-padded to 32 bytes each before concatenating with `v` for recovery.

### Package Version Update (as of 2026-03-13)
- **`on_chain ^8.0.0`** + **`blockchain_utils ^6.0.0`** + **Dart SDK `^3.11.0`** — supersedes all prior v7.1.0/v5.4.0 notes. Upgrade path was clean.
- **Non-canonical RLP zero bug**: `blockchain_utils` v6 `BigintUtils.bitlengthInBytes(BigInt.zero)` returns `1` (not `0`) due to `if (bitlength == 0) return 1` guard. This causes `toBytes(BigInt.zero)` = `[0x00]`, which RLP-encodes as `0x00` (non-canonical) instead of `0x80` (canonical empty byte string). Geth rejects EIP-1559 transactions with this encoding with: `rlp: non-canonical integer (leading zero bytes) for *big.Int, decoding into (types.DynamicFeeTx).Value`.
- **Fix Pattern**: Add a `_canonicalBigIntBytes` helper that returns `<int>[]` for `BigInt.zero`, then skip `ETHTransaction.serialized` and build EIP-1559 RLP bytes directly with `RLPEncoder`. See `RpcHelper._buildEip1559Bytes`.
- **Infura Sepolia fee quirk**: `EthereumProvider.request(EthereumRequestGetFeeHistory(..., rewardPercentiles: [50]))` returns empty `rewards` array on Infura Sepolia, causing `FeeHistory.toFee()` to throw `RangeError`. Use a try/catch fallback: fetch `baseFeePerGas.first` directly and compute `maxFeePerGas = baseFee * 2 + maxPriorityFeePerGas`.

### Dependency & Encoding Quirks
- **`blockchain_utils` Versioning**: When using `on_chain ^7.1.0`, explicitly declare `blockchain_utils: ^5.4.0` in `pubspec.yaml` to avoid version solver conflicts with the library's transitive requirements.
- **ABI `bytes32` Encoding**: Never pass hex strings directly to `on_chain`'s `Fragment.encode` for `bytes32` parameters. Always convert to `Uint8List` using `BytesUtils.fromHexString(uid.replaceAll('0x', ''))`.
- **Test Secrets**: Use `.env` file (loaded by `test/test_helpers/dotenv_loader.dart`) for RPC URLs and private keys. Never hardcode real keys. Provide `.env.example` with documented placeholders.

### Phase 4 Receipt Workflow Patterns
- **Receipt polling contract**: Add `waitForReceipt` on `RpcProvider` and implement in both `DefaultRpcProvider` and `FakeRpcProvider` so client logic remains fully interface-driven.
- **Import collision guard**: Restrict `on_chain` imports (`show AbiFunctionFragment`) in provider abstractions/tests to avoid `TransactionReceipt` name collisions with local value objects.
- **Timestamped topic decode**: Parse indexed `uint64` topic from hex via `BigInt.parse(topic.replaceFirst('0x', ''), radix: 16)`.
- **Event topic verification**: Always verify hardcoded event topic constants with a test that computes `keccak256(signature)` to catch placeholder/hash mistakes.

### Phase 5 Fixed-Schema Sepolia Patterns
- **Separate bootstrap from recurring runs**: Register LP-only schema once via `dart run scripts/sepolia_schema_bootstrap.dart`, then persist printed `SEPOLIA_EXISTING_SCHEMA_UID` in `.env`.
- **Recurring suite must stay registration-free**: `--tags sepolia` tests should use fixed UID checks and attest/fetch parity only, without calling schema registration APIs.
- **Skip behavior should be explicit**: For network-gated integration tests, prefer group-level `skip` reason strings over silent `return` in `main()` so test output explains why tests did not run.

### Phase 6 Validation Patterns
- **Build-then-wire sequencing**: Implement and harden `LocationValidator` tests first, migrate downstream fixtures second, then wire into `LPPayload` to avoid broad fixture breakage.
- **Static registry isolation**: Any tests that call `LocationValidator.register(...)` must use `tearDown(() => LocationValidator.resetCustomTypes())` to avoid test-order pollution.
- **Parser exception normalization**: Catch parser `FormatException` and throw `ArgumentError` so callers observe one validation error type at API boundaries.
- **Fixture migration preference**: For tests focused on encoding/signing/network behavior (not validation semantics), prefer canonical valid fixtures (for example `address` + string) over bypassing validation.
- **Bypass scope discipline**: Use `validateLocation: false` only as a temporary migration tool; keep all other constructor validations active.

### Phase 7 Documentation Snippet Validation Patterns
- **Doc snippet extraction must normalize line endings**: Use `trim()` for fence matching so CRLF markdown fences are detected on Windows.
- **Derived test artifacts are executable contracts**: Treat `test/docs/docs_snippets_test.dart` as generated output only; regenerate from docs and validate with analyzer/tests instead of manual edits.
- **Runtime-safe snippet adaptation**: If docs include harness-only APIs like `tearDown(...)` in snippet prose, transform to runtime-safe equivalents when generating executable tests.
- **Network flake policy for generated docs**: For Sepolia-tagged generated tests, use explicit env skip guards and handle mempool duplicate transaction errors (`already known`) by marking tests skipped rather than failing unrelated documentation validation.
- **Idempotency gate**: Run generator twice and compare file hashes to ensure deterministic output before phase closeout.
