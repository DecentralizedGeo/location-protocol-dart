/// Result of [EASClient.timestamp] after the transaction is mined.
///
/// Contains the transaction hash, the offchain attestation UID that was
/// anchored, and the block timestamp at which anchoring occurred.
class TimestampResult {
  /// The submitted transaction hash (`0x`-prefixed, 66 chars).
  final String txHash;

  /// The offchain attestation UID that was anchored (`0x`-prefixed, 66 chars).
  final String uid;

  /// The `block.timestamp` (uint64) at which the anchoring occurred.
  final BigInt time;

  const TimestampResult({
    required this.txHash,
    required this.uid,
    required this.time,
  });

  @override
  String toString() => 'TimestampResult(txHash: $txHash, uid: $uid, time: $time)';
}
