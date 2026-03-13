# Phase 2: Onchain Operations — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement RPC-dependent methods to perform onchain operations (schema registration, onchain attestation, timestamping) against a real Ethereum network.

**Architecture:** A thin `HttpRpcService` transport layer wraps `dart:io`'s `HttpClient` to implement `on_chain`'s `EthereumServiceProvider` mixin. This feeds into `EthereumProvider`, which powers the JSON-RPC calls in `SchemaRegistryClient` and `EASClient`. A shared `RpcHelper` handles the common transaction lifecycle: nonce fetch → gas estimation → ETHTransaction build → sign → serialize → sendRawTransaction → return tx hash. All four existing stub methods (`register`, `getSchema`, `attest`, `timestamp`) get fleshed out using this infrastructure.

**Tech Stack:** Dart 3.6.2, `on_chain: ^7.1.0` (EIP-712/1559, ABI, ETHTransaction, EthereumProvider), `blockchain_utils: ^5.4.0` (crypto, bytes), `dart:io` (HttpClient), `dart:convert` (JSON).

---

## Table of Contents

| Phase | Description | Tasks |
|-------|-------------|-------|
| [A](#phase-a-rpc-transport-layer) | RPC Transport Layer | 1–2 |
| [B](#phase-b-schema-registry-onchain) | Schema Registry (Onchain) | 3–5 |
| [C](#phase-c-eas-client-onchain) | EAS Client (Onchain) | 6–8 |
| [D](#phase-d-integration--verification) | Integration & Verification | 9–10 |

**Total:** 10 tasks

---

## Phase A: RPC Transport Layer

### Task 1: HttpRpcService (HTTP Transport for on_chain's EthereumProvider)

A small internal service that implements `EthereumServiceProvider` using `dart:io`'s `HttpClient`. This is the bridge between `on_chain`'s `EthereumProvider` and any JSON-RPC endpoint.

**Files:**
- Create: `lib/src/rpc/http_rpc_service.dart`
- Test: `test/rpc/http_rpc_service_test.dart`

**Step 1: Write the failing test**

Create `test/rpc/http_rpc_service_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:location_protocol/src/rpc/http_rpc_service.dart';

void main() {
  group('HttpRpcService', () {
    test('constructs with a valid URL', () {
      final service = HttpRpcService('https://rpc.sepolia.org');
      expect(service.url, equals('https://rpc.sepolia.org'));
    });

    test('constructs with custom timeout', () {
      final service = HttpRpcService(
        'https://rpc.sepolia.org',
        defaultTimeout: const Duration(seconds: 60),
      );
      expect(service.url, equals('https://rpc.sepolia.org'));
    });

    test('throws on empty URL', () {
      expect(() => HttpRpcService(''), throwsArgumentError);
    });
  });
}
```

**Step 2: Run tests to verify they fail**

```bash
dart test test/rpc/http_rpc_service_test.dart
```

Expected: FAIL — `http_rpc_service.dart` does not exist.

**Step 3: Write minimal implementation**

Create `lib/src/rpc/http_rpc_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

/// HTTP-based JSON-RPC service for communicating with Ethereum nodes.
///
/// Implements `EthereumServiceProvider` using `dart:io`'s [HttpClient]
/// so that `on_chain`'s [EthereumProvider] can issue JSON-RPC calls
/// to any standard Ethereum RPC endpoint.
///
/// Usage:
/// ```dart
/// final service = HttpRpcService('https://rpc.sepolia.org');
/// final provider = EthereumProvider(service);
/// ```
class HttpRpcService with EthereumServiceProvider {
  /// The JSON-RPC endpoint URL.
  final String url;

  /// Default timeout for HTTP requests.
  final Duration defaultTimeout;

  final HttpClient _client;

  HttpRpcService(
    this.url, {
    this.defaultTimeout = const Duration(seconds: 30),
  }) : _client = HttpClient() {
    if (url.isEmpty) {
      throw ArgumentError('RPC URL must not be empty');
    }
  }

  @override
  Future<EthereumServiceResponse<T>> doRequest<T>(
    EthereumRequestDetails params, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? defaultTimeout;
    final uri = params.toUri(url);
    final body = params.body();

    final request = await _client.postUrl(uri);
    request.headers.set('Content-Type', 'application/json');
    if (body != null) {
      request.add(body);
    }

    final response = await request.close().timeout(effectiveTimeout);
    final responseBytes = await _collectBytes(response);

    final statusCode = response.statusCode;
    return params.toResponse(responseBytes, statusCode);
  }

  Future<List<int>> _collectBytes(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    return builder.toBytes();
  }

  /// Closes the underlying HTTP client.
  void close() {
    _client.close();
  }
}
```

**Step 4: Run tests to verify they pass**

```bash
dart test test/rpc/http_rpc_service_test.dart
```

Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/rpc/http_rpc_service.dart test/rpc/http_rpc_service_test.dart
git commit -m "feat: add HttpRpcService for dart:io-based JSON-RPC transport"
```

---

### Task 2: RpcHelper (Shared Transaction Lifecycle)

Centralizes the common transaction build → sign → send flow using `on_chain`'s
`ETHTransactionBuilder`. Both `SchemaRegistryClient` and `EASClient` delegate to this helper.

> [!IMPORTANT]
> Uses `ETHTransactionBuilder.autoFill()` + `.sign()` + `.sendTransaction()` instead of
> manually constructing `ETHTransaction` and signing. This delegates nonce, gas estimation,
> EIP-1559 fee calculation, and signing to the package's battle-tested implementation,
> avoiding a critical signing bug (manual pre-hashing would double-hash the digest).

**Files:**
- Create: `lib/src/rpc/rpc_helper.dart`
- Test: `test/rpc/rpc_helper_test.dart`

**Step 1: Write the failing test**

Create `test/rpc/rpc_helper_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:on_chain/on_chain.dart';
import 'package:location_protocol/src/rpc/rpc_helper.dart';

void main() {
  group('RpcHelper', () {
    test('constructs with required parameters', () {
      final helper = RpcHelper(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(helper.chainId, equals(11155111));
    });

    test('derives sender address from private key', () {
      final helper = RpcHelper(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      // Hardhat account #0 address
      expect(helper.senderAddress.address.toLowerCase(),
          equals('0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266'));
    });
  });
}
```

**Step 2: Run tests to verify they fail**

```bash
dart test test/rpc/rpc_helper_test.dart
```

Expected: FAIL — `rpc_helper.dart` does not exist.

**Step 3: Write minimal implementation**

Create `lib/src/rpc/rpc_helper.dart`:

```dart
import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

import 'http_rpc_service.dart';

/// Shared helper for building, signing, and sending Ethereum transactions.
///
/// Delegates the full transaction lifecycle to `on_chain`'s
/// [ETHTransactionBuilder]:
/// 1. `autoFill()` — fetches nonce, estimates gas, calculates fees
///    (EIP-1559 if supported, legacy fallback otherwise)
/// 2. `sign()` — signs with [ETHPrivateKey] (correct keccak256 hashing)
/// 3. `sendTransaction()` — serializes signed tx and sends via
///    `eth_sendRawTransaction`
class RpcHelper {
  final String rpcUrl;
  final int chainId;

  late final ETHPrivateKey _privateKey;
  late final EthereumProvider _provider;
  late final HttpRpcService _service;

  RpcHelper({
    required this.rpcUrl,
    required String privateKeyHex,
    required this.chainId,
  }) {
    _privateKey = ETHPrivateKey(privateKeyHex);
    _service = HttpRpcService(rpcUrl);
    _provider = EthereumProvider(_service);
  }

  /// The sender's Ethereum address derived from the private key.
  ETHAddress get senderAddress =>
      _privateKey.publicKey().toAddress();

  /// Sends a contract-calling transaction and returns the tx hash.
  ///
  /// [to] is the contract address.
  /// [data] is the ABI-encoded call data (with function selector).
  /// [value] is the ETH value to send (default 0).
  Future<String> sendTransaction({
    required String to,
    required Uint8List data,
    BigInt? value,
  }) async {
    // Build the transaction using ETHTransactionBuilder
    final builder = ETHTransactionBuilder(
      from: senderAddress,
      to: ETHAddress(to),
      value: value ?? BigInt.zero,
      chainId: BigInt.from(chainId),
      memo: null,
    );

    // Set the raw call data directly on the builder's internal data field.
    // ETHTransactionBuilder.contract() would also work but requires an
    // AbiFunctionFragment; since we pre-encode call data externally,
    // we set the data bytes after construction.
    // NOTE: If ETHTransactionBuilder doesn't expose a way to set raw data,
    // we'll fall back to building ETHTransaction directly. Verify during
    // implementation by checking if the builder's _data field is accessible
    // or if there's a setter method.

    // autoFill handles: nonce, gas estimation, EIP-1559 fee calculation
    await builder.autoFill(_provider);

    // sign uses the correct internal hashing (no double-hash bug)
    builder.sign(_privateKey);

    // sendTransaction serializes and sends via eth_sendRawTransaction
    return await builder.sendTransaction(_provider);
  }

  /// Performs an `eth_call` (read-only) against a contract.
  ///
  /// Returns the decoded ABI output.
  Future<List<dynamic>> callContract({
    required String contractAddress,
    required AbiFunctionFragment function,
    List<dynamic> params = const [],
  }) async {
    return await _provider.request(
      EthereumRequestFunctionCall(
        contractAddress: contractAddress,
        function: function,
        params: params,
      ),
    );
  }

  /// Closes the underlying HTTP client.
  void close() {
    _service.close();
  }
}
```

> [!NOTE]
> **Implementation decision point:** `ETHTransactionBuilder` has two construction paths:
> 1. `ETHTransactionBuilder(...)` for basic transactions (memo only)
> 2. `ETHTransactionBuilder.contract(...)` for contract calls (takes `AbiFunctionFragment` + params)
>
> Since our callers (`register`, `attest`, `timestamp`) already pre-encode call data via
> `buildRegisterCallData` / `buildAttestCallData` / `buildTimestampCallData`, we need to
> pass raw bytes. During implementation, verify whether:
> - (a) `ETHTransactionBuilder` exposes a way to set raw `data` bytes, or
> - (b) We should use `ETHTransactionBuilder.contract()` with the `AbiFunctionFragment` directly
>   (passing the fragment + params into `RpcHelper` instead of pre-encoded bytes), or
> - (c) Build `ETHTransaction` directly but use the correct signing pattern:
>   `_privateKey.sign(tx.serialized)` with `hashMessage: true` (the default).
>
> Option (c) is the safest fallback if the builder doesn't support raw data injection.

**Step 4: Run tests to verify they pass**

```bash
dart test test/rpc/rpc_helper_test.dart
```

Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/rpc/rpc_helper.dart test/rpc/rpc_helper_test.dart
git commit -m "feat: add RpcHelper for shared transaction lifecycle"
```

---

## Phase B: Schema Registry (Onchain)

### Task 3: Implement SchemaRegistryClient.register()

Replace the `UnimplementedError` stub with a real RPC-backed implementation.

**Files:**
- Modify: `lib/src/eas/schema_registry.dart`
- Modify: `test/eas/schema_registry_test.dart`

**Step 1: Write the failing test**

Add to `test/eas/schema_registry_test.dart`:

```dart
    test('register throws UnimplementedError (pre-implementation check)', () {
      final registry = SchemaRegistryClient(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      // After implementation, this will no longer throw UnimplementedError.
      // This test verifies the stub exists before we replace it.
      expect(
        () => registry.register(
          SchemaDefinition(
            fields: [SchemaField(type: 'uint256', name: 'timestamp')],
          ),
        ),
        throwsUnimplementedError,
      );
    });
```

**Step 2: Run test to verify it passes (pre-implementation)**

```bash
dart test test/eas/schema_registry_test.dart -n "register throws UnimplementedError"
```

Expected: PASS (confirms stub exists).

**Step 3: Implement register()**

Modify `lib/src/eas/schema_registry.dart`:

1. Add import for `RpcHelper`:
```dart
import '../rpc/rpc_helper.dart';
```

2. Replace the `register()` method body:

```dart
  /// Registers a schema on-chain.
  ///
  /// Sends a transaction to `SchemaRegistry.register()` and returns
  /// the transaction hash.
  ///
  /// Requires an RPC connection and a funded wallet.
  Future<String> register(SchemaDefinition schema) async {
    final callData = buildRegisterCallData(schema);
    final helper = RpcHelper(
      rpcUrl: rpcUrl,
      privateKeyHex: privateKeyHex,
      chainId: chainId,
    );
    try {
      return await helper.sendTransaction(
        to: contractAddress,
        data: callData,
      );
    } finally {
      helper.close();
    }
  }
```

**Step 4: Update test — the UnimplementedError test should now fail**

```bash
dart test test/eas/schema_registry_test.dart -n "register throws UnimplementedError"
```

Expected: FAIL — `register()` no longer throws `UnimplementedError` (it will try an actual RPC call and fail with a network error, which is correct).

**Step 5: Replace the test with a proper unit test**

Replace the `UnimplementedError` test with:

```dart
    test('register attempts RPC call (fails gracefully without network)', () {
      final registry = SchemaRegistryClient(
        rpcUrl: 'http://localhost:1', // intentionally unreachable
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      // Calling register should attempt a real RPC call and throw
      // a network/connection error (not UnimplementedError)
      expect(
        () => registry.register(
          SchemaDefinition(
            fields: [SchemaField(type: 'uint256', name: 'timestamp')],
          ),
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });
```

**Step 6: Run tests to verify they pass**

```bash
dart test test/eas/schema_registry_test.dart
```

Expected: All tests PASS.

**Step 7: Commit**

```bash
git add lib/src/eas/schema_registry.dart test/eas/schema_registry_test.dart
git commit -m "feat: implement SchemaRegistryClient.register() with RPC"
```

---

### Task 4: Implement SchemaRegistryClient.getSchema()

Replace the `UnimplementedError` stub with an `eth_call` to `getSchema(bytes32)`.

**Files:**
- Modify: `lib/src/eas/schema_registry.dart`
- Modify: `test/eas/schema_registry_test.dart`

**Step 1: Write the failing test**

Add to `test/eas/schema_registry_test.dart`:

```dart
    test('getSchema attempts RPC call (fails gracefully without network)', () {
      final registry = SchemaRegistryClient(
        rpcUrl: 'http://localhost:1', // intentionally unreachable
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(
        () => registry.getSchema(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });
```

**Step 2: Run test to verify it fails**

```bash
dart test test/eas/schema_registry_test.dart -n "getSchema attempts"
```

Expected: FAIL — `getSchema()` throws `UnimplementedError`, not a network error.

**Step 3: Implement getSchema()**

Add a static `getSchema` ABI fragment and implement the method in `lib/src/eas/schema_registry.dart`:

```dart
  /// ABI fragment for `getSchema(bytes32)`.
  static final _getSchemaFragment = AbiFunctionFragment.fromJson({
    'name': 'getSchema',
    'type': 'function',
    'stateMutability': 'view',
    'inputs': [
      {'name': 'uid', 'type': 'bytes32'},
    ],
    'outputs': [
      {
        'name': '',
        'type': 'tuple',
        'components': [
          {'name': 'uid', 'type': 'bytes32'},
          {'name': 'resolver', 'type': 'address'},
          {'name': 'revocable', 'type': 'bool'},
          {'name': 'schema', 'type': 'string'},
        ],
      },
    ],
  });

  /// Queries a schema by its UID from the SchemaRegistry.
  ///
  /// Returns the schema record or null if not found.
  Future<SchemaRecord?> getSchema(String uid) async {
    final helper = RpcHelper(
      rpcUrl: rpcUrl,
      privateKeyHex: privateKeyHex,
      chainId: chainId,
    );
    try {
      final uidBytes =
          BytesUtils.fromHexString(uid.replaceAll('0x', ''));

      final result = await helper.callContract(
        contractAddress: contractAddress,
        function: _getSchemaFragment,
        params: [uidBytes],
      );

      if (result.isEmpty) return null;

      // The result is a list: [uid, resolver, revocable, schema]
      // Parse based on ABI output tuple structure
      final decoded = result[0]; // Tuple result
      if (decoded is List && decoded.length >= 4) {
        final recordUid = decoded[0]; // bytes32
        final resolver = decoded[1]; // address
        final revocable = decoded[2]; // bool
        final schema = decoded[3]; // string

        final uidHex = recordUid is List<int>
            ? BytesUtils.toHexString(recordUid, prefix: '0x')
            : recordUid.toString();

        // Check for zero UID (schema not found)
        if (uidHex ==
            '0x0000000000000000000000000000000000000000000000000000000000000000') {
          return null;
        }

        return SchemaRecord(
          uid: uidHex,
          resolver: resolver.toString(),
          revocable: revocable as bool,
          schema: schema.toString(),
        );
      }

      return null;
    } finally {
      helper.close();
    }
  }
```

> [!NOTE]
> The exact shape of `result` from `EthereumRequestFunctionCall` will need to be verified during implementation. The `on_chain` library may return the tuple slightly differently than expected. The implementer should add a debug print/log if the output shape is unclear, then adjust the parsing accordingly.

**Step 4: Run test to verify it passes**

```bash
dart test test/eas/schema_registry_test.dart
```

Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/eas/schema_registry.dart test/eas/schema_registry_test.dart
git commit -m "feat: implement SchemaRegistryClient.getSchema() with eth_call"
```

---

### Task 5: Add buildAttestCallData to EASClient

Before implementing `attest()`, we need the `buildAttestCallData` static method, similar to how `buildTimestampCallData` already works. The EAS `attest()` function takes a nested struct `AttestationRequest`:

```solidity
function attest(AttestationRequest calldata request) external payable returns (bytes32)

struct AttestationRequest {
    bytes32 schema;
    AttestationRequestData data;
}

struct AttestationRequestData {
    address recipient;
    uint64 expirationTime;
    bool revocable;
    bytes32 refUID;
    bytes data;
    uint256 value;
}
```

**Files:**
- Modify: `lib/src/eas/onchain_client.dart`
- Modify: `test/eas/onchain_client_test.dart`

**Step 1: Write the failing test**

Add to `test/eas/onchain_client_test.dart`:

```dart
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
```

And add the test:

```dart
    test('buildAttestCallData produces non-empty bytes', () {
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: 'test-location',
      );

      final callData = EASClient.buildAttestCallData(
        schema: schema,
        lpPayload: lpPayload,
        userData: {'timestamp': BigInt.from(1710000000)},
      );
      expect(callData, isNotEmpty);
      // Must start with the 4-byte function selector
      expect(callData.length, greaterThan(4));
    });

    test('buildAttestCallData includes function selector', () {
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: 'test-location',
      );

      final data1 = EASClient.buildAttestCallData(
        schema: schema,
        lpPayload: lpPayload,
        userData: {'timestamp': BigInt.from(1710000000)},
      );
      final data2 = EASClient.buildAttestCallData(
        schema: schema,
        lpPayload: lpPayload,
        userData: {'timestamp': BigInt.from(9999999999)},
      );
      // Same function selector (first 4 bytes)
      expect(data1.sublist(0, 4), equals(data2.sublist(0, 4)));
      // Different data
      expect(data1, isNot(equals(data2)));
    });
```

**Step 2: Run tests to verify they fail**

```bash
dart test test/eas/onchain_client_test.dart
```

Expected: FAIL — `buildAttestCallData` doesn't exist.

**Step 3: Write minimal implementation**

Add to `lib/src/eas/onchain_client.dart`:

1. Add imports at the top:
```dart
import '../schema/schema_uid.dart';
import 'abi_encoder.dart';
import 'constants.dart';
```

2. Add the static method to the `EASClient` class:
```dart
  /// Builds ABI-encoded call data for `EAS.attest(AttestationRequest)`.
  ///
  /// The EAS `attest()` function takes a nested struct:
  /// ```solidity
  /// struct AttestationRequest {
  ///     bytes32 schema;
  ///     AttestationRequestData data;
  /// }
  /// struct AttestationRequestData {
  ///     address recipient;
  ///     uint64 expirationTime;
  ///     bool revocable;
  ///     bytes32 refUID;
  ///     bytes data;
  ///     uint256 value;
  /// }
  /// ```
  static Uint8List buildAttestCallData({
    required SchemaDefinition schema,
    required LPPayload lpPayload,
    required Map<String, dynamic> userData,
    String recipient = '0x0000000000000000000000000000000000000000',
    BigInt? expirationTime,
    String? refUID,
  }) {
    final schemaUID = SchemaUID.compute(schema);
    final encodedData = AbiEncoder.encode(
      schema: schema,
      lpPayload: lpPayload,
      userData: userData,
    );
    final expTime = expirationTime ?? BigInt.zero;
    final ref = refUID ?? EASConstants.zeroBytes32;

    final fragment = AbiFunctionFragment.fromJson({
      'name': 'attest',
      'type': 'function',
      'stateMutability': 'payable',
      'inputs': [
        {
          'name': 'request',
          'type': 'tuple',
          'components': [
            {'name': 'schema', 'type': 'bytes32'},
            {
              'name': 'data',
              'type': 'tuple',
              'components': [
                {'name': 'recipient', 'type': 'address'},
                {'name': 'expirationTime', 'type': 'uint64'},
                {'name': 'revocable', 'type': 'bool'},
                {'name': 'refUID', 'type': 'bytes32'},
                {'name': 'data', 'type': 'bytes'},
                {'name': 'value', 'type': 'uint256'},
              ],
            },
          ],
        },
      ],
      'outputs': [
        {'name': '', 'type': 'bytes32'},
      ],
    });

    final schemaUIDBytes =
        BytesUtils.fromHexString(schemaUID.replaceAll('0x', ''));
    final refUIDBytes =
        BytesUtils.fromHexString(ref.replaceAll('0x', ''));

    final encoded = fragment.encode([
      [
        schemaUIDBytes, // bytes32 schema
        [
          recipient, // address recipient
          expTime, // uint64 expirationTime
          schema.revocable, // bool revocable
          refUIDBytes, // bytes32 refUID
          encodedData, // bytes data
          BigInt.zero, // uint256 value (ETH to send, typically 0)
        ],
      ],
    ]);

    return Uint8List.fromList(encoded);
  }
```

> [!NOTE]
> The nested tuple encoding format for `on_chain`'s `AbiFunctionFragment.encode()` may need adjustment. The exact way to pass nested tuples (as a nested List vs flat list) should be verified during implementation by testing against a known-good ABI encoding. If encoding fails, try flattening the parameters or adjusting the nesting structure.

**Step 4: Run tests to verify they pass**

```bash
dart test test/eas/onchain_client_test.dart
```

Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/eas/onchain_client.dart test/eas/onchain_client_test.dart
git commit -m "feat: add EASClient.buildAttestCallData for onchain attestation"
```

---

## Phase C: EAS Client (Onchain)

### Task 6: Implement EASClient.attest()

Replace the `UnimplementedError` stub with a real RPC-backed implementation using `buildAttestCallData` + `RpcHelper`.

**Files:**
- Modify: `lib/src/eas/onchain_client.dart`
- Modify: `test/eas/onchain_client_test.dart`

**Step 1: Write the failing test**

Add to `test/eas/onchain_client_test.dart`:

```dart
    test('attest attempts RPC call (fails gracefully without network)', () {
      final client = EASClient(
        rpcUrl: 'http://localhost:1', // intentionally unreachable
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: 'test',
      );
      expect(
        () => client.attest(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000)},
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });
```

**Step 2: Run test to verify it fails**

```bash
dart test test/eas/onchain_client_test.dart -n "attest attempts"
```

Expected: FAIL — `attest()` throws `UnimplementedError`.

**Step 3: Implement attest()**

Modify `lib/src/eas/onchain_client.dart`:

1. Add import:
```dart
import '../rpc/rpc_helper.dart';
```

2. Replace the `attest()` method body:

```dart
  /// Submit an onchain attestation.
  ///
  /// Sends a transaction to `EAS.attest()` and returns
  /// the transaction hash.
  ///
  /// Requires the schema to already be registered on-chain.
  Future<String> attest({
    required SchemaDefinition schema,
    required LPPayload lpPayload,
    required Map<String, dynamic> userData,
    String recipient = '0x0000000000000000000000000000000000000000',
    BigInt? expirationTime,
    String? refUID,
  }) async {
    final callData = buildAttestCallData(
      schema: schema,
      lpPayload: lpPayload,
      userData: userData,
      recipient: recipient,
      expirationTime: expirationTime,
      refUID: refUID,
    );
    final helper = RpcHelper(
      rpcUrl: rpcUrl,
      privateKeyHex: privateKeyHex,
      chainId: chainId,
    );
    try {
      return await helper.sendTransaction(
        to: easAddress,
        data: callData,
      );
    } finally {
      helper.close();
    }
  }
```

**Step 4: Run test to verify it passes**

```bash
dart test test/eas/onchain_client_test.dart
```

Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/eas/onchain_client.dart test/eas/onchain_client_test.dart
git commit -m "feat: implement EASClient.attest() with RPC"
```

---

### Task 7: Implement EASClient.timestamp()

Replace the `UnimplementedError` stub. Uses the existing `buildTimestampCallData` + `RpcHelper`.

**Files:**
- Modify: `lib/src/eas/onchain_client.dart`
- Modify: `test/eas/onchain_client_test.dart`

**Step 1: Write the failing test**

Add to `test/eas/onchain_client_test.dart`:

```dart
    test('timestamp attempts RPC call (fails gracefully without network)', () {
      final client = EASClient(
        rpcUrl: 'http://localhost:1', // intentionally unreachable
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(
        () => client.timestamp(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });
```

**Step 2: Run test to verify it fails**

```bash
dart test test/eas/onchain_client_test.dart -n "timestamp attempts"
```

Expected: FAIL — `timestamp()` throws `UnimplementedError`.

**Step 3: Implement timestamp()**

Replace the `timestamp()` method body in `lib/src/eas/onchain_client.dart`:

```dart
  /// Timestamp an offchain attestation UID onchain.
  ///
  /// Records a timestamp on the EAS contract proving the UID existed
  /// at a specific block time. Returns the transaction hash.
  Future<String> timestamp(String offchainUID) async {
    final callData = buildTimestampCallData(offchainUID);
    final helper = RpcHelper(
      rpcUrl: rpcUrl,
      privateKeyHex: privateKeyHex,
      chainId: chainId,
    );
    try {
      return await helper.sendTransaction(
        to: easAddress,
        data: callData,
      );
    } finally {
      helper.close();
    }
  }
```

**Step 4: Run test to verify it passes**

```bash
dart test test/eas/onchain_client_test.dart
```

Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/eas/onchain_client.dart test/eas/onchain_client_test.dart
git commit -m "feat: implement EASClient.timestamp() with RPC"
```

---

### Task 8: Update EASClient.registerSchema() and barrel export

The `registerSchema()` already delegates to `SchemaRegistryClient.register()`, which is now implemented. Just need to add the `rpc/` exports to the barrel file.

**Files:**
- Modify: `lib/location_protocol.dart`

**Step 1: Add exports**

Add to `lib/location_protocol.dart`:

```dart
// RPC layer
export 'src/rpc/http_rpc_service.dart';
export 'src/rpc/rpc_helper.dart';
```

**Step 2: Verify analysis passes**

```bash
dart analyze
```

Expected: No errors.

**Step 3: Run all tests**

```bash
dart test
```

Expected: All tests PASS (existing 86 tests + new tests from this phase).

**Step 4: Commit**

```bash
git add lib/location_protocol.dart
git commit -m "chore: add RPC layer exports to barrel file"
```

---

## Phase D: Integration & Verification

### Task 9: Environment Config & Sepolia Integration Test (Tagged)

Create `.env.example` and `.env` files for test configuration, a small `.env` file loader helper, and write Sepolia integration tests tagged with `@Tags(['sepolia'])` so they are **excluded from normal `dart test` runs**.

> [!IMPORTANT]
> This test requires a funded Sepolia wallet. The private key and RPC URL are loaded from a `.env` file in the project root. Copy `.env.example` to `.env` and fill in your values. Do NOT commit `.env` to git.

**Files:**
- Create: `.env.example`
- Create: `.gitignore`
- Create: `test/test_helpers/dotenv_loader.dart`
- Create: `test/integration/sepolia_onchain_test.dart`
- Create: `dart_test.yaml`

**Step 1: Create `.env.example`**

Create `.env.example` in the project root (modeled after Astral SDK):

```bash
# Location Protocol Dart — Environment Configuration
# Copy this file to .env and fill in your actual values
#
#   cp .env.example .env

# =============================================================================
# BLOCKCHAIN RPC PROVIDERS
# =============================================================================

# Get API keys from: https://infura.io/ or https://alchemy.com/

# Infura API Key (recommended for development)
INFURA_API_KEY=

# Alternative: Alchemy API Key
ALCHEMY_API_KEY=

# Sepolia Testnet RPC URL (required for integration tests)
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/${INFURA_API_KEY}
# Alternative: SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY}

# =============================================================================
# TESTING CONFIGURATION
# =============================================================================

# Test wallet private key (create a dedicated test wallet for this)
# Generate with: dart run script/generate_wallet.dart
# WARNING: Only use for testing with minimal Sepolia ETH
SEPOLIA_PRIVATE_KEY=

# =============================================================================
# QUICK START
# =============================================================================

# 1. Copy this file: cp .env.example .env
# 2. Get Infura API key: https://infura.io/ → set INFURA_API_KEY
# 3. Set SEPOLIA_RPC_URL with your full Infura/Alchemy URL
# 4. Generate or import a test wallet → set SEPOLIA_PRIVATE_KEY
# 5. Fund the wallet with Sepolia ETH: https://sepoliafaucet.com/
# 6. Run integration tests: dart test --tags sepolia

# =============================================================================
# SECURITY REMINDERS
# =============================================================================

# ⚠️  NEVER commit your .env file to version control
# ⚠️  Only fund test wallets with minimal Sepolia ETH
# ⚠️  Use dedicated test wallets — never reuse mainnet keys
# ⚠️  Rotate API keys regularly
```

**Step 2: Create `.gitignore`**

Create `.gitignore` in the project root:

```gitignore
# Environment secrets
.env

# Dart/Flutter
.dart_tool/
.packages
build/
pubspec.lock

# IDE
.idea/
*.iml
.vscode/

# OS
.DS_Store
Thumbs.db
```

**Step 3: Create the .env loader test helper**

Create `test/test_helpers/dotenv_loader.dart` — a zero-dependency helper that loads `.env` files:

```dart
import 'dart:io';

/// Loads key-value pairs from a `.env` file into a Map.
///
/// Supports:
/// - `KEY=VALUE` pairs (one per line)
/// - Lines starting with `#` are comments (ignored)
/// - Empty lines are ignored
/// - Values are NOT expanded (no `${VAR}` interpolation)
/// - Surrounding quotes on values are stripped
///
/// Returns an empty map if the file does not exist.
Map<String, String> loadDotEnv({String path = '.env'}) {
  final file = File(path);
  if (!file.existsSync()) return {};

  final env = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final eqIndex = trimmed.indexOf('=');
    if (eqIndex < 0) continue;

    final key = trimmed.substring(0, eqIndex).trim();
    var value = trimmed.substring(eqIndex + 1).trim();

    // Strip surrounding quotes
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }

    if (key.isNotEmpty && value.isNotEmpty) {
      env[key] = value;
    }
  }
  return env;
}
```

**Step 4: Create test tag configuration**

Create `dart_test.yaml` in the project root:

```yaml
tags:
  sepolia:
    # Tests requiring a live Sepolia RPC connection.
    # Run with: dart test --tags sepolia
    # Requires .env file with SEPOLIA_RPC_URL and SEPOLIA_PRIVATE_KEY
```

**Step 5: Write the integration test**

Create `test/integration/sepolia_onchain_test.dart`:

```dart
@Tags(['sepolia'])
library;

import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/schema_registry.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';
import 'package:location_protocol/src/eas/offchain_signer.dart';

import '../test_helpers/dotenv_loader.dart';

void main() {
  final env = loadDotEnv();
  final rpcUrl = env['SEPOLIA_RPC_URL'];
  final privateKey = env['SEPOLIA_PRIVATE_KEY'];

  if (rpcUrl == null || privateKey == null) {
    print('⚠️  Skipping Sepolia tests: .env file missing or incomplete.');
    print('   Copy .env.example to .env and fill in your values.');
    return;
  }

  group('Sepolia Onchain Operations', () {
    test('register a schema on Sepolia', () async {
      final registry = SchemaRegistryClient(
        rpcUrl: rpcUrl,
        privateKeyHex: privateKey,
        chainId: 11155111,
      );

      // Use a unique schema to avoid "already registered" reverts.
      final uniqueField =
          'test_${DateTime.now().millisecondsSinceEpoch}';
      final schema = SchemaDefinition(
        fields: [
          SchemaField(type: 'string', name: uniqueField),
        ],
      );

      final txHash = await registry.register(schema);
      expect(txHash, startsWith('0x'));
      expect(txHash.length, equals(66));

      print('Schema registered. TX: $txHash');
      print('Expected UID: ${SchemaRegistryClient.computeSchemaUID(schema)}');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('timestamp an offchain attestation on Sepolia', () async {
      final client = EASClient(
        rpcUrl: rpcUrl,
        privateKeyHex: privateKey,
        chainId: 11155111,
      );

      // First create an offchain attestation to get a UID
      final schema = SchemaDefinition(fields: []);
      final signer = OffchainSigner(
        privateKeyHex: privateKey,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );

      final signed = await signer.signOffchainAttestation(
        schema: schema,
        lpPayload: LPPayload(
          lpVersion: '1.0.0',
          srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
          locationType: 'geojson-point',
          location: 'test-location',
        ),
        userData: {},
      );

      final txHash = await client.timestamp(signed.uid);
      expect(txHash, startsWith('0x'));
      expect(txHash.length, equals(66));

      print('Timestamp TX: $txHash');
      print('Timestamped UID: ${signed.uid}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
```

**Step 6: Verify the test is excluded from normal runs**

```bash
dart test
```

Expected: All tests PASS, Sepolia tests are SKIPPED (not tagged for default runs).

**Step 7: Run Sepolia tests explicitly (requires .env)**

```bash
# Ensure .env exists with SEPOLIA_RPC_URL and SEPOLIA_PRIVATE_KEY
dart test --tags sepolia
```

Expected: Tests PASS against live Sepolia network.

**Step 8: Commit**

```bash
git add .env.example .gitignore dart_test.yaml \
  test/test_helpers/dotenv_loader.dart \
  test/integration/sepolia_onchain_test.dart
git commit -m "feat: add .env config and Sepolia integration tests"

---

### Task 10: Final Verification & Cleanup

**Step 1: Run full analysis**

```bash
dart analyze
```

Expected: No errors, no warnings.

**Step 2: Run all tests**

```bash
dart test
```

Expected: All tests PASS (≥90 tests). Output is clean — no warnings, no deprecation notices.

**Step 3: Verify no unused imports or dead code**

Review each modified file for unused imports. Remove any that were added during development but not needed in the final implementation.

**Step 4: Commit any cleanup changes**

```bash
git add -A
git commit -m "chore: final cleanup for Phase 2 onchain operations"
```

**Step 5: Consolidate Memory**

Update `.ai/memory/` to record Phase 2 learnings:

- `episodic.md`: Add `[ID: PHASE2_ONCHAIN_OPS]` entry
- `semantic.md`: Add notes about `HttpRpcService`, `RpcHelper`, `EthereumServiceProvider` mixin, `EthereumProvider` pattern
- `procedural.md`: Add quirks discovered (e.g., nested tuple encoding in `on_chain`, `HttpClient` usage patterns)

**Step 6: Create walkthrough.md**

Create a walkthrough documenting what was implemented, what was tested, and verification results.

---

## Verification Plan

### Automated Tests (run with every commit)

```bash
# Run all unit tests (excludes Sepolia):
dart test

# Run static analysis:
dart analyze
```

### Sepolia Integration Tests (manual trigger)

```bash
# 1. Copy .env.example to .env and fill in values:
cp .env.example .env

# 2. Edit .env with your Sepolia RPC URL and funded private key

# 3. Run:
dart test --tags sepolia
```

### Manual Verification
- Verify registered schema UIDs on [Sepolia EASScan](https://sepolia.easscan.org)
- Verify timestamped UIDs on EASScan
- Confirm all transaction hashes are valid on Sepolia Etherscan

---

## Files Summary

| Action | Path |
|--------|------|
| **CREATE** | `lib/src/rpc/http_rpc_service.dart` |
| **CREATE** | `lib/src/rpc/rpc_helper.dart` |
| **MODIFY** | `lib/src/eas/schema_registry.dart` |
| **MODIFY** | `lib/src/eas/onchain_client.dart` |
| **MODIFY** | `lib/location_protocol.dart` |
| **CREATE** | `test/rpc/http_rpc_service_test.dart` |
| **CREATE** | `test/rpc/rpc_helper_test.dart` |
| **MODIFY** | `test/eas/schema_registry_test.dart` |
| **MODIFY** | `test/eas/onchain_client_test.dart` |
| **CREATE** | `test/test_helpers/dotenv_loader.dart` |
| **CREATE** | `test/integration/sepolia_onchain_test.dart` |
| **CREATE** | `.env.example` |
| **CREATE** | `.gitignore` |
| **CREATE** | `dart_test.yaml` |
