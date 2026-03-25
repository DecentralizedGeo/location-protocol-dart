# `location_protocol` Dart Library — Implementation Plan (Part 3 of 3)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Continues from** [Part 2](2025-03-12_phase1-project-init-part2.md) (Tasks 7–10: EAS constants, models, ABI encoder, offchain signer)

---

## Task 11: Chain Config

Known EAS and SchemaRegistry contract addresses per chain.

**Files:**
- Create: `lib/src/config/chain_config.dart`
- Test: `test/config/chain_config_test.dart`

### Step 1: Write the failing tests

Create `test/config/chain_config_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:location_protocol/src/config/chain_config.dart';

void main() {
  group('ChainConfig', () {
    test('has Sepolia config', () {
      final config = ChainConfig.forChainId(11155111);
      expect(config, isNotNull);
      expect(config!.eas, startsWith('0x'));
      expect(config.schemaRegistry, startsWith('0x'));
      expect(config.chainName, equals('Sepolia'));
    });

    test('has Ethereum Mainnet config', () {
      final config = ChainConfig.forChainId(1);
      expect(config, isNotNull);
      expect(config!.chainName, equals('Ethereum Mainnet'));
    });

    test('returns null for unknown chain', () {
      final config = ChainConfig.forChainId(999999);
      expect(config, isNull);
    });

    test('custom chain config can be created', () {
      final config = ChainAddresses(
        eas: '0xCustomEAS',
        schemaRegistry: '0xCustomRegistry',
        chainName: 'My Testnet',
      );
      expect(config.eas, equals('0xCustomEAS'));
      expect(config.chainName, equals('My Testnet'));
    });

    test('supportedChainIds returns known chain IDs', () {
      final ids = ChainConfig.supportedChainIds;
      expect(ids, contains(1));
      expect(ids, contains(11155111));
    });
  });
}
```

### Step 2: Run tests to verify they fail

```bash
dart test test/config/chain_config_test.dart
```

Expected: FAIL.

### Step 3: Write minimal implementation

Create `lib/src/config/chain_config.dart`:

```dart
/// Contract addresses for a specific EVM chain.
class ChainAddresses {
  /// The EAS contract address.
  final String eas;

  /// The SchemaRegistry contract address.
  final String schemaRegistry;

  /// Human-readable chain name.
  final String chainName;

  const ChainAddresses({
    required this.eas,
    required this.schemaRegistry,
    required this.chainName,
  });
}

/// Known EAS contract addresses per chain.
///
/// Reference: [EAS Deployments](https://docs.attest.org/doc/quick--start/contracts)
class ChainConfig {
  static const Map<int, ChainAddresses> _chains = {
    // Ethereum Mainnet
    1: ChainAddresses(
      eas: '0xA1207F3BBa224E2c9c3c6D5aF63D0eb1582Ce587',
      schemaRegistry: '0xA7b39296258348C78294F95B872b282326A97BDF',
      chainName: 'Ethereum Mainnet',
    ),
    // Sepolia Testnet
    11155111: ChainAddresses(
      eas: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      schemaRegistry: '0x0a7E2Ff54e76B8E6659aedc9103FB21c038050D0',
      chainName: 'Sepolia',
    ),
    // Base Mainnet
    8453: ChainAddresses(
      eas: '0x4200000000000000000000000000000000000021',
      schemaRegistry: '0x4200000000000000000000000000000000000020',
      chainName: 'Base',
    ),
    // Arbitrum One
    42161: ChainAddresses(
      eas: '0xbD75f629A22Dc1ceD33dDA0b68c546A1c035c458',
      schemaRegistry: '0xA310da9c5B885E7fb3fbA9D66E9Ba6Df512b78eB',
      chainName: 'Arbitrum One',
    ),
  };

  /// Get config for a chain ID, or null if unknown.
  static ChainAddresses? forChainId(int chainId) => _chains[chainId];

  /// All supported chain IDs.
  static List<int> get supportedChainIds => _chains.keys.toList();
}
```

### Step 4: Run tests to verify they pass

```bash
dart test test/config/chain_config_test.dart
```

Expected: All tests PASS.

### Step 5: Commit

```bash
git add lib/src/config/ test/config/
git commit -m "feat: add ChainConfig with EAS contract addresses"
```

---

## Task 12: Schema Registry Client

