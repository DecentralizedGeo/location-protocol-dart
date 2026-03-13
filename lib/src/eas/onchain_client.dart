import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

import '../lp/lp_payload.dart';
import '../schema/schema_definition.dart';
import '../config/chain_config.dart';
import '../schema/schema_uid.dart';
import '../rpc/rpc_helper.dart';
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

    final uidBytes = BytesUtils.fromHexString(uid.replaceAll('0x', ''));
    return Uint8List.fromList(fragment.encode([uidBytes]));
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

    final schemaBytes = BytesUtils.fromHexString(schemaUID.replaceAll('0x', ''));
    final refBytes = (ref is String)
        ? BytesUtils.fromHexString(ref.replaceAll('0x', ''))
        : ref;

    final encoded = fragment.encode([
      [
        schemaBytes,
        [
          recipient,
          expTime,
          schema.revocable,
          refBytes,
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

  /// Timestamp an offchain attestation UID onchain.
  ///
  /// Records a timestamp on the EAS contract proving the UID existed
  /// at a specific block time.
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

  /// ABI fragment for `getAttestation(bytes32)`.
  static final _getAttestationFragment = AbiFunctionFragment.fromJson({
    'name': 'getAttestation',
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

  /// Queries an attestation by its UID from the EAS contract.
  ///
  /// Returns the attestation record or null if not found.
  Future<Attestation?> getAttestation(String uid) async {
    final helper = RpcHelper(
      rpcUrl: rpcUrl,
      privateKeyHex: privateKeyHex,
      chainId: chainId,
    );
    try {
      final uidBytes = BytesUtils.fromHexString(uid.replaceAll('0x', ''));

      final result = await helper.callContract(
        contractAddress: easAddress,
        function: _getAttestationFragment,
        params: [uidBytes],
      );

      if (result.isEmpty) return null;

      final decoded = result[0];
      if (decoded is List && decoded.length >= 10) {
        final recordUid = decoded[0];
        final schema = decoded[1];
        final time = decoded[2];
        final expirationTime = decoded[3];
        final revocationTime = decoded[4];
        final refUID = decoded[5];
        final recipient = decoded[6];
        final attester = decoded[7];
        final revocable = decoded[8];
        final data = decoded[9];

        final uidHex = recordUid is List<int>
            ? BytesUtils.toHexString(recordUid, prefix: '0x')
            : recordUid.toString();

        // Check for zero UID (attestation not found)
        if (uidHex == EASConstants.zeroBytes32) {
          return null;
        }

        return Attestation(
          uid: uidHex,
          schema: schema is List<int>
              ? BytesUtils.toHexString(schema, prefix: '0x')
              : schema.toString(),
          time: time is BigInt ? time : BigInt.from(time),
          expirationTime:
              expirationTime is BigInt ? expirationTime : BigInt.from(expirationTime),
          revocationTime:
              revocationTime is BigInt ? revocationTime : BigInt.from(revocationTime),
          refUID: refUID is List<int>
              ? BytesUtils.toHexString(refUID, prefix: '0x')
              : refUID.toString(),
          recipient: recipient.toString(),
          attester: attester.toString(),
          revocable: revocable as bool,
          data: data is List<int> ? Uint8List.fromList(data) : data as Uint8List,
        );
      }

      return null;
    } finally {
      helper.close();
    }
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

/// A record representing an on-chain attestation.
class Attestation {
  final String uid;
  final String schema;
  final BigInt time;
  final BigInt expirationTime;
  final BigInt revocationTime;
  final String refUID;
  final String recipient;
  final String attester;
  final bool revocable;
  final Uint8List data;

  const Attestation({
    required this.uid,
    required this.schema,
    required this.time,
    required this.expirationTime,
    required this.revocationTime,
    required this.refUID,
    required this.recipient,
    required this.attester,
    required this.revocable,
    required this.data,
  });
}
