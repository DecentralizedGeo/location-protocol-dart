import 'dart:convert';
import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

import '../config/chain_config.dart';
import '../lp/lp_payload.dart';
import '../schema/schema_definition.dart';
import '../schema/schema_uid.dart';
import '../models/attestation.dart';
import '../models/signature.dart';
import '../models/verification_result.dart';
import '../utils/byte_utils.dart';
import '../utils/hex_utils.dart';
import 'abi_encoder.dart';
import 'constants.dart';

import 'package:collection/collection.dart';

import 'signer.dart';
import 'local_key_signer.dart';

/// Deep equality used for EIP-712 structural verification.
const _deepEq = DeepCollectionEquality();

/// EIP-712 offchain attestation signer and verifier.
///
/// Signs Location Protocol attestations using EIP-712 typed data (Version 2
/// with salt). No RPC connection required.
///
/// Use [OffchainSigner.fromPrivateKey] for local key signing (backward
/// compatible), or pass any [Signer] implementation for wallet-backed signing.
class OffchainSigner {
  final Signer signer;
  final int chainId;
  final String easContractAddress;
  final String easVersion;

  /// Creates a signer with the given [Signer] and chain configuration.
  ///
  /// For wallet-backed signing, pass a custom [Signer] implementation that
  /// calls `eth_signTypedData_v4`. For local key signing, prefer
  /// [OffchainSigner.fromPrivateKey].
  ///
  /// If [easVersion] is not supplied, it is resolved automatically from
  /// [ChainConfig] using [chainId]. Unsupported chains must supply
  /// [easVersion] explicitly.
  OffchainSigner({
    required this.signer,
    required this.chainId,
    required this.easContractAddress,
    String? easVersion,
  }) : easVersion = easVersion ?? _resolveEasVersion(chainId);

  /// Convenience factory for local private key signing (backward compatible).
  ///
  /// Wraps [privateKeyHex] in a [LocalKeySigner] and delegates to the primary
  /// constructor. This preserves backward compatibility with existing code.
  ///
  /// If [easVersion] is not supplied, it is resolved automatically from
  /// [ChainConfig] using [chainId]. Unsupported chains must supply
  /// [easVersion] explicitly.
  factory OffchainSigner.fromPrivateKey({
    required String privateKeyHex,
    required int chainId,
    required String easContractAddress,
    String? easVersion,
  }) {
    return OffchainSigner(
      signer: LocalKeySigner(privateKeyHex: privateKeyHex),
      chainId: chainId,
      easContractAddress: easContractAddress,
      easVersion: easVersion,
    );
  }

  /// The Ethereum address derived from the signer.
  String get signerAddress => signer.address;

