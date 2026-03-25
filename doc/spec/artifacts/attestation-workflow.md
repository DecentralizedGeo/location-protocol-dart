Here's a complete guide to the **offline-first workflow** — sign and save offchain attestations locally, then submit them onchain when connectivity is restored.

---

## The Offline-First Offchain Attestation Workflow

The EAS SDK has built-in serialization utilities specifically for this use case in [`src/offchain/offchain-utils.ts`](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain-utils.ts).

### Key Types & Functions

| Export | Purpose |
|---|---|
| `AttestationShareablePackageObject` | The wrapper type for storage: `{ sig, signer }` |
| `zipAndEncodeToBase64(pkg)` | Compresses + Base64-encodes for compact storage |
| `decodeBase64ZippedBase64(str)` | Reverses the above — reconstructs the full object |
| `verifyOffchainAttestationSignature(attester, sig)` | Validates the signature before submitting |

---

### Step 1 — Sign the Attestation (Offline-capable, no network needed)

Signing only requires the signer's private key — no RPC call is needed.

name=sign-offchain.ts

```typescript
import {
  EAS,
  NO_EXPIRATION,
  SchemaEncoder,
  AttestationShareablePackageObject,
  zipAndEncodeToBase64
} from '@ethereum-attestation-service/eas-sdk';
import { ethers } from 'ethers';

const EASContractAddress = '0xC2679fBD37d54388Ce493F1DB75320D236e1815e'; // Sepolia

// NOTE: No provider needed for signing — use a Wallet with just a private key
const signer = new ethers.Wallet(privateKey); // no provider attached

const eas = new EAS(EASContractAddress);
eas.connect(signer);

const offchain = await eas.getOffchain();

const schemaEncoder = new SchemaEncoder('uint256 eventId, uint8 voteIndex');
const encodedData = schemaEncoder.encodeData([
  { name: 'eventId', value: 1, type: 'uint256' },
  { name: 'voteIndex', value: 1, type: 'uint8' }
]);

const signedAttestation = await offchain.signOffchainAttestation(
  {
    schema: '0xb16fa048b0d597f5a821747eba64efa4762ee5143e9a80600d0005386edfc995',
    recipient: '0xFD50b031E778fAb33DfD2Fc3Ca66a1EeF0652165',
    time: BigInt(Math.floor(Date.now() / 1000)),
    expirationTime: NO_EXPIRATION,
    revocable: true,
    refUID: '0x0000000000000000000000000000000000000000000000000000000000000000',
    data: encodedData
  },
  signer
  // NOTE: Do NOT pass { verifyOnchain: true } — that requires a network call
);
```

---

### Step 2 — Serialize & Save Locally

Wrap the signed attestation into an `AttestationShareablePackageObject`, then encode it for compact storage (e.g., `localStorage`, a file, SQLite, AsyncStorage in React Native, etc.).

name=save-offchain.ts

```typescript
import {
  AttestationShareablePackageObject,
  zipAndEncodeToBase64
} from '@ethereum-attestation-service/eas-sdk';

// Build the shareable package
const pkg: AttestationShareablePackageObject = {
  sig: signedAttestation,
  signer: await signer.getAddress()
};

// Serialize to a compact Base64-encoded string (gzip compressed)
const encoded = zipAndEncodeToBase64(pkg);

// --- Save however suits your environment ---

// Browser: localStorage
localStorage.setItem(`eas_attestation_${signedAttestation.uid}`, encoded);

// Node.js / React Native: write to a file or database
import { writeFileSync } from 'fs';
writeFileSync(`./attestations/${signedAttestation.uid}.b64`, encoded, 'utf-8');

console.log('Saved attestation UID:', signedAttestation.uid);
```

---

### Step 3 — Restore & Verify (When Back Online)

Reconstruct the full attestation object and optionally verify the signature before submitting.

name=restore-offchain.ts

