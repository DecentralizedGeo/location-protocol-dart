import 'dart:typed_data';
import 'package:on_chain/on_chain.dart' show AbiFunctionFragment;

import 'transaction_receipt.dart';

/// Abstract interface for on-chain state queries and transaction submission.
abstract class RpcProvider {
  /// The Ethereum address of the configured signer.
  String get signerAddress;

  /// The Chain ID the provider is connected to.
  int get chainId;

  /// Sends a signed transaction to the given contract address.
  Future<String> sendTransaction({
    required String to,
    required Uint8List data,
    BigInt? value,
  });

  /// Executes a read-only `eth_call` against a contract.
  Future<List<dynamic>> callContract({
    required String contractAddress,
    required AbiFunctionFragment function,
    List<dynamic> params = const [],
  });

  /// Polls `eth_getTransactionReceipt` until the transaction is mined,
  /// then returns a typed receipt.
  ///
  /// Throws [TimeoutException] if [timeout] elapses before the tx is mined.
  Future<TransactionReceipt> waitForReceipt(
    String txHash, {
    Duration? timeout,
    Duration pollInterval = const Duration(seconds: 4),
  });
  
  /// Closes underlying resources.
  void close();
}
