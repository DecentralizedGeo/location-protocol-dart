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
  bool get hasMain => code.contains(RegExp(r'(?:Future<void>|void)\s+main\s*\('));

  /// True if this snippet contains an `import` statement.
  bool get hasImport => code.contains(RegExp(r"^import\s+'", multiLine: true));

  /// The step number, if this heading matches "Step N" pattern. Null otherwise.
  int? get stepNumber {
    final match = RegExp(r'Step\s+(\d+)', caseSensitive: false).firstMatch(heading);
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
      if (inBlockquoteBlock && trimmed.startsWith('>') && trimmed.contains('```')) {
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

    if (inBlockquoteBlock && trimmed.startsWith('>') && trimmed.contains('```')) {
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

    final stepSequence = fileSnippets.where((snippet) => snippet.stepNumber != null).toList()
      ..sort((a, b) => a.stepNumber!.compareTo(b.stepNumber!));

    final errorExamples = fileSnippets.where((snippet) => snippet.isErrorExample).toList();

    final stepAndErrorIds = {
      ...stepSequence.map((snippet) => snippet.lineNumber),
      ...errorExamples.map((snippet) => snippet.lineNumber),
    };

    final standaloneSnippets =
        fileSnippets.where((snippet) => !stepAndErrorIds.contains(snippet.lineNumber)).toList();

    final allCode = fileSnippets.map((snippet) => snippet.code).join('\n');
    final requiresRpc = allCode.contains('DefaultRpcProvider') || allCode.contains('Platform.environment');
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

void main(List<String> args) {
  final outputFlagIndex = args.indexOf('--output');
  final outputPath = outputFlagIndex >= 0 && outputFlagIndex + 1 < args.length
      ? args[outputFlagIndex + 1]
      : 'test/docs/docs_snippets_test.dart';
  final verbose = args.contains('--verbose');

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

  stdout.writeln('Found ${allSnippets.length} dart snippet(s) '
      'across ${filesToScan.length} file(s).');

  final groups = groupSnippets(allSnippets);
  for (final group in groups) {
    stdout.writeln('  Group: ${group.groupName}');
    stdout.writeln('    Steps: ${group.stepSequence.length}, '
        'Standalone: ${group.standaloneSnippets.length}, '
        'Errors: ${group.errorExamples.length}');
    stdout.writeln('    RPC: ${group.requiresRpc}, '
        'TearDown: ${group.requiresTearDown}');
  }

  // Phase 7A.4+ will add code manipulation helpers and full test generation.
}
