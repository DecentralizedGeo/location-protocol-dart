# Phase 3: Codebase Review Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor the Location Protocol Dart library to prioritize readability and maintainability. We will consolidate duplicative logic and introduce a strict Dependency Injection pattern for the RPC transport layer to make testing and maintenance easier.

**Architecture:** 
- **Utilities:** Extract shared hex string stripping and standard byte conversions into a dedicated `HexUtils` and `ByteUtils` so the intent of the code is immediately obvious (`"0x123".toBytes()`).
- **ABIs:** Consolidate inline `AbiFunctionFragment` JSONs into a static `EASAbis` registry.
- **RPC Abstraction:** Extract an `RpcProvider` interface. Rename `RpcHelper` to `DefaultRpcProvider`. Clients (`EASClient`, `SchemaRegistryClient`) will NO LONGER take `rpcUrl` or `privateKey` in their constructors. They will strictly require an `RpcProvider` instance.
- **Testing Payoff:** Create a `FakeRpcProvider` to write pure, instant, offline unit tests for the clients.

**Tech Stack:** Dart, `on_chain`, `blockchain_utils`

---

### Task 1: Create Shared Byte and Hex Utilities

**Files:**
- Create: `lib/src/utils/hex_utils.dart`
- Create: `lib/src/utils/byte_utils.dart`
- Create: `test/utils/hex_utils_test.dart`
- Create: `test/utils/byte_utils_test.dart`

**Step 1: Write the failing tests**

```dart
// test/utils/hex_utils_test.dart
import 'package:test/test.dart';
import '../../lib/src/utils/hex_utils.dart';

void main() {
  group('HexStringX', () {
    test('strip0x removes 0x prefix', () {
      expect('0x123abc'.strip0x, '123abc');
      expect('123abc'.strip0x, '123abc');
    });

    test('toBytes converts hex to Uint8List correctly', () {
      final bytes = '0x0102'.toBytes();
      expect(bytes, [1, 2]);
    });
  });
}
```

```dart
// test/utils/byte_utils_test.dart
import 'package:test/test.dart';
import '../../lib/src/utils/byte_utils.dart';

void main() {
  group('ByteUtils', () {
    test('uint16ToBytes pads to 2 bytes', () {
      expect(ByteUtils.uint16ToBytes(2), [0, 2]);
    });

    test('uint64ToBytes pads to 8 bytes', () {
      expect(ByteUtils.uint64ToBytes(BigInt.from(257)), [0, 0, 0, 0, 0, 0, 1, 1]);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/utils/hex_utils_test.dart`
Run: `dart test test/utils/byte_utils_test.dart`
Expected: FAIL due to missing files/classes.

**Step 3: Write minimal implementation**

```dart
// lib/src/utils/hex_utils.dart
import 'dart:typed_data';
import 'package:blockchain_utils/blockchain_utils.dart';

/// Extension methods for making hex string manipulation more readable.
extension HexStringX on String {
  /// Removes the '0x' prefix if present. Returns the original string otherwise.
  String get strip0x => startsWith('0x') ? substring(2) : this;

  /// Safely converts a hex string (with or without '0x') to a Uint8List.
  Uint8List toBytes() {
    return Uint8List.fromList(BytesUtils.fromHexString(strip0x));
  }
}
```

```dart
// lib/src/utils/byte_utils.dart
import 'dart:typed_data';

/// Explicit utility class for explicit endian-aware byte conversions.
class ByteUtils {
  /// Converts an integer to a 2-byte big-endian array.
  static List<int> uint16ToBytes(int value) {
    final b = ByteData(2);
    b.setUint16(0, value, Endian.big);
    return b.buffer.asUint8List();
  }

  /// Converts a BigInt to an 8-byte big-endian array.
  static List<int> uint64ToBytes(BigInt value) {
    final b = ByteData(8);
    // Use toUnsigned(64) to handle potential signed representation quirks
    b.setUint64(0, value.toUnsigned(64).toInt(), Endian.big);
    return b.buffer.asUint8List();
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/utils/hex_utils_test.dart`
Run: `dart test test/utils/byte_utils_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add test/utils/ lib/src/utils/
git commit -m "refactor: add explicit HexUtils and ByteUtils for readability"
```

