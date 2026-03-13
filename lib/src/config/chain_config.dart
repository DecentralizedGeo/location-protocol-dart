/// Contract addresses for a specific EVM chain.
class ChainAddresses {
  /// The EAS contract address.
  final String eas;

  /// The SchemaRegistry contract address.
  final String schemaRegistry;

  /// Human-readable chain name.
  final String chainName;

  const ChainAddresses({
    required this.eas,
    required this.schemaRegistry,
    required this.chainName,
  });
}

/// Known EAS contract addresses per chain.
///
/// Reference: [EAS Deployments](https://docs.attest.org/docs/quick--start/contracts)
class ChainConfig {
  static const Map<int, ChainAddresses> _chains = {
    // Ethereum Mainnet
    1: ChainAddresses(
      eas: '0xA1207F3BBa224E2c9c3c6D5aF63D0eb1582Ce587',
      schemaRegistry: '0xA7b39296258348C78294F95B872b282326A97BDF',
      chainName: 'Ethereum Mainnet',
    ),
    // Sepolia Testnet
    11155111: ChainAddresses(
      eas: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      schemaRegistry: '0x0a7E2Ff54e76B8E6659aedc9103FB21c038050D0',
      chainName: 'Sepolia',
    ),
    // Base Mainnet
    8453: ChainAddresses(
      eas: '0x4200000000000000000000000000000000000021',
      schemaRegistry: '0x4200000000000000000000000000000000000020',
      chainName: 'Base',
    ),
    // Arbitrum One
    42161: ChainAddresses(
      eas: '0xbD75f629A22Dc1ceD33dDA0b68c546A1c035c458',
      schemaRegistry: '0xA310da9c5B885E7fb3fbA9D66E9Ba6Df512b78eB',
      chainName: 'Arbitrum One',
    ),
  };

  /// Get config for a chain ID, or null if unknown.
  static ChainAddresses? forChainId(int chainId) => _chains[chainId];

  /// All supported chain IDs.
  static List<int> get supportedChainIds => _chains.keys.toList();
}
