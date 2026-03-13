import 'package:test/test.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';

void main() {
  group('EASClient', () {
    test('constructs with required parameters', () {
      final client = EASClient(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(client.chainId, equals(11155111));
    });

    test('resolves EAS address from ChainConfig', () {
      final client = EASClient(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(client.easAddress, startsWith('0x'));
    });

    test('accepts custom EAS address', () {
      final client = EASClient(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
        easAddress: '0xCustomEAS',
      );
      expect(client.easAddress, equals('0xCustomEAS'));
    });

    test('buildTimestampCallData produces non-empty bytes', () {
      final callData = EASClient.buildTimestampCallData(
        '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
      );
      expect(callData, isNotEmpty);
    });
  });
}
