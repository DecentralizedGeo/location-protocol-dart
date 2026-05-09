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
        easVersion: '1.0.0',
      );
      expect(config.eas, equals('0xCustomEAS'));
      expect(config.chainName, equals('My Testnet'));
      expect(config.easVersion, equals('1.0.0'));
    });

    test('supportedChainIds returns known chain IDs', () {
      final ids = ChainConfig.supportedChainIds;
      expect(ids, contains(1));
      expect(ids, contains(11155111));
    });

    test('has config for all active EAS mainnet deployments', () {
      // Mainnets sourced from:
      // https://github.com/ethereum-attestation-service/eas-contracts#deployments
      const mainnets = {
        1: 'Ethereum Mainnet',
        10: 'Optimism',
        40: 'Telos',
        130: 'Unichain',
        137: 'Polygon',
        1868: 'Soneium',
        8453: 'Base',
        42161: 'Arbitrum One',
        42170: 'Arbitrum Nova',
        42220: 'Celo',
        57073: 'Ink',
        59144: 'Linea',
        81457: 'Blast',
        534352: 'Scroll',
      };
      for (final entry in mainnets.entries) {
        final config = ChainConfig.forChainId(entry.key);
        expect(config, isNotNull, reason: 'Missing config for chain ${entry.key} (${entry.value})');
        expect(config!.eas, startsWith('0x'), reason: 'Bad EAS address for ${entry.value}');
        expect(config.schemaRegistry, startsWith('0x'), reason: 'Bad registry address for ${entry.value}');
        expect(config.chainName, equals(entry.value), reason: 'Wrong chainName for chain ${entry.key}');
      }
    });

    test('has config for all active EAS testnet deployments', () {
      // Testnets sourced from:
      // https://github.com/ethereum-attestation-service/eas-contracts#deployments
      // Deprecated Goerli-based testnets are intentionally excluded.
      const testnets = {
        11155111: 'Sepolia',
        11155420: 'Optimism Sepolia',
        84532: 'Base Sepolia',
        80002: 'Polygon Amoy',
        421614: 'Arbitrum Sepolia',
        534351: 'Scroll Sepolia',
        763373: 'Ink Sepolia',
      };
      for (final entry in testnets.entries) {
        final config = ChainConfig.forChainId(entry.key);
        expect(config, isNotNull, reason: 'Missing config for chain ${entry.key} (${entry.value})');
        expect(config!.eas, startsWith('0x'), reason: 'Bad EAS address for ${entry.value}');
        expect(config.schemaRegistry, startsWith('0x'), reason: 'Bad registry address for ${entry.value}');
        expect(config.chainName, equals(entry.value), reason: 'Wrong chainName for chain ${entry.key}');
      }
    });

    group('easVersion', () {
      test('Sepolia is 0.26', () {
        expect(ChainConfig.forChainId(11155111)!.easVersion, equals('0.26'));
      });

      test('Ethereum Mainnet is 0.26', () {
        expect(ChainConfig.forChainId(1)!.easVersion, equals('0.26'));
      });

      test('Arbitrum One is 0.26', () {
        expect(ChainConfig.forChainId(42161)!.easVersion, equals('0.26'));
      });

      test('Optimism is 1.0.1', () {
        expect(ChainConfig.forChainId(10)!.easVersion, equals('1.0.1'));
      });

      test('Base is 1.0.1', () {
        expect(ChainConfig.forChainId(8453)!.easVersion, equals('1.0.1'));
      });

      test('Optimism Sepolia is 1.0.2', () {
        expect(ChainConfig.forChainId(11155420)!.easVersion, equals('1.0.2'));
      });

      test('Linea is 1.2.0', () {
        expect(ChainConfig.forChainId(59144)!.easVersion, equals('1.2.0'));
      });

      test('Base Sepolia is 1.2.0', () {
        expect(ChainConfig.forChainId(84532)!.easVersion, equals('1.2.0'));
      });

      test('Polygon is 1.3.0', () {
        expect(ChainConfig.forChainId(137)!.easVersion, equals('1.3.0'));
      });

      test('Telos is 1.4.0', () {
        expect(ChainConfig.forChainId(40)!.easVersion, equals('1.4.0'));
      });

      test('Unichain is 1.4.1-beta.1', () {
        expect(ChainConfig.forChainId(130)!.easVersion, equals('1.4.1-beta.1'));
      });

      test('all supported chains have a non-empty easVersion', () {
        for (final chainId in ChainConfig.supportedChainIds) {
          final config = ChainConfig.forChainId(chainId)!;
          expect(
            config.easVersion,
            isNotEmpty,
            reason: 'easVersion is empty for chain $chainId (${config.chainName})',
          );
        }
      });
    });
  });
}
