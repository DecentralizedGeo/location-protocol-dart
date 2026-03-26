import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:location_protocol/src/eas/signer.dart';
import 'package:location_protocol/src/eas/local_key_signer.dart';
import 'package:location_protocol/src/models/signature.dart';

// ---------------------------------------------------------------------------
// Test helper: minimal concrete Signer that returns canned values
// ---------------------------------------------------------------------------

/// Captures the digest passed to signDigest for assertion.
class _CapturingSigner extends Signer {
  final EIP712Signature _cannedSig;
  Uint8List? capturedDigest;

  _CapturingSigner({required EIP712Signature cannedSig})
    : _cannedSig = cannedSig;

  @override
  String get address => '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

  @override
  Future<EIP712Signature> signDigest(Uint8List digest) async {
    capturedDigest = digest;
    return _cannedSig;
  }
}

// ---------------------------------------------------------------------------
// Shared test fixtures
// ---------------------------------------------------------------------------

const _hardhatKey =
    'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const _hardhatAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

const _easAddress = '0xC2679fBD37d54388Ce493F1DB75320D236e1815e';
const _chainId = 11155111;

// A JSON-safe EAS typed data map (decimal strings for uint, hex for bytes)
Map<String, dynamic> _buildTestTypedDataJson() {
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
      'version': '1.0.0',
      'chainId': '$_chainId', // decimal string
      'verifyingContract': _easAddress,
    },
    'message': {
      'version': '2', // decimal string
      'schema':
          '0x0000000000000000000000000000000000000000000000000000000000000001',
      'recipient': '0x0000000000000000000000000000000000000000',
      'time': '1710000000', // decimal string
      'expirationTime': '0', // decimal string
      'revocable': true,
      'refUID':
          '0x0000000000000000000000000000000000000000000000000000000000000000',
      'data': '0x',
      'salt':
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    },
  };
}

// ---------------------------------------------------------------------------
// Task 2: Signer abstract class tests
// ---------------------------------------------------------------------------

void main() {
  group('Signer (abstract class)', () {
    final cannedSig = EIP712Signature(
      v: 27,
      r: '0x${'aa' * 32}',
      s: '0x${'bb' * 32}',
    );

    test('concrete subclass returns correct address', () {
      final signer = _CapturingSigner(cannedSig: cannedSig);
      expect(signer.address, equals(_hardhatAddress));
    });

    test('signDigest returns canned signature', () async {
      final signer = _CapturingSigner(cannedSig: cannedSig);
      final sig = await signer.signDigest(Uint8List(32));
      expect(sig.v, equals(27));
      expect(sig.r, equals(cannedSig.r));
    });

    test(
      'default signTypedData delegates to signDigest with correct digest',
      () async {
        final signer = _CapturingSigner(cannedSig: cannedSig);
        final jsonMap = _buildTestTypedDataJson();

        // Independently compute the expected digest
        final expectedDigest = Uint8List.fromList(
          Eip712TypedData.fromJson(jsonMap).encode(),
        );

        final sig = await signer.signTypedData(jsonMap);

        // signDigest was called with the correct 32-byte digest
        expect(signer.capturedDigest, isNotNull);
        expect(signer.capturedDigest!.length, equals(32));
        expect(signer.capturedDigest, equals(expectedDigest));

        // returned signature matches canned value
        expect(sig.v, equals(cannedSig.v));
        expect(sig.r, equals(cannedSig.r));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Task 3: LocalKeySigner tests
  // ---------------------------------------------------------------------------

  group('LocalKeySigner', () {
    late LocalKeySigner signer;

    setUp(() {
      signer = LocalKeySigner(privateKeyHex: _hardhatKey);
    });

    test('address returns Hardhat #0 address (case-insensitive)', () {
      expect(
        signer.address.toLowerCase(),
        equals(_hardhatAddress.toLowerCase()),
      );
    });

    test('signDigest produces a valid signature (real crypto)', () async {
      // Build a test digest (32 bytes)
      final digest = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        digest[i] = i;
      }

      final sig = await signer.signDigest(digest);

      expect(sig.v, anyOf(equals(27), equals(28)));
      expect(sig.r, startsWith('0x'));
      expect(sig.r.length, equals(66));
      expect(sig.s, startsWith('0x'));
      expect(sig.s.length, equals(66));

      // Recover signer from signature
      final rBytes = BytesUtils.fromHexString(sig.r.substring(2));
      final sBytes = BytesUtils.fromHexString(sig.s.substring(2));
      final sigBytes = <int>[
        ...List<int>.filled(32 - rBytes.length, 0),
        ...rBytes,
        ...List<int>.filled(32 - sBytes.length, 0),
        ...sBytes,
        sig.v,
      ];

      final recovered = ETHPublicKey.getPublicKey(
        digest,
        sigBytes,
        hashMessage: false,
      );
      expect(recovered, isNotNull);
      expect(
        recovered!.toAddress().address.toLowerCase(),
        equals(_hardhatAddress.toLowerCase()),
      );
    });

    test(
      'signTypedData (inherited default) produces same digest as signDigest',
      () async {
        final jsonMap = _buildTestTypedDataJson();

        // Sign via signTypedData
        final sigA = await signer.signTypedData(jsonMap);

        // Sign via signDigest with the manually computed digest
        final digest = Uint8List.fromList(
          Eip712TypedData.fromJson(jsonMap).encode(),
        );
        final sigB = await signer.signDigest(digest);

        // Both paths must produce byte-identical signatures (deterministic signing)
        expect(sigA.v, equals(sigB.v));
        expect(sigA.r, equals(sigB.r));
        expect(sigA.s, equals(sigB.s));
      },
    );
  });
}
