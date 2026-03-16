// ignore_for_file: avoid_print

import 'dart:io';

// ──────────────────────────────────────────────
// Data model
// ──────────────────────────────────────────────

/// A single dart code block extracted from a markdown file.
class ExtractedSnippet {
  final String sourceFile;
  final int lineNumber;
  final String heading;
  final String code;

  ExtractedSnippet({
    required this.sourceFile,
    required this.lineNumber,
    required this.heading,
    required this.code,
  });

  /// True if this code block contains `void main` or `Future<void> main`.
  bool get hasMain =>
      code.contains(RegExp(r'(?:Future<void>|void)\s+main\s*\('));

  /// True if this snippet contains an `import` statement.
  bool get hasImport => code.contains(RegExp(r"^import\s+'", multiLine: true));

  /// The step number, if this heading matches "Step N" pattern. Null otherwise.
  int? get stepNumber {
    final match = RegExp(
      r'Step\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(heading);
    return match != null ? int.parse(match.group(1)!) : null;
  }

  /// True if the heading indicates a negative/error example.
  bool get isErrorExample =>
      heading.toLowerCase().contains('constraint') &&
      (code.contains('// Throws:') || code.contains('// throws'));

  @override
  String toString() =>
      'ExtractedSnippet($sourceFile:$lineNumber "$heading" '
      'main=$hasMain import=$hasImport step=$stepNumber)';
}

/// Resolved group of snippets from one markdown file, ready for test generation.
class SnippetGroup {
  final String sourceFile;
  final String groupName;
  final List<ExtractedSnippet> snippets;
  final List<ExtractedSnippet> stepSequence;
  final List<ExtractedSnippet> standaloneSnippets;
  final List<ExtractedSnippet> errorExamples;
  final bool requiresRpc;
  final bool requiresTearDown;

  SnippetGroup({
    required this.sourceFile,
    required this.groupName,
    required this.snippets,
    required this.stepSequence,
    required this.standaloneSnippets,
    required this.errorExamples,
    required this.requiresRpc,
    required this.requiresTearDown,
  });
}

// ──────────────────────────────────────────────
// Markdown parsing
// ──────────────────────────────────────────────

/// Scans a markdown file and extracts all ```dart fenced code blocks.
///
/// Skips code blocks inside blockquotes (lines starting with `> `).
/// Returns snippets with source file, line number, nearest heading, and code.
List<ExtractedSnippet> extractSnippetsFromFile(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    stderr.writeln('Warning: $filePath not found, skipping.');
    return [];
  }

  final content = file.readAsStringSync();
  final lines = content.split('\n');
  final snippets = <ExtractedSnippet>[];

  String currentHeading = '';
  int? codeBlockStartLine;
  bool inBlockquoteBlock = false;
  var codeBuffer = StringBuffer();

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    final trimmedLeft = line.trimLeft();

    final headingMatch = RegExp(r'^#{1,3}\s+(.+)').firstMatch(trimmedLeft);
    if (headingMatch != null) {
      currentHeading = headingMatch.group(1)!.trim();
    }

    if (codeBlockStartLine == null) {
      if (inBlockquoteBlock &&
          trimmed.startsWith('>') &&
          trimmed.contains('```')) {
        inBlockquoteBlock = false;
        continue;
      }

      if (trimmed.startsWith('>') && trimmed.contains('```dart')) {
        inBlockquoteBlock = true;
        continue;
      }

      if (trimmed == '```dart') {
        codeBlockStartLine = i + 2;
        codeBuffer = StringBuffer();
        continue;
      }

      continue;
    }

    if (trimmed == '```') {
      if (inBlockquoteBlock) {
        inBlockquoteBlock = false;
        codeBlockStartLine = null;
        continue;
      }

      snippets.add(
        ExtractedSnippet(
          sourceFile: filePath,
          lineNumber: codeBlockStartLine,
          heading: currentHeading,
          code: codeBuffer.toString().trimRight(),
        ),
      );
      codeBlockStartLine = null;
      continue;
    }

    if (inBlockquoteBlock &&
        trimmed.startsWith('>') &&
        trimmed.contains('```')) {
      inBlockquoteBlock = false;
      codeBlockStartLine = null;
      continue;
    }

    if (!inBlockquoteBlock) {
      codeBuffer.writeln(line);
    }
  }

  return snippets;
}

// ──────────────────────────────────────────────
// Snippet grouping & classification
// ──────────────────────────────────────────────

