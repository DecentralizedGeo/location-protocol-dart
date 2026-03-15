import 'dart:typed_data';

import '../schema/schema_definition.dart';
import '../schema/schema_uid.dart';
import '../models/register_result.dart';
import '../config/chain_config.dart';
import '../rpc/rpc_provider.dart';
import '../utils/hex_utils.dart';
import 'eas_abis.dart';
import 'constants.dart';

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
  final RpcProvider provider;
  final String? schemaRegistryAddress;

  SchemaRegistryClient({
    required this.provider,
    this.schemaRegistryAddress,
  });

  /// The SchemaRegistry contract address for this chain.
  String get contractAddress {
    if (schemaRegistryAddress != null) return schemaRegistryAddress!;
    final config = ChainConfig.forChainId(provider.chainId);
    if (config == null) {
      throw StateError('No SchemaRegistry address for chainId ${provider.chainId}. '
          'Provide one via schemaRegistryAddress parameter.');
    }
    return config.schemaRegistry;
  }

  /// Builds the ABI-encoded call data for `register(string,address,bool)`.
  ///
  /// This is a static method that doesn't require RPC — useful for
  /// pre-computing the transaction data.
  static Uint8List buildRegisterCallData(SchemaDefinition schema) {
    final encoded = EASAbis.registerSchema.encode([
      schema.toEASSchemaString(), 
      schema.resolverAddress, 
      schema.revocable
    ]);
    return Uint8List.fromList(encoded);
  }

  /// Computes the schema UID locally (no RPC needed).
  static String computeSchemaUID(SchemaDefinition schema) {
    return SchemaUID.compute(schema);
  }

  /// Registers a schema on-chain.
  ///
  /// Sends a transaction to `SchemaRegistry.register()` and returns a
  /// [RegisterResult] with the transaction hash and deterministic schema UID.
  ///
  /// Requires an RPC connection and a funded wallet.
  Future<RegisterResult> register(SchemaDefinition schema) async {
    final callData = buildRegisterCallData(schema);
    final txHash = await provider.sendTransaction(
      to: contractAddress,
      data: callData,
    );
    final uid = SchemaUID.compute(schema);
    return RegisterResult(txHash: txHash, uid: uid);
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

  factory SchemaRecord.fromTuple(List<dynamic> decoded) {
    if (decoded.length < 4) {
      throw ArgumentError('Tuple missing fields for SchemaRecord');
    }
    final recordUid = decoded[0];
    final uidHex = recordUid is List<int>
        // Use a generic byte-to-hex strategy without dragging blockchain_utils everywhere if we can,
        // but blockchain_utils exists for now. We can keep it or use hex_utils if we expand it. But for now, we leave blockchain_utils import out or we must import it.
        // Wait, I removed `blockchain_utils` import above, but used BytesUtils here. So I should probably add it back or use something else.
        // Let's actually import blockchain_utils above at the top or put it here.
        ? '0x${recordUid.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'
        : recordUid.toString();

    return SchemaRecord(
      uid: uidHex,
      resolver: decoded[1].toString(),
      revocable: decoded[2] as bool,
      schema: decoded[3].toString(),
    );
  }
}
