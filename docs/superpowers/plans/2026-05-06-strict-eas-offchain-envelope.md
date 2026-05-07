# Strict EAS Offchain Envelope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor offchain attestation support so `SignedOffchainAttestation` becomes the single canonical preserved EAS envelope, serializes as exact EAS package JSON, and verifies the preserved signed payload directly.

**Architecture:** Keep one public offchain model, `SignedOffchainAttestation`, but change its stored state from a flattened derived record to preserved EAS envelope fields: `signer`, `domain`, `primaryType`, `types`, `message`, `signature`, and `uid`. `OffchainSigner` remains the signing entry point, but it now derives wallet-safe typed data from the canonical envelope only as an internal helper. Verification uses the preserved envelope directly and reports structured failure categories through `VerificationResult`.

**Tech Stack:** Dart 3.x, `test`, `on_chain`, `blockchain_utils`, existing `docs_snippet_extractor.dart` workflow

---

## File Structure

**Modify**

- `lib/src/models/attestation.dart` — redefine `SignedOffchainAttestation` as the canonical preserved EAS envelope and add JSON round-trip + derived getters
- `lib/src/models/signature.dart` — add JSON helpers for `EIP712Signature` if needed
- `lib/src/models/verification_result.dart` — add structured failure categories for strict verification
- `lib/src/eas/offchain_signer.dart` — build canonical envelopes when signing, verify preserved envelopes directly, keep typed-data request generation internal/helper-only
- `lib/location_protocol.dart` — keep exports aligned with the canonical API surface
- `test/models/attestation_test.dart` — specify canonical model shape, JSON round-trip, and derived getters
- `test/eas/offchain_signer_test.dart` — specify strict verification behavior, tamper failures, SDK-shape compatibility, and version-2 `salt`
- `test/integration/full_workflow_test.dart` — update integration expectations to use the canonical envelope + getters
- `README.md` — update offchain examples to show canonical EAS serialization and verification
- `doc/guides/reference-api.md` — update API docs for the new `SignedOffchainAttestation` semantics
- `doc/guides/tutorial-first-attestation.md` — update tutorial snippets
- `doc/guides/tutorial-wallet-signer.md` — update wallet-signing examples

**Keep As-Is Unless Tests Prove Otherwise**

- `lib/src/eas/constants.dart` — only modify if SDK parity work requires new constants or docs
- `test/docs/docs_snippets_test.dart` — generated artifact; regenerate instead of hand-editing

---

### Task 1: Lock Down Canonical Envelope Behavior With Failing Tests

**Files:**

- Modify: `test/models/attestation_test.dart`
- Modify: `test/eas/offchain_signer_test.dart`
- Test: `test/models/attestation_test.dart`
- Test: `test/eas/offchain_signer_test.dart`

- [ ] **Step 1: Rewrite the model tests around exact EAS JSON shape**

Replace the current flat-model assertions in `test/models/attestation_test.dart` with tests like this:

```dart
group('SignedOffchainAttestation', () {
 final canonical = SignedOffchainAttestation.fromJson({
  'signer': '0x1111111111111111111111111111111111111111',
  'sig': {
   'domain': {
    'name': 'EAS Attestation',
    'version': '1.0.0',
    'chainId': 11155111,
    'verifyingContract': '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
   },
   'primaryType': 'Attest',
   'types': {
    'Attest': [
     {'name': 'version', 'type': 'uint16'},
     {'name': 'schema', 'type': 'bytes32'},
     {'name': 'recipient', 'type': 'address'},
     {'name': 'time', 'type': 'uint64'},
     {'name': 'expirationTime', 'type': 'uint64'},
     {'name': 'revocable', 'type': 'bool'},
     {'name': 'refUID', 'type': 'bytes32'},
     {'name': 'data', 'type': 'bytes'},
     {'name': 'salt', 'type': 'bytes32'},
    ],
   },
   'message': {
    'version': 2,
    'schema': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'recipient': '0x0000000000000000000000000000000000000000',
    'time': 1710000000,
    'expirationTime': 0,
    'revocable': true,
    'refUID': '0x0000000000000000000000000000000000000000000000000000000000000000',
    'data': '0x010203',
    'salt': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
   },
   'signature': {
    'v': 28,
    'r': '0x1111111111111111111111111111111111111111111111111111111111111111',
    's': '0x2222222222222222222222222222222222222222222222222222222222222222',
   },
   'uid': '0x3333333333333333333333333333333333333333333333333333333333333333',
  },
 });

 test('toJson emits exact EAS package shape', () {
  final json = canonical.toJson();
  expect(json.keys, equals(['signer', 'sig']));
  expect((json['sig'] as Map<String, dynamic>).keys, equals([
   'domain',
   'primaryType',
   'types',
   'message',
   'signature',
   'uid',
  ]));
 });

 test('derived getters project common EAS fields without flattening', () {
  expect(canonical.schemaUID, equals('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'));
  expect(canonical.offchainVersion, equals(2));
  expect(canonical.saltHex, equals('0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'));
 });
});
```

- [ ] **Step 2: Run the model tests and verify they fail for the right reason**

Run: `dart test test/models/attestation_test.dart -r expanded`

Expected: FAIL because `SignedOffchainAttestation.fromJson()`, `toJson()`, and derived getters like `schemaUID` / `offchainVersion` / `saltHex` do not exist yet or still reflect the old flat shape.

- [ ] **Step 3: Add strict verification tests for preserved-envelope semantics**

Extend `test/eas/offchain_signer_test.dart` with explicit preserved-envelope tests:

```dart
test('signOffchainAttestation returns canonical EAS envelope JSON', () async {
 final signed = await signer.signOffchainAttestation(
  schema: schema,
  lpPayload: lpPayload,
  userData: {'timestamp': BigInt.from(1710000000), 'memo': 'shape test'},
 );

 final json = signed.toJson();
 expect(json['signer'], equals(signed.signer));
 expect((json['sig'] as Map<String, dynamic>)['primaryType'], equals('Attest'));
 expect(((json['sig'] as Map<String, dynamic>)['message'] as Map<String, dynamic>)['salt'], isNotNull);
});

test('verifyOffchainAttestation fails when uid is tampered', () async {
 final signed = await signer.signOffchainAttestation(
  schema: schema,
  lpPayload: lpPayload,
  userData: {'timestamp': BigInt.from(1710000000), 'memo': 'tamper test'},
 );

 final tampered = SignedOffchainAttestation.fromJson({
  ...signed.toJson(),
  'sig': {
   ...(signed.toJson()['sig'] as Map<String, dynamic>),
   'uid': '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  },
 });

 final result = signer.verifyOffchainAttestation(tampered);
 expect(result.isValid, isFalse);
 expect(result.code, equals(VerificationFailure.uidMismatch));
});
```

Also add one test each for tampered `domain`, `types`, `primaryType`, `message`, `signature`, and missing v2 `salt`.

- [ ] **Step 4: Run the offchain signer tests and verify they fail for the right reason**

Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

Expected: FAIL because current signing still returns the old flat model, `VerificationResult.code` does not exist, and verification still rebuilds typed data instead of validating the preserved envelope directly.

- [ ] **Step 5: Commit the red tests**

```bash
git add test/models/attestation_test.dart test/eas/offchain_signer_test.dart
git commit -m "test: specify canonical EAS offchain envelope behavior"
```

### Task 2: Implement the Canonical `SignedOffchainAttestation` Model

**Files:**

- Modify: `lib/src/models/attestation.dart`
- Modify: `lib/src/models/signature.dart`
- Modify: `test/models/attestation_test.dart`
- Test: `test/models/attestation_test.dart`

- [ ] **Step 1: Replace the flat stored fields on `SignedOffchainAttestation` with preserved envelope fields**

