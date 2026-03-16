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

    test('alreadyExisted is false when txHash is present', () {
      final result = RegisterResult(
        txHash: '0xabc123',
        uid: '0xdef456',
      );
      expect(result.alreadyExisted, isFalse);
    });

    test('alreadyExisted is true when txHash is null', () {
      final result = RegisterResult(
        txHash: null,
        uid: '0xdef456',
      );
      expect(result.alreadyExisted, isTrue);
      expect(result.txHash, isNull);
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

    test('toString with null txHash does not throw', () {
      final result = RegisterResult(
        txHash: null,
        uid: '0xdef456',
      );
      final str = result.toString();
      expect(str, contains('null'));
      expect(str, contains('0xdef456'));
    });
  });
}