```typescript
import {
  decodeBase64ZippedBase64,
  Offchain,
  OffchainAttestationVersion,
  OffchainConfig
} from '@ethereum-attestation-service/eas-sdk';
import { readFileSync } from 'fs';

// Load from storage
const encoded = readFileSync(`./attestations/${uid}.b64`, 'utf-8');
// or from localStorage: const encoded = localStorage.getItem(`eas_attestation_${uid}`);

// Deserialize
const pkg = decodeBase64ZippedBase64(encoded);

// Optional: verify the signature is still valid before spending gas
const offchainConfig: OffchainConfig = {
  address: pkg.sig.domain.verifyingContract,
  version: pkg.sig.domain.version,
  chainId: pkg.sig.domain.chainId
};
const offchain = new Offchain(offchainConfig, OffchainAttestationVersion.Version2);
const isValid = offchain.verifyOffchainAttestationSignature(pkg.signer, pkg.sig);

if (!isValid) {
  throw new Error('Attestation signature is invalid — do not submit!');
}

console.log('Attestation verified, ready to submit.');
```

---

### Step 4 — Timestamp Onchain (Pushes the UID to the EAS contract)

> **Important:** EAS does not "convert" an offchain attestation into a fully onchain one via `attest()`. Instead, you **timestamp the UID** onchain — this cryptographically anchors the offchain attestation to the chain without re-creating it.

name=timestamp-onchain.ts

```typescript
import { EAS } from '@ethereum-attestation-service/eas-sdk';
import { ethers } from 'ethers';

const provider = new ethers.JsonRpcProvider('https://rpc.sepolia.org');
const signer = new ethers.Wallet(privateKey, provider); // now attach a provider

const eas = new EAS('0xC2679fBD37d54388Ce493F1DB75320D236e1815e');
eas.connect(signer);

// Timestamp a single offchain attestation UID
const transaction = await eas.timestamp(pkg.sig.uid);
await transaction.wait();

console.log('Attestation UID timestamped onchain:', pkg.sig.uid);
```

For **multiple queued attestations** (ideal for the offline batch scenario):

name=timestamp-batch-onchain.ts

```typescript
// Timestamp all saved attestations in one transaction (gas efficient)
const uids = savedPackages.map(pkg => pkg.sig.uid);
const transaction = await eas.multiTimestamp(uids);
await transaction.wait();

console.log(`${uids.length} attestation UIDs anchored onchain.`);
```

---

### Full Flow Summary

```
[ No connectivity ]
  1. signOffchainAttestation(params, signer)      → SignedOffchainAttestation
  2. zipAndEncodeToBase64({ sig, signer })         → compact Base64 string
  3. Save string to localStorage / file / DB

[ Back online ]
  4. decodeBase64ZippedBase64(saved string)        → AttestationShareablePackageObject
  5. verifyOffchainAttestationSignature(...)        → validate before spending gas
  6. eas.timestamp(sig.uid)                        → anchors UID onchain
     — or —
     eas.multiTimestamp([uid1, uid2, ...])         → batch all queued attestations
```

### Key Notes

- **`signOffchainAttestation` does not require a network connection** as long as you do not pass `{ verifyOnchain: true }` in the options.
- The **`zipAndEncodeToBase64` / `decodeBase64ZippedBase64`** pair (from [`offchain-utils.ts`](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain-utils.ts)) handles `bigint` serialization correctly — plain `JSON.stringify` will fail on the `bigint` fields.
- `eas.timestamp()` / `eas.multiTimestamp()` anchors the offchain attestation UID to the chain — this is the standard EAS pattern for "promoting" offchain attestations, rather than calling `attest()` again.
- You can share the Base64-encoded string with anyone — it contains everything needed to verify and timestamp the attestation.



Great question — and this is an important distinction. Here's the full picture:

---

## Two Ways to Commit the Full Data Payload Onchain

### The Core Problem with `timestamp()`

