import 'package:test/test.dart';
import 'package:on_chain/on_chain.dart';
import 'package:location_protocol/src/rpc/rpc_helper.dart';

void main() {
  group('RpcHelper', () {
    test('constructs with required parameters', () {
      final helper = RpcHelper(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(helper.chainId, equals(11155111));
    });

    test('derives sender address from private key', () {
      final helper = RpcHelper(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      // Hardhat account #0 address
      expect(helper.senderAddress.address.toLowerCase(),
          equals('0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266'));
    });
  });
}
