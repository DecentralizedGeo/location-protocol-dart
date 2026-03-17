import 'package:test/test.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';
import 'package:location_protocol/src/rpc/default_rpc_provider.dart';

void main() {
  group('EASClient', () {
    test('constructs with required parameters', () {
      final client = EASClient(
        provider: DefaultRpcProvider(
          rpcUrl: 'https://rpc.sepolia.org',
          privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
          chainId: 11155111,
        ),
      );
      expect(client.provider.chainId, equals(11155111));
    });

    test('resolves EAS address from ChainConfig', () {
      final client = EASClient(
        provider: DefaultRpcProvider(
          rpcUrl: 'https://rpc.sepolia.org',
          privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
          chainId: 11155111,
        ),
      );
      expect(client.easAddress, startsWith('0x'));
    });

    test('accepts custom EAS address', () {
      final client = EASClient(
        provider: DefaultRpcProvider(
          rpcUrl: 'https://rpc.sepolia.org',
          privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
          chainId: 11155111,
        ),
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
        locationType: 'address',
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
        locationType: 'address',
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
        provider: DefaultRpcProvider(
          rpcUrl: 'http://localhost:1',
          privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
          chainId: 11155111,
        ),
      );
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'address',
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
        provider: DefaultRpcProvider(
          rpcUrl: 'http://localhost:1',
          privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
          chainId: 11155111,
        ),
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
        provider: DefaultRpcProvider(
          rpcUrl: 'http://localhost:1',
          privateKeyHex: 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
          chainId: 11155111,
        ),
      );
      expect(
        () => client.getAttestation(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });

    // -------------------------------------------------------------------------
    // Task 7: buildAttestTxRequest
    // -------------------------------------------------------------------------

    group('buildAttestTxRequest', () {
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );
      final lpPayload = LPPayload(
        lpVersion: '1.0.0',
        srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
        locationType: 'address',
        location: 'test-location',
      );
      const easAddress = '0xC2679fBD37d54388Ce493F1DB75320D236e1815e';

      test('builds correct transaction request map (no from, no value)', () {
        final callData = EASClient.buildAttestCallData(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000)},
        );

        final tx = EASClient.buildAttestTxRequest(
          easAddress: easAddress,
          callData: callData,
        );

        expect(tx['to'], equals(easAddress));
        expect(tx['data'], startsWith('0x'));
        expect(tx['value'], equals('0x0'));
        expect(tx.containsKey('from'), isFalse);
      });

      test('includes from key when provided', () {
        final callData = EASClient.buildAttestCallData(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000)},
        );

        const fromAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
        final tx = EASClient.buildAttestTxRequest(
          easAddress: easAddress,
          callData: callData,
          from: fromAddress,
        );

        expect(tx['from'], equals(fromAddress));
        expect(tx['to'], equals(easAddress));
      });

      test('custom value renders as hex string', () {
        final callData = EASClient.buildAttestCallData(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000)},
        );

        final tx = EASClient.buildAttestTxRequest(
          easAddress: easAddress,
          callData: callData,
          value: BigInt.from(1000000000000000000), // 1 ETH
        );

        expect(tx['value'], equals('0xde0b6b3a7640000'));
      });

      test('data hex matches buildAttestCallData output', () {
        final callData = EASClient.buildAttestCallData(
          schema: schema,
          lpPayload: lpPayload,
          userData: {'timestamp': BigInt.from(1710000000)},
        );

        final tx = EASClient.buildAttestTxRequest(
          easAddress: easAddress,
          callData: callData,
        );

        final dataHex = tx['data'] as String;
        expect(dataHex, startsWith('0x'));

        // First 4 bytes (8 hex chars + 0x prefix) are the function selector
        expect(dataHex.length, greaterThan(10));

        // Decoded bytes match original callData
        final decoded = List<int>.generate(
          (dataHex.length - 2) ~/ 2,
          (i) => int.parse(dataHex.substring(2 + i * 2, 4 + i * 2), radix: 16),
        );
        expect(decoded, equals(callData));
      });
    });
  });
}
