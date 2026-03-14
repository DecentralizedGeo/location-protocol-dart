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