---

### Task 2: Simplify Constants & AbiEncoder

**Files:**
- Modify: `lib/src/eas/constants.dart`
- Modify: `test/eas/constants_test.dart`
- Modify: `lib/src/eas/abi_encoder.dart`

**Step 1: Write/Verify the failing test**

Ensure `test/eas/constants_test.dart` exists and tests `saltToHex`. Ensure `test/eas/abi_encoder_test.dart` exists and passes before refactoring.
Run: `dart test test/eas/constants_test.dart test/eas/abi_encoder_test.dart`

**Step 2: Write minimal implementation**

```dart
// In lib/src/eas/constants.dart
import 'dart:math';
import 'dart:typed_data';
import 'package:blockchain_utils/blockchain_utils.dart';

class EASConstants {
  static const String zeroAddress = '0x0000000000000000000000000000000000000000';
  static const String zeroBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';
  static const int saltSize = 32;
  static const int attestationVersion = 2;
  static const String eip712DomainName = 'EAS Attestation';

  static Uint8List generateSalt() {
    final random = Random.secure();
    final salt = Uint8List(saltSize);
    for (var i = 0; i < saltSize; i++) {
      salt[i] = random.nextInt(256);
    }
    return salt;
  }

  static String saltToHex(Uint8List salt) {
    return BytesUtils.toHexString(salt, prefix: '0x');
  }
}
```

In `lib/src/eas/abi_encoder.dart`:
Refactor it to utilize our new `HexUtils` to robustly preprocess user arguments. Often, users will pass a hex string for `bytes32` or `bytes` fields. We should intercept these and convert them to `Uint8List` using `.toBytes()` before passing them to the `on_chain` tuple coder.

```dart
// lib/src/eas/abi_encoder.dart
// ...
import '../utils/hex_utils.dart';
// ...

    // Append user field values in schema declaration order
    for (final field in schema.fields) {
      dynamic value = userData[field.name];
      
      // HexUtils: Robust conversion for bytes/bytes32 fields passed as hex strings
      if ((field.type.startsWith('bytes') || field.type.startsWith('uint256')) && value is String && value.startsWith('0x')) {
        // NOTE: if it's uint256, blockchain_utils might want BigInt instead of bytes, 
        // string hex parsing for bytes is strictly using toBytes()
        if (field.type.startsWith('bytes')) {
          value = value.toBytes();
        }
      }
      
      values.add(value);
    }
// ...
```

---

### Task 3: Extract ABI Fragments to a Registry

**Files:**
- Create: `lib/src/eas/eas_abis.dart`

**Step 1: Extract ABIs (Readability Refactor)**

```dart
// lib/src/eas/eas_abis.dart
import 'package:on_chain/on_chain.dart';

/// Central registry of ABI function fragments used by the Location Protocol.
class EASAbis {
  static final AbiFunctionFragment timestamp = AbiFunctionFragment.fromJson({
    'name': 'timestamp',
    'type': 'function',
    'stateMutability': 'nonpayable',
    'inputs': [{'name': 'data', 'type': 'bytes32'}],
    'outputs': [{'name': '', 'type': 'uint64'}],
  });

  static final AbiFunctionFragment attest = AbiFunctionFragment.fromJson({
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
    'outputs': [{'name': '', 'type': 'bytes32'}],
  });

  static final AbiFunctionFragment getAttestation = AbiFunctionFragment.fromJson({
    'name': 'getAttestation',
    'type': 'function',
    'stateMutability': 'view',
    'inputs': [{'name': 'uid', 'type': 'bytes32'}],
    'outputs': [
      {
        'name': '',
        'type': 'tuple',
        'components': [
          {'name': 'uid', 'type': 'bytes32'},
          {'name': 'schema', 'type': 'bytes32'},
          {'name': 'time', 'type': 'uint64'},
          {'name': 'expirationTime', 'type': 'uint64'},
          {'name': 'revocationTime', 'type': 'uint64'},
          {'name': 'refUID', 'type': 'bytes32'},
          {'name': 'recipient', 'type': 'address'},
          {'name': 'attester', 'type': 'address'},
          {'name': 'revocable', 'type': 'bool'},
          {'name': 'data', 'type': 'bytes'},
        ],
      },
    ],
  });

  static final AbiFunctionFragment registerSchema = AbiFunctionFragment.fromJson({
    'name': 'register',
    'type': 'function',
    'stateMutability': 'nonpayable',
    'inputs': [
      {'name': 'schema', 'type': 'string'},
      {'name': 'resolver', 'type': 'address'},
      {'name': 'revocable', 'type': 'bool'},
    ],
    'outputs': [{'name': '', 'type': 'bytes32'}],
  });

  static final AbiFunctionFragment getSchema = AbiFunctionFragment.fromJson({
    'name': 'getSchema',
    'type': 'function',
    'stateMutability': 'view',
    'inputs': [{'name': 'uid', 'type': 'bytes32'}],
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
}
```