/// Groups extracted snippets by source file and classifies them.
List<SnippetGroup> groupSnippets(List<ExtractedSnippet> snippets) {
  final byFile = <String, List<ExtractedSnippet>>{};
  for (final snippet in snippets) {
    byFile.putIfAbsent(snippet.sourceFile, () => []).add(snippet);
  }

  final groups = <SnippetGroup>[];
  for (final entry in byFile.entries) {
    final filePath = entry.key;
    final fileSnippets = entry.value;

    final fileName = filePath.split('/').last;
    final groupName = fileName.replaceAll('.md', '');

    final stepSequence =
        fileSnippets.where((snippet) => snippet.stepNumber != null).toList()
          ..sort((a, b) => a.stepNumber!.compareTo(b.stepNumber!));

    final errorExamples = fileSnippets
        .where((snippet) => snippet.isErrorExample)
        .toList();

    final stepAndErrorIds = {
      ...stepSequence.map((snippet) => snippet.lineNumber),
      ...errorExamples.map((snippet) => snippet.lineNumber),
    };

    final standaloneSnippets = fileSnippets
        .where((snippet) => !stepAndErrorIds.contains(snippet.lineNumber))
        .toList();

    final allCode = fileSnippets.map((snippet) => snippet.code).join('\n');
    final requiresRpc =
        allCode.contains('DefaultRpcProvider') ||
        allCode.contains('Platform.environment');
    final requiresTearDown = allCode.contains('LocationValidator.register');

    groups.add(
      SnippetGroup(
        sourceFile: filePath,
        groupName: groupName,
        snippets: fileSnippets,
        stepSequence: stepSequence,
        standaloneSnippets: standaloneSnippets,
        errorExamples: errorExamples,
        requiresRpc: requiresRpc,
        requiresTearDown: requiresTearDown,
      ),
    );
  }

  return groups;
}

// ──────────────────────────────────────────────
// Code manipulation helpers
// ──────────────────────────────────────────────

/// Well-known Hardhat account #0 test key (same as full_workflow_test.dart).
const _testPrivateKey =
    'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

/// Extracts the body of a `main()` function from a complete program snippet.
///
/// Returns the code between the opening `{` of `main()` and its matching `}`.
/// If no `main()` is found, returns the original code unchanged.
String extractMainBody(String code) {
  final mainMatch = RegExp(
    r'(?:Future<void>|void)\s+main\s*\([^)]*\)\s*(async\s*)?\{',
  ).firstMatch(code);
  if (mainMatch == null) {
    return code;
  }

  final start = mainMatch.end;
  var depth = 1;
  var end = start;

  for (var i = start; i < code.length; i++) {
    if (code[i] == '{') {
      depth++;
    }
    if (code[i] == '}') {
      depth--;
    }
    if (depth == 0) {
      end = i;
      break;
    }
  }

  return code.substring(start, end).trimRight();
}

/// Strips `import` statements from code. Returns the remaining code.
String stripImports(String code) {
  return code
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('import '))
      .join('\n')
      .trimLeft();
}

/// Replaces placeholder private keys with the well-known test key.
String substitutePlaceholderKeys(String code) {
  return code
      .replaceAll("'YOUR_PRIVATE_KEY_HEX'", "'$_testPrivateKey'")
      .replaceAll('"YOUR_PRIVATE_KEY_HEX"', "'$_testPrivateKey'");
}

/// Strips trailing commented-out code blocks.
///
/// Removes contiguous blocks of `//`-only lines at the end.
String stripTrailingCommentBlock(String code) {
  final lines = code.split('\n');
  while (lines.isNotEmpty) {
    final trimmed = lines.last.trim();
    if (trimmed.isEmpty || trimmed.startsWith('//')) {
      lines.removeLast();
    } else {
      break;
    }
  }
  return lines.join('\n');
}

/// Indents every line of [code] by [spaces] spaces.
String indent(String code, int spaces) {
  final prefix = ' ' * spaces;
  return code
      .split('\n')
      .map((line) => line.isEmpty ? '' : '$prefix$line')
      .join('\n');
}

// ──────────────────────────────────────────────
// Cross-document prerequisite injection
// ──────────────────────────────────────────────