On-chain schema registration via JSON-RPC. Calls `SchemaRegistry.register()` and `SchemaRegistry.getSchema()`.

**Files:**
- Create: `lib/src/eas/schema_registry.dart`
- Test: `test/eas/schema_registry_test.dart`

> [!IMPORTANT]
> This task requires JSON-RPC calls to an Ethereum node. The tests for `register()` and `getSchema()` cannot run without a real RPC endpoint. For unit tests, we'll test the **transaction construction** (ABI encoding of the call data) and UID computation. The actual RPC calls should be tested in the integration test (Task 14) or manually against Sepolia.

### Step 1: Write the failing tests

Create `test/eas/schema_registry_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/schema_registry.dart';

void main() {
  group('SchemaRegistryClient', () {
    test('builds register call data as non-empty bytes', () {
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );

      final callData = SchemaRegistryClient.buildRegisterCallData(schema);
      expect(callData, isNotEmpty);
    });

    test('register call data starts with function selector', () {
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );

      final callData = SchemaRegistryClient.buildRegisterCallData(schema);
      // Function selector is first 4 bytes
      expect(callData.length, greaterThanOrEqualTo(4));
    });

    test('different schemas produce different call data', () {
      final schema1 = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );
      final schema2 = SchemaDefinition(
        fields: [SchemaField(type: 'string', name: 'memo')],
      );

      final data1 = SchemaRegistryClient.buildRegisterCallData(schema1);
      final data2 = SchemaRegistryClient.buildRegisterCallData(schema2);
      expect(data1, isNot(equals(data2)));
    });

    test('computeSchemaUID matches SchemaUID.compute', () {
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );

      final uid = SchemaRegistryClient.computeSchemaUID(schema);
      expect(uid, startsWith('0x'));
      expect(uid.length, equals(66));
    });
  });
}
```

### Step 2: Run tests to verify they fail

```bash
dart test test/eas/schema_registry_test.dart
```

Expected: FAIL.

### Step 3: Write minimal implementation

Create `lib/src/eas/schema_registry.dart`:

```dart
import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';

import '../schema/schema_definition.dart';
import '../schema/schema_uid.dart';
import '../config/chain_config.dart';

/// Client for interacting with the EAS SchemaRegistry contract.
///
/// Supports:
/// - Building `register(schema, resolver, revocable)` call data
/// - Computing schema UIDs locally
/// - Registering schemas on-chain (requires RPC)
/// - Querying existing schemas (requires RPC)
///
/// Reference: [schema-registration.md](https://github.com/DecentralizedGeo/eas-sandbox)
class SchemaRegistryClient {
  final String rpcUrl;
  final String privateKeyHex;
  final int chainId;
  final String? schemaRegistryAddress;

  SchemaRegistryClient({
    required this.rpcUrl,
    required this.privateKeyHex,
    required this.chainId,
    this.schemaRegistryAddress,
  });

  /// The SchemaRegistry contract address for this chain.
  String get contractAddress {
    if (schemaRegistryAddress != null) return schemaRegistryAddress!;
    final config = ChainConfig.forChainId(chainId);
    if (config == null) {
      throw StateError('No ChemaRegistry address for chainId $chainId. '
          'Provide one via schemaRegistryAddress parameter.');
    }
    return config.schemaRegistry;
  }

  /// Builds the ABI-encoded call data for `register(string,address,bool)`.
  ///
  /// This is a static method that doesn't require RPC — useful for
  /// pre-computing the transaction data.
  static Uint8List buildRegisterCallData(SchemaDefinition schema) {
    final schemaString = schema.toEASSchemaString();
    final resolver = schema.resolverAddress;
    final revocable = schema.revocable;

    // ABI encode: register(string schema, address resolver, bool revocable)
    // Function signature: register(string,address,bool)
    // Selector: first 4 bytes of keccak256("register(string,address,bool)")

    // Build using on_chain's ABI utilities
    final fragment = AbiFunctionFragment.fromJson({
      'name': 'register',
      'type': 'function',
      'stateMutability': 'nonpayable',
      'inputs': [
        {'name': 'schema', 'type': 'string'},
        {'name': 'resolver', 'type': 'address'},
        {'name': 'revocable', 'type': 'bool'},
      ],
      'outputs': [
        {'name': '', 'type': 'bytes32'},
      ],
    });

    final encoded = fragment.encode([schemaString, resolver, revocable]);
    return Uint8List.fromList(encoded);
  }

  /// Computes the schema UID locally (no RPC needed).
  static String computeSchemaUID(SchemaDefinition schema) {
    return SchemaUID.compute(schema);
  }

  /// Registers a schema on-chain.
  ///
  /// Sends a transaction to `SchemaRegistry.register()` and returns
  /// the transaction hash.
  ///
  /// Requires an RPC connection and a funded wallet.
  Future<String> register(SchemaDefinition schema) async {
    // Build and send the transaction using on_chain's RPC client
    // This will use EIP-1559 if supported by the chain
    throw UnimplementedError('TODO: implement with on_chain RPC');
  }

  /// Queries a schema by its UID from the SchemaRegistry.
  ///
  /// Returns the schema record or null if not found.
  Future<SchemaRecord?> getSchema(String uid) async {
    throw UnimplementedError('TODO: implement with on_chain RPC');
  }
}

/// A schema record from the SchemaRegistry contract.
class SchemaRecord {
  final String uid;
  final String resolver;
  final bool revocable;
  final String schema;

  const SchemaRecord({
    required this.uid,
    required this.resolver,
    required this.revocable,
    required this.schema,
  });
}
```

