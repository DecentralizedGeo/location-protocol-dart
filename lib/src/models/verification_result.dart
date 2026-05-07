/// Strict failure categories for offchain verification.
enum VerificationFailure {
  uidMismatch,
  invalidDomain,
  invalidPrimaryType,
  invalidTypes,
  invalidMessage,
  invalidSignature,
  signerMismatch,
}

/// Result of verifying an offchain attestation signature.
class VerificationResult {
  /// Whether the signature is valid and the UID matches.
  final bool isValid;

  /// The Ethereum address recovered from the signature.
  final String recoveredAddress;

  /// A structured failure category, when verification fails.
  final VerificationFailure? code;

  /// If invalid, the reason for failure.
  final String? reason;

  const VerificationResult({
    required this.isValid,
    required this.recoveredAddress,
    this.code,
    this.reason,
  });
}
