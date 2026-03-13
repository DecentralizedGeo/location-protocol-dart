import 'package:test/test.dart';
import 'package:location_protocol/src/eas/constants.dart';

void main() {
  group('EAS Constants', () {
    test('ZERO_ADDRESS is 42-char hex string', () {
      expect(EASConstants.zeroAddress, equals('0x0000000000000000000000000000000000000000'));
      expect(EASConstants.zeroAddress.length, equals(42));
    });

    test('ZERO_BYTES32 is 66-char hex string', () {
      expect(
        EASConstants.zeroBytes32,
        equals('0x0000000000000000000000000000000000000000000000000000000000000000'),
      );
      expect(EASConstants.zeroBytes32.length, equals(66));
    });

    test('SALT_SIZE is 32', () {
      expect(EASConstants.saltSize, equals(32));
    });

    test('EAS_ATTESTATION_VERSION is 2', () {
      expect(EASConstants.attestationVersion, equals(2));
    });

    test('EIP712_DOMAIN_NAME is "EAS Attestation"', () {
      expect(EASConstants.eip712DomainName, equals('EAS Attestation'));
    });

    test('generateSalt produces 32-byte Uint8List', () {
      final salt = EASConstants.generateSalt();
      expect(salt.length, equals(32));
    });

    test('generateSalt produces different values each call', () {
      final salt1 = EASConstants.generateSalt();
      final salt2 = EASConstants.generateSalt();
      // Probability of collision is 2^-256, so this is safe
      expect(salt1, isNot(equals(salt2)));
    });

    test('saltToHex returns 0x-prefixed 64-char hex string', () {
      final salt = EASConstants.generateSalt();
      final hex = EASConstants.saltToHex(salt);
      expect(hex, startsWith('0x'));
      expect(hex.length, equals(66));
    });
  });
}
