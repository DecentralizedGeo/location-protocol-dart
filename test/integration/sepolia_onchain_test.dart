@Tags(['sepolia'])
library;

import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/schema_registry.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';
import 'package:location_protocol/src/eas/offchain_signer.dart';
import 'package:location_protocol/src/rpc/default_rpc_provider.dart';

import '../test_helpers/dotenv_loader.dart';

void main() {
  final env = loadDotEnv();
  final rpcUrl = env['SEPOLIA_RPC_URL'];
  final privateKey = env['SEPOLIA_PRIVATE_KEY'];

  if (rpcUrl == null || privateKey == null) {
    print('⚠️  Skipping Sepolia tests: .env file missing or incomplete.');
    print('   Copy .env.example to .env and fill in your values.');
    return;
  }

  group('Sepolia Onchain Operations', () {
    test('register a schema on Sepolia', () async {
      final registry = SchemaRegistryClient(
        provider: DefaultRpcProvider(
          rpcUrl: rpcUrl,
          privateKeyHex: privateKey,
          chainId: 11155111,
        ),
      );

      // Use a unique schema to avoid "already registered" reverts.
      final uniqueField =
          'test_${DateTime.now().millisecondsSinceEpoch}';
      final schema = SchemaDefinition(
        fields: [
          SchemaField(type: 'string', name: uniqueField),
        ],
      );

      final txHash = await registry.register(schema);
      expect(txHash, startsWith('0x'));
      expect(txHash.length, equals(66));

      print('Schema registered. TX: $txHash');
      print('Expected UID: ${SchemaRegistryClient.computeSchemaUID(schema)}');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('timestamp an offchain attestation on Sepolia', () async {
      final client = EASClient(
        provider: DefaultRpcProvider(
          rpcUrl: rpcUrl,
          privateKeyHex: privateKey,
          chainId: 11155111,
        ),
      );

      // First create an offchain attestation to get a UID
      final schema = SchemaDefinition(fields: []);
      final signer = OffchainSigner(
        privateKeyHex: privateKey,
        chainId: 11155111,
        easContractAddress: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      );

      final signed = await signer.signOffchainAttestation(
        schema: schema,
        lpPayload: LPPayload(
          lpVersion: '1.0.0',
          srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
          locationType: 'geojson-point',
          location: 'test-location',
        ),
        userData: {},
      );

      final txHash = await client.timestamp(signed.uid);
      expect(txHash, startsWith('0x'));
      expect(txHash.length, equals(66));

      print('Timestamp TX: $txHash');
      print('Timestamped UID: ${signed.uid}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
