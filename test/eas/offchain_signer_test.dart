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
import 'package:location_protocol/src/models/attestation.dart';
import 'package:location_protocol/src/models/signature.dart';
import 'package:location_protocol/src/models/verification_result.dart';
import 'package:location_protocol/src/utils/hex_utils.dart';

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

  Map<String, dynamic> _canonicalEnvelopeJsonFor(
    SignedOffchainAttestation signed,
  ) {
    return signed.toJson();
  }

  SignedOffchainAttestation _tamperEnvelope(
    SignedOffchainAttestation signed,
    void Function(Map<String, dynamic> sig) mutate,
  ) {
    final json = _canonicalEnvelopeJsonFor(signed);
    final sig = Map<String, dynamic>.from(json['sig'] as Map);
    mutate(sig);
    return SignedOffchainAttestation.fromJson({
      'signer': json['signer'],
      'sig': sig,
    });
  }

  group('OffchainSigner', () {
    group('signOffchainAttestation', () {
      test('returns canonical EAS envelope JSON', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'shape test',
          },
        );

        final json = signed.toJson();
        final sig = json['sig'] as Map<String, dynamic>;
        final message = sig['message'] as Map<String, dynamic>;

        expect(json.keys.toList(), equals(['signer', 'sig']));
        expect(json['signer'], equals(signed.signer));
        expect(sig['primaryType'], equals('Attest'));
        expect(message['salt'], isNotNull);
      });

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

      test(
        'signOffchainWithData supports dynamic custom schema payloads',
        () async {
          final dynamicSchema = SchemaDefinition(
            fields: [
              SchemaField(type: 'string[]', name: 'tags'),
              SchemaField(type: 'bytes32', name: 'content_hash'),
            ],
          );

          final signed = await signer.signOffchainWithData(
            schema: dynamicSchema,
            lpPayload: lpPayload,
            userData: {
              'tags': ['user-defined', 'payload'],
              'content_hash':
                  '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            },
          );

          final result = signer.verifyOffchainAttestation(signed);
          expect(result.isValid, isTrue);
        },
      );

      test(
        'signOffchainWithData throws ArgumentError on schema key mismatch',
        () async {
          await expectLater(
            signer.signOffchainWithData(
              schema: schema,
              lpPayload: lpPayload,
              userData: {
                'wrong_key': BigInt.from(1710000000),
                'memo': 'Test mismatch',
              },
            ),
            throwsA(isA<ArgumentError>()),
          );
        },
      );
    });

    group('verifyOffchainAttestation', () {
      test('fails when sig.uid is tampered', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'uid tamper',
          },
        );

        final tampered = _tamperEnvelope(signed, (sig) {
          sig['uid'] =
              '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
        });

        final result = signer.verifyOffchainAttestation(tampered);

        expect(result.isValid, isFalse);
        expect(result.code, equals(VerificationFailure.uidMismatch));
      });

      test('fails when sig.domain is tampered', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'domain tamper',
          },
        );

        final tampered = _tamperEnvelope(signed, (sig) {
          final domain = Map<String, dynamic>.from(
            sig['domain'] as Map<String, dynamic>,
          );
          domain['chainId'] = 1;
          sig['domain'] = domain;
        });

        final result = signer.verifyOffchainAttestation(tampered);

        expect(result.isValid, isFalse);
        expect(result.code, equals(VerificationFailure.invalidDomain));
      });

      test('fails when sig.types is tampered', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'types tamper',
          },
        );

        final tampered = _tamperEnvelope(signed, (sig) {
          final types = Map<String, dynamic>.from(
            sig['types'] as Map<String, dynamic>,
          );
          final attest = List<dynamic>.from(types['Attest'] as List<dynamic>);
          final firstField = Map<String, dynamic>.from(
            attest.first as Map<String, dynamic>,
          );
          firstField['type'] = 'uint8';
          attest[0] = firstField;
          types['Attest'] = attest;
          sig['types'] = types;
        });

        final result = signer.verifyOffchainAttestation(tampered);

        expect(result.isValid, isFalse);
        expect(result.code, equals(VerificationFailure.invalidTypes));
      });

      test('fails when sig.primaryType is tampered', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'primary type tamper',
          },
        );

        final tampered = _tamperEnvelope(signed, (sig) {
          sig['primaryType'] = 'Permit';
        });

        final result = signer.verifyOffchainAttestation(tampered);

        expect(result.isValid, isFalse);
        expect(result.code, equals(VerificationFailure.invalidPrimaryType));
      });

      test('fails when sig.message is tampered', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'message tamper',
          },
        );

        final tampered = _tamperEnvelope(signed, (sig) {
          final message = Map<String, dynamic>.from(
            sig['message'] as Map<String, dynamic>,
          );
          message['version'] = 3;
          sig['message'] = message;
        });

        final result = signer.verifyOffchainAttestation(tampered);

        expect(result.isValid, isFalse);
        expect(result.code, equals(VerificationFailure.invalidMessage));
      });

      test('fails when sig.signature is tampered', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'signature tamper',
          },
        );

        final tampered = _tamperEnvelope(signed, (sig) {
          final signature = Map<String, dynamic>.from(
            sig['signature'] as Map<String, dynamic>,
          );
          signature['v'] = 29;
          sig['signature'] = signature;
        });

        final result = signer.verifyOffchainAttestation(tampered);

        expect(result.isValid, isFalse);
        expect(result.code, equals(VerificationFailure.invalidSignature));
      });

      test('fails when version 2 salt is missing', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'salt tamper',
          },
        );

        final tampered = _tamperEnvelope(signed, (sig) {
          final message = Map<String, dynamic>.from(
            sig['message'] as Map<String, dynamic>,
          );
          message.remove('salt');
          sig['message'] = message;
        });

        final result = signer.verifyOffchainAttestation(tampered);

        expect(result.isValid, isFalse);
        expect(result.code, equals(VerificationFailure.invalidMessage));
      });

      test('fails cleanly when salt encoding is malformed', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'bad salt encoding',
          },
        );

        final tampered = _tamperEnvelope(signed, (sig) {
          final message = Map<String, dynamic>.from(
            sig['message'] as Map<String, dynamic>,
          );
          message['salt'] = 'not-hex';
          sig['message'] = message;
        });

        final result = signer.verifyOffchainAttestation(tampered);

        expect(result.isValid, isFalse);
        expect(result.code, equals(VerificationFailure.invalidMessage));
      });

      test('fails cleanly when signature encoding is malformed', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'bad signature encoding',
          },
        );

        final tampered = _tamperEnvelope(signed, (sig) {
          final signature = Map<String, dynamic>.from(
            sig['signature'] as Map<String, dynamic>,
          );
          signature['r'] = '0xzz';
          sig['signature'] = signature;
        });

        final result = signer.verifyOffchainAttestation(tampered);

        expect(result.isValid, isFalse);
        expect(result.code, equals(VerificationFailure.invalidSignature));
      });

      test('fails when signer field is tampered', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'signer tamper',
          },
        );

        final tampered = SignedOffchainAttestation.fromJson({
          ...signed.toJson(),
          'signer': '0x000000000000000000000000000000000000dEaD',
        });

        final result = signer.verifyOffchainAttestation(tampered);

        expect(result.isValid, isFalse);
        expect(result.code, equals(VerificationFailure.signerMismatch));
      });

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

    test('buildOffchainTypedDataJsonFromEnvelope normalizes string chainId', () async {
      final signed = await signer.signOffchainAttestation(
        schema: schema,
        lpPayload: lpPayload,
        userData: {'timestamp': BigInt.from(1710000000), 'memo': 'chainId'},
      );

      final json = signed.toJson();
      final sig = Map<String, dynamic>.from(json['sig'] as Map<String, dynamic>);
      final domain = Map<String, dynamic>.from(sig['domain'] as Map<String, dynamic>);
      domain['chainId'] = '11155111';
      sig['domain'] = domain;

      final fromJson = SignedOffchainAttestation.fromJson({
        'signer': json['signer'],
        'sig': sig,
      });

      final typedData = OffchainSigner.buildOffchainTypedDataJsonFromEnvelope(fromJson);

      expect((typedData['domain'] as Map<String, dynamic>)['chainId'], equals('11155111'));
    });

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

    test('computeOffchainUID matches pinned deterministic fixture', () async {
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

      expect(
        signed.uid,
        equals('0x1d433596db24f913cc5c68e3f8d84cdc66629c0608639fe0db803f1538423dd6'),
      );
    });

    test(
      'offchain UID matches across chains for identical attestation payloads',
      () async {
        final deterministicSalt = Uint8List(32)
          ..[0] = 0x12
          ..[1] = 0x34;
        final deterministicTime = BigInt.from(1710000000);

        final sepoliaSigner = OffchainSigner.fromPrivateKey(
          privateKeyHex: testPrivateKeyHex,
          chainId: 11155111,
          easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
        );
        final baseSepoliaSigner = OffchainSigner.fromPrivateKey(
          privateKeyHex: testPrivateKeyHex,
          chainId: 84532,
          easContractAddress: '0x4200000000000000000000000000000000000021',
        );

        final sepoliaSigned = await sepoliaSigner.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': deterministicTime,
            'memo': 'cross-chain parity',
          },
          time: deterministicTime,
          salt: deterministicSalt,
        );
        final baseSepoliaSigned = await baseSepoliaSigner
            .signOffchainAttestation(
              schema: schema,
              lpPayload: lpPayload,
              userData: {
                'timestamp': deterministicTime,
                'memo': 'cross-chain parity',
              },
              time: deterministicTime,
              salt: deterministicSalt,
            );

        final sepoliaComputedUid = _computeUidFromSigned(sepoliaSigned);
        final baseSepoliaComputedUid = _computeUidFromSigned(baseSepoliaSigned);
        final sepoliaTypedData = _buildTypedDataFromSigned(
          signed: sepoliaSigned,
          chainId: 11155111,
          easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
        );
        final baseSepoliaTypedData = _buildTypedDataFromSigned(
          signed: baseSepoliaSigned,
          chainId: 84532,
          easContractAddress: '0x4200000000000000000000000000000000000021',
        );

        expect(sepoliaSigned.uid, equals(baseSepoliaSigned.uid));
        expect(sepoliaComputedUid, equals(sepoliaSigned.uid));
        expect(baseSepoliaComputedUid, equals(baseSepoliaSigned.uid));
        expect(sepoliaComputedUid, equals(baseSepoliaComputedUid));

        expect(sepoliaSigned.schemaUID, equals(baseSepoliaSigned.schemaUID));
        expect(sepoliaSigned.recipient, equals(baseSepoliaSigned.recipient));
        expect(sepoliaSigned.time, equals(baseSepoliaSigned.time));
        expect(
          sepoliaSigned.expirationTime,
          equals(baseSepoliaSigned.expirationTime),
        );
        expect(sepoliaSigned.revocable, equals(baseSepoliaSigned.revocable));
        expect(sepoliaSigned.refUID, equals(baseSepoliaSigned.refUID));
        expect(sepoliaSigned.data, orderedEquals(baseSepoliaSigned.data));
        expect(sepoliaSigned.salt, equals(baseSepoliaSigned.salt));
        expect(sepoliaSigned.signer, equals(baseSepoliaSigned.signer));

        expect(
          sepoliaTypedData['message'],
          equals(baseSepoliaTypedData['message']),
        );
        expect(
          (sepoliaTypedData['domain'] as Map<String, dynamic>)['chainId'],
          isNot(
            equals(
              (baseSepoliaTypedData['domain']
                  as Map<String, dynamic>)['chainId'],
            ),
          ),
        );
        expect(
          (sepoliaTypedData['domain']
              as Map<String, dynamic>)['verifyingContract'],
          isNot(
            equals(
              (baseSepoliaTypedData['domain']
                  as Map<String, dynamic>)['verifyingContract'],
            ),
          ),
        );
        expect(
          Eip712TypedData.fromJson(sepoliaTypedData).encode(),
          isNot(
            equals(Eip712TypedData.fromJson(baseSepoliaTypedData).encode()),
          ),
        );

        expect(
          sepoliaSigned.signature.r,
          isNot(equals(baseSepoliaSigned.signature.r)),
        );
        expect(
          sepoliaSigned.signature.s,
          isNot(equals(baseSepoliaSigned.signature.s)),
        );
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

String _computeUidFromSigned(SignedOffchainAttestation signed) {
  return OffchainSigner.computeOffchainUID(
    schemaUID: signed.schemaUID,
    recipient: signed.recipient,
    time: signed.time,
    expirationTime: signed.expirationTime,
    revocable: signed.revocable,
    refUID: signed.refUID,
    data: signed.data,
    salt: signed.salt.toBytes(),
  );
}

Map<String, dynamic> _buildTypedDataFromSigned({
  required SignedOffchainAttestation signed,
  required int chainId,
  required String easContractAddress,
}) {
  return OffchainSigner.buildOffchainTypedDataJson(
    chainId: chainId,
    easContractAddress: easContractAddress,
    schemaUID: signed.schemaUID,
    recipient: signed.recipient,
    time: signed.time,
    expirationTime: signed.expirationTime,
    revocable: signed.revocable,
    refUID: signed.refUID,
    data: signed.data,
    salt: signed.salt.toBytes(),
  );
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
