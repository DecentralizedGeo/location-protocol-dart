import 'package:test/test.dart';
import 'package:location_protocol/location_protocol.dart';
import 'dart:typed_data';

void main() {
  group('TxUtils.buildTxRequest', () {
    test('builds basic tx map without from or value', () {
      final req = TxUtils.buildTxRequest(
        to: '0xabc',
        data: Uint8List.fromList([1, 2, 3]),
      );
      expect(req['to'], equals('0xabc'));
      expect(req['data'], equals('0x010203')); // 1, 2, 3 in hex
      expect(req['value'], equals('0x0'));
      expect(req.containsKey('from'), isFalse);
    });

    test('builds tx map with from and value', () {
      final req = TxUtils.buildTxRequest(
        to: '0xabc',
        data: Uint8List.fromList([1, 2, 3]),
        from: '0xsender',
        value: BigInt.from(100),
      );
      expect(req['to'], equals('0xabc'));
      expect(req['data'], equals('0x010203'));
      expect(req['value'], equals('0x64')); // 100 in hex
      expect(req['from'], equals('0xsender'));
    });
  });
}