/// Prerequisites injected before onchain guide step code.
const _tutorialPrerequisites = '''
  // Prerequisites from tutorial (schema + LP payload)
  final schema = SchemaDefinition(
    fields: [
      SchemaField(type: 'uint256', name: 'timestamp'),
      SchemaField(type: 'string', name: 'memo'),
    ],
  );

  final lpPayload = LPPayload(
    lpVersion: '1.0.0',
    srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
    locationType: 'geojson-point',
    location: {'type': 'Point', 'coordinates': [-103.771556, 44.967243]},
  );''';

/// Offchain signing prerequisite for onchain guide Step 4 (timestamp).
const _offchainSigningPrerequisite =
    '''
  // Offchain signing prerequisite for timestamp step
  const testPrivateKey = '$_testPrivateKey';

  final easAddress = ChainConfig.forChainId(chainId)!.eas;

  final signer = OffchainSigner(
    privateKeyHex: testPrivateKey,
    chainId: chainId,
    easContractAddress: easAddress,
  );

  final signed = await signer.signOffchainAttestation(
    schema: schema,
    lpPayload: lpPayload,
    userData: {
      'timestamp': BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      'memo': 'Prerequisite for timestamp test',
    },
  );''';

/// Maps source file basenames to prerequisite identifiers.
const _filePrerequisites = {
  'how-to-register-and-attest-onchain.md': 'tutorial',
};

// ──────────────────────────────────────────────
// Test file generation
// ──────────────────────────────────────────────

/// Generates the file header for the test file.
String generateFileHeader() {
  return '''
// AUTO-GENERATED by scripts/docs_snippet_extractor.dart — DO NOT EDIT
// Regenerate with: dart run scripts/docs_snippet_extractor.dart

// ignore_for_file: avoid_print

@Tags(['doc-snippets'])
library;

import 'package:test/test.dart';
import 'package:location_protocol/location_protocol.dart';

import '../test_helpers/dotenv_loader.dart';
''';
}

/// Generates a `test()` block for a standalone snippet.
String generateStandaloneTest(
  ExtractedSnippet snippet, {
  bool requiresRpc = false,
}) {
  final sourceLine = 'L${snippet.lineNumber}';
  final testName = '${snippet.heading} ($sourceLine)';
  var code = snippet.code;

  code = substitutePlaceholderKeys(code);

  if (snippet.hasMain) {
    code = extractMainBody(code);
    code = stripTrailingCommentBlock(code);
  }

  if (code.contains('tearDown(() => LocationValidator.resetCustomTypes());')) {
    code = code.replaceAll(
      'tearDown(() => LocationValidator.resetCustomTypes());',
      'LocationValidator.resetCustomTypes();',
    );
  }

  final indented = indent(code, 6);

  final rpcGuard = requiresRpc
      ? '''
      if (sepoliaRpcUrl.isEmpty || sepoliaPrivateKey.isEmpty) {
        markTestSkipped('Missing SEPOLIA_RPC_URL or SEPOLIA_PRIVATE_KEY in .env');
        return;
      }

    final rpcUrl = sepoliaRpcUrl;
    final privateKey = sepoliaPrivateKey;

'''
      : '';

  if (requiresRpc) {
    return '''
    test('$testName', () async {
$rpcGuard      try {
$indented
      } catch (error) {
        final message = error.toString().toLowerCase();
        if (message.contains('already known')) {
          markTestSkipped('Skipping flaky Sepolia mempool duplicate transaction.');
          return;
        }
        rethrow;
      }
    });''';
  }

  return '''
    test('$testName', () async {
$indented
    });''';
}