> [!NOTE]
> The `register()` and `getSchema()` methods have `UnimplementedError` placeholders. These require `on_chain`'s JSON-RPC client to build, sign, and send transactions. During implementation:
> 1. Use `on_chain`'s RPC provider to connect to the Ethereum node
> 2. Build an EIP-1559 (or legacy) transaction targeting the SchemaRegistry address
> 3. Set the `data` field to the output of `buildRegisterCallData()`
> 4. Sign and broadcast the transaction
> 5. Wait for the transaction receipt and extract the UID from the return value

### Step 4: Run tests to verify they pass

```bash
dart test test/eas/schema_registry_test.dart
```

Expected: All tests PASS (static methods only — RPC methods not tested here).

### Step 5: Commit

```bash
git add lib/src/eas/schema_registry.dart test/eas/schema_registry_test.dart
git commit -m "feat: add SchemaRegistryClient for schema registration"
```

---

## Task 13: Onchain Client

The high-level client for onchain EAS operations: `attest()` and `timestamp()`.

**Files:**
- Create: `lib/src/eas/onchain_client.dart`
- Test: `test/eas/onchain_client_test.dart`

> [!NOTE]
> Like the Schema Registry, onchain operations require RPC. Unit tests cover transaction construction; actual RPC calls are tested in integration tests or manually.

### Step 1: Write the failing tests

Create `test/eas/onchain_client_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';

void main() {
  group('EASClient', () {
    test('constructs with required parameters', () {
      final client = EASClient(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(client.chainId, equals(11155111));
    });

    test('resolves EAS address from ChainConfig', () {
      final client = EASClient(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(client.easAddress, startsWith('0x'));
    });

    test('accepts custom EAS address', () {
      final client = EASClient(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
        easAddress: '0xCustomEAS',
      );
      expect(client.easAddress, equals('0xCustomEAS'));
    });

    test('buildTimestampCallData produces non-empty bytes', () {
      final callData = EASClient.buildTimestampCallData(
        '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
      );
      expect(callData, isNotEmpty);
    });
  });
}
```

### Step 2: Run tests to verify they fail

```bash
dart test test/eas/onchain_client_test.dart
```

Expected: FAIL.

### Step 3: Write minimal implementation

Create `lib/src/eas/onchain_client.dart`:

