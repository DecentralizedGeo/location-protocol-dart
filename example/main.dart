import 'package:location_protocol/location_protocol.dart';

Future<void> main() async {
  print('--- Location Protocol Example ---');

  // 1. Define a schema with business-specific fields.
  //    LP base fields (lp_version, srs, location_type, location) are prepended automatically.
  final schema = SchemaDefinition(fields: [
    SchemaField(type: 'uint256', name: 'observedAt'),
    SchemaField(type: 'string', name: 'memo'),
    SchemaField(type: 'address', name: 'observer'),
  ]);

  print('EAS Schema String:');
  print(schema.toEASSchemaString());
  // => string lp_version,string srs,string location_type,string location,uint256 observedAt,string memo,address observer

  // 2. Create an LP payload with a GeoJSON point location.
  final payload = LPPayload(
    lpVersion: '0.1.0',
    srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
    locationType: 'geojson-point',
    location: {
      'type': 'Point',
      'coordinates': [-122.4194, 37.7749]
    },
  );

  // 3. Create an OffchainSigner targeting Sepolia.
  //    In a real app, use a secure way to manage private keys.
  //    This is a dummy key for demonstration purposes.
  const dummyPrivateKeyHex =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  final addresses = ChainConfig.forChainId(11155111)!; // Sepolia

  final signer = OffchainSigner.fromPrivateKey(
    privateKeyHex: dummyPrivateKeyHex,
    chainId: 11155111,
    easContractAddress: addresses.eas,
  );

  print('\nSigning offchain attestation...');

  // 4. Sign the attestation offchain (EIP-712 typed data).
  final signed = await signer.signOffchainAttestation(
    schema: schema,
    lpPayload: payload,
    userData: {
      'observedAt': BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      'memo': 'Example reading from main.dart',
      'observer': signer.signerAddress,
    },
  );

  print('UID: ${signed.uid}');
  print('Signer: ${signed.signer}');

  // 5. Verify the signed attestation locally.
  final result = signer.verifyOffchainAttestation(signed);
  print('Verification Result: ${result.isValid ? "VALID" : "INVALID"}');
  if (result.isValid) {
    print('Recovered address: ${result.recoveredAddress}');
  } else {
    print('Reason: ${result.reason}');
  }
}
