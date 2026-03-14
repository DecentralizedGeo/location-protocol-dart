import 'package:test/test.dart';
import 'package:location_protocol/src/utils/byte_utils.dart';

void main() {
  group('ByteUtils', () {
    test('uint16ToBytes pads to 2 bytes', () {
      expect(ByteUtils.uint16ToBytes(2), [0, 2]);
    });

    test('uint64ToBytes pads to 8 bytes', () {
      expect(ByteUtils.uint64ToBytes(BigInt.from(257)), [0, 0, 0, 0, 0, 0, 1, 1]);
    });
  });
}