`eas.timestamp(uid)` **only anchors the UID** — a hash derived from the attestation parameters. The raw `data` payload, `recipient`, `schema`, `expirationTime`, etc. are **not stored onchain**. Anyone who wants to verify the attestation must still have a copy of the offchain object to reconstruct and check the UID.

To store the **full context** onchain, you have two approaches depending on your needs:

---

## Option A — `eas.attest()`: Re-attest Fully Onchain (Simplest)

Simply use `eas.attest()` with the exact same parameters from the saved offchain attestation. This creates a **brand-new, fully onchain attestation** — all data is stored in the EAS contract and queryable forever.

name=promote-to-onchain.ts

```typescript
import {
  EAS,
  decodeBase64ZippedBase64,
  AttestationShareablePackageObject
} from '@ethereum-attestation-service/eas-sdk';
import { ethers } from 'ethers';
import { readFileSync } from 'fs';

// Step 1: Restore the saved offchain attestation
const encoded = readFileSync(`./attestations/${uid}.b64`, 'utf-8');
const pkg: AttestationShareablePackageObject = decodeBase64ZippedBase64(encoded);

const { sig } = pkg;

// Step 2: Connect with a provider now that we're online
const provider = new ethers.JsonRpcProvider('https://rpc.sepolia.org');
const signer = new ethers.Wallet(privateKey, provider);

const eas = new EAS('0xC2679fBD37d54388Ce493F1DB75320D236e1815e');
eas.connect(signer);

// Step 3: Re-attest onchain using the exact same data from the saved offchain attestation
const transaction = await eas.attest({
  schema: sig.message.schema,
  data: {
    recipient:      sig.message.recipient,
    expirationTime: sig.message.expirationTime,
    revocable:      sig.message.revocable,
    refUID:         sig.message.refUID,
    data:           sig.message.data   // ← full encoded payload goes onchain
  }
});

const onchainUID = await transaction.wait();
console.log('Full onchain attestation UID:', onchainUID);

// NOTE: onchainUID will differ from sig.uid because the attester address
// (msg.sender) and time are part of the UID derivation, and the original
// offchain time is preserved separately below.
```

> ⚠️ **UID caveat:** The onchain UID will differ from the offchain UID because `msg.sender` and `block.timestamp` are baked into the onchain UID derivation. See Option B below if preserving the original UID matters.

---

## Option B — `eas.attestByDelegation()`: Preserve the Original Attester & Onchain UID (Advanced)

