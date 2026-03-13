import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:location_protocol/src/models/attestation.dart';
import 'package:location_protocol/src/models/signature.dart';
import 'package:location_protocol/src/models/verification_result.dart';

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
    test('stores attestation data + signature + uid + salt', () {
      final signed = SignedOffchainAttestation(
        uid: '0xuid123',
        schemaUID: '0xschema',
        recipient: '0xrecip',
        time: BigInt.from(1710000000),
        expirationTime: BigInt.zero,
        revocable: true,
        refUID: '0x0000000000000000000000000000000000000000000000000000000000000000',
        data: Uint8List.fromList([1, 2, 3]),
        salt: '0xsalt',
        version: 2,
        signature: EIP712Signature(v: 28, r: '0xr', s: '0xs'),
        signer: '0xSignerAddress',
      );
      expect(signed.uid, equals('0xuid123'));
      expect(signed.signature.v, equals(28));
      expect(signed.signer, equals('0xSignerAddress'));
      expect(signed.version, equals(2));
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
