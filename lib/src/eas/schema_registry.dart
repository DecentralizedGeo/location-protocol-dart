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
      throw StateError('No SchemaRegistry address for chainId $chainId. '
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