This is the **correct approach** if you want the onchain UID to match the offchain UID, or if the transaction submitter is a **different address** from the original signer (e.g., a relayer). The EAS [`Delegated`](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/eas.ts#L267-L311) flow lets the original signer pre-sign the attestation request, and a third-party (the relayer/submitter with gas) submits it — with `attester` correctly recorded as the original signer.

name=promote-delegated-onchain.ts

```typescript
import {
  EAS,
  decodeBase64ZippedBase64,
  AttestationShareablePackageObject
} from '@ethereum-attestation-service/eas-sdk';
import { ethers } from 'ethers';
import { readFileSync } from 'fs';

// Step 1: Restore the saved offchain attestation
const encoded = readFileSync(`./attestations/${uid}.b64`, 'utf-8');
const pkg: AttestationShareablePackageObject = decodeBase64ZippedBase64(encoded);
const { sig, signer: attesterAddress } = pkg;

// Step 2: Connect — can be a DIFFERENT wallet (relayer) that pays gas
const provider = new ethers.JsonRpcProvider('https://rpc.sepolia.org');
const submitterWallet = new ethers.Wallet(submitterPrivateKey, provider);

const eas = new EAS('0xC2679fBD37d54388Ce493F1DB75320D236e1815e');
eas.connect(submitterWallet);

// Step 3: Get the delegated helper and sign a delegated attestation request
// This is done by the ORIGINAL signer (attester), offline if needed
const originalSigner = new ethers.Wallet(originalPrivateKey); // no provider needed for signing
const delegated = await eas.getDelegated();

const delegatedAttestation = await delegated.signDelegatedAttestation(
  {
    schema:         sig.message.schema,
    recipient:      sig.message.recipient,
    expirationTime: sig.message.expirationTime,
    revocable:      sig.message.revocable,
    refUID:         sig.message.refUID,
    data:           sig.message.data,  // ← full payload
    value:          0n,
    nonce:          await eas.getNonce(attesterAddress),
    deadline:       0n  // no deadline
  },
  originalSigner  // ← original attester signs the delegation
);

// Step 4: Submitter broadcasts the tx — full data goes onchain, attester = originalSigner
const transaction = await eas.attestByDelegation({
  schema: sig.message.schema,
  data: {
    recipient:      sig.message.recipient,
    expirationTime: sig.message.expirationTime,
    revocable:      sig.message.revocable,
    refUID:         sig.message.refUID,
    data:           sig.message.data   // ← full payload stored onchain
  },
  signature: delegatedAttestation.signature,
  attester:  attesterAddress,           // ← original signer is recorded as attester
  deadline:  0n
});

const onchainUID = await transaction.wait();
console.log('Onchain attestation UID (attester preserved):', onchainUID);
```

---

## Option C — Batch: `eas.multiAttest()` for Multiple Queued Attestations

If you've been offline and accumulated multiple attestations, submit them all in a single transaction:

name=promote-batch-onchain.ts

```typescript
import { EAS, decodeBase64ZippedBase64 } from '@ethereum-attestation-service/eas-sdk';
import { readFileSync, readdirSync } from 'fs';

const eas = new EAS('0xC2679fBD37d54388Ce493F1DB75320D236e1815e');
eas.connect(signer); // signer with provider attached

// Load all saved attestations
const files = readdirSync('./attestations').filter(f => f.endsWith('.b64'));
const packages = files.map(f => decodeBase64ZippedBase64(readFileSync(`./attestations/${f}`, 'utf-8')));

// Group by schema (multiAttest requires grouping by schema)
const bySchema = packages.reduce((acc, pkg) => {
  const schema = pkg.sig.message.schema;
  if (!acc[schema]) acc[schema] = [];
  acc[schema].push(pkg);
  return acc;
}, {} as Record<string, typeof packages>);

const requests = Object.entries(bySchema).map(([schema, pkgs]) => ({
  schema,
  data: pkgs.map(pkg => ({
    recipient:      pkg.sig.message.recipient,
    expirationTime: pkg.sig.message.expirationTime,
    revocable:      pkg.sig.message.revocable,
    refUID:         pkg.sig.message.refUID,
    data:           pkg.sig.message.data  // ← full payload for each attestation
  }))
}));

const transaction = await eas.multiAttest(requests);
const onchainUIDs = await transaction.wait();
console.log(`${onchainUIDs.length} attestations fully committed onchain:`, onchainUIDs);
```

---

## Summary: Which Approach to Use?

| Goal | Method | Full Data Onchain? | Original UID Preserved? |
|---|---|---|---|
| Just anchor existence | `eas.timestamp(uid)` | ❌ UID only | ✅ |
| Full data, you pay gas | `eas.attest()` | ✅ | ❌ New UID |
| Full data, original attester recorded, relayer pays gas | `eas.attestByDelegation()` | ✅ | ⚠️ Closest match* |
| Batch multiple full attestations | `eas.multiAttest()` | ✅ | ❌ New UIDs |

> *The onchain UID is always derived from `block.timestamp` (not the offchain `time`), so it will technically differ. However, **the attester address and the full data payload are faithfully preserved onchain** with `attestByDelegation`. You can store the original offchain UID in `refUID` to create a verifiable link between the two records.

**The recommended pattern for your use case** (offline → online) is:
1. **Offline:** `signOffchainAttestation()` → save with `zipAndEncodeToBase64()`
2. **Online:** `multiAttest()` or `multiAttestByDelegation()` to push all queued attestations with full data in one gas-efficient transaction

Your understanding is **correct** — and it's actually a clean, idiomatic EAS pattern. Let me confirm exactly how it works and what you can and cannot infer from it.

### Can the Original Attester Be Both Signer AND Submitter?

**Yes, absolutely.** The whole point of `attestByDelegation` is to decouple *who signs* from *who sends the transaction*. But there is no rule preventing the original signer from also being the one to broadcast it. When back online, the original attester can:

1. Sign the delegated attestation request (offline, already done)
2. Attach a provider and submit the transaction themselves

name=self-relay-delegation.ts

```typescript
// The original signer IS the relayer ��� they sign AND submit
const signer = new ethers.Wallet(privateKey, provider); // provider attached when back online

const eas = new EAS(EASContractAddress);
eas.connect(signer); // same wallet signs the delegation AND submits the tx

const delegated = await eas.getDelegated();

const delegatedAttestation = await delegated.signDelegatedAttestation(
  {
    schema:         sig.message.schema,
    recipient:      sig.message.recipient,
    expirationTime: sig.message.expirationTime,
    revocable:      sig.message.revocable,
    refUID:         sig.message.refUID,
    data:           sig.message.data,
    value:          0n,
    nonce:          await eas.getNonce(await signer.getAddress()),
    deadline:       0n
  },
  signer  // ← original attester signs
);

const transaction = await eas.attestByDelegation({
  schema:    sig.message.schema,
  data: {
    recipient:      sig.message.recipient,
    expirationTime: sig.message.expirationTime,
    revocable:      sig.message.revocable,
    refUID:         sig.message.refUID,
    data:           sig.message.data
  },
  signature: delegatedAttestation.signature,
  attester:  await signer.getAddress(), // ← same address
  deadline:  0n
});
// attester recorded onchain = signer's address ✅
```

The delegation mechanism is still useful here even when self-relaying because it gives you a **deadline** and **nonce** control, but yes — the same wallet can do both.

---

## How `refUID` Works as a Link

`refUID` is a first-class field on every onchain EAS attestation. It is stored in the contract and returned when you call `getAttestation(uid)`. Looking at the `Attestation` interface in the SDK:

```typescript name=eas.ts url=https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/eas.ts#L44-L55
export interface Attestation {
  uid: string;
  schema: string;
  refUID: string;      // ← stored onchain, queryable forever
  time: bigint;
  expirationTime: bigint;
  revocationTime: bigint;
  recipient: string;
  revocable: boolean;
  attester: string;
  data: string;
}
```

When you submit onchain with `refUID = sig.uid` (the offchain UID), that value is **permanently stored in the EAS contract** alongside the full data payload. Anyone who fetches the onchain attestation gets the `refUID` back.

---

## What You Can and Cannot Infer

### ✅ What you CAN correctly infer

1. **The `refUID` value is the offchain UID** — you stored it there intentionally, and it's immutable onchain
2. **The offchain attestation's data was signed before the onchain submission** — the offchain UID is derived from the data payload + `time` + `salt`, so it proves the content was committed to at signing time
3. **`refUID !== ZERO_BYTES32` means something is being referenced** — your convention of "non-zero `refUID` = originated offline" is a valid application-level convention
4. **You can reconstruct and verify the offchain attestation independently** — given the saved `AttestationShareablePackageObject`, anyone can recompute `Offchain.getOffchainUID(...)` and confirm it matches the `refUID` on the onchain record

### ⚠️ One important caveat

`refUID` is not *validated* by the EAS contract against offchain attestations — it only validates that if a `refUID` points to an **onchain** attestation, that attestation exists. For offchain UIDs passed as `refUID`, the contract simply stores whatever value you provide without checking it. This means:

- The link is **a trusted convention, not a contract-enforced proof**
- The integrity guarantee comes from your application layer: you verify the offchain signature yourself, confirm the `sig.uid` matches what you compute from the data, then confirm that value matches the `refUID` on the onchain record

---

## The Full Verification Flow

Here is exactly how to close the loop — given an onchain attestation, verify its offchain origin:

name=verify-offchain-origin.ts

```typescript
import {
  EAS,
  Offchain,
  OffchainAttestationVersion,
  decodeBase64ZippedBase64,
  AttestationShareablePackageObject
} from '@ethereum-attestation-service/eas-sdk';
import { ZERO_BYTES32 } from '@ethereum-attestation-service/eas-sdk/dist/utils';

const eas = new EAS(EASContractAddress);
eas.connect(provider);

// Step 1: Fetch the onchain attestation
const onchainAttestation = await eas.getAttestation(onchainUID);

// Step 2: Check if it references an offchain origin
const hasOffchainOrigin = onchainAttestation.refUID !== ZERO_BYTES32;
console.log('Has offchain origin:', hasOffchainOrigin);

if (hasOffchainOrigin) {
  // Step 3: Load the saved offchain package (from your local store)
  const saved = loadFromStorage(onchainAttestation.refUID); // keyed by offchain UID
  const pkg: AttestationShareablePackageObject = decodeBase64ZippedBase64(saved);

  // Step 4: Recompute the offchain UID from the saved package's data
  const recomputedOffchainUID = Offchain.getOffchainUID(
    pkg.sig.message.version,
    pkg.sig.message.schema,
    pkg.sig.message.recipient,
    pkg.sig.message.time,
    pkg.sig.message.expirationTime,
    pkg.sig.message.revocable,
    pkg.sig.message.refUID,
    pkg.sig.message.data,
    pkg.sig.message.salt
  );

  // Step 5: Confirm the recomputed offchain UID matches the onchain refUID
  const offchainUIDMatches = recomputedOffchainUID === onchainAttestation.refUID;
  console.log('Offchain UID matches refUID:', offchainUIDMatches);

  // Step 6: Verify the offchain signature is valid
  const offchainConfig = {
    address:  pkg.sig.domain.verifyingContract,
    version:  pkg.sig.domain.version,
    chainId:  pkg.sig.domain.chainId
  };
  const offchain = new Offchain(offchainConfig, OffchainAttestationVersion.Version2, eas);
  const signatureValid = offchain.verifyOffchainAttestationSignature(pkg.signer, pkg.sig);
  console.log('Offchain signature valid:', signatureValid);

  // Step 7: Confirm the attester is consistent between both records
  const attesterConsistent = pkg.signer === onchainAttestation.attester;
  console.log('Attester consistent:', attesterConsistent);

  // Step 8: Confirm the data payload is identical between both records
  const dataConsistent = pkg.sig.message.data === onchainAttestation.data;
  console.log('Data payload consistent:', dataConsistent);
}
```

---

## Summary of What the Pattern Guarantees

```
Onchain attestation
  ├── data:    <full encoded payload>    ← stored on the EAS contract forever
  ├── refUID:  <offchain UID>            ← your link back to the original signed object
  ├── attester: <original signer>        ← who signed it
  └── schema:  <same schema UID>         ← no schema change required

Offchain package (your local store, keyed by offchain UID)
  ├── sig.uid:      == onchain.refUID    ← the link, verifiable by recomputing
  ├── sig.message:  == onchain.data      ← same data payload
  ├── sig.signature                      ← proof it was signed before submission
  └── signer:       == onchain.attester  ← same person
```

Your understanding is correct. **`refUID` is the right tool for this**, and the pattern you've described — "a non-zero `refUID` means this attestation originated offline" — is a sound application-level convention. The EAS contract faithfully stores and returns the `refUID`, the data payload is fully onchain, and you can independently verify the entire chain of custody using `Offchain.getOffchainUID()` + `verifyOffchainAttestationSignature()`.

---

To view the full sequence diagram illustrating this workflow, see the [visualization document](./visualize-offline-workflow.md).