/// Generates a `group()` with accumulated step tests.
String generateStepSequenceTests(SnippetGroup group) {
  if (group.stepSequence.isEmpty) {
    return '';
  }

  final steps = group.stepSequence;
  final buffer = StringBuffer();
  final fileName = group.sourceFile.split('/').last;

  buffer.writeln("    group('Step sequence', () {");

  final accumulatedBodies = <String>[];

  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    var stepCode = step.code;

    if (i == 0) {
      if (step.hasMain) {
        stepCode = extractMainBody(stepCode);
      } else {
        stepCode = stripImports(stepCode);
      }

      if (group.requiresRpc) {
        stepCode = _generateOnchainStep1Setup();
      }
    }

    stepCode = substitutePlaceholderKeys(stepCode);
    accumulatedBodies.add(stepCode);

    final testBody = StringBuffer();

    if (_filePrerequisites.containsKey(fileName) && i >= 1) {
      testBody.writeln(accumulatedBodies.first);
      testBody.writeln();
      testBody.writeln(_tutorialPrerequisites);
      testBody.writeln();
      if (i >= 3) {
        testBody.writeln(_offchainSigningPrerequisite);
        testBody.writeln();
      }
      for (final body in accumulatedBodies.skip(1)) {
        testBody.writeln(body);
        testBody.writeln();
      }
    } else {
      for (final body in accumulatedBodies) {
        testBody.writeln(body);
        testBody.writeln();
      }
    }

    final testName = '${step.heading} (L${step.lineNumber})';
    final bodyContent = testBody.toString().trimRight();
    if (group.requiresRpc) {
      final rpcGuard = '''
        if (sepoliaRpcUrl.isEmpty || sepoliaPrivateKey.isEmpty) {
          markTestSkipped('Missing SEPOLIA_RPC_URL or SEPOLIA_PRIVATE_KEY in .env');
          return;
        }

''';
      final indented = indent(bodyContent, 10);
      buffer.writeln("      test('$testName', () async {");
      buffer.write(rpcGuard);
      buffer.writeln('        try {');
      buffer.writeln(indented);
      buffer.writeln('        } catch (error) {');
      buffer.writeln(
        '          final message = error.toString().toLowerCase();',
      );
      buffer.writeln("          if (message.contains('already known')) {");
      buffer.writeln(
        "            markTestSkipped('Skipping flaky Sepolia mempool duplicate transaction.');",
      );
      buffer.writeln('            return;');
      buffer.writeln('          }');
      buffer.writeln('          rethrow;');
      buffer.writeln('        }');
      buffer.writeln('      });');
    } else {
      final indented = indent(bodyContent, 8);
      buffer.writeln("      test('$testName', () async {");
      buffer.writeln(indented);
      buffer.writeln('      });');
    }
    buffer.writeln();
  }

  buffer.writeln('    });');
  return buffer.toString();
}

/// Generates the adapted onchain Step 1 setup code.
String _generateOnchainStep1Setup() {
  return '''
  // Adapted from doc snippet: uses loadDotEnv() instead of Platform.environment.
  // Doc uses EAS_RPC_URL/EAS_PRIVATE_KEY; tests use SEPOLIA_RPC_URL/SEPOLIA_PRIVATE_KEY.
  const chainId = 11155111; // Sepolia

  final provider = DefaultRpcProvider(
    rpcUrl: sepoliaRpcUrl,
    privateKeyHex: sepoliaPrivateKey,
    chainId: chainId,
  );''';
}

