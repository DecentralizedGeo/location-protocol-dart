import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';

import '../lp/lp_payload.dart';
import '../schema/schema_definition.dart';
import '../config/chain_config.dart';
import '../schema/schema_uid.dart';
import '../rpc/rpc_provider.dart';
import '../rpc/transaction_receipt.dart';
import '../models/attestation.dart';
import '../models/attest_result.dart';
import '../models/register_result.dart';
import '../models/timestamp_result.dart';
import '../utils/hex_utils.dart';
import 'abi_encoder.dart';
import 'eas_abis.dart';
import 'constants.dart';
import 'schema_registry.dart';

/// High-level client for onchain EAS operations.
///
/// Provides:
/// - [attest]: Submit an onchain attestation
/// - [timestamp]: Timestamp an offchain attestation UID onchain
/// - [registerSchema]: Register a schema (delegates to [SchemaRegistryClient])
class EASClient {
  final RpcProvider provider;
  final String? _easAddress;

  EASClient({
    required this.provider,
    String? easAddress,
  }) : _easAddress = easAddress;

  /// The EAS contract address for this chain.
  String get easAddress {
    if (_easAddress != null) return _easAddress;
    final config = ChainConfig.forChainId(provider.chainId);
    if (config == null) throw StateError('No EAS address for chainId ${provider.chainId}.');
    return config.eas;
  }

  /// Builds ABI-encoded call data for `EAS.timestamp(bytes32)`.
  static Uint8List buildTimestampCallData(String uid) {
    return Uint8List.fromList(EASAbis.timestamp.encode([uid.toBytes()]));
  }

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
    String recipient = EASConstants.zeroAddress,
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

    final encoded = EASAbis.attest.encode([
      [
        schemaUID.toBytes(),
        [
          recipient,
          expTime,
          schema.revocable,
          ref.toBytes(),
          encodedData,
          BigInt.zero, // transaction value in request data, usually 0
        ]
      ]
    ]);

    return Uint8List.fromList(encoded);
  }


  /// Submit an onchain attestation.
  ///
  /// Requires the schema to already be registered on-chain.
  static String _parseAttestedUID(
    List<TransactionLog> logs,
    String contractAddress,
  ) {
    final lowerAddress = contractAddress.toLowerCase();
    for (final log in logs) {
      if (log.topics.isNotEmpty &&
          log.topics[0] == EASConstants.attestedEventTopic &&
          log.address.toLowerCase() == lowerAddress) {
        return log.data;
      }
    }

    throw StateError(
      'No Attested event found in receipt logs from $contractAddress',
    );
  }

  /// Submit an onchain attestation.
  ///
  /// Requires the schema to already be registered on-chain.
  Future<AttestResult> attest({
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

    final txHash = await provider.sendTransaction(
      to: easAddress,
      data: callData,
    );

    final receipt = await provider.waitForReceipt(txHash);
    final uid = _parseAttestedUID(receipt.logs, easAddress);
    return AttestResult(
      txHash: txHash,
      uid: uid,
      blockNumber: receipt.blockNumber,
    );
  }

  /// Timestamp an offchain attestation UID onchain.
  ///
  /// Records a timestamp on the EAS contract proving the UID existed
  /// at a specific block time.
  static (String uid, BigInt time) _parseTimestampedEvent(
    List<TransactionLog> logs,
    String contractAddress,
  ) {
    final lowerAddress = contractAddress.toLowerCase();
    for (final log in logs) {
      if (log.topics.length >= 3 &&
          log.topics[0] == EASConstants.timestampedEventTopic &&
          log.address.toLowerCase() == lowerAddress) {
        final uid = log.topics[1];
        final timeHex = log.topics[2].replaceFirst('0x', '');
        final time = BigInt.parse(timeHex, radix: 16);
        return (uid, time);
      }
    }

    throw StateError(
      'No Timestamped event found in receipt logs from $contractAddress',
    );
  }

  /// Timestamp an offchain attestation UID onchain.
  ///
  /// Records a timestamp on the EAS contract proving the UID existed
  /// at a specific block time.
  Future<TimestampResult> timestamp(String offchainUID) async {
    final callData = buildTimestampCallData(offchainUID);
    final txHash = await provider.sendTransaction(
      to: easAddress,
      data: callData,
    );

    final receipt = await provider.waitForReceipt(txHash);
    final (uid, time) = _parseTimestampedEvent(receipt.logs, easAddress);
    return TimestampResult(txHash: txHash, uid: uid, time: time);
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

  /// Register a schema on-chain. Convenience wrapper around [SchemaRegistryClient].
  Future<RegisterResult> registerSchema(SchemaDefinition schema) async {
    final registry = SchemaRegistryClient(
      provider: provider,
    );
    return registry.register(schema);
  }
}
