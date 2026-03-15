/// Result of [EASClient.attest] after the transaction is mined.
///
/// Contains the transaction hash, the attestation UID extracted from
/// the `Attested` event log, and the block number.
class AttestResult {
  /// The submitted transaction hash (`0x`-prefixed, 66 chars).
  final String txHash;

  /// The keccak256 UID of the new onchain attestation (`0x`-prefixed, 66 chars).
  final String uid;

  /// The block number in which the transaction was mined.
  final int blockNumber;

  const AttestResult({
    required this.txHash,
    required this.uid,
    required this.blockNumber,
  });

  @override
  String toString() => 'AttestResult(txHash: $txHash, uid: $uid, block: $blockNumber)';
}