  /// Signs an offchain attestation using EIP-712 typed data.
  Future<SignedOffchainAttestation> signOffchainAttestation({
    required SchemaDefinition schema,
    required LPPayload lpPayload,
    required Map<String, dynamic> userData,
    String recipient = '0x0000000000000000000000000000000000000000',
    BigInt? time,
    BigInt? expirationTime,
    String? refUID,
    Uint8List? salt,
  }) async {
    final now =
        time ?? BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final expTime = expirationTime ?? BigInt.zero;
    final ref = refUID ?? EASConstants.zeroBytes32;
    final saltBytes = salt ?? EASConstants.generateSalt();
    final saltHex = EASConstants.saltToHex(saltBytes);

    // 1. ABI-encode the data payload
    final encodedData = AbiEncoder.encode(
      schema: schema,
      lpPayload: lpPayload,
      userData: userData,
    );

    // 2. Compute schema UID
    final schemaUID = SchemaUID.compute(schema);

    // 3. Build canonical signedTypedStruct maps (preserved in the attestation)
    // Use _expectedDomain() and _canonicalTypes() to ensure consistency
    final domain = _expectedDomain();
    final types = _canonicalTypes();

    final message = {
      'version': EASConstants.attestationVersion,
      'schema': schemaUID,
      'recipient': recipient,
      'time': now, // stored as BigInt
      'expirationTime': expTime,
      'revocable': schema.revocable,
      'refUID': ref,
      'data': '0x${BytesUtils.toHexString(encodedData)}',
      'salt': saltHex,
    };

    // 4. Build transient wallet signing request (decimal strings for on_chain compat)
    final typedDataJson = _buildTypedDataJsonForSigning(
      domain: domain,
      message: message,
      types: types,
    );

    // 5. Sign via the Signer interface (supports both local keys and wallets)
    final rawSig = await signer.signTypedData(typedDataJson);

    // 6. Normalize v to 27/28 (wallets may return 0/1)
    final normalizedV = rawSig.v < 27 ? rawSig.v + 27 : rawSig.v;

    // 7. Compute offchain UID
    final uid = computeOffchainUID(
      schemaUID: schemaUID,
      recipient: recipient,
      time: now,
      expirationTime: expTime,
      revocable: schema.revocable,
      refUID: ref,
      data: encodedData,
      salt: saltBytes,
    );

    return SignedOffchainAttestation(
      signer: signerAddress,
      domain: domain,
      primaryType: 'Attest',
      types: types,
      message: message,
      signature: EIP712Signature(v: normalizedV, r: rawSig.r, s: rawSig.s),
      uid: uid,
    );
  }

  /// Signs an offchain attestation with an explicit dynamic user-data map.
  ///
  /// This is a convenience alias for [signOffchainAttestation] that makes the
  /// dynamic payload use case more discoverable for downstream apps that build
  /// schemas and user data at runtime.
  Future<SignedOffchainAttestation> signOffchainWithData({
    required SchemaDefinition schema,
    required LPPayload lpPayload,
    required Map<String, dynamic> userData,
    String recipient = EASConstants.zeroAddress,
    BigInt? time,
    BigInt? expirationTime,
    String? refUID,
    Uint8List? salt,
  }) {
    return signOffchainAttestation(
      schema: schema,
      lpPayload: lpPayload,
      userData: userData,
      recipient: recipient,
      time: time,
      expirationTime: expirationTime,
      refUID: refUID,
      salt: salt,
    );
  }

