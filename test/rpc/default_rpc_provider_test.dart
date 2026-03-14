import 'package:test/test.dart';
import 'package:on_chain/on_chain.dart';
import 'package:location_protocol/src/rpc/default_rpc_provider.dart';
import 'package:location_protocol/src/rpc/rpc_provider.dart';

void main() {
  group('DefaultRpcProvider', () {
    test('constructs with required parameters and implements RpcProvider', () {
      final helper = DefaultRpcProvider(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(helper.chainId, equals(11155111));
      expect(helper, isA<RpcProvider>());
    });

    test('derives sender address from private key', () {
      final helper = DefaultRpcProvider(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      // Hardhat account #0 address
      expect(helper.signerAddress.toLowerCase(),
          equals('0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266'));
    });
  });
}
