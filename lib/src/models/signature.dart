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
}
