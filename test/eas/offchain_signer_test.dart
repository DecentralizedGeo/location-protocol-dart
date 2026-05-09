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

        expect(signed.saltHex, startsWith('0x'));
        expect(signed.saltHex!.length, equals(66)); // 0x + 64 hex chars
      });

      test('sets version to 2', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000), 'memo': 'Test'},
        );

        expect(signed.offchainVersion, equals(EASConstants.attestationVersion));
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

      test(
        'accepts cross-tool attestation with different domain version (mirrors strict=false)',
        () async {
          // Sign with easVersion='0.26' — simulating an attestation produced by
          // a different EAS SDK version.
          final altSigner = OffchainSigner.fromPrivateKey(
            privateKeyHex: testPrivateKeyHex,
            chainId: 11155111,
            easContractAddress:
                '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
            easVersion: '0.26',
          );
          final signed = await altSigner.signOffchainAttestation(
            schema: schema,
            lpPayload: lpPayload,
            userData: {
              'timestamp': BigInt.from(1710000000),
              'memo': 'cross-tool',
            },
          );

          // The stored domain will have version '0.26'.
          expect(signed.domain['version'], equals('0.26'));

          // A verifier configured with easVersion='1.0.0' should still accept
          // it — the signature is cryptographically valid regardless of version.
          final result = signer.verifyOffchainAttestation(signed);
          expect(result.isValid, isTrue,
              reason: result.reason ?? 'expected isValid=true');
        },
      );
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
  // Task 4: UID utility tests
  // ---------------------------------------------------------------------------

  group('public utilities', () {
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
          data: signed.dataBytes,
          salt: deterministicSalt,
        );

        expect(computedUID, equals(signed.uid));
      },
    );

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
        final sepoliaTypedData = _buildTypedDataFromSigned(sepoliaSigned);
        final baseSepoliaTypedData = _buildTypedDataFromSigned(baseSepoliaSigned);

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
      expect(sepoliaSigned.dataBytes, orderedEquals(baseSepoliaSigned.dataBytes));
      expect(sepoliaSigned.saltHex, equals(baseSepoliaSigned.saltHex));
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

    test('auto-wires easVersion from ChainConfig when not supplied', () {
      // Chain 11155111 (Sepolia) → easVersion = '0.26'
      final sepoliaNoVersion = OffchainSigner.fromPrivateKey(
        privateKeyHex: testPrivateKeyHex,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );
      expect(sepoliaNoVersion.easVersion, equals('0.26'));
      expect(
        sepoliaNoVersion.easVersion,
        equals(ChainConfig.forChainId(11155111)!.easVersion),
      );

      // Chain 10 (Optimism) → easVersion = '1.0.1'
      final optimism = OffchainSigner.fromPrivateKey(
        privateKeyHex: testPrivateKeyHex,
        chainId: 10,
        easContractAddress: '0x4200000000000000000000000000000000000021',
      );
      expect(optimism.easVersion, equals('1.0.1'));

      // Chain 84532 (Base Sepolia) → easVersion = '1.2.0'
      final baseSepolia = OffchainSigner.fromPrivateKey(
        privateKeyHex: testPrivateKeyHex,
        chainId: 84532,
        easContractAddress: '0x4200000000000000000000000000000000000021',
      );
      expect(baseSepolia.easVersion, equals('1.2.0'));

      // Unknown chain must now fail fast unless easVersion is supplied.
      expect(
        () => OffchainSigner.fromPrivateKey(
          privateKeyHex: testPrivateKeyHex,
          chainId: 999999,
          easContractAddress: '0xUnknown',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Explicit version override is still allowed for unsupported chains.
      final unknownWithVersion = OffchainSigner.fromPrivateKey(
        privateKeyHex: testPrivateKeyHex,
        chainId: 999999,
        easContractAddress: '0xUnknown',
        easVersion: '1.4.0',
      );
      expect(unknownWithVersion.easVersion, equals('1.4.0'));
    });

    test('explicit easVersion overrides ChainConfig lookup', () {
      // Sepolia would normally be '0.26', but explicit override wins
      final s = OffchainSigner.fromPrivateKey(
        privateKeyHex: testPrivateKeyHex,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
        easVersion: '1.4.0',
      );
      expect(s.easVersion, equals('1.4.0'));
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
    data: signed.dataBytes,
    salt: signed.saltBytes!,
  );
}

/// Builds a wallet-signing-format typed data JSON from a signed attestation.
///
/// Converts canonical envelope maps (integers stored as [int]/[BigInt]) into
/// decimal-string format required by [Eip712TypedData.fromJson].
Map<String, dynamic> _buildTypedDataFromSigned(
  SignedOffchainAttestation signed,
) {
  final signDomain = {
    ...signed.domain,
    'chainId': (signed.domain['chainId'] as int).toString(),
  };
  final timeVal = signed.time;
  final expVal = signed.expirationTime;
  final verVal = signed.message['version'];
  final signMessage = {
    ...signed.message,
    'time': timeVal.toString(),
    'expirationTime': expVal.toString(),
    'version': (verVal is int ? verVal : int.parse(verVal.toString())).toString(),
  };
  return {
    'types': signed.types,
    'primaryType': 'Attest',
    'domain': signDomain,
    'message': signMessage,
  };
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
