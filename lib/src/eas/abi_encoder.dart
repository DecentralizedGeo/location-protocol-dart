import 'dart:typed_data';

import 'package:on_chain/on_chain.dart';

import '../lp/lp_payload.dart';
import '../lp/location_serializer.dart';
import '../schema/schema_definition.dart';
import '../utils/hex_utils.dart';

/// Schema-aware ABI encoder for Location Protocol attestations.
///
/// Merges LP payload fields and user-defined business data into
/// ABI-encoded bytes matching the combined EAS schema.
class AbiEncoder {
  /// Encodes LP payload + user data according to the schema.
  ///
  /// The encoding order matches [SchemaDefinition.allFields]:
  /// LP fields first (lp_version, srs, location_type, location),
  /// then user fields in declaration order.
  ///
  /// The [lpPayload.location] is serialized to a string via
  /// [LocationSerializer] before encoding.
  ///
  /// Throws [ArgumentError] if [userData] keys don't match schema fields.
  static Uint8List encode({
    required SchemaDefinition schema,
    required LPPayload lpPayload,
    required Map<String, dynamic> userData,
  }) {
    // Validate user data keys match schema fields
    final userFieldNames = schema.fields.map((f) => f.name).toSet();
    final providedKeys = userData.keys.toSet();

    final missing = userFieldNames.difference(providedKeys);
    if (missing.isNotEmpty) {
      throw ArgumentError(
        'Missing user data fields: ${missing.join(", ")}',
      );
    }

    final extra = providedKeys.difference(userFieldNames);
    if (extra.isNotEmpty) {
      throw ArgumentError(
        'Unknown user data fields (not in schema): ${extra.join(", ")}',
      );
    }

    // Build ordered values list: LP fields first, then user fields
    final serializedLocation = LocationSerializer.serialize(lpPayload.location);

    final List<dynamic> values = [
      lpPayload.lpVersion, // string lp_version
      lpPayload.srs, // string srs
      lpPayload.locationType, // string location_type
      serializedLocation, // string location
    ];

    // Append user field values in schema declaration order
    for (final field in schema.fields) {
      dynamic value = userData[field.name];
      
      // HexUtils: Robust conversion for bytes/bytes32 fields passed as hex strings
      if ((field.type.startsWith('bytes') || field.type.startsWith('uint256')) && value is String && value.startsWith('0x')) {
        // NOTE: if it's uint256, blockchain_utils might want BigInt instead of bytes, 
        // string hex parsing for bytes is strictly using toBytes()
        if (field.type.startsWith('bytes')) {
          value = value.toBytes();
        }
      }
      
      values.add(value);
    }

    // Build ABI type list from all fields
    final allFields = schema.allFields;

    // Use on_chain's ABI encoding
    // Build parameter types for encoding
    final components = <AbiParameter>[];
    for (final field in allFields) {
      // AbiParameter.fromJson is used as a convenient way to construct it
      // though the direct constructor works too.
      components.add(AbiParameter(name: field.name, type: field.type));
    }

    // To encode multiple parameters, we treat them as a tuple
    final tupleParam = AbiParameter(
      name: null,
      type: 'tuple',
      components: components,
    );

    // Get the tuple coder and encode
    final coder = ABICoder.fromType('tuple');
    final result = coder.abiEncode(tupleParam, values);

    return Uint8List.fromList(result.encoded);
  }
}