```dart
import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';

import '../lp/lp_payload.dart';
import '../schema/schema_definition.dart';
import '../schema/schema_uid.dart';
import '../config/chain_config.dart';
import 'abi_encoder.dart';
import 'constants.dart';
import 'schema_registry.dart';

/// High-level client for onchain EAS operations.
///
/// Provides:
/// - [attest]: Submit an onchain attestation
/// - [timestamp]: Timestamp an offchain attestation UID onchain
/// - [registerSchema]: Register a schema (delegates to [SchemaRegistryClient])
class EASClient {
  final String rpcUrl;
  final String privateKeyHex;
  final int chainId;
  final String? _easAddress;

  EASClient({
    required this.rpcUrl,
    required this.privateKeyHex,
    required this.chainId,
    String? easAddress,
  }) : _easAddress = easAddress;

  /// The EAS contract address for this chain.
  String get easAddress {
    if (_easAddress != null) return _easAddress!;
    final config = ChainConfig.forChainId(chainId);
    if (config == null) {
      throw StateError('No EAS address for chainId $chainId. '
          'Provide one via easAddress parameter.');
    }
    return config.eas;
  }

  /// Builds ABI-encoded call data for `EAS.timestamp(bytes32)`.
  static Uint8List buildTimestampCallData(String uid) {
    final fragment = AbiFunctionFragment.fromJson({
      'name': 'timestamp',
      'type': 'function',
      'stateMutability': 'nonpayable',
      'inputs': [
        {'name': 'data', 'type': 'bytes32'},
      ],
      'outputs': [
        {'name': '', 'type': 'uint64'},
      ],
    });

    return Uint8List.fromList(fragment.encode([uid]));
  }

  /// Submit an onchain attestation.
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
    throw UnimplementedError('TODO: implement with on_chain RPC');
  }

  /// Timestamp an offchain attestation UID onchain.
  ///
  /// Records a timestamp on the EAS contract proving the UID existed
  /// at a specific block time.
  Future<String> timestamp(String offchainUID) async {
    throw UnimplementedError('TODO: implement with on_chain RPC');
  }

  /// Register a schema on-chain. Convenience wrapper around [SchemaRegistryClient].
  Future<String> registerSchema(SchemaDefinition schema) async {
    final registry = SchemaRegistryClient(
      rpcUrl: rpcUrl,
      privateKeyHex: privateKeyHex,
      chainId: chainId,
    );
    return registry.register(schema);
  }
}
```

### Step 4: Run tests to verify they pass

```bash
dart test test/eas/onchain_client_test.dart
```

Expected: All tests PASS (construction + static methods only).

### Step 5: Commit

```bash
git add lib/src/eas/onchain_client.dart test/eas/onchain_client_test.dart
git commit -m "feat: add EASClient for onchain attestation and timestamping"
```

---

## Task 14: Integration Test — Full Offline Workflow

End-to-end test of the offline signing + verification workflow. This proves the entire pipeline works together without any RPC.

**Files:**
- Test: `test/integration/full_workflow_test.dart`

### Step 1: Write the integration test

Create `test/integration/full_workflow_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/lp/location_serializer.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/schema/schema_uid.dart';
import 'package:location_protocol/src/eas/offchain_signer.dart';

void main() {
  // Well-known test key — Hardhat account #0
  const testKey =
      'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  group('Full Offline Workflow', () {
    test('define schema → create payload → sign → verify', () async {
      // Step 1: Define business schema
      final schema = SchemaDefinition(
        fields: [
          SchemaField(type: 'uint256', name: 'timestamp'),
          SchemaField(type: 'string', name: 'surveyor_id'),
          SchemaField(type: 'string', name: 'memo'),
        ],
      );

      // Verify schema string includes LP fields
      final schemaString = schema.toEASSchemaString();
      expect(schemaString, startsWith('string lp_version,string srs'));
      expect(schemaString, contains('uint256 timestamp'));

      // Verify schema UID is deterministic
      final uid1 = SchemaUID.compute(schema);
      final uid2 = SchemaUID.compute(schema);
      expect(uid1, equals(uid2));

      // Step 2: Create LP payload with Map location
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {
          'type': 'Point',
          'coordinates': [-103.771556, 44.967243],
        },
      );

      // Verify serialization works
      final serialized = LocationSerializer.serialize(lpPayload.location);
      expect(serialized, contains('"type":"Point"'));

      // Step 3: Sign offchain attestation
      final signer = OffchainSigner(
        privateKeyHex: testKey,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );

      final signed = await signer.signOffchainAttestation(
        schema: schema,
        lpPayload: lpPayload,
        userData: {
          'timestamp': BigInt.from(1710000000),
          'surveyor_id': 'surveyor-42',
          'memo': 'Boundary marker GPS reading',
        },
      );

      // Verify signed attestation structure
      expect(signed.uid, startsWith('0x'));
      expect(signed.uid.length, equals(66));
      expect(signed.version, equals(2));
      expect(signed.salt, startsWith('0x'));
      expect(signed.signature.v, anyOf(equals(27), equals(28)));
      expect(signed.signer, startsWith('0x'));
      expect(signed.signer.length, equals(42));

      // Step 4: Verify the attestation
      final verification = signer.verifyOffchainAttestation(signed);
      expect(verification.isValid, isTrue);
      expect(
        verification.recoveredAddress.toLowerCase(),
        equals(signed.signer.toLowerCase()),
      );
    });

    test('different locations produce different attestation UIDs', () async {
      final schema = SchemaDefinition(fields: []);

      final signer = OffchainSigner(
        privateKeyHex: testKey,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );

      final payload1 = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {'type': 'Point', 'coordinates': [-103.77, 44.96]},
      );

      final payload2 = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {'type': 'Point', 'coordinates': [-73.93, 40.73]},
      );

      final signed1 = await signer.signOffchainAttestation(
        schema: schema,
        lpPayload: payload1,
        userData: {},
      );
      final signed2 = await signer.signOffchainAttestation(
        schema: schema,
        lpPayload: payload2,
        userData: {},
      );

      // Different data → different UIDs (even ignoring salt)
      expect(signed1.data, isNot(equals(signed2.data)));
    });

    test('LP-only schema works (no user fields)', () async {
      final schema = SchemaDefinition(fields: []);

      expect(
        schema.toEASSchemaString(),
        equals('string lp_version,string srs,string location_type,string location'),
      );

      final signer = OffchainSigner(
        privateKeyHex: testKey,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );

      final signed = await signer.signOffchainAttestation(
        schema: schema,
        lpPayload: LPPayload(
          lpVersion: '1.0.0',
          srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
          locationType: 'h3',
          location: '8928308280fffff',
        ),
        userData: {},
      );

      final result = signer.verifyOffchainAttestation(signed);
      expect(result.isValid, isTrue);
    });
  });
}
```

