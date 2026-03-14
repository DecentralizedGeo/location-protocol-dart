import 'dart:typed_data';
import 'package:on_chain/on_chain.dart';
import 'package:location_protocol/src/rpc/rpc_provider.dart';

class FakeRpcProvider implements RpcProvider {
  final Map<String, List<dynamic>> contractCallMocks = {};
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
  void close() {}
}