**Step 2: Commit**

```bash
git add lib/src/eas/eas_abis.dart
git commit -m "refactor: extract ABI fragments to EASAbis for cleaner client code"
```

---

### Task 4: Introduce the RpcProvider Interface

**Files:**
- Create: `lib/src/rpc/rpc_provider.dart`
- Rename & Modify: `lib/src/rpc/rpc_helper.dart` -> `lib/src/rpc/default_rpc_provider.dart`
- Rename & Modify: `test/rpc/rpc_helper_test.dart` -> `test/rpc/default_rpc_provider_test.dart`

**Step 1: Write the failing test**

```bash
mv lib/src/rpc/rpc_helper.dart lib/src/rpc/default_rpc_provider.dart
mv test/rpc/rpc_helper_test.dart test/rpc/default_rpc_provider_test.dart
```

In `test/rpc/default_rpc_provider_test.dart`, replace all imports/references of `RpcHelper` with `DefaultRpcProvider`. Include a test verifying it implements `RpcProvider`.

```dart
// test/rpc/default_rpc_provider_test.dart
import 'package:test/test.dart';
import 'package:location_protocol/src/rpc/default_rpc_provider.dart';
import 'package:location_protocol/src/rpc/rpc_provider.dart';

// ... update existing test file, ensuring it expects `DefaultRpcProvider is RpcProvider`
```

**Step 2: Write minimal implementation**

```dart
// lib/src/rpc/rpc_provider.dart
import 'dart:typed_data';
import 'package:on_chain/on_chain.dart';

/// Abstract interface for on-chain state queries and transaction submission.
abstract class RpcProvider {
  /// The Ethereum address of the configured signer.
  String get signerAddress;

  /// The Chain ID the provider is connected to.
  int get chainId;

  /// Sends a signed transaction to the given contract address.
  Future<String> sendTransaction({
    required String to,
    required Uint8List data,
    BigInt? value,
  });

  /// Executes a read-only `eth_call` against a contract.
  Future<List<dynamic>> callContract({
    required String contractAddress,
    required AbiFunctionFragment function,
    List<dynamic> params = const [],
  });
  
  /// Closes underlying resources.
  void close();
}
```

```dart
// lib/src/rpc/default_rpc_provider.dart
import 'dart:typed_data';
import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'http_rpc_service.dart';
import 'rpc_provider.dart';

/// Standard implementation of RpcProvider using on_chain and HttpRpcService.
class DefaultRpcProvider implements RpcProvider {
  final String rpcUrl;
  @override
  final int chainId;

  late final ETHPrivateKey _privateKey;
  late final EthereumProvider _provider;
  late final HttpRpcService _service;

  DefaultRpcProvider({
    required this.rpcUrl,
    required String privateKeyHex,
    required this.chainId,
  }) {
    _privateKey = ETHPrivateKey(privateKeyHex);
    _service = HttpRpcService(rpcUrl);
    _provider = EthereumProvider(_service);
  }

  @override
  String get signerAddress => _privateKey.publicKey().toAddress().address;

  // Keep existing sendTransaction implementation...
  // Keep existing callContract implementation...
  // Keep existing close implementation...
}
```

