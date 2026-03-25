# Semantic Memory

### Core Abstractions
- **Location Protocol (LP)**: A standard for decentralized location data.
- **LP Base Fields**: `lp_version` (semver), `srs` (CRS URI), `location_type` (format), `location` (actual data).
- **SchemaDefinition**: A composer that takes user-defined business fields and auto-prepends the 4 LP base fields to ensure EAS compliance.
- **SchemaUID**: A deterministic 32-byte identifier for an EAS schema, computed from the schema string, resolver address, and revocable flag.
- **Offchain UID (v2)**: A 32-byte Keccak256 hash of: `version | schemaUID | recipient | attester(0) | time | expirationTime | revocable | refUID | data | salt | 0(uint32)`.

### Package Selection Rationale
- **`on_chain` chosen over `web3dart`**: Built-in EIP-712 v1/v3/v4, EIP-1559, typed schema classes. In practice downgraded to `^7.1.0` (Dart SDK 3.6.2 < 3.7.0 required by v8).
- **`blockchain_utils`**: Transitive dep of `on_chain`, used directly for `QuickCrypto.keccack256Hash` and `BytesUtils`.
- **Rejected**: `web3_signers` (Flutter-only), `eth-sig-util` (stale), `eip1559` (gas estimation only).

### Core Abstractions
- **Attestation Models**: 
  - `UnsignedAttestation`: Raw data for offchain.
  - `SignedOffchainAttestation`: Data + salt + sig + UID.
  - `Attestation`: Full onchain record populated from EAS `getAttestation(bytes32)`.
- **EIP-712 Signing**: Uses `EIP712Domain` (name, version, chainId, verifyingContract) and an `Attest` struct.
- **OffchainSigner**: A stateless engine for creating and verifying EIP-712 signatures for EAS without an active RPC connection. Successfully recovers signer using `ETHPublicKey.getPublicKey` (ecRecover).

### Quirks & Mappings
- **Location Field flexibility**: The `location` field in Dart can be `String`, `List`, or `Map`. The library serializes it to a JSON string for ABI encoding if it's a `List` or `Map`.
- **BigInt Serialization**: EAS attestations often use `uint64` or `uint256`. Use `BigInt` in Dart for these to prevent precision loss, ensuring they are serialized to numbers (or strings if necessary) correctly within the `AbiEncoder`.
- **Snake Case**: LP fields MUST be `snake_case` in the EAS schema string to match the spec, even though Dart uses `camelCase` for class members.
- **ABI Encoding Location**: The `location` field (JSON string) is encoded as `string` in Solidity.
- **User Data Merging**: `AbiEncoder` automatically merges the 4 fixed LP fields with user-provided fields from the `SchemaDefinition` before encoding.
- **Signature Recovery**: `ecRecover` in Dart (`ETHPublicKey.getPublicKey`) requires the `v,r,s` hash as a single 65-byte `Uint8List` (r[32]|s[32]|v[1]) plus the original message hash.
- **ABI Multi-Param Encoding**: Use `TupleCoder` for multi-parameter schemas instead of top-level `ABICoder.encode` for consistent behavior in `on_chain` v7.1.0.

### Infrastructure & Clients
- **ChainConfig**: A central registry of EAS and SchemaRegistry contract addresses mapped to EVM ChainIDs (e.g., 11155111 for Sepolia). Supports custom chain injection.
- **SchemaRegistryClient**: Handles `register` transaction construction. Computes `SchemaUID` locally to allow offline pre-verification.
- **EASClient**: The primary interface for onchain interactions (`attest`, `timestamp`, `registerSchema`). Delegates registry work to `SchemaRegistryClient`.

