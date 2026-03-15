/// Result of [SchemaRegistryClient.register] after the transaction is broadcast.
///
/// The UID is computed locally via [SchemaUID.compute] — no receipt polling needed.
class RegisterResult {
  /// The submitted transaction hash (`0x`-prefixed, 66 chars).
  final String txHash;

  /// The deterministic schema UID (`0x`-prefixed, 66 chars).
  final String uid;

  const RegisterResult({
    required this.txHash,
    required this.uid,
  });

  @override
  String toString() => 'RegisterResult(txHash: $txHash, uid: $uid)';
}