**Step 3: Run test to verify it passes**

Run: `dart test test/rpc/default_rpc_provider_test.dart`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/src/rpc/ test/rpc/
git commit -m "refactor: extract RpcProvider interface and rename RpcHelper"
```

---

### Task 5: Move Tuple Decoding to Domain Models

**Files:**
- Modify: `lib/src/models/attestation.dart`
- Modify: `lib/src/eas/schema_registry.dart` (SchemaRecord)

**Step 1: Write explicit factories**

```dart
// Inside lib/src/models/attestation.dart
import 'dart:typed_data';
import 'package:blockchain_utils/blockchain_utils.dart';

class Attestation {
  // existing fields...

  // Create the factory:
  factory Attestation.fromTuple(List<dynamic> decoded) {
    final recordUid = decoded[0];
    final schema = decoded[1];
    final time = decoded[2];
    final expirationTime = decoded[3];
    final revocationTime = decoded[4];
    final refUID = decoded[5];
    final data = decoded[9];

    return Attestation(
      uid: recordUid is List<int> ? BytesUtils.toHexString(recordUid, prefix: '0x') : recordUid.toString(),
      schema: schema is List<int> ? BytesUtils.toHexString(schema, prefix: '0x') : schema.toString(),
      time: time is BigInt ? time : BigInt.from(time),
      expirationTime: expirationTime is BigInt ? expirationTime : BigInt.from(expirationTime),
      revocationTime: revocationTime is BigInt ? revocationTime : BigInt.from(revocationTime),
      refUID: refUID is List<int> ? BytesUtils.toHexString(refUID, prefix: '0x') : refUID.toString(),
      recipient: decoded[6].toString(),
      attester: decoded[7].toString(),
      revocable: decoded[8] as bool,
      data: data is List<int> ? Uint8List.fromList(data) : data as Uint8List,
    );
  }
}
```

```dart
// Inside lib/src/eas/schema_registry.dart (or moved to separate file if desired)
import 'package:blockchain_utils/blockchain_utils.dart';

// In SchemaRecord class:
  factory SchemaRecord.fromTuple(List<dynamic> decoded) {
    final recordUid = decoded[0];
    final uidHex = recordUid is List<int>
        ? BytesUtils.toHexString(recordUid, prefix: '0x')
        : recordUid.toString();

    return SchemaRecord(
      uid: uidHex,
      resolver: decoded[1].toString(),
      revocable: decoded[2] as bool,
      schema: decoded[3].toString(),
    );
  }
```

**Step 2: Commit**
```bash
git add lib/src/models/attestation.dart lib/src/eas/schema_registry.dart
git commit -m "refactor: encapsulate tuple parsing inside domain model factories"
```

---

### Task 6: Refactor Clients with Strict DI

**REQUIRED:** `EASClient` and `SchemaRegistryClient` must no longer accept raw connection strings in their constructor. Make `provider` a required named parameter. Update `test/eas/` scripts to instantiate a `DefaultRpcProvider` to pass in.

**Files:**
- Modify: `lib/src/eas/onchain_client.dart`
- Modify: `lib/src/eas/schema_registry.dart`
- Modify: `lib/src/eas/offchain_signer.dart`

**Step 1: Rewrite SchemaRegistryClient**

```dart
// In lib/src/eas/schema_registry.dart
import '../rpc/rpc_provider.dart';
import '../utils/hex_utils.dart';
import 'eas_abis.dart';
import 'constants.dart';

class SchemaRegistryClient {
  final RpcProvider provider;
  final String? schemaRegistryAddress;

  SchemaRegistryClient({
    required this.provider,
    this.schemaRegistryAddress,
  });

  String get contractAddress {
    if (schemaRegistryAddress != null) return schemaRegistryAddress!;
    final config = ChainConfig.forChainId(provider.chainId);
    if (config == null) throw StateError('No SchemaRegistry address for chainId ${provider.chainId}.');
    return config.schemaRegistry;
  }

