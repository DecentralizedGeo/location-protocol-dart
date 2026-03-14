import 'package:test/test.dart';
import 'package:location_protocol/src/utils/hex_utils.dart';

void main() {
  group('HexStringX', () {
    test('strip0x removes 0x prefix', () {
      expect('0x123abc'.strip0x, '123abc');
      expect('123abc'.strip0x, '123abc');
    });

    test('toBytes converts hex to Uint8List correctly', () {
      final bytes = '0x0102'.toBytes();
      expect(bytes, [1, 2]);
    });
  });
}
