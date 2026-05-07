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

    final domain = _expectedDomainMap(
      chainId: chainId,
      easVersion: easVersion,
      easContractAddress: easContractAddress,
    );
    final types = _expectedTypesMap();
    final message = _expectedMessageMap(
      schemaUID: schemaUID,
      recipient: recipient,
      time: now,
      expirationTime: expTime,
      revocable: schema.revocable,
      refUID: ref,
      data: encodedData,
      saltHex: saltHex,
    );

    // 3. Build JSON-safe EIP-712 typed data map
    final typedDataJson = _buildTypedDataJsonFromParts(
      chainId: chainId,
      easContractAddress: easContractAddress,
      easVersion: easVersion,
      primaryType: 'Attest',
      domain: domain,
      types: types,
      message: message,
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
  VerificationResult verifyOffchainAttestation(
    SignedOffchainAttestation attestation,
  ) {
    final expectedDomain = _expectedDomainMap(
      chainId: chainId,
      easVersion: easVersion,
      easContractAddress: easContractAddress,
    );
    if (!_deepEquals(attestation.domain, expectedDomain)) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidDomain,
        reason:
            'Preserved EAS domain does not match signer configuration',
      );
    }

    if (attestation.primaryType != 'Attest') {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidPrimaryType,
        reason: 'Unexpected primary type: ${attestation.primaryType}',
      );
    }

    final expectedTypes = _expectedTypesMap();
    if (!_deepEquals(attestation.types, expectedTypes)) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidTypes,
        reason: 'Preserved EAS types do not match signer configuration',
      );
    }

    final messageValidation = _validateMessage(attestation);
    if (messageValidation != null) {
      return messageValidation;
    }

    final saltBytes = attestation.saltBytes;

    // 1. Verify UID
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

    // 2. Recover signer address via preserved envelope → digest → ecRecover
    final typedDataJson = buildOffchainTypedDataJsonFromEnvelope(attestation);

    final hash = Eip712TypedData.fromJson(typedDataJson).encode();
    final sigBytesOrError = _signatureToRecoveryBytes(attestation.signature);
    if (sigBytesOrError == null) {
      return VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidSignature,
        reason: 'Invalid EIP-712 signature encoding',
      );
    }

    final recoveredPubKey = ETHPublicKey.getPublicKey(
      hash,
      sigBytesOrError,
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

    return VerificationResult(
      isValid: isValid,
      recoveredAddress: recoveredAddress,
      code: isValid ? null : VerificationFailure.signerMismatch,
      reason: isValid
          ? null
          : 'Signer mismatch: recovered $recoveredAddress, expected ${attestation.signer}',
    );
  }

  // ---------------------------------------------------------------------------
  // Public static utilities
  // ---------------------------------------------------------------------------

  /// Builds a JSON-safe EIP-712 typed data helper map for an EAS offchain
  /// attestation.
  ///
  /// This is a derived wallet helper only; the canonical preserved model is
  /// [SignedOffchainAttestation]. The returned map conforms to the EIP-712 JSON
  /// structure:
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
    return _buildTypedDataJsonFromParts(
      chainId: chainId,
      easContractAddress: easContractAddress,
      easVersion: easVersion,
      primaryType: 'Attest',
      domain: _expectedDomainMap(
        chainId: chainId,
        easContractAddress: easContractAddress,
        easVersion: easVersion,
      ),
      types: _expectedTypesMap(),
      message: _expectedMessageMap(
        schemaUID: schemaUID,
        recipient: recipient,
        time: time,
        expirationTime: expirationTime,
        revocable: revocable,
        refUID: refUID,
        data: data,
        saltHex: '0x${BytesUtils.toHexString(salt).padLeft(64, '0')}',
      ),
    );
  }

  /// Builds JSON-safe typed data from an already preserved canonical EAS
  /// envelope.
  static Map<String, dynamic> buildOffchainTypedDataJsonFromEnvelope(
    SignedOffchainAttestation attestation,
  ) {
    final chainId = _tryParseChainId(attestation.domain['chainId']);
    if (chainId == null) {
      throw ArgumentError.value(
        attestation.domain['chainId'],
        'attestation.domain[chainId]',
        'Expected an int or decimal string chain ID',
      );
    }

    return _buildTypedDataJsonFromParts(
      chainId: chainId,
      easContractAddress: attestation.domain['verifyingContract'] as String,
      easVersion: attestation.domain['version'].toString(),
      primaryType: attestation.primaryType,
      domain: attestation.domain,
      types: attestation.types,
      message: attestation.message,
    );
  }

  static Map<String, dynamic> _buildTypedDataJsonFromParts({
    required int chainId,
    required String easContractAddress,
    required String easVersion,
    required String primaryType,
    required Map<String, dynamic> domain,
    required Map<String, dynamic> types,
    required Map<String, dynamic> message,
  }) {
    return {
      'types': {
        'EIP712Domain': [
          {'name': 'name', 'type': 'string'},
          {'name': 'version', 'type': 'string'},
          {'name': 'chainId', 'type': 'uint256'},
          {'name': 'verifyingContract', 'type': 'address'},
        ],
        ...types,
      },
      'primaryType': primaryType,
      'domain': {
        ...domain,
        'chainId': chainId.toString(),
        'version': easVersion,
        'verifyingContract': easContractAddress,
      },
      'message': {
        ...message,
        'version': message['version'].toString(),
        'time': message['time'].toString(),
        'expirationTime': message['expirationTime'].toString(),
      },
    };
  }

  static Map<String, dynamic> _expectedDomainMap({
    int chainId = 11155111,
    String easVersion = '1.0.0',
    String easContractAddress = '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
  }) {
    return {
      'name': EASConstants.eip712DomainName,
      'version': easVersion,
      'chainId': chainId,
      'verifyingContract': easContractAddress,
    };
  }

  static Map<String, dynamic> _expectedTypesMap() {
    return {
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
  }

  static Map<String, dynamic> _expectedMessageMap({
    required String schemaUID,
    required String recipient,
    required BigInt time,
    required BigInt expirationTime,
    required bool revocable,
    required String refUID,
    required Uint8List data,
    required String saltHex,
  }) {
    return {
      'version': EASConstants.attestationVersion,
      'schema': schemaUID,
      'recipient': recipient,
      'time': time.toInt(),
      'expirationTime': expirationTime.toInt(),
      'revocable': revocable,
      'refUID': refUID,
      'data': '0x${BytesUtils.toHexString(data)}',
      'salt': saltHex,
    };
  }

  static VerificationResult? _validateMessage(
    SignedOffchainAttestation attestation,
  ) {
    final message = attestation.message;

    const expectedKeys = <String>{
      'version',
      'schema',
      'recipient',
      'time',
      'expirationTime',
      'revocable',
      'refUID',
      'data',
      'salt',
    };
    final actualKeys = message.keys.toSet();
    if (actualKeys.length != expectedKeys.length ||
        !actualKeys.containsAll(expectedKeys)) {
      return const VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidMessage,
        reason: 'Preserved EAS message does not have the expected shape',
      );
    }

    final salt = message['salt'];
    if (salt is! String || salt.isEmpty) {
      return const VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidMessage,
        reason: 'Missing version-2 salt in preserved EAS message',
      );
    }

    if (message['version'] is! num ||
        (message['version'] as num).toInt() != EASConstants.attestationVersion) {
      return const VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidMessage,
        reason: 'Unsupported offchain attestation version',
      );
    }

    if (message['schema'] is! String ||
        message['recipient'] is! String ||
        message['refUID'] is! String ||
        message['data'] is! String ||
        message['revocable'] is! bool) {
      return const VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidMessage,
        reason: 'Preserved EAS message contains invalid field types',
      );
    }

    if (_tryParseBigInt(message['time']) == null ||
        _tryParseBigInt(message['expirationTime']) == null ||
        !_isHexString(message['schema'] as String, expectedBytes: 32) ||
        !_isHexString(message['recipient'] as String, expectedBytes: 20) ||
        !_isHexString(message['refUID'] as String, expectedBytes: 32) ||
        !_isHexString(message['data'] as String) ||
        !_isHexString(salt, expectedBytes: 32)) {
      return const VerificationResult(
        isValid: false,
        recoveredAddress: '',
        code: VerificationFailure.invalidMessage,
        reason: 'Preserved EAS message contains malformed encodings',
      );
    }

    return null;
  }

  static Uint8List? _signatureToRecoveryBytes(EIP712Signature signature) {
    if (signature.v != 27 && signature.v != 28) {
      return null;
    }

    late final List<int> r;
    late final List<int> s;
    try {
      r = BytesUtils.fromHexString(signature.r.strip0x);
      s = BytesUtils.fromHexString(signature.s.strip0x);
    } catch (_) {
      return null;
    }

    if (r.length != 32 || s.length != 32) {
      return null;
    }

    return Uint8List.fromList(<int>[...r, ...s, signature.v]);
  }

  static bool _deepEquals(dynamic left, dynamic right) {
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key)) return false;
        if (!_deepEquals(entry.value, right[entry.key])) return false;
      }
      return true;
    }

    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!_deepEquals(left[i], right[i])) return false;
      }
      return true;
    }

    return left == right;
  }

  static int? _tryParseChainId(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  static BigInt? _tryParseBigInt(dynamic value) {
    if (value is BigInt) {
      return value;
    }

    if (value is int) {
      return BigInt.from(value);
    }

    if (value is num) {
      return BigInt.from(value.toInt());
    }

    if (value is String) {
      return BigInt.tryParse(value);
    }

    return null;
  }

  static bool _isHexString(String value, {int? expectedBytes}) {
    try {
      final bytes = value.toBytes();
      return expectedBytes == null || bytes.length == expectedBytes;
    } catch (_) {
      return false;
    }
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
