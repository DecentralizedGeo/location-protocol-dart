# Signer Interface Implementation Report  
**Supporting the `location_protocol` Dart Library PRD**

**Date:** March 17, 2026  
**Author:** Technical Analysis Session  
**Repository:** DecentralizedGeo/location-protocol-dart

***

## Executive Summary

This report provides implementation guidance for introducing an abstract `Signer` interface into the **location_protocol** Dart library. The interface enables wallet-backed signing (Privy, MetaMask, WalletConnect, secure enclaves) while the library retains ownership of all EIP-712 typed data construction, digest computation, UID generation, and verification logic. 

**Key findings:**

- The `on_chain` and `blockchain_utils` dependencies already provide all necessary cryptographic primitives.
- The `Signer` abstraction sits cleanly between EIP-712 / transaction construction and signature generation.
- Existing domain models (schemas, payloads, ABI encoding, serializers) require zero changes. 
- Only `OffchainSigner` and `DefaultRpcProvider` need refactoring to accept `Signer` instead of raw private keys.
- A two-tier interface (`Signer` + optional `CustomSigner`) supports progressive enhancement for advanced wallet providers.

***

## Table of Contents

- [Introduction and Context](#1-introduction-and-context)
- [Technical Architecture](#2-technical-architecture)
- [Signing Sequence Deep-Dive](#3-signing-sequence-deep-dive)
- [Signer Interface Design](#4-signer-interface-design)
- [Impact on Existing Components](#5-impact-on-existing-components)
- [Delegated Attestations](#6-delegated-attestations)
- [Implementation Guidance](#7-implementation-guidance)
- [PRD Amendments](#8-prd-amendments)

***

## 1. Introduction and Context

### 1.1 Current State

The `location_protocol` library (v0.1.0) currently requires raw private key hex strings in constructor parameters:

- `OffchainSigner(privateKeyHex: '0xabc...')` for EIP-712 offchain signing  
- `DefaultRpcProvider(privateKeyHex: '0xabc...')` for onchain transaction signing

This design prevents integration with wallet providers (Privy embedded wallets, MetaMask, WalletConnect) that expose signing capabilities through SDK methods like `eth_signTypedData_v4` instead of raw key access.

### 1.2 Prior Art

The TypeScript **EAS SDK** solves this with ethers.js-compatible signers:

```ts
const eas = new EAS(easAddress);
eas.connect(signer); // ethers Signer or Wallet
```

Privy integration uses `walletClientToSigner()` to bridge Privy’s embedded wallet into this interface. 

### 1.3 Goals

1. Enable wallet-backed signing without consumers reimplementing EIP-712 logic. 
2. Maintain 100% backward compatibility via convenience factories. 
3. Expose typed-data construction and UID computation as public utilities. 
4. Extend the pattern to onchain transaction signing. 
5. Support delegated attestations (future).

***

## 2. Technical Architecture

### 2.1 Dependency Analysis

Current dependencies from `pubspec.yaml`:

| Package              | Version  | Purpose                                                       |
|----------------------|----------|---------------------------------------------------------------|
| `on_chain`           | ^8.0.0   | `ETHPrivateKey`, `ETHPublicKey`, `Eip712TypedData`, RLP       |
| `blockchain_utils`   | ^6.0.0   | Keccak256, byte utilities, BigInt helpers                    |
| `geobase`            | ^1.5.0   | Geospatial types (not signing-related)                        |

**Key findings:**

- `ETHPrivateKey.sign(hash, hashMessage: false)` already exists and is used in both `OffchainSigner` and `DefaultRpcProvider`.
- `Eip712TypedData` handles typed data construction; `.encode()` computes the 32-byte digest.
- `ETHPublicKey.getPublicKey(hash, sigBytes)` performs ECDSA public key recovery for verification.
- No new crypto code is required — only abstraction wrappers.

### 2.2 Current File Structure

**Files requiring modification:**

| File                                   | Current responsibility                                   |
|----------------------------------------|----------------------------------------------------------|
| `lib/src/eas/offchain_signer.dart`     | EIP-712 signing, UID computation, verification           |
| `lib/src/rpc/default_rpc_provider.dart`| Transaction building, signing, broadcasting              |
| `lib/src/eas/onchain_client.dart`      | High-level EAS operations (attest, timestamp, register)  |

**Files remaining unchanged:** 

- `lib/src/eas/abi_encoder.dart` — ABI encoding logic  
- `lib/src/lp/*.dart` — Location Protocol payload models  
- `lib/src/schema/*.dart` — Schema definitions and UID computation  
- `lib/src/models/*.dart` — Data models (`Attestation`, `SignedOffchainAttestation`, etc.)

***

## 3. Signing Sequence Deep-Dive

### 3.1 Offchain Attestation Flow (EIP-712)

Current implementation in `OffchainSigner.signOffchainAttestation()`:

1. **ABI-encode the data payload** — `AbiEncoder.encode(schema, lpPayload, userData)` → `bytes`.  
2. **Compute schema UID** — `SchemaUID.compute(schema)` via keccak256.  
3. **Build EIP-712 typed data** — `_buildTypedData()` constructs `Eip712TypedData` with domain + message.  
4. **Compute digest** — `typedData.encode()` runs EIP-712 hashing: `keccak256("\x19\x01" || domainHash || structHash)`.  
5. **Sign the digest** — `ETHPrivateKey.sign(hash, hashMessage: false)` → `(r, s, v)`.  
6. **Compute offchain UID** — `_computeOffchainUID()` via packed keccak256.  
7. **Return `SignedOffchainAttestation`** — includes signature, UID, and all message fields.

**Signer interface boundary:** between steps 4 and 5. The library owns 1–4 and 6–7; a `Signer` implementation owns only step 5.

Current code excerpt:

```dart
// Build typed data
final typedData = _buildTypedData(...);

// Sign typed data
final privateKey = ETHPrivateKey(_privateKeyHex);
final hash = typedData.encode();
final sig = privateKey.sign(hash, hashMessage: false);
```

With `Signer`:

```dart
final typedData = _buildTypedData(...);
final typedDataJson = _buildTypedDataJson(...); // JSON representation
final sig = await signer.signTypedData(typedDataJson);
```

### 3.2 Onchain Transaction Flow

Current implementation in `DefaultRpcProvider.sendTransaction()`:

1. **Build ABI call data** — `EASClient.buildAttestCallData()` encodes function selector + arguments.  
2. **Fetch nonce** — `eth_getTransactionCount`.  
3. **Fetch gas parameters** — `eth_feeHistory` (EIP-1559) or `eth_gasPrice` (legacy).  
4. **Estimate gas limit** — `eth_estimateGas`.  
5. **Build unsigned transaction** — `_buildEip1559Bytes()` constructs RLP-encoded EIP-1559 fields.  
6. **Sign raw transaction bytes** — `_privateKey.sign(unsignedBytes)`.  
7. **Broadcast** — `eth_sendRawTransaction` with signed bytes.

**Signer interface boundary:** between steps 5 and 6. The provider owns transaction construction; the `Signer` owns signing raw bytes.

Current code excerpt:

```dart
final unsignedBytes = _buildEip1559Bytes(...);
final signature = _privateKey.sign(unsignedBytes);
```

With `Signer`:

```dart
final unsignedBytes = _buildEip1559Bytes(...);
final signature = await signer.signTransactionBytes(unsignedBytes);
```

### 3.3 Verification Flow (Signer-Independent)

Offchain verification in `OffchainSigner.verifyOffchainAttestation()`:

1. Recompute UID using `_computeOffchainUID()` and compare to attestation UID.  
2. Rebuild EIP-712 typed data via `_buildTypedData()`.  
3. Compute digest via `typedData.encode()`.  
4. Recover public key via `ETHPublicKey.getPublicKey(hash, sigBytes, hashMessage: false)`.  
5. Derive address and compare to `attestation.signer`.

Verification never touches the `Signer` interface; it only needs message fields, signature bytes, and typed-data/domain definitions.

Onchain verification happens entirely in EVM and EAS contracts (`attest`, `getAttestation`), so Dart-side verification logic is unaffected by signer abstraction.

***

## 4. Signer Interface Design

### 4.1 Minimal Core Interface

```dart
abstract class Signer {
  /// Ethereum address of this signer.
  String get address;

  /// Sign a raw 32-byte digest (for local key / secure enclave signers).
  Future<EIP712Signature> signDigest(Uint8List digest);

  /// Sign EIP-712 typed data as JSON (for wallet providers).
  ///
  /// Default: compute digest from typedData via Eip712TypedData.encode()
  /// and delegate to signDigest().
  Future<EIP712Signature> signTypedData(Map<String, dynamic> typedData) async {
    final digest = Eip712TypedData.fromJson(typedData).encode();
    return signDigest(digest);
  }
}
```

**Rationale:**

- `signDigest()` is the lowest-level primitive — all signing ultimately targets a 32-byte hash.  
- `signTypedData()` provides convenience for wallet SDKs exposing `eth_signTypedData_v4`.  
- `LocalKeySigner` only needs to implement `signDigest()`; `signTypedData()` defaults correctly.

### 4.2 Extended `CustomSigner` Interface

```dart
abstract class CustomSigner extends Signer {
  /// Sign raw transaction bytes (for onchain operations).
  Future<ETHSignature> signTransactionBytes(Uint8List unsignedTxBytes) {
    throw UnimplementedError('signTransactionBytes not supported by this signer');
  }

  /// Sign delegated attestation typed data (future).
  Future<EIP712Signature> signDelegation(
    Map<String, dynamic> delegationTypedData,
  ) {
    return signTypedData(delegationTypedData);
  }
}
```

- `Signer` covers offchain attestations.  
- `CustomSigner` adds transaction signing and delegation flows.

### 4.3 `LocalKeySigner` Implementation

```dart
class LocalKeySigner implements Signer {
  final ETHPrivateKey _privateKey;

  LocalKeySigner({required String privateKeyHex})
      : _privateKey = ETHPrivateKey(privateKeyHex);

  @override
  String get address => _privateKey.publicKey().toAddress().address;

  @override
  Future<EIP712Signature> signDigest(Uint8List digest) async {
    final sig = _privateKey.sign(digest, hashMessage: false);
    return EIP712Signature(
      v: sig.v,
      r: '0x${BytesUtils.toHexString(sig.rBytes).padLeft(64, "0")}',
      s: '0x${BytesUtils.toHexString(sig.sBytes).padLeft(64, "0")}',
    );
  }
}
```

This directly wraps the existing usage of `ETHPrivateKey.sign(...)` and requires no new cryptographic logic.

### 4.4 Example Wallet Adapter (Consumer-Implemented)

```dart
class PrivyWalletSigner extends CustomSigner {
  final PrivyEmbeddedWallet _wallet;

  PrivyWalletSigner(this._wallet);

  @override
  String get address => _wallet.address;

  @override
  Future<EIP712Signature> signTypedData(Map<String, dynamic> typedData) async {
    final rawSig = await _wallet.request('eth_signTypedData_v4', [
      address,
      jsonEncode(typedData),
    ]);
    return EIP712Signature.fromHex(rawSig);
  }

  @override
  Future<ETHSignature> signTransactionBytes(Uint8List unsignedTxBytes) async {
    final rawSig = await _wallet.signTransaction(unsignedTxBytes);
    return ETHSignature.fromBytes(rawSig);
  }
}
```

Adapters like this live in consumer apps and never reimplement EIP-712 or UID logic.

***

## 5. Impact on Existing Components

### 5.1 Components Requiring Changes

#### 5.1.1 `OffchainSigner`

Current constructor:

```dart
OffchainSigner({
  required String privateKeyHex,
  required this.chainId,
  required this.easContractAddress,
  this.easVersion = '1.0.0',
});
```

New constructor:

```dart
OffchainSigner({
  required Signer signer,
  required this.chainId,
  required this.easContractAddress,
  this.easVersion = '1.0.0',
});
```

Backward-compatible factory:

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

`signOffchainAttestation()` changes:

- Replace direct `ETHPrivateKey` usage with `signer.signTypedData(typedDataJson)`.  
- Add a helper to emit both `Eip712TypedData` and a JSON map.  
- Keep UID computation, verification, and models unchanged.

#### 5.1.2 `DefaultRpcProvider`

Current constructor:

```dart
DefaultRpcProvider({
  required this.rpcUrl,
  required String privateKeyHex,
  required this.chainId,
  this.receiptTimeout = const Duration(minutes: 2),
});
```

New constructor:

```dart
DefaultRpcProvider({
  required this.rpcUrl,
  required Signer signer,
  required this.chainId,
  this.receiptTimeout = const Duration(minutes: 2),
});
```

Backward-compatible factory:

```dart
factory DefaultRpcProvider.fromPrivateKey({
  required String rpcUrl,
  required String privateKeyHex,
  required int chainId,
  Duration receiptTimeout = const Duration(minutes: 2),
}) {
  return DefaultRpcProvider(
    rpcUrl: rpcUrl,
    signer: LocalKeySigner(privateKeyHex: privateKeyHex),
    chainId: chainId,
    receiptTimeout: receiptTimeout,
  );
}
```

`sendTransaction()` changes:

- Replace `_privateKey.sign(unsignedBytes)` with `signer.signTransactionBytes(unsignedBytes)` for `CustomSigner`.  
- Optionally fall back to digest + `signDigest()` for base `Signer` only.

### 5.2 Components Requiring No Changes

| Component           | Why no changes                                                  |
|---------------------|-----------------------------------------------------------------|
| `AbiEncoder`        | Only encodes data; no keys or signatures.                      |
| `SchemaDefinition`  | Pure data model.                                               |
| `LPPayload`         | Pure data model.                                               |
| `LocationSerializer`| Converts location objects to `userData` maps.                  |
| Attestation models  | Pure data structures.                                          |
| `EASClient`         | Calls provider methods; does not sign directly.                |
| `SchemaRegistryClient` | Delegates to `RpcProvider`.                                |
| Verification logic  | Uses public key recovery, not `Signer`.               |

These operate solely on **what** is being attested, not **who** signs it.

### 5.3 New Utility Functions

#### 5.3.1 Build EIP-712 Typed Data JSON

New utility returning both `Eip712TypedData` and JSON map (shape abbreviated here):

```dart
static ({Eip712TypedData typedData, Map<String, dynamic> jsonMap})
    buildOffchainTypedData({
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
}) {
  final typedData = Eip712TypedData(...); // existing logic

  final jsonMap = {
    'types': {
      'EIP712Domain': [
        {'name': 'name', 'type': 'string'},
        {'name': 'version', 'type': 'string'},
        {'name': 'chainId', 'type': 'uint256'},
        {'name': 'verifyingContract', 'type': 'address'},
      ],
      'Attest': [
        {'name': 'version', 'type': 'uint16'},
        {'name': 'schema', 'type': 'bytes32'},
        {'name': 'recipient', 'type': 'address'},
        {'name': 'time', 'type': 'uint64'},
        {'name': 'expirationTime', 'type': 'uint64'},
        {'name': 'revocable', 'type': 'bool'},
        {'name': 'refUID', 'type': 'bytes32'},
        {'name': 'data', 'type': 'bytes'},
        {'name': 'salt', 'type': 'bytes32'},
      ],
    },
    'primaryType': 'Attest',
    'domain': {
      'name': 'EAS Attestation',
      'version': easVersion,
      'chainId': chainId.toString(),
      'verifyingContract': easContractAddress,
    },
    'message': {
      'version': EASConstants.attestationVersion,
      'schema': schemaUID,
      'recipient': recipient,
      'time': time.toString(),
      'expirationTime': expirationTime.toString(),
      'revocable': revocable,
      'refUID': refUID,
      'data': '0x${BytesUtils.toHexString(data)}',
      'salt': '0x${BytesUtils.toHexString(salt)}',
    },
  };

  return (typedData: typedData, jsonMap: jsonMap);
}
```

Serialization rules:

- `BigInt` → decimal string.  
- `Uint8List` → `0x`-prefixed hex.  
- Types → array of `{name, type}` maps.  
- Matches `eth_signTypedData_v4` expectations.

#### 5.3.2 Public UID Computation

Expose `_computeOffchainUID()` as a static public helper (logic identical to current code):

```dart
static String computeOffchainUID({ ... }) {
  // same as current _computeOffchainUID
}
```

***

## 6. Delegated Attestations

### 6.1 Concept

Delegated attestations allow a user to sign attestation intent offchain while a relayer submits onchain and pays gas. EAS provides `attestByDelegation(DelegatedAttestationRequest)` with a signature over an EIP-712 structure.

### 6.2 How `Signer` Supports Delegation

The user flow is identical to offchain signing:

- Build EIP-712 typed data for delegation (`DelegatedAttestationRequest`).  
- Sign via `signer.signTypedData(...)`.  
- Relay the signature and payload to a backend.  

The backend uses its own provider/signer to call `EAS.attestByDelegation()` onchain.

### 6.3 New User Story (US-006)

As an app developer, I want users to sign attestations without holding ETH so a backend relayer can pay transaction fees.

Acceptance criteria include:

- `EASClient.buildDelegatedAttestTypedData()` emitting correct EIP-712 JSON.  
- `EASClient.attestByDelegation()` submitting via relayer provider.  
- Onchain attestation shows the user as `attester`, not relayer.

***

## 7. Implementation Guidance

### 7.1 Phases

1. **Phase 1 (MVP)** — core `Signer`, `LocalKeySigner`, `OffchainSigner` refactor, public typed-data and UID utilities.
2. **Phase 2** — `CustomSigner`, `DefaultRpcProvider` refactor, onchain tests.
3. **Phase 3** — delegated attestations (new models and `EASClient` helpers).

### 7.2 Testing

- Unit tests: parity between old direct `ETHPrivateKey` and new `LocalKeySigner`; typed-data digest consistency; UID consistency.
- Integration tests: wallet-style mock `Signer`; onchain attest; delegated attestations with distinct attester/relayer signers.
- Backward compatibility: all existing tests pass using `fromPrivateKey` factories; performance within 5%.

### 7.3 `v` Normalization

Providers may return `v` as `0/1` or `27/28`. Normalize inside `OffchainSigner` before building `EIP712Signature`, e.g. `v >= 27 ? v - 27 : v`, so `ETHPublicKey.getPublicKey(...)` always receives 0 or 1.

### 7.4 Migration Example

Before:

```dart
final signer = OffchainSigner(
  privateKeyHex: '0xabc...',
  chainId: 11155111,
  easContractAddress: '0x...',
);
```

After (compatible):

```dart
final signer = OffchainSigner.fromPrivateKey(
  privateKeyHex: '0xabc...',
  chainId: 11155111,
  easContractAddress: '0x...',
);
```

With a wallet provider, developers implement a `Signer` adapter and pass it into `OffchainSigner(signer: ...)`.

***

## 8. PRD Amendments

### 8.1 Functional Requirements Updates

- **FR-2:** explicitly require `LocalKeySigner.signDigest()` to call `ETHPrivateKey.sign(digest, hashMessage: false)`.
- **FR-6:** define JSON serialization rules for typed data (BigInt as decimal strings, bytes as hex).
- **FR-9:** promote to MUST; `DefaultRpcProvider` must accept `Signer` and expose `fromPrivateKey` factory.
- **New FR-10:** delegated attestation helpers (`buildDelegatedAttestTypedData`, `attestByDelegation`).

### 8.2 Open Questions Resolutions

| Question                            | Recommended resolution                                                                                                                                       |
|-------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Q1: Abstract class naming           | Keep `Signer` — matches ethers.js / EAS SDK and avoids collisions with app-level types.                                                                     |
| Q2: `DefaultRpcProvider` scope      | Include `Signer` support in the initial deliverable; `sendTransaction()` already routes everything through `_privateKey.sign(...)` and can be swapped.      |
| Q3: `signTypedData` default impl    | Use Option A: a utility builds both `Eip712TypedData` and JSON map so `signTypedData(Map)` can either call wallet APIs or fall back to `.encode()`.        |
| Q4: `v` normalization               | Normalize `v` inside `OffchainSigner` (e.g., 27/28 → 0/1) so wallet adapters can return either convention while recovery always receives the expected id.   |
