import 'package:test/test.dart';
import 'package:location_protocol/src/models/signature.dart';

void main() {
  // Hardhat key #0 signature (deterministic from known inputs)
  // A valid 65-byte signature: r[32] || s[32] || v[1]
  // Using a well-known test vector: 65 bytes = 130 hex chars = 132 with 0x prefix
  const validSig65 =
      '0x'
      'a0b3c4d5e6f70819aabbccddeeff00112233445566778899aabbccddeeff0011' // r (32 bytes)
      'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100' // s (32 bytes)
      '1b'; // v = 27

  group('EIP712Signature.fromHex', () {
    test('parses valid 65-byte hex string (0x-prefixed)', () {
      final sig = EIP712Signature.fromHex(validSig65);

      expect(sig.v, equals(27)); // 0x1b = 27
      expect(sig.r, startsWith('0x'));
      expect(sig.r.length, equals(66)); // 0x + 64 hex chars
      expect(sig.s, startsWith('0x'));
      expect(sig.s.length, equals(66));
      expect(sig.r, equals('0xa0b3c4d5e6f70819aabbccddeeff00112233445566778899aabbccddeeff0011'));
      expect(sig.s, equals('0xffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100'));
    });

    test('parses hex without 0x prefix', () {
      final rawHex = validSig65.substring(2); // strip 0x
      final sig = EIP712Signature.fromHex(rawHex);

      expect(sig.v, equals(27));
      expect(sig.r, startsWith('0x'));
      expect(sig.s, startsWith('0x'));
    });

    test('parses v=28 correctly', () {
      final sig28 = validSig65.substring(0, validSig65.length - 2) + '1c';
      final sig = EIP712Signature.fromHex(sig28);
      expect(sig.v, equals(28)); // 0x1c = 28
    });

    test('throws ArgumentError for wrong length (64 bytes)', () {
      // 64 bytes = 128 hex chars
      final short = '0x' + 'aa' * 64;
      expect(() => EIP712Signature.fromHex(short), throwsArgumentError);
    });

    test('throws ArgumentError for wrong length (66 bytes)', () {
      // 66 bytes = 132 hex chars
      final long = '0x' + 'aa' * 66;
      expect(() => EIP712Signature.fromHex(long), throwsArgumentError);
    });

    test('throws ArgumentError for empty string', () {
      expect(() => EIP712Signature.fromHex(''), throwsArgumentError);
    });

    test('r is padded to 64 hex chars', () {
      // Build a sig where r's first bytes are zero (testing left-pad)
      final zeroR = '0x' +
          '00' * 32 + // r = zero
          'ff' * 32 + // s
          '1b'; // v
      final sig = EIP712Signature.fromHex(zeroR);
      expect(sig.r, equals('0x' + '0' * 64));
    });
  });
}