/// Generates `test()` blocks for error-demonstrating snippets.
String generateErrorExampleTests(List<ExtractedSnippet> errorExamples) {
  if (errorExamples.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  for (final snippet in errorExamples) {
    final testName = '${snippet.heading} (L${snippet.lineNumber})';

    final code = snippet.code
        .split('\n')
        .where((line) => !line.trim().startsWith('// Throws:'))
        .join('\n')
        .replaceAll('{ ... }', '{}')
        .trim();

    final indented = indent(code, 10);

    buffer.writeln("    test('$testName', () {");
    buffer.writeln('      expect(() {');
    buffer.writeln(indented);
    buffer.writeln('      }, throwsA(isA<ArgumentError>()));');
    buffer.writeln('    });');
    buffer.writeln();
  }

  return buffer.toString();
}

/// Assembles the complete test file from all snippet groups.
String generateTestFile(List<SnippetGroup> groups) {
  final buffer = StringBuffer();
  buffer.writeln(generateFileHeader());

  buffer.writeln('void main() {');

  for (final group in groups) {
    if (group.snippets.isEmpty) {
      continue;
    }

    if (group.requiresRpc) {
      buffer.writeln("  group('${group.groupName}', tags: ['sepolia'], () {");
      buffer.writeln('    final env = loadDotEnv();');
      buffer.writeln("    final sepoliaRpcUrl = env['SEPOLIA_RPC_URL'] ?? '';");
      buffer.writeln(
        "    final sepoliaPrivateKey = env['SEPOLIA_PRIVATE_KEY'] ?? '';",
      );
      buffer.writeln();
    } else {
      buffer.writeln("  group('${group.groupName}', () {");
    }

    if (group.requiresTearDown) {
      buffer.writeln(
        '    tearDown(() => LocationValidator.resetCustomTypes());',
      );
      buffer.writeln();
    }

    final stepTests = generateStepSequenceTests(group);
    if (stepTests.isNotEmpty) {
      buffer.writeln(stepTests);
    }

    for (final snippet in group.standaloneSnippets) {
      buffer.writeln(
        generateStandaloneTest(snippet, requiresRpc: group.requiresRpc),
      );
      buffer.writeln();
    }

    final errorTests = generateErrorExampleTests(group.errorExamples);
    if (errorTests.isNotEmpty) {
      buffer.writeln(errorTests);
    }

    buffer.writeln('  });');
    buffer.writeln();
  }

  buffer.writeln('}');
  return buffer.toString();
}

void main(List<String> args) {
  final outputFlagIndex = args.indexOf('--output');
  final outputPath = outputFlagIndex >= 0 && outputFlagIndex + 1 < args.length
      ? args[outputFlagIndex + 1]
      : 'test/docs/docs_snippets_test.dart';
  final verbose = args.contains('--verbose');

  if (args.contains('--self-test')) {
    final sample = '''
import 'package:location_protocol/location_protocol.dart';

void main() async {
  final x = 1;
  print(x);
}
''';
    assert(extractMainBody(sample).contains('final x = 1'));
    assert(!extractMainBody(sample).contains('import'));
    assert(stripImports(sample).contains('void main'));
    assert(!stripImports(sample).contains('import'));
    assert(
      substitutePlaceholderKeys(
        "'YOUR_PRIVATE_KEY_HEX'",
      ).contains(_testPrivateKey),
    );

    final futureMain = '''
import 'package:foo/foo.dart';

Future<void> main() async {
  final y = 2;
  print(y);
}
''';
    assert(extractMainBody(futureMain).contains('final y = 2'));
    assert(!extractMainBody(futureMain).contains('Future<void>'));
    stdout.writeln('Self-test passed.');
    return;
  }

  stdout.writeln('Documentation Snippet Extractor');
  stdout.writeln('Output: $outputPath');
  if (verbose) {
    stdout.writeln('Verbose mode enabled');
  }

  final filesToScan = <String>[
    'README.md',
    ...Directory('docs/guides')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.md'))
        .map((file) => file.path.replaceAll(r'\', '/')),
  ];

  final allSnippets = <ExtractedSnippet>[];
  for (final filePath in filesToScan) {
    final snippets = extractSnippetsFromFile(filePath);
    allSnippets.addAll(snippets);

    if (verbose) {
      stdout.writeln('  $filePath: ${snippets.length} dart snippet(s)');
      for (final snippet in snippets) {
        stdout.writeln(
          '    L${snippet.lineNumber} [${snippet.heading}] '
          'main=${snippet.hasMain} step=${snippet.stepNumber}',
        );
      }
    }
  }

  stdout.writeln(
    'Found ${allSnippets.length} dart snippet(s) '
    'across ${filesToScan.length} file(s).',
  );

  final groups = groupSnippets(allSnippets);
  for (final group in groups) {
    stdout.writeln('  Group: ${group.groupName}');
    stdout.writeln(
      '    Steps: ${group.stepSequence.length}, '
      'Standalone: ${group.standaloneSnippets.length}, '
      'Errors: ${group.errorExamples.length}',
    );
    stdout.writeln(
      '    RPC: ${group.requiresRpc}, '
      'TearDown: ${group.requiresTearDown}',
    );
  }

  final testFileContent = generateTestFile(groups);

  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(testFileContent);

  final totalSnippets = groups.fold<int>(
    0,
    (sum, group) => sum + group.snippets.length,
  );
  final totalSteps = groups.fold<int>(
    0,
    (sum, group) => sum + group.stepSequence.length,
  );
  final totalStandalone = groups.fold<int>(
    0,
    (sum, group) => sum + group.standaloneSnippets.length,
  );
  final totalErrors = groups.fold<int>(
    0,
    (sum, group) => sum + group.errorExamples.length,
  );

  stdout.writeln('');
  stdout.writeln('Generated $outputPath');
  stdout.writeln(
    '  $totalSnippets snippet(s): '
    '$totalSteps step(s), $totalStandalone standalone, $totalErrors error example(s)',
  );
  stdout.writeln('  ${groups.length} test group(s)');
  stdout.writeln('');
  stdout.writeln('Run offline tests:');
  stdout.writeln('  dart test --tags doc-snippets --exclude-tags sepolia');
  stdout.writeln('Run all (requires .env):');
  stdout.writeln('  dart test --tags doc-snippets');
}
