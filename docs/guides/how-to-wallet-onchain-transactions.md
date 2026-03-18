# How to build a wallet-based onchain transaction

This guide shows how to package an onchain EAS attestation for submission via an external wallet — without running a `DefaultRpcProvider`. It assumes familiarity with `EASClient` and a wallet SDK that implements `eth_sendTransaction`.

---

## Prerequisites

- `location_protocol` in your `pubspec.yaml`
- A schema already registered onchain (see [How to register and attest onchain](how-to-register-and-attest-onchain.md))
- A wallet SDK available in your app context (Privy, MetaMask Flutter, FlutterWeb3, etc.)

---

## Step 1 — Build the ABI-encoded calldata

Use the **`static`** builder methods on `EASClient` or `SchemaRegistryClient` to produce the raw ABI-encoded calldata. Because these are static methods, they run purely offline in memory — you do **not** need to instantiate the client or provide an `RpcProvider`:

```dart
import 'package:location_protocol/location_protocol.dart';

void main() async {
  final schema = SchemaDefinition(
    fields: [SchemaField(type: 'string', name: 'memo')],
  );

  final lpPayload = LPPayload(
    lpVersion: '1.0.0',
    srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
    locationType: 'geojson-point',
    location: {'type': 'Point', 'coordinates': [-73.9857, 40.7484]},
  );

  final callData = EASClient.buildAttestCallData(
    schema: schema,
    lpPayload: lpPayload,
    userData: {'memo': 'My attestation'},
  );

  print('callData length: ${callData.length}');
}
```

---

## Step 2 — Build the wallet transaction request

Wrap the calldata into a standard wallet transaction request map using `TxUtils.buildTxRequest()`. Add the following inside `main`, after `callData`:

```dart
  final chainId = 11155111; // Sepolia
  final easAddress = ChainConfig.forChainId(chainId)!.eas;
  const myWalletAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

  final txRequest = TxUtils.buildTxRequest(
    to: easAddress,
    data: callData,
    from: myWalletAddress, // omit if your wallet SDK infers the sender
  );

  // txRequest is:
  // {
  //   'to':    '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
  //   'data':  '0x<abi-encoded calldata>',
  //   'value': '0x0',
  //   'from':  '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
  // }
  print('to:    ${txRequest['to']}');
  print('value: ${txRequest['value']}');
```

---

## Step 3 — Submit via your wallet SDK

Pass the transaction request map directly to your wallet SDK. The exact API varies by SDK. Add the following after `txRequest`:

```dart
  // Pass txRequest to your wallet SDK — exact API varies by SDK:
  // Privy:       final txHash = await privy.sendTransaction(txRequest);
  // FlutterWeb3: final txHash = await provider.request('eth_sendTransaction', [txRequest]);
  print('Transaction request ready: $txRequest');
```

---

## Other Onchain Operations

The exact same two-step pipeline (`buildCallData` → `TxUtils.buildTxRequest`) works for the other onchain operations.

**To Register a Schema via Wallet:**
```dart
// 1. Build the calldata offline (static method)
final callData = SchemaRegistryClient.buildRegisterCallData(schema);

// 2. Build the transaction request targeting the Registry
final txRequest = TxUtils.buildTxRequest(
  to: schemaRegistryAddress, 
  data: callData,
  from: myWalletAddress, 
);
```

**To Timestamp an Offchain UID via Wallet:**
```dart
// 1. Build the calldata offline (static method)
final callData = EASClient.buildTimestampCallData(offchainUid);

// 2. Build the transaction request targeting EAS
final txRequest = TxUtils.buildTxRequest(
  to: easAddress, 
  data: callData,
  from: myWalletAddress, 
);
```

---

## Notes

- `value` is always `'0x0'` for standard EAS attestations (no ETH transfer is needed).
- `from` is optional — omit it if your wallet SDK derives the sender automatically from the connected account.
- To wait for confirmation, use your wallet SDK's own receipt polling, or construct a read-only `DefaultRpcProvider` and call `provider.waitForReceipt(txHash)`.
- The calldata builders (`buildAttestCallData`, `buildRegisterCallData`, `buildTimestampCallData`) are all **`static`**. They never require an active RPC connection or a private key.
- `TxUtils.buildTxRequest` does not broadcast anything — it produces a plain `Map<String, dynamic>`. Your wallet holds all signing authority.

---

## What's next

- [API reference — TxUtils.buildTxRequest](reference-api.md#config)
- [Tutorial: Sign attestations with an external wallet signer](tutorial-wallet-signer.md)
- [Concepts: The Signer interface and wallet integration](explanation-concepts.md#7-the-signer-interface-and-wallet-integration)
