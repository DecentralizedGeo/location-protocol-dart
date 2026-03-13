# Procedural Memory

### Implementation Standards
- **TDD Rigor (Red-Green-Refactor)**: 
  - 1. Write failing test (ensure it fails for the right reason, e.g., Missing class or failing validation).
  - 2. Implement minimal code to pass.
  - 3. Refactor for Dart idiomatic patterns.
- **Dependency Management**:
  - Always verify `dart pub get` succeeds.
  - If SDK constraints conflict, downgrade library cautiously or request SDK upgrade.
- **KECCAK256 / Crypto**:
  - Use `QuickCrypto.keccack256Hash(Uint8List)` from `blockchain_utils` for pure Dart hashing.
  - Use `BytesUtils` for hex/Uint8List conversions.

### Pitfalls to Avoid
- **ABI Encoding Location**: Do not try to ABI encode a `Map` or `List` directly for the `location` field; serialize to a JSON string first.
- **Reserved Names**: User-defined fields must not collide with `lp_version`, `srs`, `location_type`, or `location`.
