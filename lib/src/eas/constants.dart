import 'dart:math';
import 'dart:typed_data';

/// EAS protocol constants.
///
/// References:
/// - [EAS SDK utils.ts](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/utils.ts#L4-L6)
/// - [EAS SDK offchain.ts](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain.ts#L133)
class EASConstants {
  /// The Ethereum zero address.
  static const String zeroAddress =
      '0x0000000000000000000000000000000000000000';

  /// A 32-byte zero value.
  static const String zeroBytes32 =
      '0x0000000000000000000000000000000000000000000000000000000000000000';

  /// Salt size in bytes for offchain attestation UID uniqueness.
  static const int saltSize = 32;

  /// The offchain attestation version we implement (Version 2 includes salt).
  static const int attestationVersion = 2;

  /// The EIP-712 domain name used by EAS.
  static const String eip712DomainName = 'EAS Attestation';

  /// Generates a cryptographically secure random salt.
  ///
  /// Uses [Random.secure] (CSPRNG) to generate [saltSize] random bytes.
  /// Reference: [EAS SDK](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain.ts#L201-L203)
  static Uint8List generateSalt() {
    final random = Random.secure();
    final salt = Uint8List(saltSize);
    for (var i = 0; i < saltSize; i++) {
      salt[i] = random.nextInt(256);
    }
    return salt;
  }

  /// Converts a salt [Uint8List] to a `0x`-prefixed hex string.
  static String saltToHex(Uint8List salt) {
    final hex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '0x$hex';
  }
}
