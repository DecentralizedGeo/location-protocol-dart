# Sepolia Bootstrap Scripts

## Purpose

This folder contains one-off utilities that should **not** be part of recurring integration test runs.

## `sepolia_schema_bootstrap.dart`

Registers the LP-only schema on Sepolia once and prints a copy/paste line for `.env`:

- `SEPOLIA_EXISTING_SCHEMA_UID=<uid>`

Use it when setting up a new test environment or replacing the fixed schema UID.

## Run

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
