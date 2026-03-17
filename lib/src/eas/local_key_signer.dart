import 'dart:typed_data';
import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import '../models/signature.dart';
import 'signer.dart';

/// A [Signer] implementation that wraps an [ETHPrivateKey] for local signing.
///
/// Use this when you have access to a raw private key (e.g. in tests, scripts,
/// or server-side services). For wallet-backed applications (Privy, MetaMask,
/// WalletConnect), implement [Signer] directly in your application layer.
///
/// Inherits the default [signTypedData] implementation from [Signer]:
/// `Eip712TypedData.fromJson(typedData).encode()` → [signDigest].
class LocalKeySigner extends Signer {
  final ETHPrivateKey _privateKey;

  /// Creates a signer from a hex-encoded private key.
  ///
  /// [privateKeyHex] may optionally include a `0x` prefix.
  LocalKeySigner({required String privateKeyHex})
      : _privateKey = ETHPrivateKey(privateKeyHex);

  @override
  String get address => _privateKey.publicKey().toAddress().address;

  @override
  Future<EIP712Signature> signDigest(Uint8List digest) async {
    final sig = _privateKey.sign(digest, hashMessage: false);
    return EIP712Signature(
      v: sig.v,
      r: '0x${BytesUtils.toHexString(sig.rBytes).padLeft(64, '0')}',
      s: '0x${BytesUtils.toHexString(sig.sBytes).padLeft(64, '0')}',
    );
  }
}
