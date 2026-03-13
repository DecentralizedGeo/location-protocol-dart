/// Result of verifying an offchain attestation signature.
class VerificationResult {
  /// Whether the signature is valid and the UID matches.
  final bool isValid;

  /// The Ethereum address recovered from the signature.
  final String recoveredAddress;

  /// If invalid, the reason for failure.
  final String? reason;

  const VerificationResult({
    required this.isValid,
    required this.recoveredAddress,
    this.reason,
  });
}
