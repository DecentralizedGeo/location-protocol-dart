import 'dart:async';

import 'package:test/test.dart';
import 'package:location_protocol/src/rpc/transaction_receipt.dart';
import 'fake_rpc_provider.dart';

void main() {
  group('FakeRpcProvider.waitForReceipt', () {
    test('returns default receipt when no mock configured', () async {
      final provider = FakeRpcProvider();
      final receipt = await provider.waitForReceipt('0xabc');
      expect(receipt.txHash, equals('0xabc'));
      expect(receipt.blockNumber, equals(1));
      expect(receipt.status, isTrue);
      expect(receipt.logs, isEmpty);
    });

    test('returns mocked receipt when configured', () async {
      final provider = FakeRpcProvider();
      provider.receiptMocks['0xabc'] = TransactionReceipt(
        txHash: '0xabc',
        blockNumber: 42,
        status: true,
        logs: [
          TransactionLog(
            address: '0xContractAddr',
            topics: ['0xTopic0'],
            data: '0xData',
          ),
        ],
      );

      final receipt = await provider.waitForReceipt('0xabc');
      expect(receipt.blockNumber, equals(42));
      expect(receipt.logs, hasLength(1));
      expect(receipt.logs.first.address, equals('0xContractAddr'));
    });

    test('throws TimeoutException for configured pending transaction', () {
      final provider = FakeRpcProvider();
      provider.timeoutTxHashes.add('0xpending');

      expect(
        () => provider.waitForReceipt(
          '0xpending',
          timeout: const Duration(seconds: 3),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('throws StateError for reverted mocked receipt', () {
      final provider = FakeRpcProvider();
      provider.receiptMocks['0xreverted'] = const TransactionReceipt(
        txHash: '0xreverted',
        blockNumber: 7,
        status: false,
        logs: [],
      );

      expect(
        () => provider.waitForReceipt('0xreverted'),
        throwsStateError,
      );
    });
  });
}
