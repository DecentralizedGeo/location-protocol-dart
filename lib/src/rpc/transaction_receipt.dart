/// A single event log entry from a transaction receipt.
///
/// Insulated from `on_chain` internals — constructed by
/// [DefaultRpcProvider.waitForReceipt] from the raw RPC response.
class TransactionLog {
  /// The contract address that emitted the event.
  final String address;

  /// Event topics. `topics[0]` is the keccak256 event signature hash.
  final List<String> topics;

  /// Hex-encoded non-indexed event parameters.
  final String data;

  const TransactionLog({
    required this.address,
    required this.topics,
    required this.data,
  });

  @override
  String toString() => 'TransactionLog(address: $address, '
      'topics: [${topics.length}], data: ${data.length > 10 ? '${data.substring(0, 10)}...' : data})';
}

/// A minimal transaction receipt, insulated from `on_chain` internals.
///
/// Constructed by [DefaultRpcProvider.waitForReceipt] after polling
/// `eth_getTransactionReceipt` until the transaction is mined.
class TransactionReceipt {
  /// The transaction hash.
  final String txHash;

  /// The block number in which the transaction was mined.
  final int blockNumber;

  /// `true` = success, `false` = reverted, `null` = pre-Byzantium.
  final bool? status;

  /// Event logs emitted during the transaction.
  final List<TransactionLog> logs;

  const TransactionReceipt({
    required this.txHash,
    required this.blockNumber,
    required this.status,
    required this.logs,
  });

  @override
  String toString() => 'TransactionReceipt(txHash: $txHash, '
      'block: $blockNumber, status: $status, logs: [${logs.length}])';
}
