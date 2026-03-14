import 'dart:typed_data';
import 'package:on_chain/on_chain.dart';

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
  
  /// Closes underlying resources.
  void close();
}
