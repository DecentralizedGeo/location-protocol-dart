import 'package:test/test.dart';
import 'package:location_protocol/src/rpc/transaction_receipt.dart';

void main() {
  group('TransactionLog', () {
    test('constructs with all fields', () {
      final log = TransactionLog(
        address: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
        topics: ['0xabc', '0xdef'],
        data: '0x1234',
      );
      expect(log.address, equals('0xC2679fBD37d54388Ce493F1DB75320D236e1815e'));
      expect(log.topics, hasLength(2));
      expect(log.data, equals('0x1234'));
    });

    test('toString includes address', () {
      final log = TransactionLog(
        address: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
        topics: [],
        data: '0x',
      );
      expect(log.toString(), contains('0xC2679fBD37d54388Ce493F1DB75320D236e1815e'));
    });
  });

  group('TransactionReceipt', () {
    test('constructs with all fields', () {
      final receipt = TransactionReceipt(
        txHash: '0xabc123',
        blockNumber: 42,
        status: true,
        logs: [],
      );
      expect(receipt.txHash, equals('0xabc123'));
      expect(receipt.blockNumber, equals(42));
      expect(receipt.status, isTrue);
      expect(receipt.logs, isEmpty);
    });

    test('status can be null (pre-Byzantium)', () {
      final receipt = TransactionReceipt(
        txHash: '0xabc',
        blockNumber: 1,
        status: null,
        logs: [],
      );
      expect(receipt.status, isNull);
    });

    test('toString includes txHash and blockNumber', () {
      final receipt = TransactionReceipt(
        txHash: '0xabc123',
        blockNumber: 42,
        status: true,
        logs: [],
      );
      final str = receipt.toString();
      expect(str, contains('0xabc123'));
      expect(str, contains('42'));
    });
  });
}
