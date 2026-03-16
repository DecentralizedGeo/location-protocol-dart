# Environment configuration reference

This page documents the environment variables used by `location_protocol` for onchain operations. All offchain operations (`OffchainSigner`, `LPPayload`, `SchemaDefinition`) require zero environment configuration.

---

## When environment configuration is required

`DefaultRpcProvider` requires an RPC URL, a private key, and a chain ID at construction time. `EASClient` and `SchemaRegistryClient` use environment configuration only when constructed with a `DefaultRpcProvider`. Classes that operate entirely in memory — `LPPayload`, `SchemaDefinition`, `SchemaField`, `SchemaUID`, `OffchainSigner` (which takes a private key as a constructor argument), `LocationValidator`, `LocationSerializer`, and all model classes — require no environment configuration.

| Needs env config | Does NOT need env config |
|---|---|
| `DefaultRpcProvider` | `LPPayload`, `SchemaDefinition`, `SchemaField`, `SchemaUID` |
| `EASClient` (when using `DefaultRpcProvider`) | `OffchainSigner` |
| `SchemaRegistryClient` (when using `DefaultRpcProvider`) | `LocationValidator`, `LocationSerializer` |
| | `SignedOffchainAttestation`, `VerificationResult`, all model classes |

---

## Environment variables reference

These are the variable names used by the test suite and scripts in this repository. The `DefaultRpcProvider`, `EASClient`, and `SchemaRegistryClient` constructors accept these values as **Dart constructor parameters** — you can source them from `.env`, environment variables, a config file, secure storage, or any other mechanism.

| Variable | Type | Required | Description |
|---|---|---|---|
| `SEPOLIA_RPC_URL` | URL string | Yes (for onchain) | JSON-RPC endpoint URL for the Sepolia testnet. Any EIP-1193-compatible provider works: Alchemy, Infura, QuickNode, or public endpoints. Example: `https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY` |
| `SEPOLIA_PRIVATE_KEY` | `0x`-prefixed hex string, 66 chars total | Yes (for onchain) | Private key of the Ethereum account that will sign and pay gas for transactions. As used by the bootstrap scripts and test helpers, the value must start with `0x` followed by 64 hex characters (66 chars total). Example: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`. The corresponding address must hold ETH on the target chain. **Note:** `DefaultRpcProvider(privateKeyHex:)` accepts either the `0x`-prefixed or raw 64-char form — the underlying `on_chain` library normalizes both. |
| `SEPOLIA_EXISTING_SCHEMA_UID` | `0x`-prefixed 66-char hex | For integration tests | A previously registered schema UID on Sepolia used by the recurring integration test suite. Populated once via `scripts/sepolia_schema_bootstrap.dart`. |

> **Note:** There is no environment-variable mechanism for overriding EAS or Schema Registry contract addresses. Contract addresses are resolved from `ChainConfig.forChainId(chainId)`, where `chainId` is a constructor parameter to `DefaultRpcProvider`. To use a custom chain or unsupported testnet, construct `EASClient` and `SchemaRegistryClient` directly with explicit contract addresses.

---

## `.env` file format

A `.env` file is the recommended local development approach. Copy `.env.example` to `.env` at the project root and fill in your values.

The `scripts/sepolia_schema_bootstrap.dart` script reads `.env` and falls back to `Platform.environment`. The test helper `test/test_helpers/dotenv_loader.dart` reads `.env` only — it does not fall back to `Platform.environment`.

Example `.env` file:

```dotenv
# Sepolia RPC endpoint (Infura or Alchemy)
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY

