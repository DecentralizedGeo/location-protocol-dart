# Fixed Schema Sepolia Attest Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-run Sepolia schema registration with a fixed pre-registered LP-only schema UID, add explicit schema existence/non-existence checks, and validate end-to-end onchain attestation + fetch correctness using that fixed schema.

**Architecture:** Separate one-time bootstrap from recurring integration tests. A dedicated bootstrap test registers the LP-only schema (`SchemaDefinition.lpFields`) once and prints the resulting UID for storage in `.env` as `SEPOLIA_EXISTING_SCHEMA_UID`. Recurring Sepolia tests consume that UID to verify schema existence, non-existence with zero bytes32, and full attest→getAttestation parity (including encoded payload equivalence) without repeated registrations.

**Tech Stack:** Dart 3.11+, `test` package tags (`sepolia`, `sepolia-bootstrap`), existing EAS clients (`SchemaRegistryClient`, `EASClient`), existing ABI encoder (`AbiEncoder`).

---

## Locked Decisions

- Reusable schema shape: LP-only schema from `SchemaDefinition.lpFields`.
- Onchain attest test remains under `sepolia` tag.
- Non-existent schema test uses zero bytes32 UID.

---

## File Plan (Exact Paths)

**Recurring test flow files**
- Modify: `test/integration/sepolia_onchain_test.dart`
- Modify: `.env.example`
- Modify: `doc/walkthrough.md`

**One-time bootstrap flow files**
- Create: `test/integration/sepolia_schema_bootstrap_test.dart`

**Tag config (only if adding explicit tag metadata)**
- Modify (optional): `dart_test.yaml`

---

### Task 1: Add fixed-schema env wiring and guardrails

**Files:**
- Modify: `.env.example`
- Modify: `test/integration/sepolia_onchain_test.dart`

- [ ] Add `SEPOLIA_EXISTING_SCHEMA_UID=` placeholder to `.env.example` with short guidance that it is populated by one-time bootstrap.
- [ ] Update Sepolia test setup to require `SEPOLIA_EXISTING_SCHEMA_UID` alongside `SEPOLIA_RPC_URL` and `SEPOLIA_PRIVATE_KEY`.
- [ ] Add validation in test bootstrap path: must be `0x`-prefixed and length 66.
- [ ] Keep skip behavior explicit when env vars are missing/incomplete.
- [ ] Run: `dart test test/integration/sepolia_onchain_test.dart --tags sepolia -r expanded`
- [ ] Expected: compile passes; tests may skip if env missing; no runtime path depends on per-run registration.

---

### Task 2: Replace per-run schema registration with existing UID usage

**Files:**
- Modify: `test/integration/sepolia_onchain_test.dart`

- [ ] Remove current “unique schema registration” test that generates a one-off field name per run.
- [ ] Introduce helper constants in test file:
  - existing UID from env
  - zero UID (`0x0000000000000000000000000000000000000000000000000000000000000000`)
- [ ] Keep the integration suite tagged `@Tags(['sepolia'])`.
- [ ] Run: `dart test test/integration/sepolia_onchain_test.dart --tags sepolia -r expanded`
- [ ] Expected: no schema registration happens during normal `sepolia` suite execution.

---

### Task 3: Add schema existence test for configured existing UID

**Files:**
- Modify: `test/integration/sepolia_onchain_test.dart`

- [ ] Add test: query schema by `SEPOLIA_EXISTING_SCHEMA_UID` using `SchemaRegistryClient.getSchema(...)`.
- [ ] Assert non-null schema response and non-empty schema string.
- [ ] Assert returned UID (if provided by model) or equivalent lookup target matches configured UID.
- [ ] Run: `dart test test/integration/sepolia_onchain_test.dart --tags sepolia -r expanded`
- [ ] Expected: test passes against a valid bootstrap UID.

---

### Task 4: Add schema non-existence test using zero bytes32 UID

**Files:**
- Modify: `test/integration/sepolia_onchain_test.dart`

- [ ] Add test: `getSchema(zeroBytes32UID)` where UID is all zeros.
- [ ] Assert non-existence behavior exactly as client currently models it (null or empty schema payload, but not throw for normal response).
- [ ] Keep assertion strict and deterministic for current API contract.
- [ ] Run: `dart test test/integration/sepolia_onchain_test.dart --tags sepolia -r expanded`
- [ ] Expected: zero UID is treated as non-existent schema and test passes consistently.

