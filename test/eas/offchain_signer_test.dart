// import 'dart:typed_data'; // Unused

import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/offchain_signer.dart';
import 'package:location_protocol/src/eas/constants.dart';

void main() {
  // A well-known test private key — NEVER use in production
  // Address: 0x2e988A386a799F506693793c6A5AF6B54dfAaBfB
  const testPrivateKeyHex =
      'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  late OffchainSigner signer;
  late SchemaDefinition schema;
  late LPPayload lpPayload;

  setUp(() {
    signer = OffchainSigner(
      privateKeyHex: testPrivateKeyHex,
      chainId: 11155111, // Sepolia
      easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      easVersion: '1.0.0',
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
      location: {'type': 'Point', 'coordinates': [-103.771556, 44.967243]},
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
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
        );

        expect(signed.salt, startsWith('0x'));
        expect(signed.salt.length, equals(66)); // 0x + 64 hex chars
      });

      test('sets version to 2', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
        );

        expect(signed.version, equals(EASConstants.attestationVersion));
      });

      test('signature has valid v, r, s components', () async {
        final signed = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
        );

        expect(signed.signature.v, anyOf(equals(27), equals(28)));
        expect(signed.signature.r, startsWith('0x'));
        expect(signed.signature.s, startsWith('0x'));
      });

      test('produces different UIDs for different salts', () async {
        final signed1 = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
        );
        final signed2 = await signer.signOffchainAttestation(
          schema: schema,
          lpPayload: lpPayload,
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
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
          userData: {
            'timestamp': BigInt.from(1710000000),
            'memo': 'Test',
          },
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
}
