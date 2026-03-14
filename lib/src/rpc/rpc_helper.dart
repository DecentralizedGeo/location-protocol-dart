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
  ETHAddress get senderAddress => _privateKey.publicKey().toAddress();

  /// Canonical RLP encoding of a BigInt — returns `[]` for zero.
  ///
  /// `blockchain_utils` v6+ `BigintUtils.bitlengthInBytes(BigInt.zero)` returns 1
  /// instead of 0, causing `BigintUtils.toBytes(BigInt.zero)` to produce `[0x00]`.
  /// The RLP encoder then emits byte `0x00` (single byte ≤ 0x7F → pass-through)
  /// instead of `0x80` (empty byte string), which is non-canonical and rejected by
  /// Geth's EIP-1559 transaction decoder with:
  ///   "rlp: non-canonical integer (leading zero bytes) for *big.Int"
  ///
  /// This helper returns `[]` for zero so the RLP encoder produces `0x80` (correct).
  static List<int> _canonicalBigIntBytes(BigInt value) {
    if (value == BigInt.zero) return <int>[];
    return BigintUtils.toBytes(
      value,
      length: BigintUtils.bitlengthInBytes(value),
    );
  }

  /// Builds canonical EIP-1559 RLP bytes (unsigned or signed).
  ///
  /// Bypasses [ETHTransaction.serialized] / [ETHTransaction.signedSerialized]
  /// to avoid the upstream `bigintToBytes(BigInt.zero)` non-canonical encoding.
  List<int> _buildEip1559Bytes({
    required BigInt chainId,
    required int nonce,
    required BigInt maxPriorityFeePerGas,
    required BigInt maxFeePerGas,
    required BigInt gasLimit,
    required ETHAddress to,
    required BigInt value,
    required List<int> data,
    ETHSignature? sig,
  }) {
    final fields = <List<dynamic>>[
      ETHTransactionUtils.bigintToBytes(chainId),
      ETHTransactionUtils.intToBytes(nonce),
      ETHTransactionUtils.bigintToBytes(maxPriorityFeePerGas),
      ETHTransactionUtils.bigintToBytes(maxFeePerGas),
      ETHTransactionUtils.bigintToBytes(gasLimit),
      to.toBytes(),
      _canonicalBigIntBytes(value), // ← fixed zero-value encoding
      data,
      <dynamic>[], // access list (empty)
    ];
    if (sig != null) {
      fields.add(ETHTransactionUtils.intToBytes(ETHTransactionUtils.parity(sig.v)));
      fields.add(ETHTransactionUtils.trimLeadingZero(sig.rBytes));
      fields.add(ETHTransactionUtils.trimLeadingZero(sig.sBytes));
    }
    return [ETHTransactionType.eip1559.prefix, ...RLPEncoder.encode(fields)];
  }

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
    final txValue = value ?? BigInt.zero;

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
      try {
        final fee = feeHistory.toFee();
        txType = ETHTransactionType.eip1559;
        maxPriorityFeePerGas = fee.normal;
        maxFeePerGas = fee.normal + fee.baseFee;
      } catch (e) {
        // Fallback to manual EIP-1559 if FeeHistory.toFee() crashes
        // (e.g., empty reward array on Infura Sepolia).
        txType = ETHTransactionType.eip1559;
        maxPriorityFeePerGas = BigInt.from(1000000000); // 1 gwei
        final baseFee = feeHistory.baseFeePerGas.isNotEmpty
            ? feeHistory.baseFeePerGas.first
            : BigInt.zero;
        maxFeePerGas = baseFee * BigInt.two + maxPriorityFeePerGas;
      }
    } else {
      gasPrice = await _provider.request(EthereumRequestGetGasPrice());
    }

    // 3. Estimate Gas — use ETHTransaction only for the estimate call (no
    //    signing involved, so the non-canonical value encoding is harmless here).
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
      value: txValue,
      chainId: chainIdBig,
    );

    final gasLimit = await _provider.request(
      EthereumRequestEstimateGas(transaction: estimateTx.toEstimate()),
    );

    // 4. Sign and Send — use canonical EIP-1559 bytes to avoid the
    //    blockchain_utils v6 non-canonical zero encoding bug.
    if (txType == ETHTransactionType.eip1559) {
      final unsignedBytes = _buildEip1559Bytes(
        chainId: chainIdBig,
        nonce: nonce,
        maxPriorityFeePerGas: maxPriorityFeePerGas!,
        maxFeePerGas: maxFeePerGas!,
        gasLimit: gasLimit,
        to: toAddress,
        value: txValue,
        data: data,
      );
      final signature = _privateKey.sign(unsignedBytes);
      final signedBytes = _buildEip1559Bytes(
        chainId: chainIdBig,
        nonce: nonce,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        maxFeePerGas: maxFeePerGas,
        gasLimit: gasLimit,
        to: toAddress,
        value: txValue,
        data: data,
        sig: signature,
      );
      return await _provider.request(
        EthereumRequestSendRawTransaction(
          transaction: BytesUtils.toHexString(signedBytes, prefix: '0x'),
        ),
      );
    }

    // Legacy fallback (gasPrice path)
    final tx = ETHTransaction(
      type: txType,
      from: fromAddress,
      to: toAddress,
      nonce: nonce,
      gasLimit: gasLimit,
      gasPrice: gasPrice,
      data: data,
      value: txValue,
      chainId: chainIdBig,
    );
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
