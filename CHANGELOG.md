# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-08

### Added
- Initial release of `location_protocol`.
- LP payload creation and validation for 9 canonical location types.
- Strict EAS offchain attestation envelope with enhanced validation
- EAS version support in chain configuration with dynamic resolution
- EIP-712 offchain signing and verification for EAS.
- Offchain attestation version verification capabilities
- Enhanced offchain attestation verification with improved flexibility
- Dynamic schema support for user-data attestations and flexible builders
- Abstract `Signer` interface for custom signing implementations
- RPC polling for UID recovery from attestation receipts
- Cross-chain UID computation standardization and parity verification
- VerificationFailure enum and error codes for detailed verification diagnostics
- `create_offchain_attestation` utility script for testing and development
- Documentation snippet validation tests
- Integration guides for Proofmode Android and mobile app development
- Support for 21 Ethereum-compatible networks.