---

### Task 5: Add recurring onchain attest workflow test using existing schema UID

**Files:**
- Modify: `test/integration/sepolia_onchain_test.dart`

- [ ] Build LP-only `SchemaDefinition` (`fields: []`) so computed UID corresponds to LP base fields.
- [ ] Assert computed LP-only UID equals `SEPOLIA_EXISTING_SCHEMA_UID` before attesting (fast-fail if mismatch).
- [ ] Submit `attest(...)` using LP payload and `userData: {}`.
- [ ] Assert attestation submit result includes tx hash and onchain attestation UID.
- [ ] Fetch onchain attestation via `getAttestation(result.uid)` and assert non-null.
- [ ] Assert key returned fields match submitted values (`uid`, `schema`, recipient/refUID/revocable/expiration semantics as applicable to current model).
- [ ] Recompute encoded payload with `AbiEncoder.encode(schema: lpOnlySchema, lpPayload: submittedPayload, userData: {})`.
- [ ] Assert fetched `attestation.data` byte content equals recomputed encoded payload.
- [ ] Run: `dart test test/integration/sepolia_onchain_test.dart --tags sepolia -r expanded`
- [ ] Expected: full attest→fetch parity passes with fixed schema UID and no schema registration.

---

### Task 6: Add one-time bootstrap test to register LP-only schema and print/store UID instructions

**Files:**
- Create: `test/integration/sepolia_schema_bootstrap_test.dart`
- Modify (optional): `dart_test.yaml`

- [ ] Create a dedicated bootstrap integration test file tagged `@Tags(['sepolia-bootstrap'])`.
- [ ] Build LP-only schema (`SchemaDefinition(fields: [])`) and call `SchemaRegistryClient.register(...)`.
- [ ] Print resulting schema UID with clear copy/paste line: `SEPOLIA_EXISTING_SCHEMA_UID=<uid>`.
- [ ] Add a note in test output that bootstrap is one-time and should not run in normal recurring suite.
- [ ] Optionally declare `sepolia-bootstrap` tag in `dart_test.yaml` comments for discoverability.
- [ ] Run: `dart test test/integration/sepolia_schema_bootstrap_test.dart --tags sepolia-bootstrap -r expanded`
- [ ] Expected: registration tx succeeds once, UID printed for `.env`; re-running may revert/duplicate depending on registry behavior and should be documented.

---

### Task 7: Update docs for recurring vs one-time flow

**Files:**
- Modify: `.env.example`
- Modify: `doc/walkthrough.md`
- Modify (optional): `dart_test.yaml`

- [ ] Document `SEPOLIA_EXISTING_SCHEMA_UID` in `.env.example` and setup steps.
- [ ] In `doc/walkthrough.md`, add short “Sepolia Fixed Schema Workflow” section:
  - one-time bootstrap command
  - where to store UID
  - recurring `sepolia` test command
  - why schema registration is excluded from recurring runs
- [ ] If `dart_test.yaml` is updated, include brief comments for `sepolia` vs `sepolia-bootstrap`.
- [ ] Run: `dart test --exclude-tags sepolia --exclude-tags sepolia-bootstrap -r expanded`
- [ ] Expected: non-network regression suite stays green and unaffected.

---

## Compact Verification Commands

- **Bootstrap run (one-time):**  
  `dart test test/integration/sepolia_schema_bootstrap_test.dart --tags sepolia-bootstrap -r expanded`  
  Expected: LP-only schema registration tx succeeds; UID is printed with `SEPOLIA_EXISTING_SCHEMA_UID=...`.

- **Sepolia recurring suite:**  
  `dart test --tags sepolia --exclude-tags sepolia-bootstrap -r expanded`  
  Expected: uses existing UID, validates schema existence/non-existence and attest workflow without registering new schema.

- **Non-Sepolia regression:**  
  `dart test --exclude-tags sepolia --exclude-tags sepolia-bootstrap -r expanded`  
  Expected: all non-Sepolia tests pass; no dependency on Sepolia env or schema bootstrap.

---

## Scope Notes

- Recurring test runs should avoid creating new schemas.
- The attest test intentionally remains a write operation on Sepolia.
- Bootstrap is explicit and manual, intended for one-time setup of `SEPOLIA_EXISTING_SCHEMA_UID`.