### Step 2: Run the integration test

```bash
dart test test/integration/full_workflow_test.dart
```

Expected: All tests PASS.

### Step 3: Commit

```bash
git add test/integration/
git commit -m "test: add full offline workflow integration test"
```

---

## Task 15: Finalize Barrel Export

Uncomment all exports in the barrel export file now that all source files exist.

**Files:**
- Modify: `lib/location_protocol.dart`

### Step 1: Update barrel export

Update `lib/location_protocol.dart` to uncomment all exports (they were commented out in Task 1):

```dart
/// Schema-agnostic Dart library implementing the Location Protocol
/// base data model on the Ethereum Attestation Service (EAS).
library location_protocol;

// LP layer
export 'src/lp/lp_payload.dart';
export 'src/lp/lp_version.dart';
export 'src/lp/location_serializer.dart';

// Schema layer
export 'src/schema/schema_field.dart';
export 'src/schema/schema_definition.dart';
export 'src/schema/schema_uid.dart';

// EAS layer
export 'src/eas/constants.dart';
export 'src/eas/abi_encoder.dart';
export 'src/eas/offchain_signer.dart';
export 'src/eas/onchain_client.dart';
export 'src/eas/schema_registry.dart';

// Config
export 'src/config/chain_config.dart';

// Models
export 'src/models/attestation.dart';
export 'src/models/signature.dart';
export 'src/models/verification_result.dart';
```

### Step 2: Verify analysis passes

```bash
dart analyze
```

Expected: No errors.

### Step 3: Run all tests

```bash
dart test
```

Expected: All tests PASS.

### Step 4: Commit

```bash
git add lib/location_protocol.dart
git commit -m "chore: finalize barrel export with all components"
```

---

## Task 16: README

Create a comprehensive README with installation, usage examples, and API overview.

**Files:**
- Create: `README.md`

### Step 1: Write README

Create `README.md`:

````markdown
# location_protocol

