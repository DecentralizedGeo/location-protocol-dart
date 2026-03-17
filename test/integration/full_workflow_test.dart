import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:on_chain/on_chain.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/lp/location_serializer.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/schema/schema_uid.dart';
import 'package:location_protocol/src/eas/offchain_signer.dart';
import 'package:location_protocol/src/eas/signer.dart';
import 'package:location_protocol/src/models/signature.dart';

// ---------------------------------------------------------------------------
// Wallet-style signer simulation
// ---------------------------------------------------------------------------

/// Simulates a wallet signer (e.g. Privy, MetaMask) that calls
/// `eth_signTypedData_v4` via the wallet SDK instead of raw key access.
///
/// - Overrides [signTypedData] to simulate the wallet call.
/// - Does NOT implement [signDigest] (throws to prove it's never called by
///   OffchainSigner after the Task 5 refactor).
class _WalletStyleSigner extends Signer {
  final ETHPrivateKey _privKey;

  _WalletStyleSigner({required String privateKeyHex})
      : _privKey = ETHPrivateKey(privateKeyHex);

  @override
  String get address => _privKey.publicKey().toAddress().address;

  @override
  Future<EIP712Signature> signTypedData(Map<String, dynamic> typedData) async {
    // Simulate eth_signTypedData_v4: compute EIP-712 digest and sign
    final digest = Eip712TypedData.fromJson(typedData).encode();
    final sig = _privKey.sign(digest, hashMessage: false);
    return EIP712Signature(
      v: sig.v,
      r: '0x${BytesUtils.toHexString(sig.rBytes).padLeft(64, '0')}',
      s: '0x${BytesUtils.toHexString(sig.sBytes).padLeft(64, '0')}',
    );
  }

  @override
  Future<EIP712Signature> signDigest(Uint8List digest) =>
      throw UnsupportedError('wallet signers use signTypedData only');
}

void main() {
  // Well-known test key — Hardhat account #0
  const testKey =
      'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  group('Full Offline Workflow', () {
    test('define schema → create payload → sign → verify', () async {
      // Step 1: Define business schema
      final schema = SchemaDefinition(
        fields: [
          SchemaField(type: 'uint256', name: 'timestamp'),
          SchemaField(type: 'string', name: 'surveyor_id'),
          SchemaField(type: 'string', name: 'memo'),
        ],
      );

      // Verify schema string includes LP fields
      final schemaString = schema.toEASSchemaString();
      expect(schemaString, startsWith('string lp_version,string srs'));
      expect(schemaString, contains('uint256 timestamp'));

      // Verify schema UID is deterministic
      final uid1 = SchemaUID.compute(schema);
      final uid2 = SchemaUID.compute(schema);
      expect(uid1, equals(uid2));

      // Step 2: Create LP payload with Map location
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {
          'type': 'Point',
          'coordinates': [-103.771556, 44.967243],
        },
      );

      // Verify serialization works
      final serialized = LocationSerializer.serialize(lpPayload.location);
      expect(serialized, contains('"type":"Point"'));

      // Step 3: Sign offchain attestation (using fromPrivateKey factory)
      final signer = OffchainSigner.fromPrivateKey(
        privateKeyHex: testKey,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );

      final signed = await signer.signOffchainAttestation(
        schema: schema,
        lpPayload: lpPayload,
        userData: {
          'timestamp': BigInt.from(1710000000),
          'surveyor_id': 'surveyor-42',
          'memo': 'Boundary marker GPS reading',
        },
      );

      // Verify signed attestation structure
      expect(signed.uid, startsWith('0x'));
      expect(signed.uid.length, equals(66));
      expect(signed.version, equals(2));
      expect(signed.salt, startsWith('0x'));
      expect(signed.signature.v, anyOf(equals(27), equals(28)));
      expect(signed.signer, startsWith('0x'));
      expect(signed.signer.length, equals(42));

      // Step 4: Verify the attestation
      final verification = signer.verifyOffchainAttestation(signed);
      expect(verification.isValid, isTrue);
      expect(
        verification.recoveredAddress.toLowerCase(),
        equals(signed.signer.toLowerCase()),
      );
    });

    test('different locations produce different attestation UIDs', () async {
      final schema = SchemaDefinition(fields: []);

      final signer = OffchainSigner.fromPrivateKey(
        privateKeyHex: testKey,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );

      final payload1 = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {'type': 'Point', 'coordinates': [-103.77, 44.96]},
      );

      final payload2 = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {'type': 'Point', 'coordinates': [-73.93, 40.73]},
      );

      final signed1 = await signer.signOffchainAttestation(
        schema: schema,
        lpPayload: payload1,
        userData: {},
      );
      final signed2 = await signer.signOffchainAttestation(
        schema: schema,
        lpPayload: payload2,
        userData: {},
      );

      // Different data → different UIDs (even ignoring salt)
      expect(signed1.data, isNot(equals(signed2.data)));
    });

    test('LP-only schema works (no user fields)', () async {
      final schema = SchemaDefinition(fields: []);

      expect(
        schema.toEASSchemaString(),
        equals('string lp_version,string srs,string location_type,string location'),
      );

      final signer = OffchainSigner.fromPrivateKey(
        privateKeyHex: testKey,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );

      final signed = await signer.signOffchainAttestation(
        schema: schema,
        lpPayload: LPPayload(
          lpVersion: '1.0.0',
          srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
          locationType: 'h3',
          location: '8928308280fffff',
        ),
        userData: {},
      );

      final result = signer.verifyOffchainAttestation(signed);
      expect(result.isValid, isTrue);
    });

    // -------------------------------------------------------------------------
    // Task 6: Wallet-style signer integration test
    // -------------------------------------------------------------------------

    test('wallet-style signer produces valid verifiable attestation', () async {
      final walletSigner = _WalletStyleSigner(privateKeyHex: testKey);

      final offchainSigner = OffchainSigner(
        signer: walletSigner,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );

      final schema = SchemaDefinition(
        fields: [
          SchemaField(type: 'string', name: 'location_note'),
        ],
      );

      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: {'type': 'Point', 'coordinates': [0.0, 0.0]},
      );

      final signed = await offchainSigner.signOffchainAttestation(
        schema: schema,
        lpPayload: lpPayload,
        userData: {'location_note': 'wallet integration test'},
      );

      // Attestation has valid structure
      expect(signed.uid, startsWith('0x'));
      expect(signed.uid.length, equals(66));
      expect(signed.signature.v, anyOf(equals(27), equals(28)));

      // Verification must pass and recovered address matches wallet address
      final result = offchainSigner.verifyOffchainAttestation(signed);
      expect(result.isValid, isTrue, reason: result.reason);
      expect(
        result.recoveredAddress.toLowerCase(),
        equals(walletSigner.address.toLowerCase()),
      );
    });
  });
}
