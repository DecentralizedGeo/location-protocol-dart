import 'dart:convert';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';

import 'schema_definition.dart';

/// Computes deterministic schema UIDs matching the EAS SchemaRegistry.
///
/// Formula: `keccak256(abi.encodePacked(schemaString, resolverAddress, revocable))`
///
/// Reference: [EAS SDK schema-registry.ts](https://github.com/ethereum-attestation-service/eas-sdk/blob/896eea3362c6ab647097fcd601d19c6cfc4d8675/src/schema-registry.ts#L50-L54)
class SchemaUID {
  /// Computes the deterministic UID for a [SchemaDefinition].
  ///
  /// Returns a `0x`-prefixed 64-character hex string (32 bytes).
  static String compute(SchemaDefinition schema) {
    final schemaString = schema.toEASSchemaString();
    final resolverAddress = schema.resolverAddress;
    final revocable = schema.revocable;

    // Build packed encoding:
    // - schema string as UTF-8 bytes (no padding)
    // - resolver address as 20 bytes (no padding)
    // - revocable as 1 byte (0x01 or 0x00)
    final schemaBytes = utf8.encode(schemaString);

    // Parse address: strip 0x prefix, decode 20 hex bytes
    final addrHex = resolverAddress.startsWith('0x')
        ? resolverAddress.substring(2)
        : resolverAddress;
    final addrBytes = BytesUtils.fromHexString(addrHex);

    final revocableByte = revocable ? 1 : 0;

    // Concatenate packed: schema + address + revocable
    final packed = Uint8List(schemaBytes.length + addrBytes.length + 1);
    packed.setAll(0, schemaBytes);
    packed.setAll(schemaBytes.length, addrBytes);
    packed[packed.length - 1] = revocableByte;

    // keccak256 hash
    final hash = QuickCrypto.keccack256Hash(packed);
    return '0x${BytesUtils.toHexString(hash)}';
  }
}
