[![pub.dev](https://img.shields.io/pub/v/location_protocol.svg)](https://pub.dev/packages/location_protocol)
[![Dart SDK](https://img.shields.io/badge/Dart-%E2%89%A53.11-blue)](https://dart.dev)
[![License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)
[![CI](https://img.shields.io/badge/CI-passing-brightgreen)](https://github.com/DecentralizedGeo/location-protocol-dart/actions)

> Dart library for building cryptographically verifiable, Location Protocol compliant records on top of your own data model.

---

## Contents

- [Contents](#contents)
- [Description](#description)
- [Library targets](#library-targets)
- [Features](#features)
- [How It Works](#how-it-works)
  - [Location validation](#location-validation)
  - [Location Protocol payloads](#location-protocol-payloads)
  - [Schema composition](#schema-composition)
  - [Offchain vs onchain](#offchain-vs-onchain)
- [Supported Chains](#supported-chains)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [Help \& Contributing](#help--contributing)
- [License](#license)

## Description

`location_protocol` is a Dart implementation of the [Location Protocol](https://spec.decentralizedgeo.org/introduction/overview/), a standard for producing self-contained, cryptographically signed units of spatial data that extend your own data model. Location records can be signed offchain as EIP‑712 typed data or anchored on-chain through [EAS](https://docs.attest.org/docs/core--concepts/how-eas-works).

This is the Dart equivalent of the signature service layer in the [Astral SDK](https://github.com/DecentralizedGeo/astral-sdk), adapted for mobile and multi‑platform deployments.

---

## Library targets

This library is built with **Pure Dart** (no Flutter dependency). It is tested across all major compilation targets:

| Target | Status | Note |
| --- | --- | --- |
| **Android / iOS** | ✅ | Works in Flutter apps and CLI |
| **Windows / macOS / Linux** | ✅ | Native desktop and server-side |
| **Web (JS / Wasm)** | ✅ | Browser-compatible (via `blockchain_utils`) |
| **Server / CLI** | ✅ | Works in any Dart runtime |

---

## Features

- **LP payload creation and validation** — enforces the 4 base fields (`lp_version`, `srs`, `location_type`, `location`) on construction; location values are validated against canonical formats *before* any signing step
- **9 canonical location type validators** — GeoJSON geometries (`geojson-point`, `geojson-line`, `geojson-polygon`), H3, geohash, WKT, address, coordinate-decimal, and scaled coordinates
- **Extend your own data model** — define your business-specific fields; LP base fields are auto-prepended, producing LP-compliant records without restructuring your existing schema
- **Deterministic schema UID computation** — matches the on-chain EAS Schema Registry result (`keccak256(schemaString, resolverAddress, revocable)`)
- **ABI encoding of LP payload + user schema data** — produces the exact byte layout expected by EAS contracts
- **EIP-712 Version 2 offchain signing and verification** — CSPRNG salt, no RPC needed; fully portable, cryptographically verifiable attestations
- **Onchain schema registration, attestation, and offchain UID timestamping** — via EIP-1559 transactions through `EASClient` and `SchemaRegistryClient`
- **Extensible custom location type registration** — add your own validators via `LocationValidator.register()`

---

## How It Works

### Location validation

Every `LPPayload` validates its `location` value against the declared `location_type` at construction time. Invalid coordinates are caught before signing — not silently embedded in a record. Custom validators can be registered via `LocationValidator.register()` for domain-specific constraints.

### Location Protocol payloads

Every attestation carries 4 required LP base fields — `lp_version`, `srs`, `location_type`, and `location` — as defined by the [LP base data model spec](https://spec.decentralizedgeo.org/specification/data-model/). `LPPayload` enforces these on construction and serializes location values via `LocationSerializer` before ABI encoding.

### Schema composition

Define your business-specific fields as `SchemaField` objects. `SchemaDefinition` automatically prepends the 4 LP base fields, producing a fully LP-compliant EAS schema string. You extend your data model — you don't replace it. Schema UIDs are computed locally via `SchemaUID.computeSchemaUID(...)` without any RPC calls.

### Offchain vs onchain

Offchain attestations are [EIP-712](https://eips.ethereum.org/EIPS/eip-712) typed data structures, signed locally.  They are gas-free, cryptographically verifiable by any wallet or the EAS SDK, and their authenticity is derived from the digital signature.

Onchain attestations are submitted to the EAS contract.  This contract acts as the enforcement layer, validating the data against a schema from the [Schema Registry contract](https://docs.attest.org/docs/core--concepts/schemas#how-schemas-are-made) and executing any custom logic defined in an attached [Resolver contract](https://docs.attest.org/docs/core--concepts/resolver-contracts) before permanently storing the attestation on the blockchain.

A hybrid approach that combines the benefits of both offchain (no gas, instant, portable) and onchain (immutable, discoverable) is to sign offchain and then submit an onchain attestation. This onchain transaction [records the current block timestamp](https://docs.attest.org/docs/tutorials/timestamping-attestations), providing an immutable, verifiable proof that the attestation (and its data) existed at least by that time.

---

## Supported Chains

21 networks are supported out of the box — 14 mainnets and 7 testnets. See the full list with chain IDs and contract addresses in the [Environment configuration reference](doc/guides/reference-environment.md#chain-selection).

Addresses are sourced from `ChainConfig` and match the [official EAS deployment registry](https://github.com/ethereum-attestation-service/eas-contracts/).

---

## Installation

```yaml
dependencies:
  location_protocol: ^0.1.0
```

Then run:

```sh
dart pub get
```

---

## Quick Start

See the [example/main.dart](example/main.dart) for a complete, runnable demonstration.

> **Security:** Never hard-code a real private key. Use environment variables or a secrets manager in production. See [Environment configuration](docs/guides/reference-environment.md).

```dart
import 'package:location_protocol/location_protocol.dart';

Future<void> main() async {
  // 1. Define a schema with business-specific fields.
  //    LP base fields (lp_version, srs, location_type, location) are prepended automatically.
  final schema = SchemaDefinition(fields: [
    SchemaField(type: 'uint256', name: 'observedAt'),
    SchemaField(type: 'string', name: 'memo'),
    SchemaField(type: 'address', name: 'observer'),
  ]);

  // Print the full EAS schema string (LP fields + your fields)
  print(schema.toEASSchemaString());
  // => string lp_version,string srs,string location_type,string location,uint256 observedAt,string memo,address observer

  // 2. Create an LP payload with a GeoJSON point location.
  final payload = LPPayload(
    lpVersion: '0.1.0',
    srs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84',
    locationType: 'geojson-point',
    location: {'type': 'Point', 'coordinates': [-122.4194, 37.7749]},
  );

  // 3. Create an OffchainSigner targeting Sepolia.
  //    Replace with a real private key; never commit secrets.
  const privateKeyHex = 'YOUR_PRIVATE_KEY_HEX'; // 64 hex chars, no 0x prefix
  final addresses = ChainConfig.forChainId(11155111)!; // Sepolia

  final signer = OffchainSigner.fromPrivateKey(
    privateKeyHex: privateKeyHex,
    chainId: 11155111,
    easContractAddress: addresses.eas,
  );

  // 4. Sign the attestation offchain (EIP-712 typed data, no RPC needed).
  final signed = await signer.signOffchainAttestation(
    schema: schema,
    lpPayload: payload,
    userData: {
      'observedAt': BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      'memo': 'Rooftop sensor reading',
      'observer': signer.signerAddress,
    },
  );

  print('UID: ${signed.uid}');
  print('Signer: ${signed.signer}');

  // 5. Verify the signed attestation locally.
  final result = signer.verifyOffchainAttestation(signed);
  assert(result.isValid, 'Attestation verification failed: ${result.reason}');
  print('Valid: ${result.isValid}');
  print('Recovered address: ${result.recoveredAddress}');

  // 6. Optional: timestamp the offchain UID on-chain for immutable anchoring.
  //
  // final rpc = DefaultRpcProvider(
  //   rpcUrl: 'https://sepolia.infura.io/v3/YOUR_KEY',
  //   privateKeyHex: privateKeyHex,
  //   chainId: 11155111,
  // );
  // final client = EASClient(provider: rpc);
  // final timestampResult = await client.timestamp(signed.uid);
  // print('Timestamped in tx: ${timestampResult.txHash}');
}
```

---

## Architecture

```mermaid
flowchart TD
  subgraph "No RPC Required"
    SK["Signer (abstract)"]
    LKS["LocalKeySigner"]
    LP["LPPayload"]
    SD["SchemaDefinition"]
    AE["AbiEncoder"]
    OS["OffchainSigner"]
    LKS -->|implements| SK
    SK --> OS
    LP --> AE
    SD --> AE
    AE --> OS
    OS -->|"EIP-712 sign/verify"| SOA["SignedOffchainAttestation"]
  end

  subgraph "RPC Required"
    EC["EASClient"]
    SR["SchemaRegistryClient"]
    TU["TxUtils"]
    AE --> EC
    AE --> SR
    EC -->|"attest()"| AR["AttestResult"]
    EC -->|"timestamp()"| TR["TimestampResult"]
    TU -->|"buildTxRequest()"| WR["WalletTxRequest"]
    SR -->|"register() (EIP-1559)"| RR["RegisterResult"]
  end
```

---

## Documentation

- [Getting started tutorial](doc/guides/tutorial-first-attestation.md)
- [Tutorial: Sign with a wallet signer](doc/guides/tutorial-wallet-signer.md)
- [How to register and attest onchain](doc/guides/how-to-register-and-attest-onchain.md)
- [How to build a wallet-based onchain transaction](doc/guides/how-to-wallet-onchain-transactions.md)
- [How to add a custom location type](doc/guides/how-to-add-custom-location-type.md)
- [Environment configuration reference](doc/guides/reference-environment.md)
- [API reference](doc/guides/reference-api.md)
- [Concepts and design](doc/guides/explanation-concepts.md)

---

## Help & Contributing

- **Found a bug?** Open an [issue](https://github.com/DecentralizedGeo/location-protocol-dart/issues).
- **Want to contribute?** See [CONTRIBUTING.md](CONTRIBUTING.md).
- **Need help?** Check the [Documentation](#documentation) or start a discussion in the repository.

---

## License

BSD 3-Clause © DecentralizedGeo contributors. See [LICENSE](LICENSE) for details.
