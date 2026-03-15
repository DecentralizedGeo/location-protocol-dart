import 'package:test/test.dart';
import 'package:location_protocol/src/models/register_result.dart';

void main() {
  group('RegisterResult', () {
    test('constructs with all fields', () {
      final result = RegisterResult(
        txHash: '0xabc123',
        uid: '0xdef456',
      );
      expect(result.txHash, equals('0xabc123'));
      expect(result.uid, equals('0xdef456'));
    });

    test('toString includes txHash and uid', () {
      final result = RegisterResult(
        txHash: '0xabc123',
        uid: '0xdef456',
      );
      final str = result.toString();
      expect(str, contains('0xabc123'));
      expect(str, contains('0xdef456'));
    });
  });
}
