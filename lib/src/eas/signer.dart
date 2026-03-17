import 'dart:typed_data';
import 'package:on_chain/on_chain.dart';
import '../models/signature.dart';

/// Abstract base class for EIP-712 signing.
///
/// Implementations can wrap raw private keys ([LocalKeySigner]), hardware
/// security modules, or wallet providers (Privy, MetaMask, WalletConnect).
///
/// ## Implementing a wallet adapter
///
/// Override [signTypedData] to call `eth_signTypedData_v4` via your wallet
/// SDK and use [EIP712Signature.fromHex] to parse the result:
///
/// ```dart
/// class MyWalletSigner extends Signer {
///   @override
///   String get address => _wallet.address;
///
///   @override
///   Future<EIP712Signature> signTypedData(Map<String, dynamic> typedData) async {
///     final rawHex = await _wallet.ethSignTypedDataV4(typedData);
///     return EIP712Signature.fromHex(rawHex);
///   }
///
///   @override
///   Future<EIP712Signature> signDigest(Uint8List digest) =>
///       throw UnsupportedError('Use signTypedData for wallet signers');
/// }
/// ```
abstract class Signer {
  /// The Ethereum address of the signer (0x-prefixed, checksummed or not).
  String get address;

  /// Signs a raw 32-byte digest. Used by local-key and secure-enclave signers.
  ///
  /// **Important:** [digest] must already be the final hash to sign —
  /// do NOT pass a pre-image. Implementations MUST use `hashMessage: false`
  /// (i.e., do not add the Ethereum message prefix again).
  Future<EIP712Signature> signDigest(Uint8List digest);

  /// Signs an EIP-712 typed data structure represented as a JSON-compatible
  /// [Map].
  ///
  /// The default implementation reconstructs an [Eip712TypedData] from
  /// [typedData] via [Eip712TypedData.fromJson], calls [Eip712TypedData.encode]
  /// to obtain the 32-byte EIP-712 digest, then delegates to [signDigest].
  ///
  /// Wallet adapters that call `eth_signTypedData_v4` directly SHOULD override
  /// this method. The [typedData] map follows the EIP-712 JSON structure:
  /// `{ types, primaryType, domain, message }` where integer values are
  /// decimal strings and byte values are `0x`-prefixed hex strings.
  Future<EIP712Signature> signTypedData(Map<String, dynamic> typedData) async {
    final digest = Eip712TypedData.fromJson(typedData).encode();
    return signDigest(Uint8List.fromList(digest));
  }
}
