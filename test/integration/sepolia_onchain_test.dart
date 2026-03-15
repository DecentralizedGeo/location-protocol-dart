// ignore_for_file: avoid_print
@Tags(['sepolia'])
library;

import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/schema_registry.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';
import 'package:location_protocol/src/eas/abi_encoder.dart';
import 'package:location_protocol/src/eas/constants.dart';
import 'package:location_protocol/src/rpc/default_rpc_provider.dart';

import '../test_helpers/dotenv_loader.dart';

void main() {
  final env = loadDotEnv();
  final rpcUrl = env['SEPOLIA_RPC_URL'];
  final privateKey = env['SEPOLIA_PRIVATE_KEY'];
  final existingSchemaUid = env['SEPOLIA_EXISTING_SCHEMA_UID'];
  final skipReason = _sepoliaSkipReason(
    rpcUrl: rpcUrl,
    privateKey: privateKey,
    existingSchemaUid: existingSchemaUid,
  );

  if (skipReason != null) {
    print('⚠️  Skipping Sepolia tests: $skipReason');
    print('   Copy .env.example to .env and fill in your values.');
  }

  group('Sepolia Onchain Operations', skip: skipReason, () {
    final provider = DefaultRpcProvider(
      rpcUrl: rpcUrl!,
      privateKeyHex: privateKey!,
      chainId: 11155111,
    );

    final registry = SchemaRegistryClient(provider: provider);

    test('configured schema UID exists on Sepolia', () async {
      final schema = await registry.getSchema(existingSchemaUid!);
      expect(schema, isNotNull);
      expect(schema!.schema, isNotEmpty);
      expect(schema.uid, equals(existingSchemaUid));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('zero UID resolves as non-existent schema', () async {
      final schema = await registry.getSchema(EASConstants.zeroBytes32);
      expect(schema, isNull);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('attest and fetch onchain attestation with fixed schema UID', () async {
      final client = EASClient(provider: provider);
      final lpOnlySchema = SchemaDefinition(fields: []);

      final computedUid = SchemaRegistryClient.computeSchemaUID(lpOnlySchema);
      expect(computedUid, equals(existingSchemaUid));

      final submittedPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: 'test-location-${DateTime.now().millisecondsSinceEpoch}',
      );

      final expectedEncodedPayload = AbiEncoder.encode(
        schema: lpOnlySchema,
        lpPayload: submittedPayload,
        userData: const {},
      );

      final result = await client.attest(
        schema: lpOnlySchema,
        lpPayload: submittedPayload,
        userData: const {},
      );
      expect(result.txHash, startsWith('0x'));
      expect(result.txHash.length, equals(66));
      expect(result.uid, startsWith('0x'));
      expect(result.uid.length, equals(66));

      final fetched = await client.getAttestation(result.uid);
      expect(fetched, isNotNull);

      final attestation = fetched!;
      expect(attestation.uid, equals(result.uid));
      expect(attestation.schema.toLowerCase(), equals(existingSchemaUid!.toLowerCase()));
      expect(attestation.recipient, equals(EASConstants.zeroAddress));
      expect(attestation.refUID, equals(EASConstants.zeroBytes32));
      expect(attestation.revocable, equals(lpOnlySchema.revocable));
      expect(attestation.expirationTime, equals(BigInt.zero));
      expect(attestation.data, equals(expectedEncodedPayload));

      print('Attestation TX: ${result.txHash}');
      print('Attestation UID: ${result.uid}');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

String? _sepoliaSkipReason({
  required String? rpcUrl,
  required String? privateKey,
  required String? existingSchemaUid,
}) {
  if (rpcUrl == null || privateKey == null || existingSchemaUid == null) {
    return 'SEPOLIA_RPC_URL, SEPOLIA_PRIVATE_KEY, or SEPOLIA_EXISTING_SCHEMA_UID missing.';
  }

  if (!existingSchemaUid.startsWith('0x') || existingSchemaUid.length != 66) {
    return 'SEPOLIA_EXISTING_SCHEMA_UID must be 0x-prefixed bytes32 (66 chars).';
  }

  return null;
}
