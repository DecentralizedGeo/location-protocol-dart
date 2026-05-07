/// Structured failure category for offchain attestation verification.
enum VerificationFailure {
  /// The recomputed UID does not match the stored UID.
  uidMismatch,

  /// The preserved EIP-712 domain does not match the signer's configuration.
  invalidDomain,

  /// The `primaryType` is not `'Attest'`.
  invalidPrimaryType,

  /// The `types` map does not match the canonical Attest field list.
  invalidTypes,

  /// The v2 `salt` field is absent from the `message` map.
  missingSalt,

  /// The signer address cannot be recovered from the signature.
  invalidSignature,

  /// The recovered signer address does not match `attestation.signer`.
  signerMismatch,
}

/// Result of verifying an offchain attestation signature.
class VerificationResult {
  /// Whether the signature is valid and the UID matches.
  final bool isValid;

  /// The Ethereum address recovered from the signature.
  ///
  /// Empty string (`''`) for failures that occur before signature recovery
  /// (e.g. [VerificationFailure.uidMismatch], [VerificationFailure.invalidDomain]).
  /// Always check [isValid] before using this value.
  final String recoveredAddress;

  /// Structured failure category. `null` when [isValid] is `true`.
  final VerificationFailure? code;

  /// Human-readable reason for failure. `null` when [isValid] is `true`.
  final String? reason;

  const VerificationResult({
    required this.isValid,
    required this.recoveredAddress,
    this.code,
    this.reason,
  });
}
