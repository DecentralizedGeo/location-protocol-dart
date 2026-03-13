import 'dart:typed_data';

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
