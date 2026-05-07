import 'dart:typed_data';
import 'package:blockchain_utils/blockchain_utils.dart';

import '../eas/constants.dart';
import '../utils/hex_utils.dart';
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
  /// The signer's Ethereum address.
  final String signer;

  /// The preserved EIP-712 domain.
  final Map<String, dynamic> domain;

  /// The preserved EIP-712 primary type.
  final String primaryType;

  /// The preserved EIP-712 types map.
  final Map<String, dynamic> types;

  /// The preserved EIP-712 message payload.
  final Map<String, dynamic> message;

  /// The EIP-712 signature.
  final EIP712Signature signature;

  /// The deterministic offchain UID.
  final String uid;

  SignedOffchainAttestation({
    required this.signer,
    required Map<String, dynamic> domain,
    required this.primaryType,
    required Map<String, dynamic> types,
    required Map<String, dynamic> message,
    required this.signature,
    required this.uid,
  })  : domain = _deepFreezeMap(domain),
        types = _deepFreezeMap(types),
        message = _deepFreezeMap(message);

  /// Creates a canonical EAS envelope from JSON.
  factory SignedOffchainAttestation.fromJson(Map<String, dynamic> json) {
    final sig = Map<String, dynamic>.from(json['sig'] as Map);

    return SignedOffchainAttestation(
      signer: json['signer'] as String,
      domain: Map<String, dynamic>.from(sig['domain'] as Map),
      primaryType: sig['primaryType'] as String,
      types: Map<String, dynamic>.from(sig['types'] as Map),
      message: Map<String, dynamic>.from(sig['message'] as Map),
      signature: EIP712Signature.fromJson(
        Map<String, dynamic>.from(sig['signature'] as Map),
      ),
      uid: sig['uid'] as String,
    );
  }

  /// Serializes this attestation to the canonical EAS package JSON shape.
  Map<String, dynamic> toJson() => {
        'signer': signer,
        'sig': {
          'domain': _deepMutableMap(domain),
          'primaryType': primaryType,
          'types': _deepMutableMap(types),
          'message': _deepMutableMap(message),
          'signature': signature.toJson(),
          'uid': uid,
        },
      };

  /// The EAS schema UID from the preserved message.
  String get schemaUID => message['schema'] as String;

  /// The EAS recipient address from the preserved message.
  String get recipient => message['recipient'] as String;

  /// The attestation time from the preserved message.
  BigInt get time => BigInt.parse(message['time'].toString());

  /// The expiration time from the preserved message.
  BigInt get expirationTime => BigInt.parse(message['expirationTime'].toString());

  /// Whether the attestation is revocable.
  bool get revocable => message['revocable'] as bool;

  /// The referenced UID from the preserved message.
  String get refUID => message['refUID'] as String;

  /// The preserved offchain version.
  int get offchainVersion => int.parse(message['version'].toString());

  /// Backward-compatible alias for [offchainVersion].
  int get version => offchainVersion;

  /// The preserved salt value as a hex string, if present.
  String? get saltHex => message['salt'] as String?;

  /// Backward-compatible alias for [saltHex].
  String get salt => saltHex ?? EASConstants.zeroBytes32;

  /// The preserved ABI-encoded data as a hex string, if present.
  String? get dataHex => message['data'] as String?;

  /// The preserved ABI-encoded data as bytes.
  Uint8List get dataBytes => dataHex?.toBytes() ?? Uint8List(0);

  /// Backward-compatible alias for [dataBytes].
  Uint8List get data => dataBytes;

  /// The preserved salt as bytes.
  Uint8List get saltBytes => (saltHex ?? EASConstants.zeroBytes32).toBytes();

  static Map<String, dynamic> _deepFreezeMap(Map<String, dynamic> source) {
    return Map.unmodifiable(
      source.map((key, value) => MapEntry(key, _deepFreezeValue(value))),
    );
  }

  static dynamic _deepFreezeValue(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable({
        for (final entry in value.entries)
          entry.key.toString(): _deepFreezeValue(entry.value),
      });
    }

    if (value is List) {
      return List.unmodifiable(value.map(_deepFreezeValue));
    }

    return value;
  }

  static Map<String, dynamic> _deepMutableMap(Map<String, dynamic> source) {
    return source.map((key, value) => MapEntry(key, _deepMutableValue(value)));
  }

  static dynamic _deepMutableValue(dynamic value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _deepMutableValue(entry.value),
      };
    }

    if (value is List) {
      return value.map(_deepMutableValue).toList();
    }

    return value;
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
