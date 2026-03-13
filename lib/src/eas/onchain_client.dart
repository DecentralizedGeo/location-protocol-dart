import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

import '../lp/lp_payload.dart';
import '../schema/schema_definition.dart';
import '../config/chain_config.dart';
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

    final uidBytes = BytesUtils.fromHexString(uid.replaceAll('0x', ''));
    return Uint8List.fromList(fragment.encode([uidBytes]));
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