Implement `SignedOffchainAttestation` in `lib/src/models/attestation.dart` with this shape:

```dart
class SignedOffchainAttestation {
 final String signer;
 final Map<String, dynamic> domain;
 final String primaryType;
 final Map<String, dynamic> types;
 final Map<String, dynamic> message;
 final EIP712Signature signature;
 final String uid;

 const SignedOffchainAttestation({
  required this.signer,
  required this.domain,
  required this.primaryType,
  required this.types,
  required this.message,
  required this.signature,
  required this.uid,
 });

 Map<String, dynamic> toJson() => {
  'signer': signer,
  'sig': {
   'domain': domain,
   'primaryType': primaryType,
   'types': types,
   'message': message,
   'signature': signature.toJson(),
   'uid': uid,
  },
 };
}
```

Preserve `UnsignedAttestation` and on-chain `Attestation` unchanged unless tests force a change.

- [ ] **Step 2: Add JSON constructors and typed derived getters on the same class**

Add `fromJson()` and derived getters directly on `SignedOffchainAttestation`:

```dart
factory SignedOffchainAttestation.fromJson(Map<String, dynamic> json) {
 final sig = json['sig'] as Map<String, dynamic>;
 return SignedOffchainAttestation(
  signer: json['signer'] as String,
  domain: Map<String, dynamic>.from(sig['domain'] as Map),
  primaryType: sig['primaryType'] as String,
  types: Map<String, dynamic>.from(sig['types'] as Map),
  message: Map<String, dynamic>.from(sig['message'] as Map),
  signature: EIP712Signature.fromJson(Map<String, dynamic>.from(sig['signature'] as Map)),
  uid: sig['uid'] as String,
 );
}

String get schemaUID => message['schema'] as String;
String get recipient => message['recipient'] as String;
BigInt get time => BigInt.parse(message['time'].toString());
BigInt get expirationTime => BigInt.parse(message['expirationTime'].toString());
bool get revocable => message['revocable'] as bool;
String get refUID => message['refUID'] as String;
int get offchainVersion => int.parse(message['version'].toString());
String? get saltHex => message['salt'] as String?;
```

Also add `dataHex` / `dataBytes` and `saltBytes` getters using the existing hex helpers.

- [ ] **Step 3: Add JSON helpers on `EIP712Signature` if the tests require them**

Add lightweight helpers in `lib/src/models/signature.dart`:

```dart
Map<String, dynamic> toJson() => {
 'v': v,
 'r': r,
 's': s,
};

factory EIP712Signature.fromJson(Map<String, dynamic> json) {
 return EIP712Signature(
  v: (json['v'] as num).toInt(),
  r: json['r'] as String,
  s: json['s'] as String,
 );
}
```

- [ ] **Step 4: Run the model tests and verify they pass**

Run: `dart test test/models/attestation_test.dart -r expanded`

Expected: PASS with all `SignedOffchainAttestation` JSON shape and getter tests green.

- [ ] **Step 5: Commit the canonical model refactor**

```bash
git add lib/src/models/attestation.dart lib/src/models/signature.dart test/models/attestation_test.dart
git commit -m "feat: make SignedOffchainAttestation a canonical EAS envelope"
```

### Task 3: Refactor Verification Results for Strict Failure Categories

**Files:**

- Modify: `lib/src/models/verification_result.dart`
- Modify: `test/eas/offchain_signer_test.dart`
- Test: `test/eas/offchain_signer_test.dart`

- [ ] **Step 1: Add a structured failure enum to `VerificationResult`**

Replace the reason-only contract in `lib/src/models/verification_result.dart` with:

```dart
enum VerificationFailure {
 uidMismatch,
 invalidDomain,
 invalidPrimaryType,
 invalidTypes,
 invalidMessage,
 invalidSignature,
 signerMismatch,
}

class VerificationResult {
 final bool isValid;
 final String recoveredAddress;
 final VerificationFailure? code;
 final String? reason;

 const VerificationResult({
  required this.isValid,
  required this.recoveredAddress,
  this.code,
  this.reason,
 });
}
```

