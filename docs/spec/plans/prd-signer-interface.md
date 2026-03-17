# PRD: Abstract Signer Interface for `location_protocol`

**Status:** Draft

## Overview

The `location_protocol` Dart library provides the full lifecycle for Location Protocol spatial attestations — payload construction, schema definition, ABI encoding, EIP-712 offchain signing, and onchain EAS operations. However, both `OffchainSigner` and `DefaultRpcProvider` require a **raw private key hex string** in their constructors, making it impossible to use wallet-backed signing (Privy embedded wallets, MetaMask, WalletConnect, secure enclaves) without reimplementing the library's EIP-712 internals externally.

This PRD defines the requirements for adding an abstract `Signer` interface to the library, enabling any Dart application to plug in arbitrary signing backends while the library continues to own all EIP-712 typed data construction, digest computation, UID generation, and verification logic.

**Analogous prior art:** The TypeScript EAS SDK accepts ethers-compatible signers via `eas.connect(signer)`. The [Privy EAS integration demo](https://github.com/DecentralizedGeo/privy-eas-integration-demo/blob/main/docs/privy-eas-integration.md) uses `walletClientToSigner()` to bridge Privy's wallet into this interface. This PRD creates the Dart equivalent.

## Goals

- Enable wallet-backed signing (Privy, MetaMask, WalletConnect, secure enclaves) without consumers reimplementing EIP-712 logic
- Maintain full backward compatibility — existing code using `OffchainSigner(privateKeyHex: ...)` continues to work via a convenience factory
- Expose typed-data construction and UID computation as public utilities so external integrations can inspect/use them
- Extend the same pattern to `DefaultRpcProvider` for onchain transaction signing

## User Personas

- **Primary:** App developers integrating `location_protocol` into Flutter or Dart apps that use wallet providers (Privy, WalletConnect, etc.) instead of raw private keys
- **Secondary:** Library maintainers who need clean separation of concerns between protocol logic and key management

## User Stories

### US-001: Sign offchain attestation with an external wallet provider

**As a** Flutter app developer using Privy for authentication, **I want** to pass my Privy wallet's signing capability into `OffchainSigner` **so that** users can sign Location Protocol attestations without the app ever handling raw private keys.

**Acceptance Criteria:**
- [ ] `OffchainSigner` accepts a `Signer` object instead of (or in addition to) a `privateKeyHex` string
- [ ] A `Signer` implementation that calls `eth_signTypedData_v4` via an RPC provider produces a valid `SignedOffchainAttestation` that passes `verifyOffchainAttestation()`
- [ ] The `SignedOffchainAttestation` is byte-identical to one produced by a `LocalKeySigner` wrapping the same private key (deterministic salt must be injected for this comparison)
- [ ] Typecheck/lint passes: `dart analyze` reports zero issues

### US-002: Sign offchain attestation with a local private key (backward compatibility)

**As a** developer already using `OffchainSigner(privateKeyHex: 'abc...')`, **I want** my existing code to keep working **so that** upgrading the library is non-breaking.

**Acceptance Criteria:**
- [ ] `OffchainSigner.fromPrivateKey(privateKeyHex: ..., chainId: ..., easContractAddress: ...)` convenience factory exists and returns a fully functional `OffchainSigner`
- [ ] All existing `offchain_signer_test.dart` tests pass without modification (or with only trivial import changes)
- [ ] `dart analyze` reports zero issues

### US-003: Inspect EIP-712 typed data before signing

**As a** developer building a wallet integration, **I want** to access the EIP-712 typed data JSON map that will be signed **so that** I can pass it to `eth_signTypedData_v4` or display it to the user for review.

**Acceptance Criteria:**
- [ ] A public method or utility produces the EIP-712 typed data as a `Map<String, dynamic>` (JSON-compatible) for a given attestation
- [ ] The typed data map contains `types`, `primaryType`, `domain`, and `message` keys matching the EAS offchain V2 spec
- [ ] The digest computed from this typed data map matches the digest computed by the internal `Eip712TypedData.encode()` path
- [ ] `dart analyze` reports zero issues

### US-004: Compute offchain UID independently

**As a** developer, **I want** to compute the deterministic offchain UID for an attestation without signing it **so that** I can verify UIDs, predict them before signing, or compute them for externally-signed attestations.

**Acceptance Criteria:**
- [ ] A public static method computes the offchain UID from the attestation's message fields (version, schema, recipient, time, expirationTime, revocable, refUID, data, salt)
- [ ] The computed UID matches the UID produced by `signOffchainAttestation()` for the same inputs
- [ ] `dart analyze` reports zero issues

### US-005: Submit onchain transactions with an external wallet

**As a** app developer using Privy or WalletConnect, **I want** to use the same `Signer` abstraction for onchain operations (attest, timestamp, registerSchema) **so that** my wallet integration works for both offchain and onchain flows.

**Acceptance Criteria:**
- [ ] `DefaultRpcProvider` (or a new provider) accepts a `Signer` for transaction signing instead of `privateKeyHex`
- [ ] `EASClient.attest()`, `EASClient.timestamp()`, and `SchemaRegistryClient.register()` work with a `Signer`-backed provider
- [ ] `dart analyze` reports zero issues

## Functional Requirements

- **FR-1:** The library MUST export an abstract `Signer` class with the following interface:
  - `String get address` — the Ethereum address of the signer
  - `Future<EIP712Signature> signDigest(Uint8List digest)` — sign a raw 32-byte hash (for local key / secure enclave signers)
  - `Future<EIP712Signature> signTypedData(Map<String, dynamic> typedData)` — sign EIP-712 typed data as a JSON map (for wallet providers that expose `eth_signTypedData_v4`). The default implementation MUST compute the EIP-712 digest from the typed data map and delegate to `signDigest()`

- **FR-2:** The library MUST export a `LocalKeySigner` class that implements `Signer`:
  - Constructor: `LocalKeySigner({required String privateKeyHex})`
  - `signDigest()` signs using `ETHPrivateKey.sign(digest, hashMessage: false)`
  - `signTypedData()` inherits the default implementation (delegates to `signDigest`)
  - `address` derives from the private key

- **FR-3:** `OffchainSigner`'s primary constructor MUST accept `Signer signer` instead of `String privateKeyHex`:
  - `OffchainSigner({required Signer signer, required int chainId, required String easContractAddress, String easVersion = '1.0.0'})`
  - `signerAddress` getter MUST return `signer.address`

- **FR-4:** `OffchainSigner` MUST provide a convenience factory `fromPrivateKey`:
  - `OffchainSigner.fromPrivateKey({required String privateKeyHex, required int chainId, required String easContractAddress, String easVersion = '1.0.0'})`
  - This wraps the key in a `LocalKeySigner` and delegates to the primary constructor

- **FR-5:** `signOffchainAttestation()` MUST call `signer.signTypedData(typedDataMap)` where `typedDataMap` is the EIP-712 JSON representation. For `LocalKeySigner`, this flows through the default `signTypedData → signDigest` path, producing identical output to the current implementation.

- **FR-6:** The library MUST expose a public utility to build the EIP-712 typed data JSON map. This is the currently-private `_buildTypedData` logic, adapted to return `Map<String, dynamic>` in addition to (or instead of) the `on_chain` `Eip712TypedData` object. Suggested API:
  - Static method or standalone function returning `({Eip712TypedData typedData, Map<String, dynamic> jsonMap})`

- **FR-7:** The library MUST expose a public utility to compute the offchain UID. This is the currently-private `_computeOffchainUID` logic. Suggested API:
  - Static method: `OffchainSigner.computeUID(...)` or standalone `computeOffchainUID(...)`

- **FR-8:** `verifyOffchainAttestation()` MUST remain signer-independent — it recomputes the digest and recovers the public key from the signature. No changes to its external behavior.

- **FR-9:** `DefaultRpcProvider` SHOULD accept a `Signer` for transaction signing. A `DefaultRpcProvider.fromPrivateKey(...)` convenience factory SHOULD preserve backward compatibility. *(Lower priority — can be a follow-up if needed.)*

- **FR-10:** The barrel export (`lib/location_protocol.dart`) MUST export `Signer`, `LocalKeySigner`, and any new typed-data/UID utility files.

## Non-Functional Requirements

- **Performance:** `signOffchainAttestation()` with `LocalKeySigner` MUST perform within 5% of the current `privateKeyHex` implementation (no measurable overhead from the abstraction layer).
- **Testing:** All existing offchain signer tests MUST pass. New tests MUST cover: `Signer` interface contract, `LocalKeySigner` behavior, parity between `fromPrivateKey` and primary constructor paths, typed data map correctness.
- **Zero Flutter dependency:** The library MUST remain pure Dart (no Flutter imports). `Signer` implementations for Flutter-specific wallets (Privy, etc.) live in consumer applications, not in the library.
- **Documentation:** `reference-api.md` and `tutorial-first-attestation.md` MUST be updated to reflect the new Signer-based API. A migration guide SHOULD be added.

## Out of Scope

- **Privy-specific `Signer` implementation** — this lives in the Flutter app, not the library. The library only defines the abstract interface.
- **WalletConnect / MetaMask `Signer` implementations** — consumer responsibility.
- **Offchain attestation serialization to EAS JSON format** — the library currently does not serialize `SignedOffchainAttestation` to/from JSON. This is a separate concern.
- **Schema registration permission checks or gas estimation** — beyond the scope of the Signer interface.
- **Breaking changes to `VerificationResult`, `SignedOffchainAttestation`, or `EIP712Signature`** models — their structure remains unchanged.

## Technical Considerations

### Dependencies
- **`on_chain` package:** Provides `ETHPrivateKey`, `ETHPublicKey`, `Eip712TypedData`. `LocalKeySigner` will use `ETHPrivateKey.sign()`. The EIP-712 typed data JSON map construction may need to replicate some of what `Eip712TypedData` does internally to produce the JSON representation for `eth_signTypedData_v4`.
- **`blockchain_utils` package:** Used transitively for keccak256 and byte utilities.

### Constraints
- `OffchainSigner._buildTypedData()` currently returns an `on_chain` `Eip712TypedData` object and calls `.encode()` to get the digest. For `signTypedData(Map)`, we also need the JSON map representation. This requires either:
  - (A) Building both the `Eip712TypedData` and the JSON map from the same parameters, or
  - (B) Having `signTypedData`'s default implementation reconstruct the `Eip712TypedData` from the JSON map to call `.encode()` for digest computation.
  - **Recommendation:** Option (A) — build both representations in the public utility function, return a named record.

### Risks
- **EIP-712 digest parity:** The JSON map passed to `signTypedData()` must, when hashed by an external wallet (MetaMask, Privy), produce the identical 32-byte digest as `Eip712TypedData.encode()`. This must be verified with integration tests against a real wallet provider.
- **`v` value normalization:** Different wallet providers return the recovery id `v` as either `0/1` or `27/28`. The library must handle both conventions when constructing `EIP712Signature`.

### Key Files to Modify (in `location-protocol-dart` repo)

| Action | File |
|--------|------|
| Create | `lib/src/eas/signer.dart` — `Signer` abstract class |
| Create | `lib/src/eas/local_key_signer.dart` — `LocalKeySigner` implementation |
| Modify | `lib/src/eas/offchain_signer.dart` — refactor constructor, expose `_buildTypedData` / `_computeOffchainUID` |
| Modify | `lib/src/rpc/default_rpc_provider.dart` — accept `Signer` (stretch goal) |
| Modify | `lib/location_protocol.dart` — export new files |
| Create | `test/eas/signer_test.dart` — interface + `LocalKeySigner` tests |
| Modify | `test/eas/offchain_signer_test.dart` — add `fromPrivateKey` parity tests |

## Success Metrics

- **Primary:** A consumer app can sign a `SignedOffchainAttestation` via an `eth_signTypedData_v4` wallet call using the library's `Signer` interface, and `verifyOffchainAttestation()` returns `isValid: true` — without any EIP-712 code outside the library.
- **Secondary:** All existing library tests pass. `dart analyze` reports zero issues. No breaking changes to existing consumer code beyond a factory rename.

## Open Questions

1. **Naming:** Should the abstract class be `Signer`, `EthSigner`, `AttestationSigner`, or `WalletSigner`? The app already has an `AttestationSigner` in its custom code. `Signer` is simplest and matches ethers.js convention.
2. **`DefaultRpcProvider` scope:** Should the Signer abstraction for onchain transactions be part of this deliverable or a follow-up? The core value is in offchain signing; onchain can be a separate PR.
3. **`signTypedData` default implementation:** Should the default compute the digest via `Eip712TypedData.encode()` (using `on_chain`), or via a custom keccak256 implementation? The former is simpler; the latter avoids re-parsing.
4. **`v` normalization:** Should the library normalize `v` from `0/1` to `27/28` inside `OffchainSigner`, or should `Signer` implementations be responsible for returning the correct convention?


