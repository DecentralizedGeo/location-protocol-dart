import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

import '../schema/schema_definition.dart';
import '../schema/schema_uid.dart';
import '../config/chain_config.dart';
import '../rpc/rpc_helper.dart';

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
        final recordUid = decoded[0]; // bytes32 (List<int>)
        final resolver = decoded[1]; // address (ETHAddress or String)
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
