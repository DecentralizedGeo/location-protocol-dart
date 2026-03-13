import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

import 'http_rpc_service.dart';

/// Shared helper for building, signing, and sending Ethereum transactions.
///
/// Handles the full transaction lifecycle:
/// 1. Fetching nonce
/// 2. Gas estimation
/// 3. Fee calculation (EIP-1559 or Legacy)
/// 4. Signing with Keccak-256
/// 5. Sending raw transaction
class RpcHelper {
  final String rpcUrl;
  final int chainId;

  late final ETHPrivateKey _privateKey;
  late final EthereumProvider _provider;
  late final HttpRpcService _service;

  RpcHelper({
    required this.rpcUrl,
    required String privateKeyHex,
    required this.chainId,
  }) {
    _privateKey = ETHPrivateKey(privateKeyHex);
    _service = HttpRpcService(rpcUrl);
    _provider = EthereumProvider(_service);
  }

  /// The sender's Ethereum address derived from the private key.
  ETHAddress get senderAddress =>
      _privateKey.publicKey().toAddress();

  /// Sends a contract-calling transaction and returns the tx hash.
  ///
  /// [to] is the contract address.
  /// [data] is the ABI-encoded call data (with function selector).
  /// [value] is the ETH value to send (default 0).
  Future<String> sendTransaction({
    required String to,
    required Uint8List data,
    BigInt? value,
  }) async {
    final fromAddress = senderAddress;
    final toAddress = ETHAddress(to);
    final chainIdBig = BigInt.from(chainId);

    // 1. Fetch Nonce
    final nonce = await _provider.request(
      EthereumRequestGetTransactionCount(address: fromAddress.address),
    );

    // 2. Fetch Fee Info (prefer EIP-1559)
    ETHTransactionType txType = ETHTransactionType.legacy;
    BigInt? gasPrice;
    BigInt? maxFeePerGas;
    BigInt? maxPriorityFeePerGas;

    final feeHistory = await _provider.request(
      EthereumRequestGetFeeHistory(
        blockCount: 1,
        newestBlock: BlockTagOrNumber.latest,
        rewardPercentiles: [50],
      ),
    ).catchError((_) => null);

    if (feeHistory != null) {
      txType = ETHTransactionType.eip1559;
      final fee = feeHistory.toFee();
      maxPriorityFeePerGas = fee.normal;
      maxFeePerGas = fee.normal + fee.baseFee;
    } else {
      gasPrice = await _provider.request(EthereumRequestGetGasPrice());
    }

    // 3. Estimate Gas
    // Create a temporary transaction for estimation
    final estimateTx = ETHTransaction(
      type: txType,
      from: fromAddress,
      to: toAddress,
      nonce: nonce,
      gasLimit: BigInt.from(30000000), // high limit for estimation
      gasPrice: gasPrice,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      data: data,
      value: value ?? BigInt.zero,
      chainId: chainIdBig,
    );

    final gasLimit = await _provider.request(
      EthereumRequestEstimateGas(transaction: estimateTx.toEstimate()),
    );

    // 4. Build Final Transaction
    final tx = ETHTransaction(
      type: txType,
      from: fromAddress,
      to: toAddress,
      nonce: nonce,
      gasLimit: gasLimit,
      gasPrice: gasPrice,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      data: data,
      value: value ?? BigInt.zero,
      chainId: chainIdBig,
    );

    // 5. Sign and Send
    final signature = _privateKey.sign(tx.serialized);
    final signedRaw = tx.signedSerialized(signature);
    
    return await _provider.request(
      EthereumRequestSendRawTransaction(
        transaction: BytesUtils.toHexString(signedRaw, prefix: '0x'),
      ),
    );
  }

  /// Performs an `eth_call` (read-only) against a contract.
  ///
  /// Returns the decoded ABI output.
  Future<List<dynamic>> callContract({
    required String contractAddress,
    required AbiFunctionFragment function,
    List<dynamic> params = const [],
  }) async {
    return await _provider.request(
      EthereumRequestFunctionCall(
        contractAddress: contractAddress,
        function: function,
        params: params,
      ),
    );
  }

  /// Closes the underlying HTTP client.
  void close() {
    _service.close();
  }
}
