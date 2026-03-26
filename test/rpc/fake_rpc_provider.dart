import 'dart:async';
import 'dart:typed_data';
import 'package:on_chain/on_chain.dart' show AbiFunctionFragment;
import 'package:location_protocol/src/rpc/rpc_provider.dart';
import 'package:location_protocol/src/rpc/transaction_receipt.dart';

class FakeRpcProvider implements RpcProvider {
  final Map<String, List<dynamic>> contractCallMocks = {};
  final Map<String, TransactionReceipt> receiptMocks = {};
  final Set<String> timeoutTxHashes = {};
  Duration? lastReceiptTimeout;
  Duration? lastReceiptPollInterval;
  String? lastTransactionTo;
  Uint8List? lastTransactionData;

  @override
  String get signerAddress => '0xFakeSignerAddress';

  @override
  int get chainId => 11155111;

  @override
  Future<String> sendTransaction({
    required String to,
    required Uint8List data,
    BigInt? value,
  }) async {
    lastTransactionTo = to;
    lastTransactionData = data;
    return '0xFakeTxHash';
  }

  @override
  Future<List<dynamic>> callContract({
    required String contractAddress,
    required AbiFunctionFragment function,
    List<dynamic> params = const [],
  }) async {
    final key = function.name;
    return contractCallMocks[key] ?? [];
  }

  @override
  Future<TransactionReceipt> waitForReceipt(
    String txHash, {
    Duration? timeout,
    Duration pollInterval = const Duration(seconds: 4),
  }) async {
    lastReceiptTimeout = timeout;
    lastReceiptPollInterval = pollInterval;

    if (timeoutTxHashes.contains(txHash)) {
      final effectiveTimeout = timeout ?? const Duration(minutes: 2);
      throw TimeoutException(
        'Transaction $txHash not mined within $effectiveTimeout',
        effectiveTimeout,
      );
    }

    final receipt = receiptMocks[txHash] ??
        TransactionReceipt(
          txHash: txHash,
          blockNumber: 1,
          status: true,
          logs: const [],
        );

    if (receipt.status == false) {
      throw StateError(
        'Transaction reverted: $txHash (block ${receipt.blockNumber})',
      );
    }

    return receipt;
  }

  @override
  void close() {}
}