- [ ] **Step 2: Update the tests to assert `code` first and `reason` second**

Use assertions like this in `test/eas/offchain_signer_test.dart`:

```dart
expect(result.isValid, isFalse);
expect(result.code, equals(VerificationFailure.invalidDomain));
expect(result.reason, contains('domain'));
```

- [ ] **Step 3: Run the signer tests and verify they still fail only on signer behavior**

Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

Expected: FAIL because `OffchainSigner.verifyOffchainAttestation()` still implements old behavior, but the failure output should now be about missing/incorrect verification logic rather than missing result types.

- [ ] **Step 4: Commit the verification result contract**

```bash
git add lib/src/models/verification_result.dart test/eas/offchain_signer_test.dart
git commit -m "feat: add structured offchain verification failure codes"
```

### Task 4: Refactor `OffchainSigner` to Sign and Verify the Preserved Envelope

**Files:**

- Modify: `lib/src/eas/offchain_signer.dart`
- Modify: `test/eas/offchain_signer_test.dart`
- Modify: `lib/location_protocol.dart`
- Test: `test/eas/offchain_signer_test.dart`

- [ ] **Step 1: Build the canonical envelope before signing**

In `lib/src/eas/offchain_signer.dart`, change `signOffchainAttestation()` so it first constructs canonical envelope maps and only then derives a wallet-safe request:

```dart
final domain = {
 'name': EASConstants.eip712DomainName,
 'version': easVersion,
 'chainId': chainId,
 'verifyingContract': easContractAddress,
};

final message = {
 'version': EASConstants.attestationVersion,
 'schema': schemaUID,
 'recipient': recipient,
 'time': now,
 'expirationTime': expTime,
 'revocable': schema.revocable,
 'refUID': ref,
 'data': '0x${BytesUtils.toHexString(encodedData)}',
 'salt': saltHex,
};

final types = {
 'Attest': [
  {'name': 'version', 'type': 'uint16'},
  {'name': 'schema', 'type': 'bytes32'},
  {'name': 'recipient', 'type': 'address'},
  {'name': 'time', 'type': 'uint64'},
  {'name': 'expirationTime', 'type': 'uint64'},
  {'name': 'revocable', 'type': 'bool'},
  {'name': 'refUID', 'type': 'bytes32'},
  {'name': 'data', 'type': 'bytes'},
  {'name': 'salt', 'type': 'bytes32'},
 ],
};
```

Then derive the transient wallet request from those canonical values rather than treating the request itself as canonical storage.

- [ ] **Step 2: Replace the return value with canonical `SignedOffchainAttestation`**

Return:

```dart
return SignedOffchainAttestation(
 signer: signerAddress,
 domain: domain,
 primaryType: 'Attest',
 types: types,
 message: message,
 signature: EIP712Signature(v: normalizedV, r: rawSig.r, s: rawSig.s),
 uid: uid,
);
```

- [ ] **Step 3: Verify the preserved envelope directly instead of reconstructing it from flat fields**

Refactor `verifyOffchainAttestation()` to:

```dart
final expectedUid = computeOffchainUID(
 schemaUID: attestation.schemaUID,
 recipient: attestation.recipient,
 time: attestation.time,
 expirationTime: attestation.expirationTime,
 revocable: attestation.revocable,
 refUID: attestation.refUID,
 data: attestation.dataBytes,
 salt: attestation.saltBytes!,
);

if (expectedUid != attestation.uid) {
 return VerificationResult(
  isValid: false,
  recoveredAddress: '',
  code: VerificationFailure.uidMismatch,
  reason: 'UID mismatch',
 );
}

if (!_mapsEqual(attestation.domain, _expectedDomain(attestation.domain['version']))) {
 return VerificationResult(
  isValid: false,
  recoveredAddress: '',
  code: VerificationFailure.invalidDomain,
  reason: 'Preserved EAS domain does not match signer configuration',
 );
}
```

