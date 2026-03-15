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
