# How to register a schema and attest onchain

This guide shows how to register a schema on the EAS Schema Registry and submit a Location Protocol attestation on-chain. It assumes you have completed the [getting started tutorial](tutorial-first-attestation.md) and have an RPC endpoint and funded Ethereum account. See [Prerequisites](#prerequisites) before starting.

---

## Prerequisites

- Dart ≥ 3.11
- `location_protocol` added to `pubspec.yaml`
- An RPC endpoint URL (e.g. Alchemy, Infura, or a public RPC)
- A funded Ethereum account private key (for gas)
- A `SchemaDefinition` and `LPPayload` ready (from [the tutorial](tutorial-first-attestation.md))

---

## Transaction lifecycle

The diagram below shows the full async RPC lifecycle for both operations. Note that schema registration does **not** poll for a receipt — the UID is deterministic and computed locally.

```mermaid
sequenceDiagram
    participant Code as Your Code
    participant RPC as DefaultRpcProvider
    participant ETH as Ethereum Node
    participant Reg as Schema Registry Contract
    participant EAS as EAS Contract

    Code->>RPC: DefaultRpcProvider(rpcUrl, privateKeyHex, chainId)
    Code->>Reg: SchemaRegistryClient(provider)
    Code->>Reg: register(schema)
    Reg->>RPC: buildRegisterCallData(schema)
    RPC->>ETH: eth_getTransactionCount
    ETH-->>RPC: nonce
    RPC->>ETH: eth_estimateGas
    ETH-->>RPC: gas estimate
    RPC->>ETH: eth_sendRawTransaction (EIP-1559 signed tx)
    ETH-->>RPC: txHash
    Note over Reg,Code: UID computed locally — no receipt poll needed
    Reg-->>Code: RegisterResult { txHash, uid }
    Code->>EAS: EASClient(provider)
    Code->>EAS: attest(schema, lpPayload, userData)
    EAS->>RPC: buildAttestCallData(...)
    RPC->>ETH: eth_getTransactionCount
    ETH-->>RPC: nonce
    RPC->>ETH: eth_estimateGas
    ETH-->>RPC: gas estimate
    RPC->>ETH: eth_sendRawTransaction (EIP-1559 signed tx)
    ETH-->>RPC: txHash
    RPC->>ETH: eth_getTransactionReceipt (poll)
    ETH-->>RPC: receipt (Attested event log)
    EAS-->>Code: AttestResult { txHash, uid, blockNumber }
```

---

## Step 1 — Set up your RPC provider

```dart
import 'dart:io';
import 'package:location_protocol/location_protocol.dart';

void main() async {
  // Load from environment variables — never hard-code credentials
  final rpcUrl = Platform.environment['EAS_RPC_URL']
      ?? (throw Exception('EAS_RPC_URL not set'));
  final privateKey = Platform.environment['EAS_PRIVATE_KEY']
      ?? (throw Exception('EAS_PRIVATE_KEY not set'));

  const chainId = 11155111; // Sepolia

  final provider = DefaultRpcProvider(
    rpcUrl: rpcUrl,
    privateKeyHex: privateKey,
    chainId: chainId,
  );
}
```

See [Environment configuration reference](reference-environment.md) for how to set these variables.

---

## Step 2 — Register the schema

```dart
  final registryClient = SchemaRegistryClient(provider: provider);

  // Compute the UID locally before registering
  final expectedUID = SchemaRegistryClient.computeSchemaUID(schema);
  print('Expected schema UID: $expectedUID');

  // Register on-chain (or reuse an existing UID if already registered)
  final registerResult = await registryClient.register(schema);
  print('Schema registered: ${registerResult.uid}');
  print('Transaction: ${registerResult.txHash}');
```

> **Note:** If the schema is already registered (same schema string + resolver + revocable), the transaction will revert. The UID is deterministic, so you can call `SchemaRegistryClient.computeSchemaUID(schema)` locally first and skip registration if the schema already exists on-chain.
>
> **Note:** `register()` broadcasts the transaction and returns immediately — it does not wait for the transaction to be mined. The `RegisterResult.uid` is computed locally from the schema parameters rather than extracted from a receipt. If you need confirmation that the transaction was mined before proceeding, poll `provider.waitForReceipt(registerResult.txHash)` manually.

---

## Step 3 — Attest onchain

```dart
  final easClient = EASClient(provider: provider);

  final attestResult = await easClient.attest(
    schema: schema,
    lpPayload: lpPayload,
    userData: {
      'timestamp': BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      'memo': 'Onchain field survey checkpoint',
    },
  );

  print('Attestation UID:   ${attestResult.uid}');
  print('Transaction hash:  ${attestResult.txHash}');
  print('Block number:      ${attestResult.blockNumber}');
```

Unlike `register()`, `attest()` polls for a receipt and extracts the UID from the `Attested` event log before returning. The call resolves only after the transaction is mined.

Optional parameters: `recipient` (defaults to the zero address), `expirationTime` (`BigInt`), and `refUID` (`String`).

---

## Step 4 — (Optional) Timestamp an offchain attestation

If you have an existing `SignedOffchainAttestation` from `OffchainSigner`, you can anchor it onchain at low cost:

```dart
  // Assumes `signed` is a SignedOffchainAttestation from OffchainSigner
  final timestampResult = await easClient.timestamp(signed.uid);

  print('Timestamped UID:  ${timestampResult.uid}');
  print('Block timestamp:  ${timestampResult.time}');
  print('Transaction hash: ${timestampResult.txHash}');
```

`TimestampResult.time` is a `BigInt` containing the `block.timestamp` (Unix seconds) at which the anchoring was recorded.

---

## What's next

- [Environment configuration reference](reference-environment.md)
- [API reference — EASClient](reference-api.md#easclient)
- [API reference — SchemaRegistryClient](reference-api.md#schemaregistryclient)
- [Concepts: Offchain vs onchain attestations](explanation-concepts.md#4-offchain-vs-onchain-attestations)
