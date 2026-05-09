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

  group('EIP712Signature JSON', () {
    const sig = EIP712Signature(
      v: 28,
      r: '0x1111111111111111111111111111111111111111111111111111111111111111',
      s: '0x2222222222222222222222222222222222222222222222222222222222222222',
    );

    test('toJson emits v, r, s', () {
      final json = sig.toJson();
      expect(json['v'], equals(28));
      expect(json['r'], equals(sig.r));
      expect(json['s'], equals(sig.s));
    });

    test('fromJson round-trips', () {
      final json = sig.toJson();
      final restored = EIP712Signature.fromJson(json);
      expect(restored.v, equals(sig.v));
      expect(restored.r, equals(sig.r));
      expect(restored.s, equals(sig.s));
    });

    test('fromJson accepts num for v (JSON deserialization returns num)', () {
      final restored = EIP712Signature.fromJson({'v': 28, 'r': sig.r, 's': sig.s});
      expect(restored.v, equals(28));
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
    // This is the canonical fixture used across all sub-tests in this group.
    // The shape mirrors what the EAS offchain SDK produces.
    final canonicalJson = {
      'signer': '0x1111111111111111111111111111111111111111',
      'sig': {
        'domain': {
          'name': 'EAS Attestation',
          'version': '1.0.0',
          'chainId': 11155111,
          'verifyingContract': '0x0a7E2Ff54e76B465dc9d8eb07dcec46b129859f9',
        },
        'primaryType': 'Attest',
        'types': {
          'EIP712Domain': [
            {'name': 'name', 'type': 'string'},
            {'name': 'version', 'type': 'string'},
            {'name': 'chainId', 'type': 'uint256'},
            {'name': 'verifyingContract', 'type': 'address'},
          ],
          'Attest': [
            {'name': 'schema', 'type': 'bytes32'},
            {'name': 'recipient', 'type': 'address'},
            {'name': 'time', 'type': 'uint64'},
            {'name': 'expirationTime', 'type': 'uint64'},
            {'name': 'revocable', 'type': 'bool'},
            {'name': 'refUID', 'type': 'bytes32'},
            {'name': 'data', 'type': 'bytes'},
            {'name': 'salt', 'type': 'bytes32'},
            {'name': 'version', 'type': 'uint16'},
          ],
        },
        'message': {
          'schema': '0xe1ec9a502c9ce3e31917fd9a6800fbb89df7abbb2e4942ce603831522cb5cb67',
          'recipient': '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
          'time': 1710000000,
          'expirationTime': 0,
          'revocable': true,
          'refUID': '0x0000000000000000000000000000000000000000000000000000000000000000',
          'data': '0x',
          'salt': '0x0000000000000000000000000000000000000000000000000000000000000000',
          'version': 2,
        },
        'signature': {
          'v': 28,
          'r': '0xdc34d28972f90b283b03ca6ae897c131ef940dbace1fdf144671211d51de5b4b',
          's': '0x027be7c54eb7f03f5b1fa797339c007d1294b895147765bb411ca4dcc7df74be',
        },
        'uid': '0x055e7dc3d45e69e83c33d75a48b0a62b050f7b2507611a6531aae43964d4dd98',
      },
    };

    late SignedOffchainAttestation canonical;

    setUp(() {
      canonical = SignedOffchainAttestation.fromJson(canonicalJson);
    });

    test('fromJson parses signer', () {
      expect(canonical.signer, equals('0x1111111111111111111111111111111111111111'));
    });

    test('fromJson parses uid', () {
      expect(canonical.uid, equals('0x055e7dc3d45e69e83c33d75a48b0a62b050f7b2507611a6531aae43964d4dd98'));
    });

    test('toJson emits exactly signer and sig at the top level', () {
      final json = canonical.toJson();
      expect(json.keys.toList(), equals(['signer', 'sig']));
    });

    test('toJson sig contains exactly the six canonical keys', () {
      final sig = canonical.toJson()['sig'] as Map<String, dynamic>;
      expect(sig.keys.toSet(), equals({'domain', 'primaryType', 'types', 'message', 'signature', 'uid'}));
    });

    test('toJson round-trips correctly', () {
      final json = canonical.toJson();
      final restored = SignedOffchainAttestation.fromJson(json);
      expect(restored.signer, equals(canonical.signer));
      expect(restored.uid, equals(canonical.uid));
      expect(restored.primaryType, equals(canonical.primaryType));
    });

    group('derived getters', () {
      test('schemaUID', () {
        expect(canonical.schemaUID, equals('0xe1ec9a502c9ce3e31917fd9a6800fbb89df7abbb2e4942ce603831522cb5cb67'));
      });

      test('recipient', () {
        expect(canonical.recipient, equals('0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'));
      });

      test('time', () {
        expect(canonical.time, equals(BigInt.from(1710000000)));
      });

      test('expirationTime', () {
        expect(canonical.expirationTime, equals(BigInt.zero));
      });

      test('revocable', () {
        expect(canonical.revocable, isTrue);
      });

      test('refUID', () {
        expect(canonical.refUID, equals('0x0000000000000000000000000000000000000000000000000000000000000000'));
      });

      test('offchainVersion', () {
        expect(canonical.offchainVersion, equals(2));
      });

      test('saltHex', () {
        expect(canonical.saltHex, equals('0x0000000000000000000000000000000000000000000000000000000000000000'));
      });

      test('saltBytes from saltHex', () {
        final bytes = canonical.saltBytes;
        expect(bytes, isNotNull);
        expect(bytes!.length, equals(32));
      });

      test('dataHex', () {
        expect(canonical.dataHex, equals('0x'));
      });

      test('dataBytes from dataHex', () {
        expect(canonical.dataBytes, isEmpty);
      });
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

  group('VerificationFailure', () {
    test('all expected codes exist', () {
      const codes = VerificationFailure.values;
      expect(codes, contains(VerificationFailure.uidMismatch));
      expect(codes, contains(VerificationFailure.invalidDomain));
      expect(codes, contains(VerificationFailure.invalidPrimaryType));
      expect(codes, contains(VerificationFailure.invalidTypes));
      expect(codes, contains(VerificationFailure.missingSalt));
      expect(codes, contains(VerificationFailure.unsupportedVersion));
      expect(codes, contains(VerificationFailure.invalidSignature));
      expect(codes, contains(VerificationFailure.signerMismatch));
    });
  });

  group('VerificationResult with code', () {
    test('valid result has null code', () {
      const result = VerificationResult(
        isValid: true,
        recoveredAddress: '0xabc',
      );
      expect(result.isValid, isTrue);
      expect(result.code, isNull);
    });

    test('invalid result can carry a code', () {
      const result = VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.uidMismatch,
        reason: 'UID mismatch',
      );
      expect(result.isValid, isFalse);
      expect(result.code, equals(VerificationFailure.uidMismatch));
      expect(result.reason, contains('UID'));
    });
  });
}