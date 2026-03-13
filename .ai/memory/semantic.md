# Semantic Memory

### Core Abstractions
- **Location Protocol (LP)**: A standard for decentralized location data.
- **LP Base Fields**: `lp_version` (semver), `srs` (CRS URI), `location_type` (format), `location` (actual data).
- **SchemaDefinition**: A composer that takes user-defined business fields and auto-prepends the 4 LP base fields to ensure EAS compliance.
- **SchemaUID**: A deterministic 32-byte identifier for an EAS schema, computed from the schema string, resolver address, and revocable flag.

### Quirks & Mappings
- **Location Field flexibility**: The `location` field in Dart can be `String`, `List`, or `Map`. The library serializes it to a JSON string for ABI encoding if it's a `List` or `Map`.
- **Snake Case**: LP fields MUST be `snake_case` in the EAS schema string to match the spec, even though Dart uses `camelCase` for class members.
