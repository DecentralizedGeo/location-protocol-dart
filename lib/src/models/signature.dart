import 'package:blockchain_utils/blockchain_utils.dart';

/// An EIP-712 ECDSA signature with v, r, s components.
class EIP712Signature {
  /// Recovery id (27 or 28).
  final int v;

  /// The r component as a hex string.
  final String r;

  /// The s component as a hex string.
  final String s;

  const EIP712Signature({
    required this.v,
    required this.r,
    required this.s,
  });

  /// Parses a raw 65-byte EIP-712 signature hex string into [v], [r], [s].
  ///
  /// Wallets (MetaMask, Privy, WalletConnect) return `eth_signTypedData_v4`
  /// results as a single `0x`-prefixed 65-byte hex string in the layout
  /// `r[32] || s[32] || v[1]`.
  ///
  /// Throws [ArgumentError] if [rawSig] does not decode to exactly 65 bytes.
  factory EIP712Signature.fromHex(String rawSig) {
    final hex = rawSig.startsWith('0x') ? rawSig.substring(2) : rawSig;

    if (hex.isEmpty) {
      throw ArgumentError.value(rawSig, 'rawSig', 'Signature hex must not be empty');
    }

    final bytes = BytesUtils.fromHexString(hex);

    if (bytes.length != 65) {
      throw ArgumentError.value(
        rawSig,
        'rawSig',
        'Expected 65-byte signature, got ${bytes.length} bytes',
      );
    }

    final r = bytes.sublist(0, 32);
    final s = bytes.sublist(32, 64);
    final v = bytes[64];

    return EIP712Signature(
      v: v,
      r: '0x${BytesUtils.toHexString(r).padLeft(64, '0')}',
      s: '0x${BytesUtils.toHexString(s).padLeft(64, '0')}',
    );
  }
}
