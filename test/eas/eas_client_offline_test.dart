import 'package:test/test.dart';
import 'package:location_protocol/src/eas/constants.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/models/attest_result.dart';
import 'package:location_protocol/src/rpc/transaction_receipt.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import '../rpc/fake_rpc_provider.dart';

void main() {
  test('EASClient handles missing attestation purely offline', () async {
    final fakeProvider = FakeRpcProvider();
    
    // Mock the raw tuple response for "not found"
    // getAttestation expects a single tuple element in the list, containing 10 fields.
    fakeProvider.contractCallMocks['getAttestation'] = [
      [
        // Return 0x000.. for the UID element to simulate missing record
        '0x0000000000000000000000000000000000000000000000000000000000000000',
        '0x0', BigInt.zero, BigInt.zero, BigInt.zero, '0x0', '0x0', '0x0', false, <int>[]
      ]
    ];

    final client = EASClient(provider: fakeProvider);
    
    final result = await client.getAttestation('0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef');
    expect(result, isNull);
  });

  group('EASClient.attest (offline)', () {
    late FakeRpcProvider fakeProvider;
    late EASClient client;
    final easAddress = '0xC2679fBD37d54388Ce493F1DB75320D236e1815e';

    setUp(() {
      fakeProvider = FakeRpcProvider();
      client = EASClient(provider: fakeProvider, easAddress: easAddress);
    });

    test('returns AttestResult with uid from Attested event log', () async {
      final expectedUid =
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
      fakeProvider.receiptMocks['0xFakeTxHash'] = TransactionReceipt(
        txHash: '0xFakeTxHash',
        blockNumber: 42,
        status: true,
        logs: [
          TransactionLog(
            address: easAddress,
            topics: [
              EASConstants.attestedEventTopic,
              '0x0000000000000000000000000000000000000000000000000000000000000000',
              '0x0000000000000000000000000000000000000000000000000000000000000000',
              '0x0000000000000000000000000000000000000000000000000000000000000000',
            ],
            data: expectedUid,
          ),
        ],
      );

      final result = await client.attest(
        schema: SchemaDefinition(
          fields: [SchemaField(type: 'string', name: 'test')],
        ),
        lpPayload: LPPayload(
          lpVersion: '1.0.0',
          srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
          locationType: 'geojson-point',
          location: 'test',
        ),
        userData: {'test': 'value'},
      );

      expect(result, isA<AttestResult>());
      expect(result.txHash, equals('0xFakeTxHash'));
      expect(result.uid, equals(expectedUid));
      expect(result.blockNumber, equals(42));
    });

    test('throws StateError when no Attested log in receipt', () async {
      fakeProvider.receiptMocks['0xFakeTxHash'] = TransactionReceipt(
        txHash: '0xFakeTxHash',
        blockNumber: 42,
        status: true,
        logs: [],
      );

      expect(
        () => client.attest(
          schema: SchemaDefinition(
            fields: [SchemaField(type: 'string', name: 'test')],
          ),
          lpPayload: LPPayload(
            lpVersion: '1.0.0',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'geojson-point',
            location: 'test',
          ),
          userData: {'test': 'value'},
        ),
        throwsStateError,
      );
    });

    test('ignores logs from wrong contract address', () async {
      fakeProvider.receiptMocks['0xFakeTxHash'] = TransactionReceipt(
        txHash: '0xFakeTxHash',
        blockNumber: 42,
        status: true,
        logs: [
          TransactionLog(
            address: '0xWrongAddress',
            topics: [
              EASConstants.attestedEventTopic,
              '0x0000000000000000000000000000000000000000000000000000000000000000',
              '0x0000000000000000000000000000000000000000000000000000000000000000',
              '0x0000000000000000000000000000000000000000000000000000000000000000',
            ],
            data: '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          ),
        ],
      );

      expect(
        () => client.attest(
          schema: SchemaDefinition(
            fields: [SchemaField(type: 'string', name: 'test')],
          ),
          lpPayload: LPPayload(
            lpVersion: '1.0.0',
            srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
            locationType: 'geojson-point',
            location: 'test',
          ),
          userData: {'test': 'value'},
        ),
        throwsStateError,
      );
    });
  });
}
