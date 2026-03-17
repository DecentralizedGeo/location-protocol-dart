# Building Wallet-Friendly Transaction Requests with `location_protocol`

## Overview

This document describes a minimal extension to the **location_protocol** Dart library that enables developers to use **external wallets** (MetaMask, Privy, WalletConnect, etc.) to submit onchain EAS attestations. The key idea is to expose a **wallet-facing transaction request helper** that packages the EAS ABI-encoded `data` field into a standard Ethereum transaction object, without changing how `location_protocol` handles payload encoding or onchain submission today.

With this capability:

- `location_protocol` remains responsible for:
  - Location Protocol payload validation and serialization.  
  - EAS schema UID computation and ABI encoding of `attest()` calls. [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/43204864/30ee7cfe-5bf1-469a-af84-2530a231007c/prd-signer-interface.md)
- Wallets remain responsible for:
  - Filling in nonce, gas, fees, and chain-specific policies.  
  - Asking users to approve, signing, and broadcasting transactions via methods like `eth_sendTransaction`. [docs.metamask](https://docs.metamask.io/wallet/how-to/send-transactions/)

This change does **not** introduce a new onchain signer abstraction inside Dart; it simply provides an “escape hatch” at the transaction boundary.

***

## Current Behavior

Today, `location_protocol` exposes:

- `EASClient.buildAttestCallData(...)` — constructs ABI-encoded call data for `EAS.attest(AttestationRequest)` from `SchemaDefinition`, `LPPayload`, and `userData`.
- `EASClient.attest(...)` — uses a `RpcProvider` to send the call onchain.
- `DefaultRpcProvider.sendTransaction(...)` — builds and signs a transaction using `ETHPrivateKey`, then calls `eth_sendRawTransaction`:
  - Fetches nonce via `eth_getTransactionCount`.  
  - Fetches fees via `eth_feeHistory` / `eth_gasPrice`.  
  - Estimates gas via `eth_estimateGas`.  
  - Builds EIP‑1559 or legacy tx bytes.  
  - Signs raw bytes with `ETHPrivateKey.sign(...)`.  
  - Sends via `eth_sendRawTransaction`.

This path **requires a raw private key** and offers no direct way to delegate transaction signing to an external wallet.

***

## Design Goal

Introduce a helper that:

- Takes the ABI-encoded call data from `EASClient.buildAttestCallData(...)`.
- Wraps it into a standard Ethereum transaction request map:
  - `to`: EAS contract address.  
  - `data`: encoded calldata as hex string.  
  - `value`: optional ETH value (usually `0x0` for EAS.attest).  
  - `from`: optional sender hint (wallet may infer). [docs.base](https://docs.base.org/base-account/reference/core/provider-rpc-methods/eth_sendTransaction)
- Can be serialized to JSON and passed to a wallet SDK on the JS/TS side for `eth_sendTransaction`.

This creates a clear boundary:

> `location_protocol`: “Here is the exact EAS contract call you should make (`to`, `data`, `value`).”  
> Wallet provider: “I will turn this into a transaction, sign it, and broadcast it.”

***

## Proposed API: `EASClient.buildAttestTxRequest`

Add a static helper to `EASClient`:

```dart
import 'dart:typed_data';

import '../utils/hex_utils.dart'; // for BytesUtils.toHexString
import '../utils/byte_utils.dart'; // if needed for other conversions

class EASClient {
  // Existing helper
  static Uint8List buildAttestCallData({
    required SchemaDefinition schema,
    required LPPayload lpPayload,
    required Map<String, dynamic> userData,
    String recipient = EASConstants.zeroAddress,
    BigInt? expirationTime,
    String? refUID,
  }) {
    // Existing implementation (unchanged).[cite:5]
  }

  /// Build a wallet-friendly transaction request for EAS.attest().
  ///
  /// This does NOT send or sign the transaction. It only packages the
  /// ABI-encoded call data into a standard Ethereum transaction map
  /// that can be serialized and passed to an external wallet.
  ///
  /// Typical usage:
  ///   1. callData = EASClient.buildAttestCallData(...)
  ///   2. txReq = EASClient.buildAttestTxRequest(
  ///        easAddress: easAddress,
  ///        callData: callData,
  ///        from: userAddress,
  ///      )
  ///   3. send txReq to a wallet SDK that calls eth_sendTransaction.
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
}
```

Notes:

- `callData` is the raw bytes returned by `buildAttestCallData(...)`.
- `BytesUtils.toHexString(callData)` is already used in `DefaultRpcProvider` to serialize transactions, so we reuse that utility.
- `value` defaults to `0x0`, which matches typical EAS usage where no ETH is attached. [docs.attest](https://docs.attest.org/docs/tutorials/make-an-attestation)

***

## Example Usage

### 1. Dart: Build call data and transaction request

```dart
// 1. Build ABI-encoded EAS.attest() call data
final callData = EASClient.buildAttestCallData(
  schema: schema,
  lpPayload: lpPayload,
  userData: userData,
  recipient: recipient,
  expirationTime: expirationTime,
  refUID: refUID,
);

// 2. Build a wallet-friendly transaction request
final txRequest = EASClient.buildAttestTxRequest(
  easAddress: easAddress,
  callData: callData,
  from: userAddress, // optional; wallet may infer from active account
);
```

At this point, `txRequest` looks like:

```json
{
  "from": "0xUserAddress",
  "to": "0xEasContractAddress",
  "data": "0x<functionSelector><encodedArguments>",
  "value": "0x0"
}
```

You can now:

- JSON-encode `txRequest`.
- Send it to your frontend (e.g., via REST, WebSocket, or platform channels).
- Use it with any wallet SDK that implements `eth_sendTransaction`.

### 2. JS/TS: Use the request with a wallet

In a JS/TS frontend (e.g., wagmi/viem, ethers, or plain EIP-1193 provider): [cubist](https://cubist.dev/blog/web3js-vs-ethersjs-how-ethereum-transactions-work)

```ts
// txRequest is the JSON from Dart.
const tx = {
  from: txRequest.from,      // optional, wallet may override
  to: txRequest.to,
  data: txRequest.data,
  value: txRequest.value,
};

// Using a generic EIP-1193 provider:
const txHash = await window.ethereum.request({
  method: 'eth_sendTransaction',
  params: [tx],
});

// Or with viem / wagmi walletClient:
const hash = await walletClient.sendTransaction({
  to: tx.to as `0x${string}`,
  data: tx.data as `0x${string}`,
  value: BigInt(tx.value),
});
```

The wallet takes over:

- Populating missing fields (nonce, gas, fee).  
- Prompting the user for confirmation.  
- Signing and broadcasting the transaction.

`location_protocol` does not need to know anything about how that happens.

***

## Scope and Non-Goals

This change is intentionally minimal:

- **In scope:**
  - New helper `EASClient.buildAttestTxRequest(...)`.  
  - Documentation and examples showing how to use it with external wallets.

- **Out of scope (for this change):**
  - Refactoring `DefaultRpcProvider` to use a `Signer` abstraction — still raw-key only.
  - Introducing onchain signer abstractions inside Dart.  
  - Adding support for delegated attestations or meta-transactions (those remain future work). [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/43204864/ac51cb3d-7f4a-4a4e-8050-6fcb4dbcbee3/Signer-Interface-Implementation-Report.txt)

***

## Benefits

- **Unlocks wallet-backed onchain flows** without exposing raw private keys in Dart:
  - Apps can keep all LP/EAS encoding logic in Dart / Flutter.  
  - Transaction signing happens entirely in the user’s wallet.

- **Keeps abstractions clean**:
  - LP + EAS semantics are modeled and encoded by `location_protocol`. [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/43204864/30ee7cfe-5bf1-469a-af84-2530a231007c/prd-signer-interface.md)
  - Transaction semantics (gas, nonces, account selection) are delegated to wallet providers.

- **Forward-compatible** with future improvements:
  - If/when a Dart-side onchain signer abstraction is added, this helper remains useful for apps that prefer delegating to browser wallets or other non-Dart environments.
  - The structure of the transaction request aligns with standard `eth_sendTransaction` expectations. [docs.metamask](https://docs.metamask.io/wallet/how-to/send-transactions/)

***

## Suggested Documentation Placement

- Add a new section under your reference or guides, e.g. **“Using External Wallets for Onchain Attestations”**, containing:
  - Brief explanation of the boundary between `location_protocol` and wallets.  
  - Code snippets from the examples above.  
  - A note that `DefaultRpcProvider` is still the raw-key path, while `buildAttestTxRequest()` is the recommended path when using external wallets.

This gives app developers a clear, supported pattern to:

> Use `location_protocol` for payload + ABI encoding, then pass a standard transaction request to their wallet provider hook to mint the attestation onchain.