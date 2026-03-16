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
}
