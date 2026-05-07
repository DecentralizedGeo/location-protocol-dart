import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:location_protocol/src/models/attestation.dart';
import 'package:location_protocol/src/models/signature.dart';
import 'package:location_protocol/src/models/verification_result.dart';

const _canonicalSigner = '0x1111111111111111111111111111111111111111';
const _canonicalSchemaUid =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _canonicalRecipient =
    '0x0000000000000000000000000000000000000000';
const _canonicalRefUid =
    '0x0000000000000000000000000000000000000000000000000000000000000000';
const _canonicalSalt =
    '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _canonicalSignatureR =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const _canonicalSignatureS =
    '0x2222222222222222222222222222222222222222222222222222222222222222';
const _canonicalUid =
    '0x3333333333333333333333333333333333333333333333333333333333333333';

Map<String, dynamic> _canonicalSignedOffchainAttestationJson() {
  return {
    'signer': _canonicalSigner,
    'sig': {
      'domain': {
        'name': 'EAS Attestation',
        'version': '1.0.0',
        'chainId': 11155111,
        'verifyingContract':
            '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      },
      'primaryType': 'Attest',
      'types': {
        'Attest': [
          {'name': 'version', 'type': 'uint16'},
          {'name': 'schema', 'type': 'bytes32'},
          {'name': 'recipient', 'type': 'address'},
          {'name': 'time', 'type': 'uint64'},
          {'name': 'expirationTime', 'type': 'uint64'},
          {'name': 'revocable', 'type': 'bool'},
          {'name': 'refUID', 'type': 'bytes32'},
          {'name': 'data', 'type': 'bytes'},
          {'name': 'salt', 'type': 'bytes32'},
        ],
      },
      'message': {
        'version': 2,
        'schema': _canonicalSchemaUid,
        'recipient': _canonicalRecipient,
        'time': 1710000000,
        'expirationTime': 0,
        'revocable': true,
        'refUID': _canonicalRefUid,
        'data': '0x010203',
        'salt': _canonicalSalt,
      },
      'signature': {
        'v': 28,
        'r': _canonicalSignatureR,
        's': _canonicalSignatureS,
      },
      'uid': _canonicalUid,
    },
  };
}

void main() {
  group('EIP712Signature', () {
    test('stores v, r, s components', () {
      final sig = EIP712Signature(v: 28, r: '0xabc', s: '0xdef');
      expect(sig.v, equals(28));
      expect(sig.r, equals('0xabc'));
      expect(sig.s, equals('0xdef'));
    });
  });

  group('UnsignedAttestation', () {
    test('stores all EAS attestation fields', () {
      final att = UnsignedAttestation(
        schemaUID: '0xschema',
        recipient: '0xrecip',
        time: BigInt.from(1710000000),
        expirationTime: BigInt.zero,
        revocable: true,
        refUID: '0x0000000000000000000000000000000000000000000000000000000000000000',
        data: Uint8List.fromList([1, 2, 3]),
      );
      expect(att.schemaUID, equals('0xschema'));
      expect(att.time, equals(BigInt.from(1710000000)));
      expect(att.revocable, isTrue);
    });
  });

  group('SignedOffchainAttestation', () {
    test('parses the canonical preserved envelope from JSON', () {
      final canonical = SignedOffchainAttestation.fromJson(
        _canonicalSignedOffchainAttestationJson(),
      );

      expect(canonical.signer, equals(_canonicalSigner));
      expect(canonical.schemaUID, equals(_canonicalSchemaUid));
      expect(canonical.offchainVersion, equals(2));
      expect(canonical.saltHex, equals(_canonicalSalt));
      expect(canonical.uid, equals(_canonicalUid));
      expect(canonical.signature.v, equals(28));
    });

    test('toJson emits exact preserved EAS envelope shape', () {
      final canonical = SignedOffchainAttestation.fromJson(
        _canonicalSignedOffchainAttestationJson(),
      );

      final json = canonical.toJson();

      expect(json.keys.toList(), equals(['signer', 'sig']));

      final sig = json['sig'] as Map<String, dynamic>;
      expect(
        sig.keys.toList(),
        equals([
          'domain',
          'primaryType',
          'types',
          'message',
          'signature',
          'uid',
        ]),
      );
    });

    test('derived getters project canonical EAS fields', () {
      final canonical = SignedOffchainAttestation.fromJson(
        _canonicalSignedOffchainAttestationJson(),
      );

      expect(canonical.schemaUID, equals(_canonicalSchemaUid));
      expect(canonical.offchainVersion, equals(2));
      expect(canonical.saltHex, equals(_canonicalSalt));
    });
  });

  group('VerificationResult', () {
    test('valid result', () {
      final result = VerificationResult(
        isValid: true,
        recoveredAddress: '0xabc',
      );
      expect(result.isValid, isTrue);
      expect(result.recoveredAddress, equals('0xabc'));
      expect(result.reason, isNull);
    });

    test('invalid result with reason', () {
      final result = VerificationResult(
        isValid: false,
        recoveredAddress: '0xwrong',
        reason: 'UID mismatch',
      );
      expect(result.isValid, isFalse);
      expect(result.reason, equals('UID mismatch'));
    });
  });
}