Schema-agnostic Dart library implementing the [Location Protocol](https://spec.decentralizedgeo.org/specification/data-model/) base data model on the [Ethereum Attestation Service](https://docs.attest.org/) (EAS).

## Features

- **Schema-agnostic** — Define your own business schemas; LP base fields are auto-prepended
- **Offchain signing** — EIP-712 typed data signing (no network needed)
- **Offchain verification** — Signature recovery + UID recomputation
- **Schema management** — Define schemas, compute UIDs locally, register on-chain
- **Onchain attestation** — Submit attestations via `EAS.attest()`
- **Onchain timestamping** — Timestamp offchain UIDs via `EAS.timestamp()`
- **Pure Dart** — No Flutter dependency. Works in CLI, servers, and Flutter apps
- **LP-compliant by construction** — Base fields are always included and validated

## Installation

```yaml
dependencies:
  location_protocol: ^0.1.0
```

## Quick Start

```dart
import 'package:location_protocol/location_protocol.dart';

// 1. Define your business schema (LP fields auto-prepended)
final schema = SchemaDefinition(
  fields: [
    SchemaField(type: 'uint256', name: 'timestamp'),
    SchemaField(type: 'string', name: 'surveyor_id'),
    SchemaField(type: 'string', name: 'memo'),
  ],
);

// 2. Create an LP-compliant payload
final lpPayload = LPPayload(
  lpVersion: '1.0.0',
  srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
  locationType: 'geojson-point',
  location: {'type': 'Point', 'coordinates': [-103.771556, 44.967243]},
);

// 3. Sign offchain (no network needed)
final signer = OffchainSigner(
  privateKeyHex: yourPrivateKey,
  chainId: 11155111,
  easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
);

final signed = await signer.signOffchainAttestation(
  schema: schema,
  lpPayload: lpPayload,
  userData: {
    'timestamp': BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    'surveyor_id': 'surveyor-42',
    'memo': 'Boundary marker GPS reading',
  },
);

// 4. Verify locally
final verification = signer.verifyOffchainAttestation(signed);
assert(verification.isValid);

// 5. When online — register schema + timestamp
final client = EASClient(
  rpcUrl: 'https://rpc.sepolia.org',
  privateKeyHex: yourPrivateKey,
  chainId: 11155111,
);
await client.registerSchema(schema);
await client.timestamp(signed.uid);
```

## Schema Composition

You define only your business fields. The library auto-prepends the LP base fields:

```
string lp_version, string srs, string location_type, string location, [your fields]
```

This ensures every attestation is LP-compliant by construction.

## Supported Location Types

The `location` field accepts flexible Dart types:

| Location Type | Dart Type | Example |
|---|---|---|
| `geojson-point` | `Map<String, dynamic>` | `{'type': 'Point', 'coordinates': [-103.77, 44.96]}` |
| `coordinate-decimal+lon-lat` | `List<num>` | `[-103.77, 44.96]` |
| `h3` | `String` | `'8928308280fffff'` |
| `geohash` | `String` | `'9xj64'` |
| `wkt` | `String` | `'POINT(-103.77 44.96)'` |
| `address` | `String` | `'123 Main St, Anytown'` |

## License

MIT
````

### Step 2: Commit

```bash
git add README.md
git commit -m "docs: add README with installation, usage, and API overview"
```

---

## Part 3 Summary

After completing Tasks 11–16, you have:

| Component | File | Tests |
|---|---|---|
| Chain Config | `lib/src/config/chain_config.dart` | `test/config/chain_config_test.dart` |
| Schema Registry | `lib/src/eas/schema_registry.dart` | `test/eas/schema_registry_test.dart` |
| Onchain Client | `lib/src/eas/onchain_client.dart` | `test/eas/onchain_client_test.dart` |
| Integration Test | — | `test/integration/full_workflow_test.dart` |
| Barrel Export | `lib/location_protocol.dart` | `dart analyze` |
| README | `README.md` | — |

---

## Full Implementation Checklist

| # | Component | Status |
|---|---|---|
| 1 | Project scaffold | ⬜ |
| 2 | LP Payload + validation | ⬜ |
| 3 | Location Serializer | ⬜ |
| 4 | Schema Field | ⬜ |
| 5 | Schema Definition (auto-prepend, conflicts) | ⬜ |
| 6 | Schema UID computation | ⬜ |
| 7 | EAS Protocol Constants | ⬜ |
| 8 | Attestation Data Models | ⬜ |
| 9 | ABI Encoder | ⬜ |
| 10 | Offchain Signer (EIP-712 + verify) | ⬜ |
| 11 | Chain Config | ⬜ |
| 12 | Schema Registry Client | ⬜ |
| 13 | Onchain Client (attest + timestamp) | ⬜ |
| 14 | Integration Test | ⬜ |
| 15 | Barrel Export finalization | ⬜ |
| 16 | README | ⬜ |