Then validate `primaryType`, `types`, presence of v2 `salt`, and finally recover the signer from the preserved payload.

- [ ] **Step 4: Keep or rename `buildOffchainTypedDataJson()` as a signing helper only**

Make sure the helper is clearly derived from canonical envelope values:

```dart
static Map<String, dynamic> buildOffchainTypedDataJsonFromEnvelope(
 SignedOffchainAttestation attestation,
) {
 return {
  'types': {
   'EIP712Domain': [
    {'name': 'name', 'type': 'string'},
    {'name': 'version', 'type': 'string'},
    {'name': 'chainId', 'type': 'uint256'},
    {'name': 'verifyingContract', 'type': 'address'},
   ],
   ...attestation.types,
  },
  'primaryType': attestation.primaryType,
  'domain': {
   ...attestation.domain,
   'chainId': attestation.domain['chainId'].toString(),
  },
  'message': {
   ...attestation.message,
   'version': attestation.offchainVersion.toString(),
   'time': attestation.time.toString(),
   'expirationTime': attestation.expirationTime.toString(),
  },
 };
}
```

If you keep the old method name for compatibility, update the doc comment to say it is a derived wallet helper, not the canonical model.

- [ ] **Step 5: Reconcile UID packing with pinned SDK expectations**

Before finalizing `computeOffchainUID()`, add a local assertion in the implementation session using a fixed fixture from `test/eas/offchain_signer_test.dart` and make the method match whatever the fixture proves. If the SDK vector requires schema packing as UTF-8 bytes of the schema hex string rather than raw `bytes32`, update the packer to:

```dart
final schemaBytes = Uint8List.fromList(utf8.encode(schemaUID));
packed.addAll(schemaBytes);
```

If the vector proves the current raw `bytes32` path is correct, keep it and document that the Dart fixture matched the pinned SDK output exactly.

- [ ] **Step 6: Run the offchain signer test suite and verify it passes**

Run: `dart test test/eas/offchain_signer_test.dart -r expanded`

Expected: PASS with canonical-shape tests, strict tamper tests, v2 `salt` tests, and signer recovery tests all green.

- [ ] **Step 7: Commit the signing and verification refactor**

```bash
git add lib/src/eas/offchain_signer.dart lib/location_protocol.dart test/eas/offchain_signer_test.dart
git commit -m "feat: sign and verify preserved EAS offchain envelopes"
```

### Task 5: Update Integration Expectations and Public Docs

**Files:**

- Modify: `test/integration/full_workflow_test.dart`
- Modify: `README.md`
- Modify: `doc/guides/reference-api.md`
- Modify: `doc/guides/tutorial-first-attestation.md`
- Modify: `doc/guides/tutorial-wallet-signer.md`
- Test: `test/integration/full_workflow_test.dart`
- Test: `test/docs/docs_snippets_test.dart`

- [ ] **Step 1: Update integration tests to consume canonical envelope getters**

Adjust `test/integration/full_workflow_test.dart` assertions from old flat storage to getter-based access:

```dart
expect(signed.uid, startsWith('0x'));
expect(signed.signer, startsWith('0x'));
expect(signed.offchainVersion, equals(2));
expect(signed.saltHex, startsWith('0x'));
expect(signed.schemaUID, startsWith('0x'));
expect(signed.dataBytes, isNotEmpty);

final result = signer.verifyOffchainAttestation(signed);
expect(result.isValid, isTrue, reason: result.reason);
```

- [ ] **Step 2: Run the integration test and verify it passes**

Run: `dart test test/integration/full_workflow_test.dart -r expanded`

Expected: PASS with the offline full workflow still intact under the canonical envelope model.

- [ ] **Step 3: Update README examples to show exact EAS serialization shape**

Replace the offchain example block in `README.md` with usage like:

