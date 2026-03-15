import 'package:test/test.dart';
import 'package:location_protocol/src/models/attest_result.dart';

void main() {
  group('AttestResult', () {
    test('constructs with all fields', () {
      final result = AttestResult(
        txHash: '0xabc123',
        uid: '0xdef456',
        blockNumber: 42,
      );
      expect(result.txHash, equals('0xabc123'));
      expect(result.uid, equals('0xdef456'));
      expect(result.blockNumber, equals(42));
    });

    test('toString includes txHash and uid', () {
      final result = AttestResult(
        txHash: '0xabc123',
        uid: '0xdef456',
        blockNumber: 42,
      );
      final str = result.toString();
      expect(str, contains('0xabc123'));
      expect(str, contains('0xdef456'));
    });
  });
}
