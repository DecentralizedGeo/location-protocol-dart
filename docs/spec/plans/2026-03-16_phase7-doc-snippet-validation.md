# Phase 7 Implementation Plan: Documentation Snippet Extraction & Validation

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an automated Dart script that extracts all `dart` code snippets from documentation markdown files and generates a test file that validates every snippet compiles and runs without error.

**Architecture:** A single Dart script (`scripts/docs_snippet_extractor.dart`) scans `README.md` and `docs/guides/*.md`, extracts fenced `dart` code blocks with source metadata, auto-detects tutorial step sequences by heading pattern, and generates `test/docs/docs_snippets_test.dart`. Tutorial step fragments are reconstructed by accumulating prior steps into each successive test. Onchain snippets use `.env` loading with skip logic. The generated test file is a derived artifact — never edited manually.

**Tech Stack:** Dart 3.11+, `dart:io` for file I/O, `test` package, existing `location_protocol` barrel import, existing `test/test_helpers/dotenv_loader.dart` for `.env` loading.

---

## Table of Contents

- [Scope and Non-Goals](#scope-and-non-goals)
- [Locked Decisions](#locked-decisions)
- [Snippet Inventory](#snippet-inventory)
- [Snippet Classification & Test Strategy](#snippet-classification--test-strategy)
- [File Plan](#file-plan)
- [Phase 7A — Extractor Script Core (5 tasks)](#phase-7a--extractor-script-core-5-tasks)
- [Phase 7B — Test Generator (5 tasks)](#phase-7b--test-generator-5-tasks)
- [Phase 7C — Integration & Verification (4 tasks)](#phase-7c--integration--verification-4-tasks)
- [Compact Verification Commands](#compact-verification-commands)

**Total tasks:** 14

---

## Scope and Non-Goals

**In scope:**
- Extract all `` ```dart `` fenced code blocks from `README.md` and `docs/guides/*.md`.
- Auto-detect step sequences by `## Step N` heading pattern.
- Reconstruct tutorial steps by accumulating prior step code into each test.
- Substitute placeholder private keys (`'YOUR_PRIVATE_KEY_HEX'`) with a well-known test key.
- Generate a complete, valid Dart test file that compiles and runs.
- Tag onchain-dependent tests with `sepolia` for conditional execution.
- Add `tearDown(() => LocationValidator.resetCustomTypes())` for custom type snippet tests.
- Inject prerequisite code (schema + LP payload) for documents that reference the tutorial.
- Update `dart_test.yaml` with a `doc-snippets` tag.
- Update `scripts/README.md` with usage documentation.

**Non-goals (explicit):**
- No HTML comment directive markers (`<!-- @test:skip -->`) — planned for future.
- No expected-output assertion extraction — tests validate "runs without error" only.
- No CI/CD pipeline changes (GitHub Actions).
- No testing of non-Dart code blocks (YAML, shell, Mermaid, dotenv).
- No testing of code blocks inside markdown blockquotes (`> ` prefixed) — these are inline supplementary examples.
- No modification of documentation content itself.

---

## Locked Decisions

- **Generated file is derived.** `test/docs/docs_snippets_test.dart` is auto-generated; its header warns against manual edits. The documentation markdown is the source of truth.
- **Blockquote code blocks are skipped.** Code fences inside `> ` blockquotes (e.g., the `alreadyExisted` branch example in the onchain guide) are V1 non-goals. They are supplementary; testing primary step code is sufficient.
- **Error-demonstrating snippets generate `expect(throwsA(...))` tests.** Snippets under headings containing "Constraints" or with `// Throws:` comments are negative examples. The generator wraps them in `expect(() => ..., throwsA(isA<ArgumentError>()))`.
- **Onchain snippets adapt `.env` loading.** Doc snippets use `Platform.environment` for credentials; generated tests use `loadDotEnv()` and `markTestSkipped()` to match the project's existing test patterns. Core API calls remain verbatim.
- **One file, not many.** The script is a single Dart file (`scripts/docs_snippet_extractor.dart`). If it grows unwieldy during implementation, splitting is acceptable but not planned.
- **The well-known Hardhat test key is used for all offline snippets.** `'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'` — same key used in `test/integration/full_workflow_test.dart`.

---

## Snippet Inventory

This is the authoritative catalog of Dart code blocks to extract and test. Line numbers are approximate and may shift as docs evolve — the extractor uses regex, not line numbers.

### README.md

| ID | Line | Heading | Type | RPC? | Notes |
|----|------|---------|------|------|-------|
| R1 | ~81 | Quick Start | Complete (`main()`) | No | Placeholder key `'YOUR_PRIVATE_KEY_HEX'` — substitute. Commented-out onchain section — strip. |

### docs/guides/tutorial-first-attestation.md

| ID | Line | Heading | Type | RPC? | Notes |
|----|------|---------|------|------|-------|
| T1 | ~55 | Step 1 — Define your schema | Step base (`import` + `main()`) | No | Has `import` and `void main() async {` |
| T2 | ~79 | Step 2 — Create an LP payload | Step fragment | No | Adds `lpPayload` inside `main()` |
| T3 | ~105 | Step 3 — Sign the attestation offchain | Step fragment | No | Adds signer + `signOffchainAttestation` |
| T4 | ~137 | Step 4 — Verify the attestation | Step fragment | No | Adds `verifyOffchainAttestation` |
| T5 | ~155 | Step 5 — Inspect the signed attestation | Step fragment | No | Adds `print()` calls for signed fields |
| T6 | ~175 | Complete program listing | Complete (`main()`) | No | Self-contained; tests independently |

### docs/guides/how-to-register-and-attest-onchain.md

| ID | Line | Heading | Type | RPC? | Notes |
|----|------|---------|------|------|-------|
| O1 | ~52 | Step 1 — Set up your RPC provider | Step base (`import` + `main()`) | Yes | Uses `Platform.environment` — adapt to `.env` |
| O2 | ~72 | Step 2 — Register the schema | Step fragment | Yes | References `schema` from tutorial |
| O3 | ~92 | Step 3 — Attest onchain | Step fragment | Yes | References `schema` + `lpPayload` from tutorial |
| O4 | ~113 | Step 4 — Timestamp an offchain attestation | Step fragment | Yes | References `signed` + `easClient` |

**Blockquote snippet (SKIPPED):** The `alreadyExisted` branch inline example (~line 82) is inside a `>` blockquote and excluded from V1.

### docs/guides/how-to-add-custom-location-type.md

| ID | Line | Heading | Type | RPC? | Notes |
|----|------|---------|------|------|-------|
| C1 | ~15 | Step 1 — Register a custom validator | Step base (has `import`, no `main()`) | No | Top-level registration call |
| C2 | ~33 | Step 2 — Use the custom type in an LP payload | Step fragment | No | Creates `LPPayload` with `plus-code` |
| C3 | ~43 | Constraints — built-in override throws | Error example | No | **Negative test** — wrap in `expect(throwsA(...))` |
| C4 | ~52 | Constraints — `resetCustomTypes()` for tests | Utility fragment | No | `tearDown` pattern — informational only, generate as standalone |

### docs/guides/reference-environment.md

No `` ```dart `` code blocks. Only `dotenv` and `sh` blocks. **Nothing to extract.**

### docs/guides/reference-api.md, explanation-concepts.md

No `` ```dart `` code blocks. Only Mermaid diagrams and tables. **Nothing to extract.**

### Summary

| Category | Count | Test Strategy |
|----------|-------|---------------|
| Complete programs (have `main()`) | 2 (R1, T6) | Extract `main()` body, wrap in `test()` |
| Step-sequence bases (have `import`/`main()`) | 3 (T1, O1, C1) | First step in sequence, forms base for accumulation |
| Step-sequence fragments | 8 (T2–T5, O2–O4, C2) | Accumulate with prior steps |
| Error examples | 1 (C3) | Wrap in `expect(throwsA(...))` |
| Utility fragments | 1 (C4) | Generate as standalone `test()` |
| **Total Dart snippets** | **15** | |
| Blockquote snippets (skipped) | 1 | N/A |

---

## Snippet Classification & Test Strategy

### Strategy 1: Complete Programs (R1, T6)

Extract the body of `main()`, strip `import` statements (they go in the file header), substitute placeholder keys, wrap in `test('...', () async { ... })`.

**README Quick Start (R1) special handling:**
- Replace `'YOUR_PRIVATE_KEY_HEX'` with test key `'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'`.
- Strip or ignore commented-out onchain section (lines starting with `//`-only blocks after `// 6. Optional:`).

### Strategy 2: Step Sequences — Offline (T1–T5)

- **T1 test:** Extract `main()` body from Step 1.
- **T2 test:** T1 body + T2 code appended.
- **T3 test:** T1 body + T2 code + T3 code.
- **T4 test:** T1 body + T2 + T3 + T4 code.
- **T5 test:** T1 body + T2 + T3 + T4 + T5 code.

Each step test runs independently (not dependent on prior test execution).

### Strategy 3: Step Sequences — Onchain (O1–O4)

- **O1 test:** Adapt `Platform.environment` to `loadDotEnv()`, add skip logic.
- **O2 test:** O1 body + prerequisite `schema` definition (from tutorial T1) + O2 code.
- **O3 test:** O1 body + prerequisite `schema` + `lpPayload` (from tutorial T1+T2) + O2 + O3 code.
- **O4 test:** O1 body + prerequisites + O2 + O3 + offchain signing setup (from tutorial T3) + O4 code.

All tagged `['sepolia']`. All skip gracefully if `.env` missing.

**Prerequisite injection:** The onchain guide explicitly states it assumes tutorial completion. The extractor injects the tutorial's `schema` and `lpPayload` definitions as prerequisites when generating onchain step tests.

### Strategy 4: Custom Type Steps (C1–C2)

- **C1 test:** Registration code, wrapped in `test()`. Group has `tearDown(() => LocationValidator.resetCustomTypes())`.
- **C2 test:** C1 code + C2 code accumulated.

### Strategy 5: Error Examples (C3)

- Wrap the throwing call in `expect(() => ..., throwsA(isA<ArgumentError>()))`.

### Strategy 6: Utility Fragments (C4)

- Generate as standalone `test()` with descriptive name.

---

## File Plan

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `scripts/docs_snippet_extractor.dart` | Main extraction & generation script |
| Create | `test/docs/docs_snippets_test.dart` | Auto-generated test file (DO NOT EDIT) |
| Modify | `scripts/README.md` | Document new script |
| Modify | `dart_test.yaml` | Add `doc-snippets` tag definition |

---

## Phase 7A — Extractor Script Core (5 tasks)

### Task 7A.1: Create script scaffold with data model

**Files:**
- Create: `scripts/docs_snippet_extractor.dart`

- [ ] **Step 1: Create the script file with data model and argument parsing**

```dart
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

void main(List<String> args) {
  final outputPath = args.contains('--output')
      ? args[args.indexOf('--output') + 1]
      : 'test/docs/docs_snippets_test.dart';
  final verbose = args.contains('--verbose');

  stdout.writeln('Documentation Snippet Extractor');
  stdout.writeln('Output: $outputPath');
  if (verbose) stdout.writeln('Verbose mode enabled');

  // Phase 7A.2 will add: extraction logic
  // Phase 7B will add: test generation logic
}
```

- [ ] **Step 2: Verify the script runs**

Run: `dart run scripts/docs_snippet_extractor.dart --verbose`
Expected: Prints header lines, exits cleanly.

- [ ] **Step 3: Commit**

```bash
git add scripts/docs_snippet_extractor.dart
git commit -m "feat(scripts): scaffold doc snippet extractor with data model"
```

---

### Task 7A.2: Implement markdown snippet extraction

**Files:**
- Modify: `scripts/docs_snippet_extractor.dart`

- [ ] **Step 1: Add the markdown scanner function**

Add the following function above `main()`:

```dart
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
  final codeBuffer = StringBuffer();

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();

    // Track headings (## or ### level)
    final headingMatch = RegExp(r'^#{1,3}\s+(.+)').firstMatch(trimmed);
    if (headingMatch != null) {
      currentHeading = headingMatch.group(1)!.trim();
    }

    // Detect code block START
    if (codeBlockStartLine == null) {
      // End blockquote block when its closing fence appears
      if (inBlockquoteBlock && trimmed.startsWith('>') && trimmed.contains('```')) {
        inBlockquoteBlock = false;
        continue;
      }
      // Skip blockquote code blocks: "> ```dart"
      if (trimmed.startsWith('>') && trimmed.contains('```dart')) {
        inBlockquoteBlock = true;
        continue;
      }
      if (trimmed == '```dart') {
        codeBlockStartLine = i + 2; // 1-based, next line
        codeBuffer.clear();
        continue;
      }
      continue;
    }

    // Inside a code block — detect END
    if (trimmed == '```') {
      if (inBlockquoteBlock) {
        inBlockquoteBlock = false;
        codeBlockStartLine = null;
        continue;
      }
      snippets.add(ExtractedSnippet(
        sourceFile: filePath,
        lineNumber: codeBlockStartLine,
        heading: currentHeading,
        code: codeBuffer.toString().trimRight(),
      ));
      codeBlockStartLine = null;
      continue;
    }

    // Also handle blockquote end: "> ```"
    if (inBlockquoteBlock && trimmed.startsWith('>') && trimmed.contains('```')) {
      inBlockquoteBlock = false;
      codeBlockStartLine = null;
      continue;
    }

    // Accumulate code lines (strip blockquote prefix if needed)
    if (!inBlockquoteBlock) {
      codeBuffer.writeln(line);
    }
  }

  return snippets;
}
```

- [ ] **Step 2: Define the file scan list and call the extractor from `main()`**

Update `main()` to add:

```dart
  // ──────────────────────────────────────────────
  // Scan documentation files
  // ──────────────────────────────────────────────
  final filesToScan = <String>[
    'README.md',
    ...Directory('docs/guides')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map((f) => f.path.replaceAll(r'\', '/')),
  ];

  final allSnippets = <ExtractedSnippet>[];
  for (final filePath in filesToScan) {
    final snippets = extractSnippetsFromFile(filePath);
    allSnippets.addAll(snippets);
    if (verbose) {
      stdout.writeln('  $filePath: ${snippets.length} dart snippet(s)');
      for (final s in snippets) {
        stdout.writeln('    L${s.lineNumber} [${s.heading}] '
            'main=${s.hasMain} step=${s.stepNumber}');
      }
    }
  }

  stdout.writeln('Found ${allSnippets.length} dart snippet(s) '
      'across ${filesToScan.length} file(s).');
```

- [ ] **Step 3: Run and verify extraction**

Run: `dart run scripts/docs_snippet_extractor.dart --verbose`
Expected: Output listing ~14 dart snippets across README.md and 3 guide files, with correct line numbers, heading context, and main/step metadata.

- [ ] **Step 4: Commit**

```bash
git add scripts/docs_snippet_extractor.dart
git commit -m "feat(scripts): implement markdown dart snippet extraction"
```

---

### Task 7A.3: Implement snippet grouping and classification

**Files:**
- Modify: `scripts/docs_snippet_extractor.dart`

- [ ] **Step 1: Add the grouping function**

Add the following function above `main()`:

```dart
// ──────────────────────────────────────────────
// Snippet grouping & classification
// ──────────────────────────────────────────────

/// Groups extracted snippets by source file and classifies them.
///
/// Within each file group:
/// - Snippets with `stepNumber != null` are collected into `stepSequence`
///   (sorted by step number).
/// - Snippets with `isErrorExample == true` go to `errorExamples`.
/// - All others go to `standaloneSnippets`.
///
/// Files containing `DefaultRpcProvider` or `Platform.environment` are marked
/// as `requiresRpc`. Files with `LocationValidator.register` are marked
/// `requiresTearDown`.
List<SnippetGroup> groupSnippets(List<ExtractedSnippet> snippets) {
  final byFile = <String, List<ExtractedSnippet>>{};
  for (final s in snippets) {
    byFile.putIfAbsent(s.sourceFile, () => []).add(s);
  }

  final groups = <SnippetGroup>[];
  for (final entry in byFile.entries) {
    final filePath = entry.key;
    final fileSnippets = entry.value;

    // Derive a human-friendly group name from the file path
    final fileName = filePath.split('/').last;
    final groupName = fileName.replaceAll('.md', '');

    final stepSequence = fileSnippets
        .where((s) => s.stepNumber != null)
        .toList()
      ..sort((a, b) => a.stepNumber!.compareTo(b.stepNumber!));

    final errorExamples = fileSnippets
        .where((s) => s.isErrorExample)
        .toList();

    final stepAndErrorIds = {
      ...stepSequence.map((s) => s.lineNumber),
      ...errorExamples.map((s) => s.lineNumber),
    };

    final standaloneSnippets = fileSnippets
        .where((s) => !stepAndErrorIds.contains(s.lineNumber))
        .toList();

    final allCode = fileSnippets.map((s) => s.code).join('\n');
    final requiresRpc = allCode.contains('DefaultRpcProvider') ||
        allCode.contains('Platform.environment');
    final requiresTearDown = allCode.contains('LocationValidator.register');

    groups.add(SnippetGroup(
      sourceFile: filePath,
      groupName: groupName,
      snippets: fileSnippets,
      stepSequence: stepSequence,
      standaloneSnippets: standaloneSnippets,
      errorExamples: errorExamples,
      requiresRpc: requiresRpc,
      requiresTearDown: requiresTearDown,
    ));
  }

  return groups;
}
```

- [ ] **Step 2: Call grouping from `main()` and print summary**

Add after the extraction loop in `main()`:

```dart
  final groups = groupSnippets(allSnippets);
  for (final g in groups) {
    stdout.writeln('  Group: ${g.groupName}');
    stdout.writeln('    Steps: ${g.stepSequence.length}, '
        'Standalone: ${g.standaloneSnippets.length}, '
        'Errors: ${g.errorExamples.length}');
    stdout.writeln('    RPC: ${g.requiresRpc}, '
        'TearDown: ${g.requiresTearDown}');
  }
```

- [ ] **Step 3: Run and verify grouping**

Run: `dart run scripts/docs_snippet_extractor.dart --verbose`
Expected:
- `README` group: 0 steps, 1 standalone, 0 errors, RPC=false
- `tutorial-first-attestation` group: 5 steps, 1 standalone (complete listing), 0 errors, RPC=false
- `how-to-register-and-attest-onchain` group: 4 steps, 0 standalone, 0 errors, RPC=true
- `how-to-add-custom-location-type` group: 2 steps, 1 standalone (C4), 1 error (C3), TearDown=true

- [ ] **Step 4: Commit**

```bash
git add scripts/docs_snippet_extractor.dart
git commit -m "feat(scripts): implement snippet grouping and classification"
```

---

### Task 7A.4: Implement code extraction helpers

**Files:**
- Modify: `scripts/docs_snippet_extractor.dart`

- [ ] **Step 1: Add helper functions for code manipulation**

Add the following utility functions above `main()`:

```dart
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
  if (mainMatch == null) return code;

  final start = mainMatch.end;
  // Find matching closing brace by tracking nesting depth
  var depth = 1;
  var end = start;
  for (var i = start; i < code.length; i++) {
    if (code[i] == '{') depth++;
    if (code[i] == '}') depth--;
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

/// Strips trailing commented-out code blocks (e.g., the README's optional
/// onchain section). Removes contiguous blocks of `//`-only lines at the end.
String stripTrailingCommentBlock(String code) {
  final lines = code.split('\n');
  // Walk backwards, removing lines that are only comments or blank
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
```

- [ ] **Step 2: Verify helpers work by adding a quick self-test to `main()`**

Add a temporary `--self-test` mode to `main()` to validate the helpers:

```dart
  if (args.contains('--self-test')) {
    // Quick validation of helper functions
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
    assert(substitutePlaceholderKeys("'YOUR_PRIVATE_KEY_HEX'")
        .contains(_testPrivateKey));

    // Verify Future<void> main() is handled
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
```

Run: `dart run scripts/docs_snippet_extractor.dart --self-test`
Expected: `Self-test passed.`

- [ ] **Step 3: Commit**

```bash
git add scripts/docs_snippet_extractor.dart
git commit -m "feat(scripts): add code extraction and manipulation helpers"
```

---

### Task 7A.5: Define prerequisite injection map

**Files:**
- Modify: `scripts/docs_snippet_extractor.dart`

- [ ] **Step 1: Add prerequisite code constants**

The onchain guide explicitly assumes `schema` and `lpPayload` from the tutorial. Rather than dynamically resolving cross-file dependencies, define the prerequisite code block that the generator will inject. Add above `main()`:

```dart
// ──────────────────────────────────────────────
// Cross-document prerequisite injection
// ──────────────────────────────────────────────

/// Prerequisites injected before onchain guide step code.
///
/// These mirror the tutorial's Step 1 (schema) and Step 2 (lpPayload)
/// definitions. Kept as a constant so the generator can prepend them
/// when the onchain guide's steps reference `schema` and `lpPayload`
/// without defining them.
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
///
/// Step 4 references `signed` (a `SignedOffchainAttestation`) and `easClient`.
/// This block creates the signed attestation using the tutorial pattern.
const _offchainSigningPrerequisite = '''
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
///
/// When generating tests for a file in this map, the generator injects
/// the corresponding prerequisite code before the step sequence code.
const _filePrerequisites = {
  'how-to-register-and-attest-onchain.md': 'tutorial',
};
```

- [ ] **Step 2: Commit**

```bash
git add scripts/docs_snippet_extractor.dart
git commit -m "feat(scripts): define cross-document prerequisite injection"
```

---

## Phase 7B — Test Generator (5 tasks)

### Task 7B.1: Implement test file header generation

**Files:**
- Modify: `scripts/docs_snippet_extractor.dart`

- [ ] **Step 1: Add the file header generator function**

```dart
// ──────────────────────────────────────────────
// Test file generation
// ──────────────────────────────────────────────

/// Generates the file header for the test file (imports, tags, library directive).
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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/docs_snippet_extractor.dart
git commit -m "feat(scripts): add test file header generation"
```

---

### Task 7B.2: Implement standalone snippet test generation

**Files:**
- Modify: `scripts/docs_snippet_extractor.dart`

- [ ] **Step 1: Add the standalone test generator**

This handles complete programs (R1, T6) and utility fragments (C4).

```dart
/// Generates a `test()` block for a standalone snippet.
///
/// For complete programs (with `main()`): extracts the body, substitutes
/// placeholder keys, and wraps in `test(..., () async { ... })`.
///
/// For fragments without `main()`: wraps the code directly.
String generateStandaloneTest(ExtractedSnippet snippet) {
  final sourceLine = 'L${snippet.lineNumber}';
  final testName = '${snippet.heading} ($sourceLine)';
  var code = snippet.code;

  // Substitute placeholder keys
  code = substitutePlaceholderKeys(code);

  if (snippet.hasMain) {
    // Extract main() body and strip trailing comment blocks
    code = extractMainBody(code);
    code = stripTrailingCommentBlock(code);
  }

  // Indent the code body for inside the test closure
  final indented = indent(code, 6);

  return '''
    test('$testName', () async {
$indented
    });''';
}
```

- [ ] **Step 2: Commit**

```bash
git add scripts/docs_snippet_extractor.dart
git commit -m "feat(scripts): implement standalone snippet test generation"
```

---

### Task 7B.3: Implement step sequence test generation

**Files:**
- Modify: `scripts/docs_snippet_extractor.dart`

- [ ] **Step 1: Add the step sequence test generator**

This handles accumulated step reconstruction (T1–T5, O1–O4, C1–C2).

```dart
/// Generates a `group()` with accumulated step tests.
///
/// Each step test includes all prior step code prepended, so Step N
/// test = Step 1 body + Step 2 body + ... + Step N body.
///
/// For step sequences in the onchain guide, prerequisite injection and
/// .env skip logic are applied to the first step.
String generateStepSequenceTests(SnippetGroup group) {
  if (group.stepSequence.isEmpty) return '';

  final steps = group.stepSequence;
  final buffer = StringBuffer();
  final fileName = group.sourceFile.split('/').last;

  buffer.writeln("    group('Step sequence', () {");

  // Accumulate code bodies across steps
  final accumulatedBodies = <String>[];

  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    var stepCode = step.code;

    if (i == 0) {
      // First step: extract main body if present, strip imports
      if (step.hasMain) {
        stepCode = extractMainBody(stepCode);
      } else {
        stepCode = stripImports(stepCode);
      }

      // For onchain guide: adapt Platform.environment to loadDotEnv
      if (group.requiresRpc) {
        stepCode = _generateOnchainStep1Setup();
      }
    }

    // Substitute placeholder keys in all steps
    stepCode = substitutePlaceholderKeys(stepCode);
    accumulatedBodies.add(stepCode);

    // Build the full test body from all accumulated steps
    final testBody = StringBuffer();

    // Inject prerequisites if this file needs them
    if (_filePrerequisites.containsKey(fileName)) {
      // Inject tutorial prerequisites before step 2+ (step 1 is provider setup)
      if (i >= 1) {
        testBody.writeln(_tutorialPrerequisites);
        testBody.writeln();
      }
      // Inject offchain signing prerequisite for the timestamp step (step 4)
      if (i >= 3) {
        testBody.writeln(_offchainSigningPrerequisite);
        testBody.writeln();
      }
    }

    for (final body in accumulatedBodies) {
      testBody.writeln(body);
      testBody.writeln();
    }

    final testName = '${step.heading} (L${step.lineNumber})';
    final indented = indent(testBody.toString().trimRight(), 8);

    buffer.writeln("      test('$testName', () async {");
    buffer.writeln(indented);
    buffer.writeln('      });');
    buffer.writeln();
  }

  buffer.writeln('    });');
  return buffer.toString();
}

/// Generates the adapted onchain Step 1 setup code.
///
/// Replaces `Platform.environment` from the doc snippet with `loadDotEnv()`
/// to match the project's test infrastructure pattern. The original snippet's
/// code parameter is intentionally not used — this is a hardcoded replacement
/// because the doc uses env var names (`EAS_RPC_URL`) that differ from the
/// project's test convention (`SEPOLIA_RPC_URL`).
String _generateOnchainStep1Setup() {
  return '''
  // Adapted from doc snippet: uses loadDotEnv() instead of Platform.environment.
  // Doc uses EAS_RPC_URL/EAS_PRIVATE_KEY; tests use SEPOLIA_RPC_URL/SEPOLIA_PRIVATE_KEY.
  final env = loadDotEnv();
  final rpcUrl = env['SEPOLIA_RPC_URL'];
  final privateKey = env['SEPOLIA_PRIVATE_KEY'];

  const chainId = 11155111; // Sepolia

  final provider = DefaultRpcProvider(
    rpcUrl: rpcUrl!,
    privateKeyHex: privateKey!,
    chainId: chainId,
  );''';
}
```

- [ ] **Step 2: Commit**

```bash
git add scripts/docs_snippet_extractor.dart
git commit -m "feat(scripts): implement step sequence test generation with accumulation"
```

---

### Task 7B.4: Implement error example test generation

**Files:**
- Modify: `scripts/docs_snippet_extractor.dart`

- [ ] **Step 1: Add the error example generator**

```dart
/// Generates `test()` blocks for error-demonstrating snippets.
///
/// Wraps the snippet code in `expect(() { ... }, throwsA(isA<ArgumentError>()))`.
String generateErrorExampleTests(List<ExtractedSnippet> errorExamples) {
  if (errorExamples.isEmpty) return '';

  final buffer = StringBuffer();
  for (final snippet in errorExamples) {
    final testName = '${snippet.heading} (L${snippet.lineNumber})';

    // Strip the "// Throws: ..." comment line and the trailing `...`
    var code = snippet.code
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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/docs_snippet_extractor.dart
git commit -m "feat(scripts): implement error example test generation"
```

---

### Task 7B.5: Implement full test file assembly and file output

**Files:**
- Modify: `scripts/docs_snippet_extractor.dart`

- [ ] **Step 1: Add the full file assembler function**

```dart
/// Assembles the complete test file from all snippet groups.
String generateTestFile(List<SnippetGroup> groups) {
  final buffer = StringBuffer();
  buffer.writeln(generateFileHeader());

  buffer.writeln('void main() {');

  for (final group in groups) {
    // Skip groups with no extractable snippets
    if (group.snippets.isEmpty) continue;

    // For RPC-dependent groups, use group-level skip (matches sepolia_onchain_test.dart pattern)
    if (group.requiresRpc) {
      buffer.writeln("  group('${group.groupName}', tags: ['sepolia'], () {");
      buffer.writeln("    final env = loadDotEnv();");
      buffer.writeln("    final rpcUrl = env['SEPOLIA_RPC_URL'];");
      buffer.writeln("    final privateKey = env['SEPOLIA_PRIVATE_KEY'];");
      buffer.writeln();
    } else {
      buffer.writeln("  group('${group.groupName}', () {");
    }

    // Add tearDown if needed (custom location type tests)
    if (group.requiresTearDown) {
      buffer.writeln(
          '    tearDown(() => LocationValidator.resetCustomTypes());');
      buffer.writeln();
    }

    // Generate step sequence tests
    final stepTests = generateStepSequenceTests(group);
    if (stepTests.isNotEmpty) {
      buffer.writeln(stepTests);
    }

    // Generate standalone snippet tests
    for (final snippet in group.standaloneSnippets) {
      buffer.writeln(generateStandaloneTest(snippet));
      buffer.writeln();
    }

    // Generate error example tests
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
```

- [ ] **Step 2: Wire the generator into `main()` and add file output**

Add at the end of `main()`:

```dart
  // ──────────────────────────────────────────────
  // Generate test file
  // ──────────────────────────────────────────────
  final testFileContent = generateTestFile(groups);

  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(testFileContent);

  // Summary
  final totalSnippets = groups.fold<int>(0, (sum, g) => sum + g.snippets.length);
  final totalSteps = groups.fold<int>(0, (sum, g) => sum + g.stepSequence.length);
  final totalStandalone =
      groups.fold<int>(0, (sum, g) => sum + g.standaloneSnippets.length);
  final totalErrors =
      groups.fold<int>(0, (sum, g) => sum + g.errorExamples.length);

  stdout.writeln('');
  stdout.writeln('Generated $outputPath');
  stdout.writeln('  $totalSnippets snippet(s): '
      '$totalSteps step(s), $totalStandalone standalone, $totalErrors error example(s)');
  stdout.writeln('  ${groups.length} test group(s)');
  stdout.writeln('');
  stdout.writeln('Run offline tests:');
  stdout.writeln('  dart test --tags doc-snippets --exclude-tags sepolia');
  stdout.writeln('Run all (requires .env):');
  stdout.writeln('  dart test --tags doc-snippets');
```

- [ ] **Step 3: Run the script and generate the test file**

Run: `dart run scripts/docs_snippet_extractor.dart --verbose`
Expected: Creates `test/docs/docs_snippets_test.dart`, prints summary of extracted snippets.

- [ ] **Step 4: Commit**

```bash
git add scripts/docs_snippet_extractor.dart
git commit -m "feat(scripts): implement full test file assembly and output"
```

---

## Phase 7C — Integration & Verification (4 tasks)

### Task 7C.1: Verify generated test file compiles

**Files:**
- Verify: `test/docs/docs_snippets_test.dart` (auto-generated)

- [ ] **Step 1: Run the script to generate the test file**

Run: `dart run scripts/docs_snippet_extractor.dart`

- [ ] **Step 2: Run the Dart analyzer on the generated file**

Run: `dart analyze test/docs/docs_snippets_test.dart`
Expected: No errors. Warnings about unused variables are acceptable (doc snippets may define vars for demonstration without using them).

- [ ] **Step 3: Fix any generation issues**

If the analyzer reports errors, fix the generator logic in `scripts/docs_snippet_extractor.dart`. Common issues to check:
- Missing semicolons from `extractMainBody()` edge cases
- Unbalanced braces from code extraction
- Incorrect indentation breaking Dart syntax
- Missing imports in the generated file header

Regenerate and re-analyze until clean: `dart run scripts/docs_snippet_extractor.dart && dart analyze test/docs/docs_snippets_test.dart`

- [ ] **Step 4: Commit the generated test file**

```bash
git add test/docs/docs_snippets_test.dart
git commit -m "test: add auto-generated documentation snippet tests"
```

---

### Task 7C.2: Run generated tests and fix issues

**Files:**
- Verify: `test/docs/docs_snippets_test.dart`
- May modify: `scripts/docs_snippet_extractor.dart` (if generator produces incorrect tests)

- [ ] **Step 1: Run offline doc-snippet tests**

Run: `dart test test/docs/docs_snippets_test.dart --exclude-tags sepolia -r expanded`
Expected: All offline tests pass (README, tutorial, custom type groups).

- [ ] **Step 2: Debug and fix any offline test failures**

If tests fail, identify the root cause:
- **Compilation error in snippet:** Likely a generator bug — fix in `docs_snippet_extractor.dart`.
- **Runtime error in snippet:** May indicate a documentation bug — check if the doc snippet itself is wrong. If so, fix the doc and regenerate. If the snippet is correct but the test wrapper is wrong, fix the generator.
- **Step accumulation error:** Verify that step N includes all prior step bodies correctly.

Iterate: fix generator → regenerate → re-run tests.

- [ ] **Step 3: Run onchain doc-snippet tests (if .env available)**

Run: `dart test test/docs/docs_snippets_test.dart --tags sepolia -r expanded`
Expected: Onchain tests pass if `.env` is configured, or skip if not.

- [ ] **Step 4: Commit fixes**

```bash
git add scripts/docs_snippet_extractor.dart test/docs/docs_snippets_test.dart
git commit -m "fix(scripts): resolve doc snippet test generation issues"
```

---

### Task 7C.3: Update configuration and documentation

**Files:**
- Modify: `dart_test.yaml`
- Modify: `scripts/README.md`

- [ ] **Step 1: Add `doc-snippets` tag to `dart_test.yaml`**

Add the new tag definition after the existing `sepolia` tag:

```yaml
tags:
  sepolia:
    # Tests requiring a live Sepolia RPC connection.
    # Run with: dart test --tags sepolia
    # Requires .env file with SEPOLIA_RPC_URL and SEPOLIA_PRIVATE_KEY
  doc-snippets:
    # Auto-generated documentation snippet validation tests.
    # Regenerate with: dart run scripts/docs_snippet_extractor.dart
    # Run offline: dart test --tags doc-snippets --exclude-tags sepolia
    # Run all:     dart test --tags doc-snippets
```

- [ ] **Step 2: Update `scripts/README.md`**

Add the new script section after the existing `sepolia_schema_bootstrap.dart` section:

```markdown
## `docs_snippet_extractor.dart`

Extracts all `` ```dart `` code blocks from `README.md` and `docs/guides/*.md`, then generates `test/docs/docs_snippets_test.dart` — a complete test file that validates every documentation code snippet compiles and runs without error.

**When to run:** After modifying any documentation that contains Dart code examples. The generated test file is a derived artifact and should not be edited manually.

**What it does:**
- Scans markdown files for fenced `dart` code blocks
- Auto-detects tutorial step sequences (`## Step 1`, `## Step 2`, etc.)
- Reconstructs step sequences by accumulating prior step code into each test
- Substitutes placeholder private keys with a well-known test key
- Injects prerequisite code for documents that reference the tutorial
- Wraps error-demonstrating snippets in `expect(throwsA(...))` assertions
- Tags RPC-dependent tests with `sepolia` for conditional execution

### Run

```bash
dart run scripts/docs_snippet_extractor.dart
```

Options:
- `--output <path>` — Override output file (default: `test/docs/docs_snippets_test.dart`)
- `--verbose` — Print detailed extraction info

### Test the generated file

```bash
# Offline tests only (no RPC needed)
dart test --tags doc-snippets --exclude-tags sepolia

# All doc snippet tests (requires .env with Sepolia credentials)
dart test --tags doc-snippets

# Expanded output
dart test --tags doc-snippets --exclude-tags sepolia -r expanded
```
```

- [ ] **Step 3: Commit**

```bash
git add dart_test.yaml scripts/README.md
git commit -m "docs: add doc-snippets tag config and extractor script docs"
```

---

### Task 7C.4: Final verification

- [ ] **Step 1: Run formatting check**

Run: `dart format --set-exit-if-changed scripts/docs_snippet_extractor.dart`
Fix any formatting issues.

- [ ] **Step 2: Run analyzer on entire project**

Run: `dart analyze`
Expected: No errors across the entire project.

- [ ] **Step 3: Run full test suite (offline)**

Run: `dart test --exclude-tags sepolia`
Expected: All existing tests still pass. New `doc-snippets` tests pass.

- [ ] **Step 4: Run doc-snippet tests specifically**

Run: `dart test --tags doc-snippets --exclude-tags sepolia -r expanded`
Expected: All offline documentation snippet tests pass. Output shows individual test names with source file + line references.

- [ ] **Step 5: Verify idempotency**

Run: `dart run scripts/docs_snippet_extractor.dart`
Then run again: `dart run scripts/docs_snippet_extractor.dart`
Compare: The generated file should be identical both times. No timestamp is included in the header, so output should be fully deterministic.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: phase 7 — automated doc snippet extraction and validation"
```

---

## Compact Verification Commands

```bash
# Generate the test file
dart run scripts/docs_snippet_extractor.dart --verbose

# Analyze generated file
dart analyze test/docs/docs_snippets_test.dart

# Run offline doc tests
dart test --tags doc-snippets --exclude-tags sepolia -r expanded

# Run all doc tests (with RPC if .env present)
dart test --tags doc-snippets -r expanded

# Run full project test suite
dart test --exclude-tags sepolia

# Verify idempotency
dart run scripts/docs_snippet_extractor.dart && dart run scripts/docs_snippet_extractor.dart
```