```dart
final signed = await signer.signOffchainAttestation(
 schema: schema,
 lpPayload: payload,
 userData: {
  'observedAt': BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
  'memo': 'Rooftop sensor reading',
  'observer': signer.signerAddress,
 },
);

print(jsonEncode(signed.toJson()));
print('UID: ${signed.uid}');
print('Schema UID: ${signed.schemaUID}');
print('Signer: ${signed.signer}');

final result = signer.verifyOffchainAttestation(signed);
assert(result.isValid, 'Attestation verification failed: ${result.reason}');
```

- [ ] **Step 4: Update reference and tutorial docs to describe the new semantics**

In `doc/guides/reference-api.md`, revise the `SignedOffchainAttestation` documentation to say:

```markdown
`SignedOffchainAttestation` is the canonical preserved EAS offchain envelope.
It serializes to:

{
 "signer": "0x...",
 "sig": {
  "domain": {...},
  "primaryType": "Attest",
  "types": {...},
  "message": {...},
  "signature": {...},
  "uid": "0x..."
 }
}

Convenience getters like `schemaUID`, `recipient`, `time`, and `saltHex` are projections from the canonical preserved message.
```

In `tutorial-first-attestation.md` and `tutorial-wallet-signer.md`, update snippets to print canonical JSON via `signed.toJson()` and use getters instead of direct flat fields like `signed.version` or raw `signed.data`.

- [ ] **Step 5: Regenerate and run documentation snippet tests**

Run:

```bash
dart run scripts/docs_snippet_extractor.dart
dart test test/docs/docs_snippets_test.dart -r expanded
```

Expected: generator completes without diff churn on a second run, and snippet tests pass with the canonical envelope examples.

- [ ] **Step 6: Commit the integration and docs update**

```bash
git add test/integration/full_workflow_test.dart README.md doc/guides/reference-api.md doc/guides/tutorial-first-attestation.md doc/guides/tutorial-wallet-signer.md test/docs/docs_snippets_test.dart
git commit -m "docs: adopt canonical EAS offchain envelope examples"
```

### Task 6: Final Regression and Completion Checkpoint

**Files:**

- Modify: `docs/superpowers/plans/2026-05-06-strict-eas-offchain-envelope.md`
- Test: `test/models/attestation_test.dart`
- Test: `test/eas/offchain_signer_test.dart`
- Test: `test/integration/full_workflow_test.dart`
- Test: `test/docs/docs_snippets_test.dart`

- [ ] **Step 1: Run the focused regression suite**

Run:

```bash
dart test test/models/attestation_test.dart test/eas/offchain_signer_test.dart test/integration/full_workflow_test.dart test/docs/docs_snippets_test.dart -r expanded
```

Expected: PASS with zero failing tests in the touched areas.

- [ ] **Step 2: Run the full non-network suite**

Run:

```bash
dart test --exclude-tags sepolia --exclude-tags sepolia-bootstrap -r expanded
```

Expected: PASS across the full offline suite.

- [ ] **Step 3: Run static analysis**

Run:

```bash
dart analyze
```

Expected: no new diagnostics in the touched offchain/model/doc-snippet files. If unrelated pre-existing diagnostics appear elsewhere, record them explicitly before finishing.

- [ ] **Step 4: Update the plan checkboxes and commit the final state**

```bash
git add docs/superpowers/plans/2026-05-06-strict-eas-offchain-envelope.md
git commit -m "chore: mark strict EAS offchain envelope plan complete"
```

---

## Self-Review Checklist

- Spec coverage: This plan covers canonical EAS payload preservation, strict verification of the preserved envelope, UID recomputation checks, tamper failures for `domain` / `types` / `primaryType` / `message` / `signature` / `uid`, v2 `salt` behavior, helper getters instead of a second flat model, docs updates, and snippet validation.
- Placeholder scan: No `TODO`, `TBD`, or “similar to Task N” placeholders remain.
- Type consistency: The plan consistently uses one canonical public type, `SignedOffchainAttestation`, and one result enum, `VerificationFailure`.
