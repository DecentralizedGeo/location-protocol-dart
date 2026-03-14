import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/schema_registry.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';
import 'package:location_protocol/src/rpc/default_rpc_provider.dart';

void main() {
  const testKey =
      'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  group('Onchain Workflow (Dry-Run)', () {
    test('register → attest → timestamp → query flow', () async {
      final rpcUrl = 'http://localhost:1'; // Unreachable for unit testing
      final chainId = 11155111;

      final registry = SchemaRegistryClient(
        provider: DefaultRpcProvider(
          rpcUrl: rpcUrl,
          privateKeyHex: testKey,
          chainId: chainId,
        ),
      );

      final client = EASClient(
        provider: DefaultRpcProvider(
          rpcUrl: rpcUrl,
          privateKeyHex: testKey,
          chainId: chainId,
        ),
      );

      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );

      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: 'test-location',
      );

      // We expect these to attempt RPC calls and fail with network errors
      // rather than UnimplementedError.

      // 1. Register Schema
      expect(
        () => registry.register(schema),
        throwsA(isNot(isA<UnimplementedError>())),
      );

      // 2. Query Schema
      expect(
        () => registry.getSchema(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );

      // 3. Attest
      expect(
        () => client.attest(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000)},
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );

      // 4. Timestamp
      expect(
        () => client.timestamp(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );

      // 5. Query Attestation
      expect(
        () => client.getAttestation(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });
  });
}
