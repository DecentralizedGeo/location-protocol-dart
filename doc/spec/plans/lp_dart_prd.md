# `location_protocol` — Dart Library Design

> **Repo:** `DecentralizedGeo/location-protocol-dart`
> **Package:** `location_protocol` (pub.dev)
> **Core Dependency:** `on_chain ^8.0.0` (pure Dart — no Flutter dependency)

## Goal

A **schema-agnostic** Dart library that implements the [Location Protocol](https://spec.decentralizedgeo.org/specification/data-model/) base data model on top of the [Ethereum Attestation Service](https://docs.attest.org/) (EAS). Users define their own business-specific schemas; the library automatically injects LP-required fields, handles all EAS crypto, and manages schema registration.

---

## Core Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Schema model | **LP base model only** (not Astral SDK schema) | Schema-agnostic — users compose their own schemas, LP fields auto-prepended |
| Schema composition | **Library owns LP fields, user owns business fields** | LP compliance guaranteed by construction; user never manually adds `lp_version`, `srs`, `location_type`, `location` |
| Architecture | **Separated layers** — LP payload validation independent of ABI encoding | Clean separation, no magic mapping |
| Package type | **Pure Dart** — no Flutter dependency | Works in CLI, servers, and Flutter apps |
| Core dependency | **`on_chain`** (replaces `web3dart`) | Built-in EIP-712 v1/v3/v4, EIP-1559, typed schema classes, contract interaction, JSON-RPC |
| EIP-712 | **`on_chain` built-in** | Typed EIP-712 classes allow schema definitions to extend base EIP712 class, eliminating manual type hash construction |
| Field naming | **`snake_case`** per LP spec | LP fields: `lp_version`, `srs`, `location_type`, `location` |

### Why `on_chain` over `web3dart`

| Capability | `web3dart` | `on_chain` |
|---|---|---|
| EIP-712 typed data signing | ❌ Manual | ✅ Built-in v1/v3/v4 |
| EIP-1559 transactions | ❌ | ✅ Native |
| ABI encoding | ✅ | ✅ (more strictly typed) |
| Contract interaction | ✅ | ✅ |
| Typed schema classes | ❌ | ✅ (`extend` base EIP712 class) |
| EIP-712 verification | ❌ Manual hash reconstruction | ✅ Built-in `verifyEIP712` |
| Maintenance | ⚠️ Inconsistent | ✅ Active (v8.0.0) |

`on_chain` is superior for EAS-heavy applications where multiple schema types are signed. Schema definitions can be Dart classes extending a base EIP712 class, keeping code clean and type-safe.

---

## MVP Scope

### ✅ In Scope

| Capability | Network? | Notes |
|---|---|---|
| **LP payload creation + validation** | ❌ | 4 base fields, semver + URI + non-empty checks |
| **Location serialization** (convert → serialize) | ❌ | `String`/`List<num>`/`Map<String,dynamic>` → ABI string |
| **Schema definition** (user fields + LP auto-prepend) | ❌ | Field name conflict detection against LP fields |
| **Schema UID computation** (deterministic) | ❌ | `keccak256(abi.encodePacked(schema, resolver, revocable))` |
| **ABI encoding** (schema-aware) | ❌ | |
| **EIP-712 signing** (offchain attestations) | ❌ | Version 2 with salt |
| **Offchain UID derivation** | ❌ | Includes CSPRNG salt + ZERO_ADDRESS placeholder |
| **Offchain attestation verification** | ❌ | Signature recovery + UID recompute |
| **Offchain attestation serialization** | ❌ | BigInt-safe JSON |
| **Schema registration** (`SchemaRegistry.register()`) | ✅ RPC | |
| **Onchain attestation** (`EAS.attest()`) | ✅ RPC | |
| **Timestamp offchain UID** (`EAS.timestamp()`) | ✅ RPC | |

### ❌ Phase 2

- Full location type validation (GeoJSON structure per RFC 7946, H3 regex, etc.)
- Location/spatial module with format-specific helpers
- JSON Schema (Draft 07) based validation using [official LP schema](https://raw.githubusercontent.com/DecentralizedGeo/location-protocol-spec/refs/heads/main/json-schema/schema.json)
- Delegated attestation (`attestByDelegation()`)
- Batch operations (`multiAttest()`, `multiTimestamp()`)
- Revocation
- Schema resolver contracts
- `web3_signers` integration for hardware-backed signing (Secure Enclave, passkeys)

---

## EAS Protocol Constants

Derived from [EAS SDK source](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/utils.ts#L4-L6):

```dart
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const ZERO_BYTES32 = '0x0000000000000000000000000000000000000000000000000000000000000000';
const SALT_SIZE = 32; // bytes, CSPRNG
```

### Offchain Attestation Version 2

**EIP-712 Attest type** ([source](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain.ts#L97-L112)):
```
Attest(uint16 version, bytes32 schema, address recipient, uint64 time, uint64 expirationTime, bool revocable, bytes32 refUID, bytes data, bytes32 salt)
```

**Domain separator** ([source](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain.ts#L150-L160)):
```
keccak256(abi.encode(
  keccak256("EAS Attestation"),
  keccak256(contractVersion),
  chainId,
  easContractAddress
))
```

**Salt generation** ([source](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain.ts#L201-L203)):
```dart
// Dart equivalent using CSPRNG
final salt = Uint8List(32);
final random = Random.secure();
for (var i = 0; i < 32; i++) { salt[i] = random.nextInt(256); }
```

**Offchain UID derivation (Version 2)** ([source](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/offchain/offchain.ts#L253-L270)):
```
solidityPackedKeccak256(
  ['uint16','bytes','address','address','uint64','uint64','bool','bytes32','bytes','bytes32','uint32'],
  [version, schema, recipient, ZERO_ADDRESS, time, expirationTime, revocable, refUID, data, salt, 0]
)
```

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                  location_protocol                    │
├──────────────────────────────────────────────────────┤
│                                                      │
│  ┌─────────────┐    ┌──────────────────────────────┐ │
│  │  LP Payload  │    │       Schema Layer           │ │
│  │  Validation  │    │  ┌────────────────────────┐  │ │
│  │              │    │  │  SchemaDefinition       │  │ │
│  │ • lp_version │    │  │  (user business fields) │  │ │
│  │ • srs        │    │  └────────────────────────┘  │ │
│  │ • loc_type   │    │  ┌────────────────────────┐  │ │
│  │ • location   │    │  │  LP field auto-prepend  │  │ │
│  └──────┬───────┘    │  │  + conflict detection   │  │ │
│         │            │  └────────────────────────┘  │ │
│         │            │  ┌────────────────────────┐  │ │
│         │            │  │  Schema UID computation │  │ │
│  ┌──────┴───────┐    │  └────────────────────────┘  │ │
│  │  Location    │    └──────────────┬───────────────┘ │
│  │  Serializer  │                   │                 │
│  │              │                   │                 │
│  │ String  → ✓  │                   │                 │
│  │ List    → ✓  │                   │                 │
│  │ Map     → ✓  │                   │                 │
│  └──────┬───────┘                   │                 │
│         │                           │                 │
│         ▼                           ▼                 │
│  ┌─────────────────────────────────────────────────┐  │
│  │              ABI Encoder                         │  │
│  │  LP payload + user data → encoded bytes          │  │
│  └──────────────────────┬──────────────────────────┘  │
│                          │                             │
│         ┌────────────────┼────────────────┐            │
│         ▼                ▼                ▼            │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Offchain    │  │   Onchain    │  │   Schema     │  │
│  │  Signer      │  │   Client     │  │   Registry   │  │
│  │              │  │              │  │              │  │
│  │ • EIP-712 v2 │  │ • attest()   │  │ • register() │  │
│  │ • sign       │  │ • timestamp()│  │ • getSchema()│  │
│  │ • verify     │  │              │  │ • computeUID │  │
│  │ • serialize  │  │  (EIP-1559)  │  │              │  │
│  │ • CSPRNG salt│  │  (needs RPC) │  │  (needs RPC) │  │
│  │ (no RPC)     │  │              │  │              │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                        │
│  ┌─────────────────────────────────────────────────┐   │
│  │           Chain Config                           │   │
│  │  EAS + SchemaRegistry addresses per chain        │   │
│  └─────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────┘
```

---

## Key Components

### 1. LP Payload (`lib/src/lp/`)

The Location Protocol base data model — 4 required fields with validation.

```dart
class LPPayload {
  final String lpVersion;      // semver "major.minor.patch"
  final String srs;            // URI, e.g. "http://www.opengis.net/def/crs/OGC/1.3/CRS84"
  final String locationType;   // e.g. "geojson-point" (non-empty)
  final dynamic location;      // String | List<num> | Map<String, dynamic>
}
```

**MVP validation** (hand-coded, fast):
- `lp_version` — matches `^\d+\.\d+\.\d+$`
- `srs` — valid URI format
- `location_type` — non-empty string
- `location` — present and non-null

> [!NOTE]
> The [official LP JSON Schema (Draft 07)](https://raw.githubusercontent.com/DecentralizedGeo/location-protocol-spec/refs/heads/main/json-schema/schema.json) is bundled as a reference asset in `lib/src/lp/schema/` and used in tests to cross-validate our hand-coded logic. Full JSON Schema validation is Phase 2.

### 2. Location Serializer (`lib/src/lp/`)

Converts flexible Dart types to ABI-compatible strings. **No validation** in MVP — just convert → serialize.

```dart
class LocationSerializer {
  /// Normalizes any location value to a String for ABI encoding.
  static String serialize(dynamic location) {
    if (location is String) return location;
    if (location is List || location is Map) return jsonEncode(location);
    throw ArgumentError('Unsupported location type: ${location.runtimeType}');
  }
}
```

### 3. Schema Layer (`lib/src/schema/`)

User-defined schema + automatic LP field injection + conflict detection.

```dart
final schema = SchemaDefinition(
  fields: [
    SchemaField(type: 'uint256', name: 'timestamp'),
    SchemaField(type: 'string', name: 'memo'),
  ],
  revocable: true,
);

// Library auto-prepends LP fields:
// "string lp_version,string srs,string location_type,string location,uint256 timestamp,string memo"
final easSchemaString = schema.toEASSchemaString();

// Throws if user fields collide with LP reserved names
// SchemaDefinition(['location_type', ...]) → Error!

// Deterministic UID (local, no RPC)
final schemaUID = schema.computeUID();
```

### 4. ABI Encoder (`lib/src/eas/`)

Schema-aware encoder merging LP payload + user data into ABI-encoded bytes.

```dart
final encodedData = abiEncoder.encode(
  schema: schema,
  lpPayload: lpPayload,
  userData: {
    'timestamp': BigInt.from(1710000000),
    'memo': 'Field survey checkpoint',
  },
);
```

### 5. Offchain Signer (`lib/src/eas/`)

EIP-712 typed data signing using `on_chain`'s built-in EIP-712 infrastructure. No RPC needed.

```dart
final signer = OffchainSigner(privateKey: key, chainId: 11155111);

// Sign — generates CSPRNG salt, constructs EIP-712 typed data, signs
final signed = await signer.signOffchainAttestation(
  schema: schema,
  lpPayload: lpPayload,
  userData: {'timestamp': BigInt.from(1710000000)},
);
// Returns SignedOffchainAttestation with uid, signature, domain, message, salt

// Verify — recovers signer address, recomputes UID
final result = signer.verifyOffchainAttestation(signed);
// Returns VerificationResult { isValid, recoveredAddress, reason? }
```

### 6. Onchain Client (`lib/src/eas/`)

JSON-RPC interactions with EAS & SchemaRegistry. Uses `on_chain`'s EIP-1559 support.

```dart
final client = EASClient(rpcUrl: 'https://rpc.sepolia.org', privateKey: key, chainId: 11155111);

await client.registerSchema(schema);                    // SchemaRegistry.register()
final uid = await client.attest(schema: schema, ...);   // EAS.attest()
await client.timestamp(offchainUID);                     // EAS.timestamp()
```

### 7. Chain Config (`lib/src/config/`)

```dart
class ChainConfig {
  static const chains = {
    11155111: ChainAddresses(  // Sepolia
      eas: '0xC2679fBD37d54388Ce493F1DB75320D236e1815e',
      schemaRegistry: '0x0a7E2Ff54e76B8E6659aedc9103FB21c038050D0',
    ),
    // Extensible — users can add custom chains
  };
}
```

---

## Package Structure

```
location-protocol-dart/
├── lib/
│   ├── location_protocol.dart              # barrel export
│   └── src/
│       ├── lp/
│       │   ├── lp_payload.dart             # LP base model + validation
│       │   ├── lp_version.dart             # version constants
│       │   ├── location_serializer.dart    # convert → serialize
│       │   └── schema/
│       │       └── lp_payload_schema.json  # official LP JSON Schema (bundled ref)
│       ├── schema/
│       │   ├── schema_definition.dart      # user schema + LP auto-prepend + conflict check
│       │   ├── schema_field.dart           # individual field type/name
│       │   └── schema_uid.dart             # deterministic UID computation
│       ├── eas/
│       │   ├── constants.dart              # ZERO_ADDRESS, ZERO_BYTES32, SALT_SIZE
│       │   ├── abi_encoder.dart            # schema-aware ABI encoding
│       │   ├── offchain_signer.dart        # EIP-712 sign + verify + salt
│       │   ├── onchain_client.dart         # EAS contract interactions (RPC)
│       │   └── schema_registry.dart        # SchemaRegistry contract (RPC)
│       ├── config/
│       │   └── chain_config.dart           # contract addresses per chain
│       └── models/
│           ├── attestation.dart            # signed/unsigned attestation types
│           ├── signature.dart              # EIP-712 signature (v, r, s)
│           └── verification_result.dart
├── test/
│   ├── lp/
│   │   ├── lp_payload_test.dart
│   │   └── location_serializer_test.dart
│   ├── schema/
│   │   ├── schema_definition_test.dart
│   │   └── schema_uid_test.dart
│   ├── eas/
│   │   ├── abi_encoder_test.dart
│   │   ├── offchain_signer_test.dart
│   │   └── constants_test.dart
│   └── integration/
│       └── full_workflow_test.dart
├── pubspec.yaml
├── README.md
├── LICENSE
└── analysis_options.yaml
```

---

## Usage Example (End-to-End)

```dart
import 'package:location_protocol/location_protocol.dart';

// 1. Define your business schema (LP fields auto-prepended)
final schema = SchemaDefinition(
  fields: [
    SchemaField(type: 'uint256', name: 'timestamp'),
    SchemaField(type: 'string', name: 'surveyor_id'),
    SchemaField(type: 'string', name: 'memo'),
  ],
);
// EAS schema: "string lp_version,string srs,string location_type,string location,uint256 timestamp,string surveyor_id,string memo"

// 2. Create an LP-compliant payload
final lpPayload = LPPayload(
  lpVersion: '1.0.0',
  srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
  locationType: 'geojson-point',
  location: {'type': 'Point', 'coordinates': [-103.771556, 44.967243]},
  // Accepts Map — library serializes to string for ABI encoding
);

// 3. Sign offchain (no network needed)
final signer = OffchainSigner(privateKey: myKey, chainId: 11155111);
final signed = await signer.signOffchainAttestation(
  schema: schema,
  lpPayload: lpPayload,
  userData: {
    'timestamp': BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    'surveyor_id': 'surveyor-42',
    'memo': 'Boundary marker GPS reading',
  },
);

// 4. Verify locally
final verification = signer.verifyOffchainAttestation(signed);
assert(verification.isValid);

// 5. When online — register schema + submit onchain
final client = EASClient(rpcUrl: rpcUrl, privateKey: myKey, chainId: 11155111);
await client.registerSchema(schema);
await client.attest(schema: schema, lpPayload: lpPayload, userData: {...});
// Or just timestamp the offchain UID:
await client.timestamp(signed.uid);
```