### RPC Transport Layer (Phase 2 & 3)
- **`RpcProvider` (Phase 3 Abstraction)**: An interface for all on-chain state queries and transaction submissions. Clients (`EASClient`, `SchemaRegistryClient`) require this interface via constructor injection, preventing them from managing raw HTTP or private key lifecycle directly.
- **`DefaultRpcProvider` (formerly `RpcHelper`)**: The standard implementation using `on_chain` and `HttpRpcService`. In `on_chain` v7.1.0, direct `data` injection for raw ABI payloads is not available via public setters in the base `ETHTransactionBuilder`. This class implements a manual construction pattern: fetch nonce/gas/fees -> build `ETHTransaction` (legacy or EIP-1559) -> use internal `autoFill` logic via `fillTransaction` to finalize before signing.
- **`FakeRpcProvider`**: An offline mock implementation of `RpcProvider` that returns hardcoded ABI byte arrays, allowing instant, network-free unit testing of client classes.
- **`HttpRpcService`**: A thin `dart:io` `HttpClient` wrapper implementing `on_chain`'s `EthereumServiceProvider` mixin. Single method to implement: `doRequest<T>()`. Zero new dependencies.
- **`ETHTransactionBuilder`**: `on_chain`'s built-in transaction builder. Two constructors: `ETHTransactionBuilder(...)` for basic tx, `.contract(...)` for contract calls with `AbiFunctionFragment`. `autoFill()` handles nonce, gas estimation, and EIP-1559 fee calculation automatically.
- **`EthereumProvider`**: Wraps a `BaseServiceProvider` (our `HttpRpcService`) and dispatches `EthereumRequest` objects as JSON-RPC calls.

