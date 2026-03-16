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
/// Reference: https://github.com/ethereum-attestation-service/eas-contracts#deployments
///
/// Addresses are sourced directly from the official EAS contracts repository.
/// Deprecated Goerli-based testnets (Optimism Goerli, Base Goerli, Linea Goerli)
/// are intentionally omitted — Goerli was shut down in 2023.
class ChainConfig {
  static const Map<int, ChainAddresses> _chains = {
    // ── Mainnets ─────────────────────────────────────────────────────────────

    // Ethereum Mainnet — v0.26
    1: ChainAddresses(
      eas: '0xA1207F3BBa224E2c9c3c6D5aF63D0eb1582Ce587',
      schemaRegistry: '0xA7b39296258348C78294F95B872b282326A97BDF',
      chainName: 'Ethereum Mainnet',
    ),
    // Optimism — v1.0.1
    10: ChainAddresses(
      eas: '0x4200000000000000000000000000000000000021',
      schemaRegistry: '0x4200000000000000000000000000000000000020',
      chainName: 'Optimism',
    ),
    // Telos — v1.4.0
    40: ChainAddresses(
      eas: '0x9898C3FF2fdCA9E734556fC4BCCd5b9239218155',
      schemaRegistry: '0x842511adC21B85C0B2fdB02AAcFA92fdf7Cda470',
      chainName: 'Telos',
    ),
    // Unichain — v1.4.1-beta.1
    130: ChainAddresses(
      eas: '0x4200000000000000000000000000000000000021',
      schemaRegistry: '0x4200000000000000000000000000000000000020',
      chainName: 'Unichain',
    ),
    // Polygon — v1.3.0
    137: ChainAddresses(
      eas: '0x5E634ef5355f45A855d02D66eCD687b1502AF790',
      schemaRegistry: '0x7876EEF51A891E737AF8ba5A5E0f0Fd29073D5a7',
      chainName: 'Polygon',
    ),
    // Base — v1.0.1
    8453: ChainAddresses(
      eas: '0x4200000000000000000000000000000000000021',
      schemaRegistry: '0x4200000000000000000000000000000000000020',
      chainName: 'Base',
    ),
    // Arbitrum One — v0.26
    42161: ChainAddresses(
      eas: '0xbD75f629A22Dc1ceD33dDA0b68c546A1c035c458',
      schemaRegistry: '0xA310da9c5B885E7fb3fbA9D66E9Ba6Df512b78eB',
      chainName: 'Arbitrum One',
    ),
    // Arbitrum Nova — v1.3.0
    42170: ChainAddresses(
      eas: '0x6d3dC0Fe5351087E3Af3bDe8eB3F7350ed894fc3',
      schemaRegistry: '0x49563d0DA8DF38ef2eBF9C1167270334D72cE0AE',
      chainName: 'Arbitrum Nova',
    ),
    // Celo — v1.3.0
    42220: ChainAddresses(
      eas: '0x72E1d8ccf5299fb36fEfD8CC4394B8ef7e98Af92',
      schemaRegistry: '0x5ece93bE4BDCF293Ed61FA78698B594F2135AF34',
      chainName: 'Celo',
    ),
    // Linea — v1.2.0
    59144: ChainAddresses(
      eas: '0xaEF4103A04090071165F78D45D83A0C0782c2B2a',
      schemaRegistry: '0x55D26f9ae0203EF95494AE4C170eD35f4Cf77797',
      chainName: 'Linea',
    ),
    // Blast — v1.3.0
    81457: ChainAddresses(
      eas: '0x4200000000000000000000000000000000000021',
      schemaRegistry: '0x4200000000000000000000000000000000000020',
      chainName: 'Blast',
    ),
    // Scroll — v1.3.0
    534352: ChainAddresses(
      eas: '0xC47300428b6AD2c7D03BB76D05A176058b47E6B0',
      schemaRegistry: '0xD2CDF46556543316e7D34e8eDc4624e2bB95e3B6',
      chainName: 'Scroll',
    ),
    // Soneium — v1.4.1-beta.1
    1868: ChainAddresses(
      eas: '0x4200000000000000000000000000000000000021',
      schemaRegistry: '0x4200000000000000000000000000000000000020',
      chainName: 'Soneium',
    ),
    // Ink — v1.4.1-beta.1
    57073: ChainAddresses(
      eas: '0x4200000000000000000000000000000000000021',
      schemaRegistry: '0x4200000000000000000000000000000000000020',
      chainName: 'Ink',
    ),

    // ── Testnets ──────────────────────────────────────────────────────────────

    // Sepolia — v0.26
    11155111: ChainAddresses(
      eas: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      schemaRegistry: '0x0a7E2Ff54e76B8E6659aedc9103FB21c038050D0',
      chainName: 'Sepolia',
    ),
    // Optimism Sepolia — v1.0.2
    11155420: ChainAddresses(
      eas: '0x4200000000000000000000000000000000000021',
      schemaRegistry: '0x4200000000000000000000000000000000000020',
      chainName: 'Optimism Sepolia',
    ),
    // Arbitrum Sepolia — v1.3.0
    421614: ChainAddresses(
      eas: '0x2521021fc8BF070473E1e1801D3c7B4aB701E1dE',
      schemaRegistry: '0x45CB6Fa0870a8Af06796Ac15915619a0f22cd475',
      chainName: 'Arbitrum Sepolia',
    ),
    // Base Sepolia — v1.2.0
    84532: ChainAddresses(
      eas: '0x4200000000000000000000000000000000000021',
      schemaRegistry: '0x4200000000000000000000000000000000000020',
      chainName: 'Base Sepolia',
    ),
    // Polygon Amoy — v1.3.0
    80002: ChainAddresses(
      eas: '0xb101275a60d8bfb14529C421899aD7CA1Ae5B5Fc',
      schemaRegistry: '0x23c5701A1BDa89C61d181BD79E5203c730708AE7',
      chainName: 'Polygon Amoy',
    ),
    // Scroll Sepolia — v1.3.0
    534351: ChainAddresses(
      eas: '0xaEF4103A04090071165F78D45D83A0C0782c2B2a',
      schemaRegistry: '0x55D26f9ae0203EF95494AE4C170eD35f4Cf77797',
      chainName: 'Scroll Sepolia',
    ),
    // Ink Sepolia — v1.4.1-beta.1
    763373: ChainAddresses(
      eas: '0x4200000000000000000000000000000000000021',
      schemaRegistry: '0x4200000000000000000000000000000000000020',
      chainName: 'Ink Sepolia',
    ),
  };

  /// Get config for a chain ID, or null if unknown.
  static ChainAddresses? forChainId(int chainId) => _chains[chainId];

  /// All supported chain IDs.
  static List<int> get supportedChainIds => _chains.keys.toList();
}