  static Uint8List buildRegisterCallData(SchemaDefinition schema) {
    final encoded = EASAbis.registerSchema.encode([
      schema.toEASSchemaString(), 
      schema.resolverAddress, 
      schema.revocable
    ]);
    return Uint8List.fromList(encoded);
  }

  Future<String> register(SchemaDefinition schema) async {
    final callData = buildRegisterCallData(schema);
    return await provider.sendTransaction(
      to: contractAddress,
      data: callData,
    );
  }

  Future<SchemaRecord?> getSchema(String uid) async {
    final result = await provider.callContract(
      contractAddress: contractAddress,
      function: EASAbis.getSchema,
      params: [uid.toBytes()],
    );

    if (result.isEmpty || result[0] is! List || (result[0] as List).length < 4) return null;
    
    final record = SchemaRecord.fromTuple(result[0] as List<dynamic>);
    if (record.uid == EASConstants.zeroBytes32) return null;
    return record;
  }
}
```

**Step 2: Rewrite EASClient**

```dart
// In lib/src/eas/onchain_client.dart
import '../rpc/rpc_provider.dart';
import '../utils/hex_utils.dart';
import 'eas_abis.dart';

class EASClient {
  final RpcProvider provider;
  final String? _easAddress;

  EASClient({
    required this.provider,
    String? easAddress,
  }) : _easAddress = easAddress;

  String get easAddress {
    if (_easAddress != null) return _easAddress!;
    final config = ChainConfig.forChainId(provider.chainId);
    if (config == null) throw StateError('No EAS address for chainId ${provider.chainId}.');
    return config.eas;
  }

  static Uint8List buildTimestampCallData(String uid) {
    return Uint8List.fromList(EASAbis.timestamp.encode([uid.toBytes()]));
  }

  static Uint8List buildAttestCallData({
    required SchemaDefinition schema,
    required LPPayload lpPayload,
    required Map<String, dynamic> userData,
    String recipient = EASConstants.zeroAddress,
    BigInt? expirationTime,
    String? refUID,
  }) {
    final schemaUID = SchemaUID.compute(schema);
    final encodedData = AbiEncoder.encode(
      schema: schema, lpPayload: lpPayload, userData: userData,
    );
    
    final ref = refUID ?? EASConstants.zeroBytes32;
    final encoded = EASAbis.attest.encode([
      [
        schemaUID.toBytes(),
        [
          recipient,
          expirationTime ?? BigInt.zero,
          schema.revocable,
          (ref is String) ? ref.toBytes() : ref,
          encodedData,
          BigInt.zero,
        ]
      ]
    ]);
    return Uint8List.fromList(encoded);
  }

  Future<String> attest({
    required SchemaDefinition schema,
    required LPPayload lpPayload,
    required Map<String, dynamic> userData,
    String recipient = EASConstants.zeroAddress,
    BigInt? expirationTime,
    String? refUID,
  }) async {
    final callData = buildAttestCallData(
      schema: schema, lpPayload: lpPayload, userData: userData,
      recipient: recipient, expirationTime: expirationTime, refUID: refUID,
    );
    return await provider.sendTransaction(to: easAddress, data: callData);
  }

  Future<String> timestamp(String offchainUID) async {
    final callData = buildTimestampCallData(offchainUID);
    return await provider.sendTransaction(to: easAddress, data: callData);
  }

  Future<Attestation?> getAttestation(String uid) async {
    final result = await provider.callContract(
      contractAddress: easAddress,
      function: EASAbis.getAttestation,
      params: [uid.toBytes()],
    );

    if (result.isEmpty || result[0] is! List || (result[0] as List).length < 10) return null;
    
    final attestation = Attestation.fromTuple(result[0] as List<dynamic>);
    if (attestation.uid == EASConstants.zeroBytes32) return null;
    return attestation;
  }