# Test wallet private key (0x-prefixed, 66 chars total)
SEPOLIA_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Schema UID from one-time bootstrap (see scripts/sepolia_schema_bootstrap.dart)
SEPOLIA_EXISTING_SCHEMA_UID=0x...
```

See [`.env.example`](../../.env.example) for the full template with all optional fields.

---

## Security considerations

- **Never commit `.env` to source control.** The repo `.gitignore` includes `.env`. Verify this before adding credentials.
- **Use a dedicated test account.** The private key holder pays gas. Use a throwaway account funded with testnet ETH for development and testing. Never reuse mainnet keys.
- **Use a secrets manager in CI.** Set `SEPOLIA_RPC_URL` and `SEPOLIA_PRIVATE_KEY` as repository secrets (GitHub Actions: `${{ secrets.SEPOLIA_RPC_URL }}`) — do not embed them in workflow YAML.
- **`SEPOLIA_PRIVATE_KEY` in `.env` must be `0x`-prefixed (66 chars total).** The bootstrap script validates that the value starts with `0x` followed by 64 hex characters. The `DefaultRpcProvider(privateKeyHex:)` constructor parameter is more permissive — it accepts either the `0x`-prefixed or a raw 64-char hex string, because the underlying `on_chain` library normalizes both formats.
- **RPC provider rate limits apply.** Public endpoints are suitable for development but not for production load. Consider Alchemy or Infura for sustained usage.

---

## Integration test configuration

The repo has tests tagged `sepolia` that require a live RPC connection, a funded wallet, and a previously bootstrapped schema UID:

```sh
dart test --tags sepolia
```

These tests **skip automatically** if `SEPOLIA_RPC_URL`, `SEPOLIA_PRIVATE_KEY`, or `SEPOLIA_EXISTING_SCHEMA_UID` is absent — they do not fail. The `test/test_helpers/dotenv_loader.dart` helper loads `.env` from the project root.

Tests not tagged `sepolia` run entirely offline and require no environment configuration:

```sh
dart test --exclude-tags sepolia
```

**One-time setup** (to obtain `SEPOLIA_EXISTING_SCHEMA_UID`):

```sh
dart run scripts/sepolia_schema_bootstrap.dart
```

Copy the emitted `SEPOLIA_EXISTING_SCHEMA_UID=0x...` value into your `.env` file. After that, the value is stable and reused across all test runs.

---

## Chain selection

Chain is selected by passing `chainId` to `DefaultRpcProvider` as a constructor parameter — not an environment variable:

```dart
final provider = DefaultRpcProvider(
  rpcUrl: rpcUrl,
  privateKeyHex: privateKey,
  chainId: 11155111, // Sepolia
);
```

The `chainId` controls which EAS contract addresses are used, resolved via `ChainConfig.forChainId(chainId)`.

**Supported chain IDs:**

_Mainnets_

| Chain ID | Network | EAS Version |
|---|---|---|
| `1` | Ethereum Mainnet | v0.26 |
| `10` | Optimism | v1.0.1 |
| `40` | Telos | v1.4.0 |
| `130` | Unichain | v1.4.1-beta.1 |
| `137` | Polygon | v1.3.0 |
| `1868` | Soneium | v1.4.1-beta.1 |
| `8453` | Base | v1.0.1 |
| `42161` | Arbitrum One | v0.26 |
| `42170` | Arbitrum Nova | v1.3.0 |
| `42220` | Celo | v1.3.0 |
| `57073` | Ink | v1.4.1-beta.1 |
| `59144` | Linea | v1.2.0 |
| `81457` | Blast | v1.3.0 |
| `534352` | Scroll | v1.3.0 |

_Testnets_

| Chain ID | Network | EAS Version |
|---|---|---|
| `11155111` | Sepolia | v0.26 |
| `11155420` | Optimism Sepolia | v1.0.2 |
| `80002` | Polygon Amoy | v1.3.0 |
| `84532` | Base Sepolia | v1.2.0 |
| `421614` | Arbitrum Sepolia | v1.3.0 |
| `534351` | Scroll Sepolia | v1.3.0 |
| `763373` | Ink Sepolia | v1.4.1-beta.1 |

> **Note:** Deprecated Goerli-based testnets (Optimism Goerli `420`, Base Goerli `84531`, Linea Goerli `59140`) are intentionally excluded — Goerli was shut down in 2023. zkSync Era (`324`) is also excluded pending verification of EIP-1559 transaction format support in the `on_chain` Dart package.

---

## See also

- [How to register and attest onchain](how-to-register-and-attest-onchain.md)
- [CONTRIBUTING.md](../../CONTRIBUTING.md)
