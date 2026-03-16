import 'dart:io';

import 'package:location_protocol/src/eas/schema_registry.dart';
import 'package:location_protocol/src/rpc/default_rpc_provider.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';

Future<void> main() async {
  final env = _loadDotEnv();
  final rpcUrl = env['SEPOLIA_RPC_URL'] ?? Platform.environment['SEPOLIA_RPC_URL'];
  final privateKey = env['SEPOLIA_PRIVATE_KEY'] ?? Platform.environment['SEPOLIA_PRIVATE_KEY'];

  final validationError = _validateBootstrapEnv(rpcUrl: rpcUrl, privateKey: privateKey);
  if (validationError != null) {
    stderr.writeln('❌ $validationError');
    stderr.writeln('Set values in .env (preferred) or environment variables.');
    exitCode = 64;
    return;
  }

  final provider = DefaultRpcProvider(
    rpcUrl: rpcUrl!,
    privateKeyHex: privateKey!,
    chainId: 11155111,
  );

  final registry = SchemaRegistryClient(provider: provider);
  final lpOnlySchema = SchemaDefinition(fields: const []);
  final computedUid = SchemaRegistryClient.computeSchemaUID(lpOnlySchema);

  stdout.writeln('Registering LP-only schema on Sepolia (one-time bootstrap)...');

  try {
    final result = await registry.register(lpOnlySchema);

    if (result.alreadyExisted) {
      stdout.writeln('ℹ️  Schema already registered on-chain (no transaction sent)');
      stdout.writeln('   UID: ${result.uid}');
    } else {
      stdout.writeln('✅ Registration submitted');
      stdout.writeln('   TX Hash: ${result.txHash}');
      stdout.writeln('   UID:     ${result.uid}');
    }
    stdout.writeln('   Computed LP UID: $computedUid');
    stdout.writeln('');
    stdout.writeln('Copy this into your .env file:');
    stdout.writeln('SEPOLIA_EXISTING_SCHEMA_UID=${result.uid}');
    stdout.writeln('');
    stdout.writeln('Use this UID for recurring tests:');
    stdout.writeln('dart test --tags sepolia -r expanded');
  } catch (error, stackTrace) {
    stderr.writeln('❌ Schema bootstrap failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

String? _validateBootstrapEnv({
  required String? rpcUrl,
  required String? privateKey,
}) {
  if (rpcUrl == null || privateKey == null) {
    return 'SEPOLIA_RPC_URL and/or SEPOLIA_PRIVATE_KEY are missing.';
  }

  if (!privateKey.startsWith('0x') || privateKey.length != 66) {
    return 'SEPOLIA_PRIVATE_KEY must be 0x-prefixed and 66 characters.';
  }

  return null;
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
