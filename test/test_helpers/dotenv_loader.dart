import 'dart:io';

/// Loads key-value pairs from a `.env` file into a Map.
///
/// Supports:
/// - `KEY=VALUE` pairs (one per line)
/// - Lines starting with `#` are comments (ignored)
/// - Empty lines are ignored
/// - Values are NOT expanded (no `${VAR}` interpolation)
/// - Surrounding quotes on values are stripped
///
/// Returns an empty map if the file does not exist.
Map<String, String> loadDotEnv({String path = '.env'}) {
  final file = File(path);
  if (!file.existsSync()) return {};

  final env = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final eqIndex = trimmed.indexOf('=');
    if (eqIndex < 0) continue;

    final key = trimmed.substring(0, eqIndex).trim();
    var value = trimmed.substring(eqIndex + 1).trim();

    // Strip surrounding quotes
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

/// Resolves the Sepolia RPC URL from [env] (already parsed from `.env`).
///
/// Priority:
/// 1. `SEPOLIA_RPC_URL` (explicit full URL)
/// 2. `INFURA_API_KEY`  → `https://sepolia.infura.io/v3/<key>`
/// 3. `ALCHEMY_API_KEY` → `https://eth-sepolia.g.alchemy.com/v2/<key>`
/// 4. Falls back to the same keys in [Platform.environment].
///
/// Returns `null` when none of the above are present.
String? resolveRpcUrl(Map<String, String> env) {
  String? get(String key) => env[key]?.isNotEmpty == true
      ? env[key]
      : (Platform.environment[key]?.isNotEmpty == true
          ? Platform.environment[key]
          : null);

  final explicit = get('SEPOLIA_RPC_URL');
  if (explicit != null) return explicit;

  final infura = get('INFURA_API_KEY');
  if (infura != null) return 'https://sepolia.infura.io/v3/$infura';

  final alchemy = get('ALCHEMY_API_KEY');
  if (alchemy != null) return 'https://eth-sepolia.g.alchemy.com/v2/$alchemy';

  return null;
}
