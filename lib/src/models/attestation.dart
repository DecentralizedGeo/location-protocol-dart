import 'dart:typed_data';
import 'package:blockchain_utils/blockchain_utils.dart';

import 'signature.dart';

/// An unsigned EAS attestation — the data payload before signing.
class UnsignedAttestation {
  /// The schema UID this attestation conforms to.
  final String schemaUID;

  /// The recipient address (can be zero address for no recipient).
  final String recipient;

  /// The attestation creation time (Unix seconds).
  final BigInt time;

  /// When this attestation expires (0 = never).
  final BigInt expirationTime;

  /// Whether this attestation can be revoked.
  final bool revocable;

  /// Reference to another attestation UID (zero bytes32 for none).
  final String refUID;

  /// ABI-encoded data payload.
  final Uint8List data;

  const UnsignedAttestation({
    required this.schemaUID,
    required this.recipient,
    required this.time,
    required this.expirationTime,
    required this.revocable,
    required this.refUID,
    required this.data,
  });
}

/// A signed offchain EAS attestation with EIP-712 signature.
class SignedOffchainAttestation {
  /// The deterministic offchain UID.
  final String uid;

  /// Schema UID.
  final String schemaUID;

  /// Recipient address.
  final String recipient;

  /// Attestation creation time (Unix seconds).
  final BigInt time;

  /// Expiration time (0 = never).
  final BigInt expirationTime;

  /// Whether revocable.
  final bool revocable;

  /// Reference UID.
  final String refUID;

  /// ABI-encoded data payload.
  final Uint8List data;

  /// Random salt (32 bytes, hex string).
  final String salt;

  /// Offchain attestation version.
  final int version;

  /// The EIP-712 signature.
  final EIP712Signature signature;

  /// The signer's Ethereum address.
  final String signer;

  const SignedOffchainAttestation({
    required this.uid,
    required this.schemaUID,
    required this.recipient,
    required this.time,
    required this.expirationTime,
    required this.revocable,
    required this.refUID,
    required this.data,
    required this.salt,
    required this.version,
    required this.signature,
    required this.signer,
  });
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
