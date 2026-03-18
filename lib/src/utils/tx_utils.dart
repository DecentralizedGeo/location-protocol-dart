import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';

/// Utilities for building wallet-friendly Ethereum transaction requests.
class TxUtils {
  /// Packages an ABI-encoded [data] byte array into a standard Ethereum
  /// transaction request map.
  ///
  /// This map corresponds directly to the JSON-RPC payload required for
  /// `eth_sendTransaction` and integrates easily with wallet SDKs (MetaMask, etc.).
  static Map<String, dynamic> buildTxRequest({
    required String to,
    required Uint8List data,
    String? from,
    BigInt? value,
  }) {
    return {
      if (from != null) 'from': from,
      'to': to,
      'data': '0x${BytesUtils.toHexString(data)}',
      'value': value != null ? '0x${value.toRadixString(16)}' : '0x0',
    };
  }
}
