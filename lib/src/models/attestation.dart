import 'dart:typed_data';
import 'package:blockchain_utils/blockchain_utils.dart';

import 'signature.dart';
import '../utils/hex_utils.dart';

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

/// A signed typed data struct for offchain EAS attestations in.
///
/// This is the exact JSON shape produced by the EAS offchain SDK:
/// ```json
/// {
///   "signer": "0x...",
///   "sig": {
///     "domain": {...},
///     "primaryType": "Attest",
///     "types": {"Attest": [...]},
///     "message": {...},
///     "signature": {"v": 28, "r": "0x...", "s": "0x..."},
///     "uid": "0x..."
///   }
/// }
/// ```
///
/// Use the convenience getters ([schemaUID], [time], [saltHex], etc.) to
/// access common fields without navigating the nested map directly.
class SignedOffchainAttestation {
  /// The Ethereum address of the signer.
  final String signer;

  /// The EIP-712 domain — contains name, version, chainId, verifyingContract.
  ///
  /// [chainId] is stored as an [int] (not a string).
  final Map<String, dynamic> domain;

  /// The EIP-712 primary type. Always `'Attest'`.
  final String primaryType;

  /// The EIP-712 types map — contains the Attest field descriptor list.
  final Map<String, dynamic> types;

  /// The EIP-712 message — the full attestation payload.
  ///
  /// Numeric fields ([time], [expirationTime], [version]) are stored as [int]
  /// when deserialized from JSON, and as [BigInt] when built during signing.
  /// The getters handle both forms automatically.
  final Map<String, dynamic> message;

  /// The EIP-712 signature components.
  final EIP712Signature signature;

  /// The deterministic offchain attestation UID.
  final String uid;

  const SignedOffchainAttestation({
    required this.signer,
    required this.domain,
    required this.primaryType,
    required this.types,
    required this.message,
    required this.signature,
    required this.uid,
  });

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Deserializes from the canonical EAS offchain JSON.
  factory SignedOffchainAttestation.fromJson(Map<String, dynamic> json) {
    final sig = json['sig'] as Map<String, dynamic>;
    return SignedOffchainAttestation(
      signer: json['signer'] as String,
      domain: sig['domain'] as Map<String, dynamic>,
      primaryType: sig['primaryType'] as String,
      types: sig['types'] as Map<String, dynamic>,
      message: sig['message'] as Map<String, dynamic>,
      signature: EIP712Signature.fromJson(sig['signature'] as Map<String, dynamic>),
      uid: sig['uid'] as String,
    );
  }

  /// Serializes to the canonical EAS offchain JSON.
  Map<String, dynamic> toJson() => {
        'signer': signer,
        'sig': {
          'domain': domain,
          'primaryType': primaryType,
          'types': types,
          'message': message,
          'signature': signature.toJson(),
          'uid': uid,
        },
      };

  // ---------------------------------------------------------------------------
  // Derived getters (projections from the preserved message map)
  // ---------------------------------------------------------------------------

  /// Schema UID from the message.
  String get schemaUID => message['schema'] as String;

  /// Recipient address from the message.
  String get recipient => message['recipient'] as String;

  /// Attestation creation time (Unix seconds) from the message.
  BigInt get time {
    final val = message['time'];
    if (val is BigInt) return val;
    if (val is int) return BigInt.from(val);
    return BigInt.parse(val.toString());
  }

  /// Expiration time (0 = never) from the message.
  BigInt get expirationTime {
    final val = message['expirationTime'];
    if (val is BigInt) return val;
    if (val is int) return BigInt.from(val);
    return BigInt.parse(val.toString());
  }

  /// Whether this attestation is revocable.
  bool get revocable => message['revocable'] as bool;

  /// Reference UID from the message.
  String get refUID => message['refUID'] as String;

  /// Offchain attestation version from the message (v2).
  int get offchainVersion {
    final val = message['version'];
    if (val is int) return val;
    return int.parse(val.toString());
  }

  /// Salt as a 0x-prefixed 64-char hex string (32 bytes), or null if missing.
  String? get saltHex {
    final val = message['salt'];
    if (val == null) return null;
    return val as String?;
  }

  /// Salt decoded to bytes, or null if not present.
  Uint8List? get saltBytes {
    final hex = saltHex;
    if (hex == null) return null;
    return hex.toBytes();
  }

  /// ABI-encoded data payload as a 0x-prefixed hex string.
  String get dataHex => message['data'] as String;

  /// ABI-encoded data payload decoded to bytes.
  Uint8List get dataBytes => dataHex.toBytes();
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