### EAS SDK Source References (verified)
- **Salt generation**: `hexlify(randomBytes(32))` — [offchain.ts L201-203](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain.ts#L201-L203)
- **Constants**: `ZERO_ADDRESS`, `ZERO_BYTES32` — [utils.ts L4-6](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/utils.ts#L4-L6)
- **Offchain UID v2**: `solidityPackedKeccak256` with version+schema+recipient+ZERO_ADDRESS+time+expTime+revocable+refUID+data+salt+0
- **EIP-712 domain**: `keccak256(encode("EAS Attestation", contractVersion, chainId, easAddress))`

### Future Roadmap (approved by user)
- Full location type validation (GeoJSON per RFC 7946, H3 regex, coordinate bounds)
- Location/spatial module with format-specific helpers
- JSON Schema (Draft 07) based validation using [official LP schema](https://raw.githubusercontent.com/DecentralizedGeo/location-protocol-spec/refs/heads/main/json-schema/schema.json)
- Delegated attestation, batch operations, revocation
- `web3_signers` integration for hardware-backed signing (Secure Enclave, passkeys)

### Phase 4 Receipt Enhancement Semantics
- **Rich write-method results**: `EASClient.attest()` now returns `AttestResult(txHash, uid, blockNumber)`, `EASClient.timestamp()` returns `TimestampResult(txHash, uid, time)`, and `SchemaRegistryClient.register()` returns `RegisterResult(txHash, uid)`.
- **Receipt abstraction boundary**: `RpcProvider.waitForReceipt()` returns library-owned `TransactionReceipt` and `TransactionLog` instead of leaking `on_chain` receipt types.
- **Event-driven extraction**: Attestation UID and timestamp are sourced from receipt logs using event topics (`attestedEventTopic`, `timestampedEventTopic`) with address + topic filtering.

### Phase 5 Fixed-Schema Sepolia Semantics
- **Recurring Sepolia contract**: `test/integration/sepolia_onchain_test.dart` uses `SEPOLIA_EXISTING_SCHEMA_UID` and must not register schemas during normal runs.
- **Guardrail contract**: Sepolia recurring tests require (`SEPOLIA_RPC_URL`, `SEPOLIA_PRIVATE_KEY`, `SEPOLIA_EXISTING_SCHEMA_UID`) and explicitly skip when missing/invalid; UID must be `0x`-prefixed bytes32 (length 66).
- **Verification contract**: Recurring suite validates (1) configured UID exists, (2) zero bytes32 UID resolves as non-existent schema, and (3) onchain `attest` + `getAttestation` parity including encoded payload byte equality from `AbiEncoder.encode(...)`.
- **Bootstrap separation**: One-time schema registration is handled outside recurring tests by `scripts/sepolia_schema_bootstrap.dart`.

### Phase 6 Location Type Structural Validation
- **LocationValidator boundary**: `LocationValidator` validates `locationType` + `location` at `LPPayload` construction time via `LPPayload._validate()`.
- **Canonical type contract**: Built-ins are `coordinate-decimal+lon-lat`, `geojson-point`, `geojson-line`, `geojson-polygon`, `h3`, `geohash`, `wkt`, `address`, `scaledCoordinates`.
- **Deep validation semantics**: Coordinate bounds, GeoJSON parsing (Point/LineString/Polygon), H3 and geohash regex checks, WKT parser-backed checks, trimmed non-empty address, and numeric `scaledCoordinates` keys.
- **Error surface**: Built-in validator failures are normalized to `ArgumentError` at constructor-time boundaries.
- **Registration rules**: Built-ins cannot be overridden; custom type registration is supported with duplicate custom registrations replacing prior custom validators.
- **Migration safety**: `LPPayload(validateLocation: false)` bypasses type dispatch only; semver, URI, and null checks still run.

### Phase 7 Documentation Snippet Validation Semantics
- **Extractor contract**: `scripts/docs_snippet_extractor.dart` scans `README.md` and `doc/guides/*.md` for fenced `dart` blocks and generates `test/doc/docs_snippets_test.dart` as a derived artifact.
- **Auto-detect step sequences**: Tutorial steps are inferred from heading patterns like `## Step 1`, `## Step 2`, etc., then reconstructed as accumulated tests where Step N includes Step 1..N code.
- **Classification model**: Snippets are categorized into step-sequence, standalone, and error examples; error snippets are wrapped with `expect(throwsA(isA<ArgumentError>()))`.
- **Cross-doc behavior**: Onchain guide snippets inject tutorial prerequisites (`schema`, `lpPayload`) and adapt env usage through `loadDotEnv()` with `sepolia` tagging.
- **Parsing boundaries**: Blockquote code fences (`> ```dart`) are intentionally excluded from extraction.

### Phase 8 Signer Interface Semantics
- **`Signer` abstract class** (`lib/src/eas/signer.dart`): The central abstraction. `address` (getter), `signDigest(Uint8List)` (abstract), `signTypedData(Map<String,dynamic>)` (concrete default using `Eip712TypedData.fromJson`).
- **`LocalKeySigner`** (`lib/src/eas/local_key_signer.dart`): Implements `Signer` by wrapping `ETHPrivateKey`. Inherits default `signTypedData`. Used for local key / server-side signing.
- **`EIP712Signature.fromHex`**: Parses 65-byte `r[32]||s[32]||v[1]` wallet response into `EIP712Signature(v,r,s)`. Throws `ArgumentError` for wrong length.
- **`OffchainSigner` refactored API**:
  - Primary ctor: `OffchainSigner({required Signer signer, required int chainId, required String easContractAddress, ...})`
  - Factory: `OffchainSigner.fromPrivateKey({required String privateKeyHex, required int chainId, required String easContractAddress, ...})` — backward compat
  - Public statics: `buildOffchainTypedDataJson(...)` (JSON-safe map with decimal string uints), `computeOffchainUID(...)` (keccak256 of packed fields)
- **`EASClient.buildAttestTxRequest`**: Static helper wrapping ABI-encoded calldata into `{to, data, value, from?}` transaction map for `eth_sendTransaction`.
- **Wallet adapter pattern**: Subclass `Signer`, override `signTypedData` to call `eth_signTypedData_v4`, parse result via `EIP712Signature.fromHex`, throw `UnsupportedError` in `signDigest`.

### Phase 8.1 Documentation Semantics
- **EAS Reference Envelope vs LP Payload**: The Location Protocol payload (the 4 base fields) is completely implementation-agnostic and universally portable. EAS acts strictly as the **Reference Envelope** for EVM networks, providing EIP-712 signing and onchain anchoring. The LP payload can be wrapped safely in Solana or Filecoin native attestation services without changing its inherent data structure.
