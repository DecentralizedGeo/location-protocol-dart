/// Result of [SchemaRegistryClient.register] after the transaction is broadcast.
///
/// The UID is computed locally via [SchemaUID.compute] — no receipt polling needed.
class RegisterResult {
  /// The submitted transaction hash (`0x`-prefixed, 66 chars), or `null` if the
  /// schema already existed on-chain and no transaction was sent.
  ///
  /// Check [alreadyExisted] to distinguish between a new registration and a
  /// no-op early return.
  final String? txHash;

  /// The deterministic schema UID (`0x`-prefixed, 66 chars).
  final String uid;

  const RegisterResult({
    required this.txHash,
    required this.uid,
  });

  /// Whether the schema already existed on-chain.
  ///
  /// `true` when [SchemaRegistryClient.register] detected the schema was already
  /// registered and returned early without broadcasting a transaction.
  bool get alreadyExisted => txHash == null;

  @override
  String toString() => 'RegisterResult(txHash: $txHash, uid: $uid)';
}
