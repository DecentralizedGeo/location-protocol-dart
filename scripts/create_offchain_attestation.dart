import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:location_protocol/location_protocol.dart';

const _sepoliaChainId = 11155111;
const _sepoliaEasContractAddress = '0xC2679fBD37d54388Ce493F1DB75320D236e1815e';

/// Recursively converts values for JSON serialization.
/// - Numeric message fields (time, expirationTime, version) → numbers
/// - Hex/bytes fields → strings (unchanged)
/// - Other BigInt → strings (safe for large numbers)
dynamic _serializableValue(dynamic value, [String? parentKey]) {
  if (value is BigInt) {
    // For numeric fields in the EIP-712 message, convert to int
    if (parentKey == 'time' ||
        parentKey == 'expirationTime' ||
        parentKey == 'version') {
      return value.toInt();
    }
    return value.toString();
  } else if (value is Map) {
    return value.map((k, v) {
      // Pass the key when recursing into message fields
      return MapEntry(k, _serializableValue(v, k));
    });
  } else if (value is List) {
    return value.map((item) => _serializableValue(item, parentKey)).toList();
  }
  return value;
}

Map<String, String> _loadDotEnv({String path = '.env'}) {
  final file = File(path);
  if (!file.existsSync()) return <String, String>{};

  final env = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final equalsIndex = trimmed.indexOf('=');
    if (equalsIndex < 0) continue;

    final key = trimmed.substring(0, equalsIndex).trim();
    var value = trimmed.substring(equalsIndex + 1).trim();

    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }

    if (key.isNotEmpty && value.isNotEmpty) {
      env[key] = value;
    }
  }

  return env;
}

String? _readEnvValue(Map<String, String> env, String key) {
  final fromDotEnv = env[key];
  if (fromDotEnv != null && fromDotEnv.isNotEmpty) {
    return fromDotEnv;
  }

  final fromProcess = Platform.environment[key];
  if (fromProcess != null && fromProcess.isNotEmpty) {
    return fromProcess;
  }

  return null;
}

String _resolvePrivateKeyHex(Map<String, String> env) {
  final privateKey = _readEnvValue(env, 'SEPOLIA_PRIVATE_KEY');
  if (privateKey != null) {
    return privateKey;
  }

  stderr.writeln(
    '⚠️  SEPOLIA_PRIVATE_KEY is missing from .env and process env; generating an ephemeral key for this run.',
  );
  return _generateEphemeralPrivateKeyHex();
}

String _generateEphemeralPrivateKeyHex() {
  final random = Random.secure();

  while (true) {
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final hex =
        '0x${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';

    try {
      OffchainSigner.fromPrivateKey(
        privateKeyHex: hex,
        chainId: _sepoliaChainId,
        easContractAddress: _sepoliaEasContractAddress,
      );
      return hex;
    } catch (_) {
      // Extremely unlikely with a 32-byte CSPRNG key, but retry if the key
      // lands outside the secp256k1 range accepted by the signer.
    }
  }
}

Future<void> main() async {
  print('--- Creating Offchain Attestation for Existing Schema ---\n');

  final env = _loadDotEnv();

  // Existing LP-only schema UID from Sepolia (registered once, reused)
  const existingSchemaUid =
      '0x3902cc7b8e415eb1ed9ac496431c31c88023cdbde0821cbb81195a8bcf74fffd';

  print('Using existing schema UID: $existingSchemaUid');
  print('Schema contains only LP base fields (no custom fields)');
  print('');

  // Create an LP payload with a GeoJSON point location
  final payload = LPPayload(
    lpVersion: '1.0.0',
    srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
    locationType: 'geojson-point',
    location: {
      'type': 'Point',
      'coordinates': [-122.4194, 37.7749], // San Francisco
    },
  );

  print('Location Payload:');
  print('  lpVersion: ${payload.lpVersion}');
  print('  srs: ${payload.srs}');
  print('  locationType: ${payload.locationType}');
  print('  location: ${jsonEncode(payload.location)}');
  print('');

  // Create an OffchainSigner targeting Sepolia
  // Uses SEPOLIA_PRIVATE_KEY from .env when available, otherwise falls back
  // to an ephemeral in-memory key for this run.
  final privateKeyHex = _resolvePrivateKeyHex(env);
  final signer = OffchainSigner.fromPrivateKey(
    privateKeyHex: privateKeyHex,
    chainId: _sepoliaChainId, // Sepolia
    easContractAddress: _sepoliaEasContractAddress,
  );

  print('Signer Address: ${signer.signerAddress}');
  print('');

  // Create an LP-only schema definition (matches the Sepolia registered schema)
  // With no custom fields, the computed UID should match existingSchemaUid
  final schema = SchemaDefinition(fields: []);

  // Verify the computed schema UID matches the existing one
  final computedSchemaUid = SchemaUID.compute(schema);
  print('Computed Schema UID: $computedSchemaUid');
  if (computedSchemaUid != existingSchemaUid) {
    print('⚠️  WARNING: Computed UID does not match existing schema UID!');
    print('   Expected: $existingSchemaUid');
    print('   Got:      $computedSchemaUid');
  } else {
    print('✓ Schema UID matches the existing Sepolia schema');
  }
  print('');

  // Sign the attestation offchain
  // Note: For LP-only schema, no userData is passed (only LP fields are used)
  print('Creating offchain attestation...');
  final signed = await signer.signOffchainAttestation(
    schema: schema,
    lpPayload: payload,
    userData: {}, // Empty for LP-only schema
  );

  print('UID: ${signed.uid}');
  print('');

  // Verify the attestation was created correctly
  final verificationResult = signer.verifyOffchainAttestation(signed);
  print(
    'Local Verification: ${verificationResult.isValid ? "✓ VALID" : "✗ INVALID"}',
  );
  if (!verificationResult.isValid) {
    print('Reason: ${verificationResult.reason}');
  }
  print('');

  // Serialize to JSON (handling BigInt conversion)
  final json = signed.toJson();

  // // Remove EIP712Domain from types (EAS verifier doesn't expect it)
  // if (json['sig'] is Map && json['sig']['types'] is Map) {
  //   (json['sig']['types'] as Map).remove('EIP712Domain');
  // }

  final serializableJson = _serializableValue(json);
  final prettyJson = JsonEncoder.withIndent('  ').convert(serializableJson);

  // Write to file
  const filename = 'offchain_attestation.json';
  final file = File(filename);
  await file.writeAsString(prettyJson);

  print('Attestation saved to: $filename');
  print('File size: ${file.lengthSync()} bytes');
  print('');
  print('JSON Output:');
  print(prettyJson);
}
