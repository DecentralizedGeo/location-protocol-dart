import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:location_protocol/src/eas/constants.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';
import 'package:location_protocol/src/models/attestation.dart';
import 'package:location_protocol/src/lp/lp_payload.dart';
import 'package:location_protocol/src/models/attest_result.dart';
import 'package:location_protocol/src/models/timestamp_result.dart';
import 'package:location_protocol/src/rpc/transaction_receipt.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import '../rpc/fake_rpc_provider.dart';

const _expectedUid =
    '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
const _schemaUid =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _refUid =
    '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _recipient =
    '0x1111111111111111111111111111111111111111';
const _attester =
    '0x2222222222222222222222222222222222222222';

TransactionReceipt _attestedReceipt(String easAddress, {bool? status = true}) {
  return TransactionReceipt(
    txHash: '0xFakeTxHash',
    blockNumber: 42,
    status: status,
    logs: [
      TransactionLog(
        address: easAddress,
        topics: [
          EASConstants.attestedEventTopic,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
        ],
        data: _expectedUid,
      ),
    ],
  );
}

List<dynamic> _attestationTuple({String uid = _expectedUid}) {
  return [
    [
      uid,
      _schemaUid,
      BigInt.from(1710000000),
      BigInt.zero,
      BigInt.zero,
      _refUid,
      _recipient,
      _attester,
      true,
      Uint8List.fromList([1, 2, 3]),
    ],
  ];
}

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
          locationType: 'address',
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
            locationType: 'address',
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
            locationType: 'address',
            location: 'test',
          ),
          userData: {'test': 'value'},
        ),
        throwsStateError,
      );
    });
  });

  group('EASClient.waitForAttestation (offline)', () {
    late FakeRpcProvider fakeProvider;
    late EASClient client;
    final easAddress = '0xC2679fBD37d54388Ce493F1DB75320D236e1815e';

    setUp(() {
      fakeProvider = FakeRpcProvider();
      client = EASClient(provider: fakeProvider, easAddress: easAddress);
    });

    test('returns uid from mined attestation receipt', () async {
      fakeProvider.receiptMocks['0xFakeTxHash'] = _attestedReceipt(easAddress);

      final uid = await client.waitForAttestation('0xFakeTxHash');

      expect(uid, equals(_expectedUid));
    });

    test('extracts first bytes32 UID from ABI-encoded log data', () async {
      fakeProvider.receiptMocks['0xFakeTxHash'] = TransactionReceipt(
        txHash: '0xFakeTxHash',
        blockNumber: 42,
        status: true,
        logs: [
          TransactionLog(
            address: easAddress,
            topics: [EASConstants.attestedEventTopic],
            data:
                '${_expectedUid}ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
          ),
        ],
      );

      final uid = await client.waitForAttestation('0xFakeTxHash');

      expect(uid, equals(_expectedUid));
    });

    test('forwards timeout and poll interval to provider', () async {
      fakeProvider.receiptMocks['0xFakeTxHash'] = _attestedReceipt(easAddress);
      const timeout = Duration(seconds: 15);
      const pollInterval = Duration(milliseconds: 250);

      await client.waitForAttestation(
        '0xFakeTxHash',
        timeout: timeout,
        pollInterval: pollInterval,
      );

      expect(fakeProvider.lastReceiptTimeout, equals(timeout));
      expect(fakeProvider.lastReceiptPollInterval, equals(pollInterval));
    });

    test('throws TimeoutException when transaction is not mined in time', () {
      fakeProvider.timeoutTxHashes.add('0xPendingTxHash');

      expect(
        () => client.waitForAttestation(
          '0xPendingTxHash',
          timeout: const Duration(seconds: 5),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('throws StateError when transaction reverts', () {
      fakeProvider.receiptMocks['0xRevertedTxHash'] = _attestedReceipt(
        easAddress,
        status: false,
      );

      expect(
        () => client.waitForAttestation('0xRevertedTxHash'),
        throwsStateError,
      );
    });

    test('throws StateError when no Attested log is present', () {
      fakeProvider.receiptMocks['0xFakeTxHash'] = TransactionReceipt(
        txHash: '0xFakeTxHash',
        blockNumber: 42,
        status: true,
        logs: const [],
      );

      expect(
        () => client.waitForAttestation('0xFakeTxHash'),
        throwsStateError,
      );
    });

    test('throws StateError when Attested log data is shorter than bytes32', () {
      fakeProvider.receiptMocks['0xFakeTxHash'] = TransactionReceipt(
        txHash: '0xFakeTxHash',
        blockNumber: 42,
        status: true,
        logs: [
          TransactionLog(
            address: easAddress,
            topics: [EASConstants.attestedEventTopic],
            data: '0x1234',
          ),
        ],
      );

      expect(
        () => client.waitForAttestation('0xFakeTxHash'),
        throwsStateError,
      );
    });
  });

  group('EASClient.timestamp (offline)', () {
    late FakeRpcProvider fakeProvider;
    late EASClient client;
    final easAddress = '0xC2679fBD37d54388Ce493F1DB75320D236e1815e';

    setUp(() {
      fakeProvider = FakeRpcProvider();
      client = EASClient(provider: fakeProvider, easAddress: easAddress);
    });

    test('returns TimestampResult with uid and time from Timestamped event', () async {
      final inputUID =
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final timeTopic =
          '0x0000000000000000000000000000000000000000000000000000000065f5a000';

      fakeProvider.receiptMocks['0xFakeTxHash'] = TransactionReceipt(
        txHash: '0xFakeTxHash',
        blockNumber: 99,
        status: true,
        logs: [
          TransactionLog(
            address: easAddress,
            topics: [
              EASConstants.timestampedEventTopic,
              inputUID,
              timeTopic,
            ],
            data: '0x',
          ),
        ],
      );

      final result = await client.timestamp(inputUID);

      expect(result, isA<TimestampResult>());
      expect(result.txHash, equals('0xFakeTxHash'));
      expect(result.uid, equals(inputUID));
      expect(result.time, equals(BigInt.from(0x65f5a000)));
    });

    test('throws StateError when no Timestamped log in receipt', () async {
      const validUid =
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      fakeProvider.receiptMocks['0xFakeTxHash'] = TransactionReceipt(
        txHash: '0xFakeTxHash',
        blockNumber: 99,
        status: true,
        logs: [],
      );

      expect(
        () => client.timestamp(validUid),
        throwsStateError,
      );
    });

    test('ignores Timestamped logs from wrong contract address', () async {
      const validUid =
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      fakeProvider.receiptMocks['0xFakeTxHash'] = TransactionReceipt(
        txHash: '0xFakeTxHash',
        blockNumber: 99,
        status: true,
        logs: [
          TransactionLog(
            address: '0xWrongAddress',
            topics: [
              EASConstants.timestampedEventTopic,
              '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              '0x0000000000000000000000000000000000000000000000000000000065f5a000',
            ],
            data: '0x',
          ),
        ],
      );

      expect(
        () => client.timestamp(validUid),
        throwsStateError,
      );
    });
  });

  group('EASClient.attestation round-trip (offline)', () {
    late FakeRpcProvider fakeProvider;
    late EASClient client;
    final easAddress = '0xC2679fBD37d54388Ce493F1DB75320D236e1815e';

    setUp(() {
      fakeProvider = FakeRpcProvider();
      client = EASClient(provider: fakeProvider, easAddress: easAddress);
    });

    test('waitForAttestation UID can be used to fetch the created attestation', () async {
      fakeProvider.receiptMocks['0xFakeTxHash'] = _attestedReceipt(easAddress);
      fakeProvider.contractCallMocks['getAttestation'] = _attestationTuple();

      final uid = await client.waitForAttestation('0xFakeTxHash');
      final attestation = await client.getAttestation(uid);

      expect(attestation, isA<Attestation>());
      expect(attestation!.uid, equals(_expectedUid));
      expect(attestation.schema, equals(_schemaUid));
      expect(attestation.refUID, equals(_refUid));
      expect(attestation.recipient, equals(_recipient));
      expect(attestation.attester, equals(_attester));
      expect(attestation.data, orderedEquals(const [1, 2, 3]));
    });
  });
}
