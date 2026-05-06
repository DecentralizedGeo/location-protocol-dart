import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

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

import 'signer.dart';
import 'local_key_signer.dart';

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
  OffchainSigner({
    required this.signer,
    required this.chainId,
    required this.easContractAddress,
    this.easVersion = '1.0.0',
  });

  /// Convenience factory for local private key signing (backward compatible).
  ///
  /// Wraps [privateKeyHex] in a [LocalKeySigner] and delegates to the primary
  /// constructor. This preserves backward compatibility with existing code.
  factory OffchainSigner.fromPrivateKey({
    required String privateKeyHex,
    required int chainId,
    required String easContractAddress,
    String easVersion = '1.0.0',
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

    // 3. Build JSON-safe EIP-712 typed data map
    final typedDataJson = buildOffchainTypedDataJson(
      chainId: chainId,
      easContractAddress: easContractAddress,
      schemaUID: schemaUID,
      recipient: recipient,
      time: now,
      expirationTime: expTime,
      revocable: schema.revocable,
      refUID: ref,
      data: encodedData,
      salt: saltBytes,
      easVersion: easVersion,
    );

    // 4. Sign via the Signer interface (supports both local keys and wallets)
    final rawSig = await signer.signTypedData(typedDataJson);

    // 5. Normalize v to 27/28 (wallets may return 0/1)
    final normalizedV = rawSig.v < 27 ? rawSig.v + 27 : rawSig.v;

    // 6. Compute offchain UID
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
      uid: uid,
      schemaUID: schemaUID,
      recipient: recipient,
      time: now,
      expirationTime: expTime,
      revocable: schema.revocable,
      refUID: ref,
      data: encodedData,
      salt: saltHex,
      version: EASConstants.attestationVersion,
      signature: EIP712Signature(v: normalizedV, r: rawSig.r, s: rawSig.s),
      signer: signerAddress,
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
  VerificationResult verifyOffchainAttestation(
    SignedOffchainAttestation attestation,
  ) {
    final saltBytes = Uint8List.fromList(attestation.salt.toBytes());

    // 1. Verify UID
    final expectedUID = computeOffchainUID(
      schemaUID: attestation.schemaUID,
      recipient: attestation.recipient,
      time: attestation.time,
      expirationTime: attestation.expirationTime,
      revocable: attestation.revocable,
      refUID: attestation.refUID,
      data: attestation.data,
      salt: saltBytes,
    );

    if (expectedUID != attestation.uid) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        reason: 'UID mismatch: expected $expectedUID, got ${attestation.uid}',
      );
    }

    // 2. Recover signer address via JSON-safe typed data → digest → ecRecover
    final typedDataJson = buildOffchainTypedDataJson(
      chainId: chainId,
      easContractAddress: easContractAddress,
      schemaUID: attestation.schemaUID,
      recipient: attestation.recipient,
      time: attestation.time,
      expirationTime: attestation.expirationTime,
      revocable: attestation.revocable,
      refUID: attestation.refUID,
      data: attestation.data,
      salt: saltBytes,
      easVersion: easVersion,
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
        reason: 'Failed to recover public key from signature',
      );
    }

    final recoveredAddress = recoveredPubKey.toAddress().address;
    final isValid =
        recoveredAddress.toLowerCase() == attestation.signer.toLowerCase();

    return VerificationResult(
      isValid: isValid,
      recoveredAddress: recoveredAddress,
      reason: !isValid
          ? 'Signer mismatch: recovered $recoveredAddress, expected ${attestation.signer}'
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Public static utilities
  // ---------------------------------------------------------------------------

  /// Builds a JSON-safe EIP-712 typed data map for an EAS offchain attestation.
  ///
  /// The returned map conforms to the EIP-712 JSON structure:
  /// `{ types, primaryType, domain, message }`. All integer values are
  /// **decimal strings** (e.g. `'11155111'`), and all byte values are
  /// `0x`-prefixed hex strings — both required by wallet SDKs and by
  /// `Eip712TypedData.fromJson()` in `on_chain` v8 (which calls
  /// `valueAsBigInt(allowHex: false)` for `uint*` types).
  static Map<String, dynamic> buildOffchainTypedDataJson({
    required int chainId,
    required String easContractAddress,
    required String schemaUID,
    required String recipient,
    required BigInt time,
    required BigInt expirationTime,
    required bool revocable,
    required String refUID,
    required Uint8List data,
    required Uint8List salt,
    String easVersion = '1.0.0',
  }) {
    return {
      'types': {
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
      },
      'primaryType': 'Attest',
      'domain': {
        'name': 'EAS Attestation',
        'version': easVersion,
        'chainId': chainId
            .toString(), // decimal string — on_chain allowHex: false
        'verifyingContract': easContractAddress,
      },
      'message': {
        // integers → decimal strings (on_chain v8 valueAsBigInt(allowHex: false))
        'version': EASConstants.attestationVersion.toString(),
        'schema': schemaUID, // hex bytes32
        'recipient': recipient, // address
        'time': time.toString(), // decimal string
        'expirationTime': expirationTime.toString(), // decimal string
        'revocable': revocable, // bool as-is
        'refUID': refUID, // hex bytes32
        'data': '0x${BytesUtils.toHexString(data)}', // hex bytes
        'salt':
            '0x${BytesUtils.toHexString(salt).padLeft(64, '0')}', // hex bytes32
      },
    };
  }

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
    packed.addAll(schemaUID.toBytes());

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
