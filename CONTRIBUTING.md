# Contributing to location_protocol

Thank you for your interest. Contributions of all kinds are welcome: bug reports, documentation improvements, test coverage, and new features. Please read this guide before submitting a pull request.

---

## Prerequisites

- Dart ≥3.11 ([install](https://dart.dev/get-dart))
- Git
- An Ethereum RPC endpoint and funded account for integration tests (optional — unit tests run offline); see [Environment configuration](docs/guides/reference-environment.md)

---

## Getting started

```bash
# Clone the repo
git clone https://github.com/DecentralizedGeo/location-protocol-dart.git
cd location-protocol-dart

# Install dependencies
dart pub get
```

---

## Running tests

**Unit tests (offline — no RPC needed):**

```bash
dart test --exclude-tags sepolia
```

**All integration tests (requires Sepolia RPC + funded account):**

```bash
# Set up .env first — see docs/guides/reference-environment.md
dart test --tags sepolia
```

**Run with verbose output:**

```bash
dart test --reporter expanded
```

> Tests tagged `sepolia` skip automatically when `SEPOLIA_RPC_URL` and `SEPOLIA_PRIVATE_KEY` are not set — they will not fail.

---

## Code style

```bash
# Format
dart format .

# Lint
dart analyze
```

The project uses the `lints` package (`analysis_options.yaml`). All contributions should pass `dart analyze` with no warnings.

---

## Project structure

```
lib/src/
  lp/          # LP payload, location serializer, location validator
  schema/      # SchemaDefinition, SchemaField, SchemaUID
  eas/         # ABI encoder, OffchainSigner, EASClient, SchemaRegistryClient
  config/      # ChainConfig
  models/      # Value objects (attestation types, results, signatures)
  rpc/         # RpcProvider interface, DefaultRpcProvider
  utils/       # Hex and byte utilities
```

---

## Pull request checklist

- [ ] `dart analyze` passes with no warnings
- [ ] `dart format .` applied
- [ ] New behavior is covered by tests (`dart test --exclude-tags sepolia` passes)
- [ ] If touching onchain behavior: integration test added or existing test updated
- [ ] Public API changes are reflected in `docs/guides/reference-api.md`
- [ ] Breaking changes are noted in the PR description

---

## Reporting issues

Open a GitHub issue at <https://github.com/DecentralizedGeo/location-protocol-dart/issues>. For security vulnerabilities, do **not** open a public issue — email the maintainers directly.
