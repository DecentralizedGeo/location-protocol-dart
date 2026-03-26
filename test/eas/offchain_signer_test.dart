import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:on_chain/on_chain.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/offchain_signer.dart';
import 'package:location_protocol/src/eas/local_key_signer.dart';
import 'package:location_protocol/src/eas/signer.dart';
import 'package:location_protocol/src/eas/constants.dart';
import 'package:location_protocol/src/models/signature.dart';

void main() {
  // A well-known test private key — NEVER use in production
  // Address: 0x2e988A386a799F506693793c6A5AF6B54dfAaBfB
  const testPrivateKeyHex =
      'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  late OffchainSigner signer;
  late SchemaDefinition schema;
  late LPPayload lpPayload;

  setUp(() {
    signer = OffchainSigner.fromPrivateKey(
      privateKeyHex: testPrivateKeyHex,
      chainId: 11155111, // Sepolia
      easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
    );

    schema = SchemaDefinition(
      fields: [
        SchemaField(type: 'uint256', name: 'timestamp'),
        SchemaField(type: 'string', name: 'memo'),
      ],
    );

    lpPayload = LPPayload(
      lpVersion: '1.0.0',
      srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
      locationType: 'geojson-point',
      location: {
        'type': 'Point',
        'coordinates': [-103.771556, 44.967243],
      },
    );
  });

  group('OffchainSigner', () {
    group('signOffchainAttestation', () {
      test('returns a SignedOffchainAttestation with valid UID', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test attestation',
          },
        );

        expect(signed.uid, startsWith('0x'));
        expect(signed.uid.length, equals(66));
      });

      test('includes CSPRNG salt in result', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000), 'memo': 'Test'},
        );

        expect(signed.salt, startsWith('0x'));
        expect(signed.salt.length, equals(66)); // 0x + 64 hex chars
      });

      test('sets version to 2', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000), 'memo': 'Test'},
        );

        expect(signed.version, equals(EASConstants.attestationVersion));
      });

      test('signature has valid v, r, s components', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000), 'memo': 'Test'},
        );

        expect(signed.signature.v, anyOf(equals(27), equals(28)));
        expect(signed.signature.r, startsWith('0x'));
        expect(signed.signature.s, startsWith('0x'));
      });

      test('produces different UIDs for different salts', () async {
        final signed1 = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000), 'memo': 'Test'},
        );
        final signed2 = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000), 'memo': 'Test'},
        );

        // Salt is random, so UIDs should differ
        expect(signed1.uid, isNot(equals(signed2.uid)));
      });
    });

    group('verifyOffchainAttestation', () {
      test('verifies a valid attestation', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test verif',
          },
        );

        final result = signer.verifyOffchainAttestation(signed);
        expect(result.isValid, isTrue);
      });

      test('recovered address matches signer', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000), 'memo': 'Test'},
        );

        final result = signer.verifyOffchainAttestation(signed);
        expect(
          result.recoveredAddress.toLowerCase(),
          equals(signed.signer.toLowerCase()),
        );
      });
    });

    group('signerAddress', () {
      test('returns a valid Ethereum address', () {
        final addr = signer.signerAddress;
        expect(addr, startsWith('0x'));
        expect(addr.length, equals(42));
        expect(addr, equals('0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'));
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4: Public typed-data and UID utility tests
  // ---------------------------------------------------------------------------

  group('public utilities', () {
    const schemaUID =
        '0x0000000000000000000000000000000000000000000000000000000000000001';
    const recipient = '0x0000000000000000000000000000000000000000';
    final time = BigInt.from(1710000000);
    final expirationTime = BigInt.zero;
    const revocable = true;
    const refUID =
        '0x0000000000000000000000000000000000000000000000000000000000000000';
    final data = Uint8List(0);
    final salt = Uint8List(32); // all-zero salt for determinism

    test('buildOffchainTypedDataJson returns correct top-level structure', () {
      final json = OffchainSigner.buildOffchainTypedDataJson(
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
        schemaUID: schemaUID,
        recipient: recipient,
        time: time,
        expirationTime: expirationTime,
        revocable: revocable,
        refUID: refUID,
        data: data,
        salt: salt,
      );

      expect(
        json.keys,
        containsAll(['types', 'primaryType', 'domain', 'message']),
      );
      expect(json['primaryType'], equals('Attest'));
    });

    test('buildOffchainTypedDataJson domain has correct values', () {
      final json = OffchainSigner.buildOffchainTypedDataJson(
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
        schemaUID: schemaUID,
        recipient: recipient,
        time: time,
        expirationTime: expirationTime,
        revocable: revocable,
        refUID: refUID,
        data: data,
        salt: salt,
      );

      final domain = json['domain'] as Map<String, dynamic>;
      expect(domain['name'], equals('EAS Attestation'));
      expect(domain['chainId'], equals('11155111')); // decimal string
      expect(
        domain['verifyingContract'],
        equals('0xC2679fBD37d54388Ce493F1DB75320D236e1815e'),
      );
    });

    test(
      'buildOffchainTypedDataJson message has correct schema and version',
      () {
        final json = OffchainSigner.buildOffchainTypedDataJson(
          chainId: 11155111,
          easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
          schemaUID: schemaUID,
          recipient: recipient,
          time: time,
          expirationTime: expirationTime,
          revocable: revocable,
          refUID: refUID,
          data: data,
          salt: salt,
        );

        final message = json['message'] as Map<String, dynamic>;
        expect(message['schema'], equals(schemaUID));
        // version is attestationVersion (int 2) — stored as decimal string
        expect(message['version'], equals('2'));
      },
    );

    test(
      'buildOffchainTypedDataJson types has 9 Attest fields and 4 EIP712Domain fields',
      () {
        final json = OffchainSigner.buildOffchainTypedDataJson(
          chainId: 11155111,
          easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
          schemaUID: schemaUID,
          recipient: recipient,
          time: time,
          expirationTime: expirationTime,
          revocable: revocable,
          refUID: refUID,
          data: data,
          salt: salt,
        );

        final types = json['types'] as Map<String, dynamic>;
        final attestFields = types['Attest'] as List<dynamic>;
        final domainFields = types['EIP712Domain'] as List<dynamic>;
        expect(attestFields.length, equals(9));
        expect(domainFields.length, equals(4));
      },
    );

    test(
      'buildOffchainTypedDataJson digest parities with native Eip712TypedData',
      () {
        final json = OffchainSigner.buildOffchainTypedDataJson(
          chainId: 11155111,
          easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
          schemaUID: schemaUID,
          recipient: recipient,
          time: time,
          expirationTime: expirationTime,
          revocable: revocable,
          refUID: refUID,
          data: data,
          salt: salt,
        );

        // Digest from JSON-safe map (wallet path)
        final digestFromJson = Eip712TypedData.fromJson(json).encode();

        // Digest from native Eip712TypedData (existing internal path) — not yet
        // exposed as public, but we can build it ourselves for the parity check:
        final nativeTypedData = Eip712TypedData(
          types: {
            'EIP712Domain': [
              Eip712TypeDetails(name: 'name', type: 'string'),
              Eip712TypeDetails(name: 'version', type: 'string'),
              Eip712TypeDetails(name: 'chainId', type: 'uint256'),
              Eip712TypeDetails(name: 'verifyingContract', type: 'address'),
            ],
            'Attest': [
              Eip712TypeDetails(name: 'version', type: 'uint16'),
              Eip712TypeDetails(name: 'schema', type: 'bytes32'),
              Eip712TypeDetails(name: 'recipient', type: 'address'),
              Eip712TypeDetails(name: 'time', type: 'uint64'),
              Eip712TypeDetails(name: 'expirationTime', type: 'uint64'),
              Eip712TypeDetails(name: 'revocable', type: 'bool'),
              Eip712TypeDetails(name: 'refUID', type: 'bytes32'),
              Eip712TypeDetails(name: 'data', type: 'bytes'),
              Eip712TypeDetails(name: 'salt', type: 'bytes32'),
            ],
          },
          primaryType: 'Attest',
          domain: {
            'name': 'EAS Attestation',
            'version': '1.0.0',
            'chainId': BigInt.from(11155111),
            'verifyingContract': '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
          },
          message: {
            'version': EASConstants.attestationVersion,
            'schema': schemaUID,
            'recipient': recipient,
            'time': time,
            'expirationTime': expirationTime,
            'revocable': revocable,
            'refUID': refUID,
            'data': data,
            'salt': salt,
          },
        );

        expect(digestFromJson, equals(nativeTypedData.encode()));
      },
    );

    test(
      'computeOffchainUID matches signOffchainAttestation UID (deterministic salt)',
      () async {
        final deterministicSalt = Uint8List(32)
          ..[0] = 0xAB
          ..[1] = 0xCD;

        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000), 'memo': 'UID test'},
          time: BigInt.from(1710000000),
          salt: deterministicSalt,
        );

        final computedUID = OffchainSigner.computeOffchainUID(
          schemaUID: signed.schemaUID,
          recipient: signed.recipient,
          time: signed.time,
          expirationTime: signed.expirationTime,
          revocable: signed.revocable,
          refUID: signed.refUID,
          data: signed.data,
          salt: deterministicSalt,
        );

        expect(computedUID, equals(signed.uid));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Task 5: OffchainSigner constructor refactor + fromPrivateKey factory
  // ---------------------------------------------------------------------------

  group('fromPrivateKey factory', () {
    test('constructs OffchainSigner with correct signerAddress', () {
      final s = OffchainSigner.fromPrivateKey(
        privateKeyHex: testPrivateKeyHex,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );
      expect(
        s.signerAddress.toLowerCase(),
        equals('0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266'),
      );
    });

    test(
      'primary constructor + fromPrivateKey produce identical attestations',
      () async {
        final detSalt = Uint8List(32)..[0] = 0x42;
        final detTime = BigInt.from(1710000001);

        // via fromPrivateKey
        final signerA = OffchainSigner.fromPrivateKey(
          privateKeyHex: testPrivateKeyHex,
          chainId: 11155111,
          easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
        );

        // via primary constructor w/ LocalKeySigner
        final signerB = OffchainSigner(
          signer: LocalKeySigner(privateKeyHex: testPrivateKeyHex),
          chainId: 11155111,
          easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
        );

        final signedA = await signerA.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000), 'memo': 'parity'},
          time: detTime,
          salt: detSalt,
        );

        final signedB = await signerB.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000), 'memo': 'parity'},
          time: detTime,
          salt: detSalt,
        );

        expect(signedA.uid, equals(signedB.uid));
        expect(signedA.signature.v, equals(signedB.signature.v));
        expect(signedA.signature.r, equals(signedB.signature.r));
        expect(signedA.signature.s, equals(signedB.signature.s));
      },
    );
  });

  group('v normalization', () {
    test('normalizes v from 0/1 range to 27/28', () async {
      const keyHex =
          'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
      final lowVSigner = _LowVSignerWrapper(privateKeyHex: keyHex);

      final offchainSigner = OffchainSigner(
        signer: lowVSigner,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );

      final signed = await offchainSigner.signOffchainAttestation(
        schema: schema,
        lpPayload: lpPayload,
        userData: {'timestamp': BigInt.from(1710000000), 'memo': 'v-norm'},
      );

      // v MUST be 27 or 28 after normalization
      expect(signed.signature.v, anyOf(equals(27), equals(28)));

      // Attestation MUST still verify correctly
      final result = offchainSigner.verifyOffchainAttestation(signed);
      expect(result.isValid, isTrue);
    });
  });
}

/// A [Signer] wrapper that shifts v back to 0/1 range to test normalization.
class _LowVSignerWrapper extends Signer {
  final LocalKeySigner _inner;

  _LowVSignerWrapper({required String privateKeyHex})
    : _inner = LocalKeySigner(privateKeyHex: privateKeyHex);

  @override
  String get address => _inner.address;

  @override
  Future<EIP712Signature> signDigest(Uint8List digest) async {
    final sig = await _inner.signDigest(digest);
    // shift v from 27/28 down to 0/1 to simulate some wallet responses
    final lowV = sig.v >= 27 ? sig.v - 27 : sig.v;
    return EIP712Signature(v: lowV, r: sig.r, s: sig.s);
  }
}
