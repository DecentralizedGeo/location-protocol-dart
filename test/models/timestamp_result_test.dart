import 'package:test/test.dart';
import 'package:location_protocol/src/models/timestamp_result.dart';

void main() {
  group('TimestampResult', () {
    test('constructs with all fields', () {
      final result = TimestampResult(
        txHash: '0xabc123',
        uid: '0xdef456',
        time: BigInt.from(1710374400),
      );
      expect(result.txHash, equals('0xabc123'));
      expect(result.uid, equals('0xdef456'));
      expect(result.time, equals(BigInt.from(1710374400)));
    });

    test('toString includes txHash and time', () {
      final result = TimestampResult(
        txHash: '0xabc123',
        uid: '0xdef456',
        time: BigInt.from(1710374400),
      );
      final str = result.toString();
      expect(str, contains('0xabc123'));
      expect(str, contains('1710374400'));
    });
  });
}
