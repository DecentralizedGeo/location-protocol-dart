import 'package:test/test.dart';
import 'package:location_protocol/src/config/chain_config.dart';

void main() {
  group('ChainConfig', () {
    test('has Sepolia config', () {
      final config = ChainConfig.forChainId(11155111);
      expect(config, isNotNull);
      expect(config!.eas, startsWith('0x'));
      expect(config.schemaRegistry, startsWith('0x'));
      expect(config.chainName, equals('Sepolia'));
    });

    test('has Ethereum Mainnet config', () {
      final config = ChainConfig.forChainId(1);
      expect(config, isNotNull);
      expect(config!.chainName, equals('Ethereum Mainnet'));
    });

    test('returns null for unknown chain', () {
      final config = ChainConfig.forChainId(999999);
      expect(config, isNull);
    });

    test('custom chain config can be created', () {
      final config = ChainAddresses(
        eas: '0xCustomEAS',
        schemaRegistry: '0xCustomRegistry',
        chainName: 'My Testnet',
      );
      expect(config.eas, equals('0xCustomEAS'));
      expect(config.chainName, equals('My Testnet'));
    });

    test('supportedChainIds returns known chain IDs', () {
      final ids = ChainConfig.supportedChainIds;
      expect(ids, contains(1));
      expect(ids, contains(11155111));
    });
  });
}
