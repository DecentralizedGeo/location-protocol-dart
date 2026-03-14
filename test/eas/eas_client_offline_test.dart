import 'package:test/test.dart';
import 'package:location_protocol/src/eas/onchain_client.dart';
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
}
