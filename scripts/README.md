# Sepolia Bootstrap Scripts

## Table of Contents
- [Sepolia Bootstrap Scripts](#sepolia-bootstrap-scripts)
  - [Table of Contents](#table-of-contents)
  - [Purpose](#purpose)
  - [`sepolia_schema_bootstrap.dart`](#sepolia_schema_bootstrapdart)
  - [`docs_snippet_extractor.dart`](#docs_snippet_extractordart)
    - [Test the generated file](#test-the-generated-file)

## Purpose

This folder contains one-off utilities that should **not** be part of recurring integration test runs.

## `sepolia_schema_bootstrap.dart`

Registers the LP-only schema on Sepolia once and prints a copy/paste line for `.env`:

- `SEPOLIA_EXISTING_SCHEMA_UID=<uid>`

Use it when setting up a new test environment or replacing the fixed schema UID.

**How to run script**

```bash
dart run scripts/sepolia_schema_bootstrap.dart
```

Expected inputs (from `.env` or process env):

- `SEPOLIA_RPC_URL`
- `SEPOLIA_PRIVATE_KEY`

After it succeeds, copy the printed `SEPOLIA_EXISTING_SCHEMA_UID` into your `.env` and run recurring Sepolia tests:

```bash
dart test --tags sepolia -r expanded
```

## `docs_snippet_extractor.dart`

Extracts all `````dart`` code blocks from `README.md` and `docs/guides/*.md`, then generates `test/docs/docs_snippets_test.dart` — a complete test file that validates every documentation code snippet compiles and runs without error.

**When to run:** After modifying any documentation that contains Dart code examples. The generated test file is a derived artifact and should not be edited manually.

**What it does:**
- Scans markdown files for fenced `dart` code blocks
- Auto-detects tutorial step sequences (`## Step 1`, `## Step 2`, etc.)
- Reconstructs step sequences by accumulating prior step code into each test
- Substitutes placeholder private keys with a well-known test key
- Injects prerequisite code for documents that reference the tutorial
- Wraps error-demonstrating snippets in `expect(throwsA(...))` assertions
- Tags RPC-dependent tests with `sepolia` for conditional execution

**How to run script**

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