  Future<String> registerSchema(SchemaDefinition schema) async {
    final registry = SchemaRegistryClient(provider: provider);
    return registry.register(schema);
  }
}
```

**Step 3: Fix OffchainSigner**
In `lib/src/eas/offchain_signer.dart`:
1. Replace internal `_uint16ToBytes` and `_uint64ToBytes` with `ByteUtils.uint16ToBytes` and `ByteUtils.uint64ToBytes`.
2. Replace `BytesUtils.fromHexString(X.replaceAll('0x', ''))` with `X.toBytes()`. (Don't forget to import `hex_utils.dart` and `byte_utils.dart`)

**Step 4: Fix Tests**

Update all tests in `test/eas/` and `test/integration/` that previously did `EASClient(rpcUrl: ..., privateKeyHex: ...)` to instead do:
```dart
final provider = DefaultRpcProvider(rpcUrl: ..., privateKeyHex: ..., chainId: ...);
final client = EASClient(provider: provider);
```

**Step 5: Run tests**
Run: `dart run test`
Expected: 100% pass.

**Step 6: Commit**
```bash
git add lib/src/eas/ test/eas/ test/integration/
git commit -m "refactor: implement strict RpcProvider DI for all clients"
```

---

### Task 7: The Payoff Unit Test (FakeRpcProvider)

To prove our DI architecture is valuable, we write a pure, instant unit test without an `.env` file or network access.

**Files:**
- Create: `test/rpc/fake_rpc_provider.dart`
- Create: `test/eas/eas_client_offline_test.dart`

**Step 1: Create the Fake Provider**

```dart
// test/rpc/fake_rpc_provider.dart
import 'dart:typed_data';
import 'package:on_chain/on_chain.dart';
import 'package:location_protocol/src/rpc/rpc_provider.dart';

class FakeRpcProvider implements RpcProvider {
  final Map<String, List<dynamic>> contractCallMocks = {};
  String? lastTransactionTo;
  Uint8List? lastTransactionData;

  @override
  String get signerAddress => '0xFakeSignerAddress';

  @override
  int get chainId => 11155111;

  @override
  Future<String> sendTransaction({
    required String to,
    required Uint8List data,
    BigInt? value,
  }) async {
    lastTransactionTo = to;
    lastTransactionData = data;
    return '0xFakeTxHash';
  }

  @override
  Future<List<dynamic>> callContract({
    required String contractAddress,
    required AbiFunctionFragment function,
    List<dynamic> params = const [],
  }) async {
    final key = function.name;
    return contractCallMocks[key] ?? [];
  }

  @override
  void close() {}
}
```

**Step 2: Write the Offline Test**

```dart
// test/eas/eas_client_offline_test.dart
import 'package:test/test.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';
import '../rpc/fake_rpc_provider.dart';

void main() {
  test('EASClient handles missing attestation purely offline', () async {
    final fakeProvider = FakeRpcProvider();
    
    // Mock the raw tuple response for "not found"
    fakeProvider.contractCallMocks['getAttestation'] = [
      [
        // Return 0x000.. for the UID element to simulate missing record
        '0x0000000000000000000000000000000000000000000000000000000000000000',
        '0x0', BigInt.zero, BigInt.zero, BigInt.zero, '0x0', '0x0', '0x0', false, []
      ]
    ];

    final client = EASClient(provider: fakeProvider);
    
    final result = await client.getAttestation('0xAnyUidWillHitTheMock');
    expect(result, isNull);
  });
}
```

**Step 3: Run test**
Run: `dart test test/eas/eas_client_offline_test.dart`
Expected: PASS (instantly)

**Step 4: Commit**
```bash
git add test/rpc/fake_rpc_provider.dart test/eas/eas_client_offline_test.dart
git commit -m "test: prove offline testability using FakeRpcProvider"
```

---

### Task 8: Quality and Verification

**Step 1: Complete Suite Run**
Run: `dart run test`
Expected: Pristine output.

**Step 2: Static Analysis**
Run: `dart analyze`
Expected: Clean of warnings.

**Step 3: Update Agent Memory**
Run the superpower skill for `agent-memory`.
Document the transition towards highly readable, interface-driven `RpcProvider`, the consolidation of boilerplate via `<String>.toBytes()`, and `ByteUtils`.

**Step 4: Create Walkthrough**
Create a `doc/walkthrough.md` visually documenting the structural clarity gained in Phase 3.
