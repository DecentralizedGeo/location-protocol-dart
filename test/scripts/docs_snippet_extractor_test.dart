import 'dart:io';

import 'package:test/test.dart';

import '../../scripts/docs_snippet_extractor.dart';

void main() {
  group('ExtractedSnippet', () {
    test('derives metadata from code and heading', () {
      final snippet = ExtractedSnippet(
        sourceFile: 'docs/guides/tutorial.md',
        lineNumber: 10,
        heading: 'Step 3 — Something',
        code: """
import 'package:foo/foo.dart';

void main() async {
  print('hi');
}
""",
      );

      expect(snippet.hasMain, isTrue);
      expect(snippet.hasImport, isTrue);
      expect(snippet.stepNumber, 3);
      expect(snippet.isErrorExample, isFalse);
    });

    test('detects error example by heading and throws comment', () {
      final snippet = ExtractedSnippet(
        sourceFile: 'docs/guides/custom.md',
        lineNumber: 40,
        heading: 'Constraints — built-in override throws',
        code: """
// Throws: ArgumentError
LocationValidator.register('address', (v) => v != null);
""",
      );

      expect(snippet.isErrorExample, isTrue);
    });
  });

  group('extractSnippetsFromFile', () {
    test('extracts dart fenced blocks and skips blockquote blocks', () {
      final tempDir = Directory.systemTemp.createTempSync('snippet_extractor_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final markdownFile = File('${tempDir.path}/sample.md');
      markdownFile.writeAsStringSync('''
## Step 1 — Setup

```dart
void main() {
  print("first");
}
```

> ```dart
> void ignoreMe() {
>   print("blockquote");
> }
> ```

## Constraints — Throws example

```dart
// Throws: ArgumentError
throw ArgumentError('bad');
```
''');

      final snippets = extractSnippetsFromFile(markdownFile.path.replaceAll('\\', '/'));

      expect(snippets, hasLength(2));
      expect(snippets[0].heading, contains('Step 1'));
      expect(snippets[0].code, contains('print("first")'));
      expect(snippets[1].heading, contains('Constraints'));
      expect(snippets[1].code, contains('throw ArgumentError'));
      expect(snippets.any((snippet) => snippet.code.contains('ignoreMe')), isFalse);
    });

    test('extracts snippets from markdown with CRLF line endings', () {
      final tempDir = Directory.systemTemp.createTempSync('snippet_extractor_test_crlf_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final markdownFile = File('${tempDir.path}/crlf.md');
      markdownFile.writeAsStringSync(
        '## Step 1 — CRLF\r\n\r\n'
        '```dart\r\n'
        'void main() {\r\n'
        "  print('crlf');\r\n"
        '}\r\n'
        '```\r\n',
      );

      final snippets = extractSnippetsFromFile(markdownFile.path.replaceAll('\\', '/'));

      expect(snippets, hasLength(1));
      expect(snippets.first.heading, contains('Step 1'));
      expect(snippets.first.code, contains("print('crlf')"));
    });
  });

  group('groupSnippets', () {
    test('classifies steps standalone and errors per file', () {
      final snippets = <ExtractedSnippet>[
        ExtractedSnippet(
          sourceFile: 'README.md',
          lineNumber: 10,
          heading: 'Quick Start',
          code: """
void main() {
  print('hello');
}
""",
        ),
        ExtractedSnippet(
          sourceFile: 'docs/guides/how-to-register-and-attest-onchain.md',
          lineNumber: 20,
          heading: 'Step 1 — Set up your RPC provider',
          code: """
import 'dart:io';
final env = Platform.environment;
final provider = DefaultRpcProvider(rpcUrl: 'x', privateKeyHex: 'y', chainId: 1);
""",
        ),
        ExtractedSnippet(
          sourceFile: 'docs/guides/how-to-add-custom-location-type.md',
          lineNumber: 30,
          heading: 'Step 1 — Register a custom validator',
          code: """
LocationValidator.register('plus-code', (value) => value != null);
""",
        ),
        ExtractedSnippet(
          sourceFile: 'docs/guides/how-to-add-custom-location-type.md',
          lineNumber: 40,
          heading: 'Constraints — built-in override throws',
          code: """
// Throws: ArgumentError
LocationValidator.register('address', (value) => value != null);
""",
        ),
      ];

      final groups = groupSnippets(snippets);

      final readme = groups.firstWhere((group) => group.sourceFile == 'README.md');
      expect(readme.stepSequence, isEmpty);
      expect(readme.standaloneSnippets, hasLength(1));
      expect(readme.errorExamples, isEmpty);
      expect(readme.requiresRpc, isFalse);

      final onchain = groups.firstWhere(
        (group) => group.sourceFile.endsWith('how-to-register-and-attest-onchain.md'),
      );
      expect(onchain.stepSequence, hasLength(1));
      expect(onchain.requiresRpc, isTrue);

      final custom = groups.firstWhere(
        (group) => group.sourceFile.endsWith('how-to-add-custom-location-type.md'),
      );
      expect(custom.stepSequence, hasLength(1));
      expect(custom.errorExamples, hasLength(1));
      expect(custom.requiresTearDown, isTrue);
    });
  });

  group('code helpers', () {
    test('extractMainBody returns body for void and Future<void> main', () {
      final voidMain = '''
import 'package:location_protocol/location_protocol.dart';

void main() async {
  final value = 1;
  print(value);
}
''';
      final futureMain = '''
Future<void> main() async {
  final value = 2;
  print(value);
}
''';

      expect(extractMainBody(voidMain), contains('final value = 1;'));
      expect(extractMainBody(voidMain), isNot(contains('void main')));
      expect(extractMainBody(futureMain), contains('final value = 2;'));
      expect(extractMainBody(futureMain), isNot(contains('Future<void> main')));
    });

    test('stripImports removes import lines', () {
      final code = '''
import 'dart:io';
import 'package:test/test.dart';

void main() {
  print('x');
}
''';

      final stripped = stripImports(code);
      expect(stripped, isNot(contains("import 'dart:io';")));
      expect(stripped, contains('void main()'));
    });

    test('substitutePlaceholderKeys replaces both quote styles', () {
      final code = "'YOUR_PRIVATE_KEY_HEX' and \"YOUR_PRIVATE_KEY_HEX\"";

      final substituted = substitutePlaceholderKeys(code);

      expect(substituted, isNot(contains('YOUR_PRIVATE_KEY_HEX')));
      expect(substituted, contains('ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'));
    });

    test('stripTrailingCommentBlock removes trailing comment-only section', () {
      final code = '''
final x = 1;

// Optional section
// More comments
''';

      final stripped = stripTrailingCommentBlock(code);
      expect(stripped.trimRight(), 'final x = 1;');
    });

    test('indent prefixes non-empty lines with spaces', () {
      final code = 'a\n\nb';
      final indented = indent(code, 4);

      expect(indented.split('\n')[0], '    a');
      expect(indented.split('\n')[1], '');
      expect(indented.split('\n')[2], '    b');
    });
  });

  group('test file generation', () {
    test('generateFileHeader contains doc-snippets tags and imports', () {
      final header = generateFileHeader();

      expect(header, contains("@Tags(['doc-snippets'])"));
      expect(header, contains("import 'package:test/test.dart';"));
      expect(header, contains("import 'package:location_protocol/location_protocol.dart';"));
      expect(header, contains("import '../test_helpers/dotenv_loader.dart';"));
    });

    test('generateStandaloneTest wraps complete main snippet as async test', () {
      final snippet = ExtractedSnippet(
        sourceFile: 'README.md',
        lineNumber: 81,
        heading: 'Quick Start',
        code: '''
void main() async {
  const privateKeyHex = 'YOUR_PRIVATE_KEY_HEX';
  print(privateKeyHex);
}
''',
      );

      final generated = generateStandaloneTest(snippet);

      expect(generated, contains("test('Quick Start (L81)', () async {"));
      expect(generated, contains('ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'));
      expect(generated, isNot(contains('void main')));
    });

    test('generateStepSequenceTests accumulates prior steps in each test body', () {
      final group = SnippetGroup(
        sourceFile: 'docs/guides/tutorial-first-attestation.md',
        groupName: 'tutorial-first-attestation',
        snippets: [
          ExtractedSnippet(
            sourceFile: 'docs/guides/tutorial-first-attestation.md',
            lineNumber: 46,
            heading: 'Step 1 — Define your schema',
            code: '''
void main() async {
  final schema = SchemaDefinition(fields: []);
}
''',
          ),
          ExtractedSnippet(
            sourceFile: 'docs/guides/tutorial-first-attestation.md',
            lineNumber: 80,
            heading: 'Step 2 — Create an LP payload',
            code: "final lpPayload = LPPayload(lpVersion: '1.0.0', srs: 'x', locationType: 'address', location: 'y');",
          ),
        ],
        stepSequence: [
          ExtractedSnippet(
            sourceFile: 'docs/guides/tutorial-first-attestation.md',
            lineNumber: 46,
            heading: 'Step 1 — Define your schema',
            code: '''
void main() async {
  final schema = SchemaDefinition(fields: []);
}
''',
          ),
          ExtractedSnippet(
            sourceFile: 'docs/guides/tutorial-first-attestation.md',
            lineNumber: 80,
            heading: 'Step 2 — Create an LP payload',
            code: "final lpPayload = LPPayload(lpVersion: '1.0.0', srs: 'x', locationType: 'address', location: 'y');",
          ),
        ],
        standaloneSnippets: const [],
        errorExamples: const [],
        requiresRpc: false,
        requiresTearDown: false,
      );

      final generated = generateStepSequenceTests(group);

      expect(generated, contains("group('Step sequence'"));
      expect(generated, contains("test('Step 1 — Define your schema (L46)'"));
      expect(generated, contains("test('Step 2 — Create an LP payload (L80)'"));
      expect(generated, contains('final schema = SchemaDefinition(fields: []);'));
      expect(generated, contains('final lpPayload = LPPayload'));
    });

    test('generateErrorExampleTests wraps snippets with ArgumentError expectation', () {
      final snippets = [
        ExtractedSnippet(
          sourceFile: 'docs/guides/how-to-add-custom-location-type.md',
          lineNumber: 43,
          heading: 'Constraints — built-in override throws',
          code: '''
// Throws: ArgumentError
LocationValidator.register('address', (value) => value != null);
''',
        ),
      ];

      final generated = generateErrorExampleTests(snippets);

      expect(generated, contains("test('Constraints — built-in override throws (L43)'"));
      expect(generated, contains('throwsA(isA<ArgumentError>())'));
      expect(generated, isNot(contains('// Throws:')));
    });

    test('generateTestFile assembles groups with teardown and tags', () {
      final group = SnippetGroup(
        sourceFile: 'docs/guides/how-to-add-custom-location-type.md',
        groupName: 'how-to-add-custom-location-type',
        snippets: [
          ExtractedSnippet(
            sourceFile: 'docs/guides/how-to-add-custom-location-type.md',
            lineNumber: 12,
            heading: 'Step 1 — Register a custom validator',
            code: "LocationValidator.register('plus-code', (value) => value != null);",
          ),
        ],
        stepSequence: [
          ExtractedSnippet(
            sourceFile: 'docs/guides/how-to-add-custom-location-type.md',
            lineNumber: 12,
            heading: 'Step 1 — Register a custom validator',
            code: "LocationValidator.register('plus-code', (value) => value != null);",
          ),
        ],
        standaloneSnippets: const [],
        errorExamples: const [],
        requiresRpc: false,
        requiresTearDown: true,
      );

      final generated = generateTestFile([group]);

      expect(generated, contains("@Tags(['doc-snippets'])"));
      expect(generated, contains("group('how-to-add-custom-location-type', () {"));
      expect(generated, contains('tearDown(() => LocationValidator.resetCustomTypes());'));
      expect(generated, contains("group('Step sequence'"));
    });
  });
}