  /// Verifies a signed offchain attestation.
  ///
  /// Checks offchain version, UID validity, EIP-712 typed data structure
  /// (domain, primaryType, types), and ecRecovers the signer address from
  /// the signature.
  ///
  /// Domain version is accepted from the attestation itself, mirroring the EAS
  /// TypeScript SDK's `strict=false` behavior. This allows attestations
  /// produced by any EAS SDK version to pass regardless of the `easVersion`
  /// string configured on this signer.
  VerificationResult verifyOffchainAttestation(
    SignedOffchainAttestation attestation,
  ) {
    // 1. Verify offchain signedTypedStruct version.
    final versionValue = attestation.message['version'];
    final versionString = versionValue == null ? null : versionValue.toString();
    final offchainVersion = versionValue is int
        ? versionValue
        : int.tryParse(versionString ?? '');
    if (offchainVersion != EASConstants.attestationVersion) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.unsupportedVersion,
        reason:
            'Unsupported offchain attestation version: ${versionString ?? 'null'}; only version ${EASConstants.attestationVersion} is supported',
      );
    }

    // 2. Verify UID
    final saltBytes = attestation.saltBytes;
    if (saltBytes == null) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.missingSalt,
        reason: 'Missing salt field in message',
      );
    }

    final expectedUID = computeOffchainUID(
      schemaUID: attestation.schemaUID,
      recipient: attestation.recipient,
      time: attestation.time,
      expirationTime: attestation.expirationTime,
      revocable: attestation.revocable,
      refUID: attestation.refUID,
      data: attestation.dataBytes,
      salt: saltBytes,
    );

    if (expectedUID != attestation.uid) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.uidMismatch,
        reason: 'UID mismatch: expected $expectedUID, got ${attestation.uid}',
      );
    }

    // 3. Validate EIP-712 typed data structure
    final structureFailure = _verifyTypedDataStructure(attestation);
    if (structureFailure != null) return structureFailure;

    // 4. Recover signer address
    return _verifySignature(attestation);
  }

  /// Checks domain, primaryType, and types against expected canonical values.
  ///
  /// Mirrors the structural half of the EAS TypeScript SDK's
  /// `verifyTypedDataRequestSignature`. Domain version is taken from the
  /// attestation itself (mirrors `strict=false`) so any EAS SDK version passes.
  ///
  /// Returns `null` if all checks pass, or a [VerificationResult] with the
  /// appropriate [VerificationFailure] code on the first failure.
  VerificationResult? _verifyTypedDataStructure(
    SignedOffchainAttestation attestation,
  ) {
    // Mirror EAS SDK strict=false: accept the attestation's own domain version
    final expectedDomain = _expectedDomain()
      ..['version'] = attestation.domain['version'] as String;
    if (!_deepEq.equals(attestation.domain, expectedDomain)) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidDomain,
        reason: 'Domain mismatch',
      );
    }

    if (attestation.primaryType != 'Attest') {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidPrimaryType,
        reason: 'Primary type must be "Attest", got ${attestation.primaryType}',
      );
    }

    if (!_deepEq.equals(attestation.types, _canonicalTypes())) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidTypes,
        reason: 'Types map does not match canonical structure',
      );
    }

    return null;
  }

  /// Recovers the signer address from the EIP-712 signature and compares it
  /// to [SignedOffchainAttestation.signer].
  ///
  /// Mirrors the cryptographic half of the EAS TypeScript SDK's
  /// `verifyTypedDataRequestSignature`.
  VerificationResult _verifySignature(SignedOffchainAttestation attestation) {
    final typedDataJson = _buildTypedDataJsonForSigning(
      domain: attestation.domain,
      message: attestation.message,
      types: attestation.types,
    );

    final hash = Eip712TypedData.fromJson(typedDataJson).encode();
    final r = BytesUtils.fromHexString(attestation.signature.r.substring(2));
    final s = BytesUtils.fromHexString(attestation.signature.s.substring(2));
    final v = attestation.signature.v;

    // Pad r and s to 32 bytes
    final sigBytes = <int>[
      ...List<int>.filled(32 - r.length, 0),
      ...r,
      ...List<int>.filled(32 - s.length, 0),
      ...s,
      v,
    ];

    final recoveredPubKey = ETHPublicKey.getPublicKey(
      hash,
      sigBytes,
      hashMessage: false,
    );
    if (recoveredPubKey == null) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidSignature,
        reason: 'Failed to recover public key from signature',
      );
    }

    final recoveredAddress = recoveredPubKey.toAddress().address;
    final isValid =
        recoveredAddress.toLowerCase() == attestation.signer.toLowerCase();

    if (!isValid) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: recoveredAddress,
        code: VerificationFailure.signerMismatch,
        reason:
            'Signer mismatch: recovered $recoveredAddress, expected ${attestation.signer}',
      );
    }

    return VerificationResult(
      isValid: true,
      recoveredAddress: recoveredAddress,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static String _resolveEasVersion(int chainId) {
    final config = ChainConfig.forChainId(chainId);
    if (config == null) {
      throw ArgumentError.value(
        chainId,
        'chainId',
        'Unsupported chain. Provide easVersion explicitly for unknown chain IDs.',
      );
    }
    return config.easVersion;
  }

  /// Builds the transient EIP-712 JSON request for wallet signing.
  ///
  /// Converts canonical signedTypedStruct maps (where integers are stored as [int] or
  /// [BigInt]) into wallet-compatible format with decimal string integers.
  /// This is required by the `on_chain` package v8 which calls
  /// `valueAsBigInt(allowHex: false)` for numeric types.
  Map<String, dynamic> _buildTypedDataJsonForSigning({
    required Map<String, dynamic> domain,
    required Map<String, dynamic> message,
    required Map<String, dynamic> types,
  }) {
    // Convert domain: chainId int → decimal string
    final signDomain = {...domain};
    signDomain['chainId'] = (domain['chainId'] as int).toString();

    // Convert message: time, expirationTime, version → decimal strings
    final signMessage = {...message};
    final timeVal = message['time'];
    signMessage['time'] =
        (timeVal is BigInt ? timeVal : BigInt.from(timeVal as int)).toString();
    final expVal = message['expirationTime'];
    signMessage['expirationTime'] =
        (expVal is BigInt ? expVal : BigInt.from(expVal as int)).toString();
    final verVal = message['version'];
    signMessage['version'] = (verVal is int ? verVal : int.parse(verVal.toString())).toString();

    return {
      'types': types,
      'primaryType': 'Attest',
      'domain': signDomain,
      'message': signMessage,
    };
  }

  /// Builds the expected EIP-712 domain for this signer's configuration.
  Map<String, dynamic> _expectedDomain() => {
        'name': EASConstants.eip712DomainName,
        'version': easVersion,
        'chainId': chainId,
        'verifyingContract': easContractAddress,
      };

  /// Returns the canonical types map for offchain attestations.
  Map<String, dynamic> _canonicalTypes() => {
        'EIP712Domain': [
          {'name': 'name', 'type': 'string'},
          {'name': 'version', 'type': 'string'},
          {'name': 'chainId', 'type': 'uint256'},
          {'name': 'verifyingContract', 'type': 'address'},
        ],
        'Attest': [
          {'name': 'version', 'type': 'uint16'},
          {'name': 'schema', 'type': 'bytes32'},
          {'name': 'recipient', 'type': 'address'},
          {'name': 'time', 'type': 'uint64'},
          {'name': 'expirationTime', 'type': 'uint64'},
          {'name': 'revocable', 'type': 'bool'},
          {'name': 'refUID', 'type': 'bytes32'},
          {'name': 'data', 'type': 'bytes'},
          {'name': 'salt', 'type': 'bytes32'},
        ],
      };

  // ---------------------------------------------------------------------------
  // Public static utilities
  // ---------------------------------------------------------------------------

  /// Computes the deterministic offchain attestation UID (v2).
  ///
  /// The UID is a keccak256 hash of the tightly-packed attestation fields as
  /// defined by the EAS offchain v2 specification.
  static String computeOffchainUID({
    required String schemaUID,
    required String recipient,
    required BigInt time,
    required BigInt expirationTime,
    required bool revocable,
    required String refUID,
    required Uint8List data,
    required Uint8List salt,
  }) {
    final List<int> packed = [];

    // 1. version (uint16)
    packed.addAll(ByteUtils.uint16ToBytes(EASConstants.attestationVersion));

    // 2. schema (bytes32) - should be 32 bytes
    // e.g. "0x3902cc7b..." → UTF-8 encoded hex string bytes
    packed.addAll(utf8.encode(schemaUID));

    // 3. recipient (address) - 20 bytes
    packed.addAll(recipient.toBytes().sublist(0, 20));

    // 4. attester (address) - 20 bytes (always ZERO_ADDRESS for offchain UID v2)
    packed.addAll(List<int>.filled(20, 0));

    // 5. time (uint64)
    packed.addAll(ByteUtils.uint64ToBytes(time));

    // 6. expirationTime (uint64)
    packed.addAll(ByteUtils.uint64ToBytes(expirationTime));

    // 7. revocable (bool)
    packed.add(revocable ? 1 : 0);

    // 8. refUID (bytes32)
    packed.addAll(refUID.toBytes());

    // 9. data (bytes)
    packed.addAll(data);

    // 10. salt (bytes32)
    packed.addAll(salt);

    // 11. trailing zero (uint32)
    packed.addAll(List<int>.filled(4, 0));

    final hash = QuickCrypto.keccack256Hash(packed);
    return BytesUtils.toHexString(hash, prefix: '0x');
  }
}
