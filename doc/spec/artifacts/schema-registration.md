**Yes, absolutely** — and this is a great question because it reveals something important: the EAS SDK is just a convenience wrapper. Everything it does ultimately reduces to a standard JSON-RPC call to an Ethereum node. As long as you have an RPC endpoint, you can interact with EAS contracts directly in any language or toolchain.

Here's the complete picture:

---

## What Schema Registration Actually Is

At its core, registering a schema is a single **write transaction** to the `SchemaRegistry` smart contract. Looking at what the SDK actually does under the hood in [`src/schema-registry.ts`](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/schema-registry.ts#L50-L62):

```typescript name=schema-registry.ts url=https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/schema-registry.ts#L44-L62
// The UID is just a keccak256 hash — computable locally before the tx is sent
public static getSchemaUID(schema: string, resolverAddress: string, revocable: boolean) {
  return solidityPackedKeccak256(['string', 'address', 'bool'], [schema, resolverAddress, revocable]);
}

// Registration = one contract call with three arguments
public async register({ schema, resolverAddress = ZERO_ADDRESS, revocable = true }) {
  await this.contract.register(schema, resolverAddress, revocable);
  // returns the UID computed above
}
```

That's it. Three inputs, one transaction, one deterministic UID back.

---

## The Three Inputs to a Schema Registration

| Input | Type | Description | Required? |
|---|---|---|---|
| `schema` | `string` | Human-readable field definitions, e.g. `"uint256 eventId, uint8 voteIndex"` | ✅ Yes |
| `resolverAddress` | `address` | Contract address that can add custom validation logic on attestation. Use the zero address (`0x0000...0000`) for no resolver | ✅ Yes (use zero address if none) |
| `revocable` | `bool` | Whether attestations made against this schema can be revoked later | ✅ Yes |

---

## How to Do It Without the SDK

Since it's just a contract call, you can register a schema from **any environment** that can:
1. Construct and sign an Ethereum transaction
2. Send it via JSON-RPC to a node

### The Contract ABI (what you need to call)

```json name=schema-registry-abi.json
[
  {
    "name": "register",
    "type": "function",
    "stateMutability": "nonpayable",
    "inputs": [
      { "name": "schema",          "type": "string"  },
      { "name": "resolver",        "type": "address" },
      { "name": "revocable",       "type": "bool"    }
    ],
    "outputs": [
      { "name": "",                "type": "bytes32" }
    ]
  },
  {
    "name": "getSchema",
    "type": "function",
    "stateMutability": "view",
    "inputs": [
      { "name": "uid",             "type": "bytes32" }
    ],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "components": [
          { "name": "uid",         "type": "bytes32" },
          { "name": "resolver",    "type": "address" },
          { "name": "revocable",   "type": "bool"    },
          { "name": "schema",      "type": "string"  }
        ]
      }
    ]
  }
]
```

### The SchemaRegistry Contract Addresses

| Network | Address |
|---|---|
| Ethereum Mainnet | `0xA7b39296258348C78294F95B872b282326A97BDF` |
| Sepolia (testnet) | `0x0a7E2Ff54e76B8E6659aedc9103FB21c038050D0` |
| Base | `0x4200000000000000000000000000000000000020` |
| Arbitrum One | `0xaEF4103A04090071165F78D45D2a05B39B1976051` |

> The full list of deployed contract addresses for all supported chains is maintained at [easscan.org](https://easscan.org) and in the [EAS contracts repository](https://github.com/ethereum-attestation-service/eas-contracts).

### Example: Raw JSON-RPC (language-agnostic)

This is literally what happens at the wire level when you register a schema:

```json name=register-schema-rpc.json
{
  "jsonrpc": "2.0",
  "method": "eth_sendRawTransaction",
  "params": ["0x<signed_transaction_hex>"],
  "id": 1
}
```

The signed transaction hex encodes:
- **`to`**: the `SchemaRegistry` contract address
- **`data`**: ABI-encoded call to `register(schema, resolverAddress, revocable)`
- **`from`** / **signature**: your wallet's address and ECDSA signature over the transaction

### Example: Python (no EAS SDK, just `web3.py`)

```python name=register_schema.py
from web3 import Web3

RPC_URL = "https://sepolia.infura.io/v3/YOUR_API_KEY"
SCHEMA_REGISTRY_ADDRESS = "0x0a7E2Ff54e76B8E6659aedc9103FB21c038050D0"
PRIVATE_KEY = "0xYOUR_PRIVATE_KEY"

w3 = Web3(Web3.HTTPProvider(RPC_URL))

abi = [
    {
        "name": "register",
        "type": "function",
        "stateMutability": "nonpayable",
        "inputs": [
            {"name": "schema",    "type": "string"},
            {"name": "resolver",  "type": "address"},
            {"name": "revocable", "type": "bool"}
        ],
        "outputs": [{"name": "", "type": "bytes32"}]
    }
]

contract = w3.eth.contract(
    address=Web3.to_checksum_address(SCHEMA_REGISTRY_ADDRESS),
    abi=abi
)

account = w3.eth.account.from_key(PRIVATE_KEY)

tx = contract.functions.register(
    "uint256 eventId, uint8 voteIndex",   # schema string
    "0x0000000000000000000000000000000000000000",  # no resolver
    True                                   # revocable
).build_transaction({
    "from":     account.address,
    "nonce":    w3.eth.get_transaction_count(account.address),
    "gas":      200000,
    "gasPrice": w3.eth.gas_price,
    "chainId":  11155111  # Sepolia
})

signed_tx = account.sign_transaction(tx)
tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)
receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

print(f"Schema registered in tx: {tx_hash.hex()}")
```

### Example: curl (bare JSON-RPC, truly no library)

```bash name=register-schema.sh
# Step 1: ABI-encode the call data offline using cast (from Foundry) or any ABI encoder
cast calldata "register(string,address,bool)" \
  "uint256 eventId, uint8 voteIndex" \
  "0x0000000000000000000000000000000000000000" \
  "true"

# Step 2: Build + sign the tx, then send via eth_sendRawTransaction
curl https://sepolia.infura.io/v3/YOUR_API_KEY \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "method":"eth_sendRawTransaction",
    "params":["0x<your_signed_tx_hex>"],
    "id":1
  }'
```

---

## Computing the Schema UID Locally (Before Sending)

You can also determine what the schema UID will be **before** broadcasting the transaction — useful for referencing the schema in attestations you're already building:

```
schemaUID = keccak256(abi.encodePacked(schemaString, resolverAddress, revocable))
```

In Python:
```python name=compute_schema_uid.py
from eth_abi.packed import encode_packed
from eth_utils import keccak

schema_uid = keccak(encode_packed(
    ['string', 'address', 'bool'],
    [
        "uint256 eventId, uint8 voteIndex",
        "0x0000000000000000000000000000000000000000",
        True
    ]
))
print(f"Schema UID: 0x{schema_uid.hex()}")
```

---

## Summary

| Question | Answer |
|---|---|
| Do you need the EAS TypeScript SDK to register a schema? | **No** — any language or tool that can sign and send an Ethereum transaction works |
| What do you actually need? | An RPC endpoint + a funded wallet (for gas) + the `SchemaRegistry` contract address for your target chain |
| Is the schema UID deterministic? | **Yes** — you can compute it locally from `keccak256(schema + resolverAddress + revocable)` before the transaction is sent |
| Does a schema need to be registered before creating attestations? | **Yes** — the EAS contract validates that the schema UID passed to `attest()` exists in the `SchemaRegistry` |
| Can the same schema be registered twice? | **No** — if the same combination of `schema + resolverAddress + revocable` already exists, the contract will revert |