import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';

void main() {
  group('EASClient', () {
    test('constructs with required parameters', () {
      final client = EASClient(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(client.chainId, equals(11155111));
    });

    test('resolves EAS address from ChainConfig', () {
      final client = EASClient(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(client.easAddress, startsWith('0x'));
    });

    test('accepts custom EAS address', () {
      final client = EASClient(
        rpcUrl: 'https://rpc.sepolia.org',
        privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
        easAddress: '0xCustomEAS',
      );
      expect(client.easAddress, equals('0xCustomEAS'));
    });

    test('buildTimestampCallData produces non-empty bytes', () {
      final callData = EASClient.buildTimestampCallData(
        '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
      );
      expect(callData, isNotEmpty);
    });

    test('buildAttestCallData produces non-empty bytes', () {
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: 'test-location',
      );

      final callData = EASClient.buildAttestCallData(
        schema: schema,
        lpPayload: lpPayload,
        userData: {'timestamp': BigInt.from(1710000000)},
      );
      expect(callData, isNotEmpty);
      // Must start with the 4-byte function selector
      expect(callData.length, greaterThan(4));
    });

    test('buildAttestCallData includes function selector', () {
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'geojson-point',
        location: 'test-location',
      );

      final data1 = EASClient.buildAttestCallData(
        schema: schema,
        lpPayload: lpPayload,
        userData: {'timestamp': BigInt.from(1710000000)},
      );
      final data2 = EASClient.buildAttestCallData(
        schema: schema,
        lpPayload: lpPayload,
        userData: {'timestamp': BigInt.from(9999999999)},
      );
      // Same function selector (first 4 bytes)
      expect(data1.sublist(0, 4), equals(data2.sublist(0, 4)));
      // Different data
      expect(data1, isNot(equals(data2)));
    });

    test('attest attempts RPC call (fails gracefully without network)', () {
      final client = EASClient(
        rpcUrl: 'http://localhost:1',
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
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

      expect(
        () => client.attest(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000)},
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });

    test('timestamp attempts RPC call (fails gracefully without network)', () {
      final client = EASClient(
        rpcUrl: 'http://localhost:1',
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(
        () => client.timestamp(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });

    test('getAttestation attempts RPC call (fails gracefully without network)', () {
      final client = EASClient(
        rpcUrl: 'http://localhost:1',
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(
        () => client.getAttestation(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });
  });
}
