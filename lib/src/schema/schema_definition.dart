import 'schema_field.dart';

/// Defines an EAS schema with automatic LP base field prepending.
///
/// Users provide only their business-specific fields. The LP base fields
/// (`lp_version`, `srs`, `location_type`, `location`) are automatically
/// prepended when generating the EAS schema string.
///
/// Field names that collide with LP reserved names will throw [ArgumentError].
class SchemaDefinition {
  /// LP base fields — always prepended to the EAS schema. All typed as `string`
  /// since the LP payload is serialized before ABI encoding.
  static final List<SchemaField> lpFields = [
    SchemaField(type: 'string', name: 'lp_version'),
    SchemaField(type: 'string', name: 'srs'),
    SchemaField(type: 'string', name: 'location_type'),
    SchemaField(type: 'string', name: 'location'),
  ];

  /// The reserved LP field names that user fields cannot use.
  static final Set<String> _reservedNames =
      lpFields.map((f) => f.name).toSet();

  /// User-defined business fields.
  final List<SchemaField> fields;

  /// Whether attestations made against this schema can be revoked.
  final bool revocable;

  /// Optional resolver contract address. Defaults to the zero address.
  final String resolverAddress;

  /// Creates a schema definition.
  ///
  /// Throws [ArgumentError] if any user field name collides with an LP
  /// reserved field name.
  SchemaDefinition({
    required this.fields,
    this.revocable = true,
    this.resolverAddress = '0x0000000000000000000000000000000000000000',
  }) {
    _validateNoConflicts();
  }

  void _validateNoConflicts() {
    for (final field in fields) {
      if (_reservedNames.contains(field.name)) {
        throw ArgumentError.value(
          field.name,
          'field.name',
          'Conflicts with LP reserved field name "${field.name}". '
              'LP fields are auto-prepended and cannot be redefined.',
        );
      }
    }
  }

  /// All fields in schema order: LP fields first, then user fields.
  List<SchemaField> get allFields => [...lpFields, ...fields];

  /// Generates the EAS-compatible schema string.
  ///
  /// Format: `type1 name1,type2 name2,...`
  /// LP fields are always first:
  /// `string lp_version,string srs,string location_type,string location,...`
  String toEASSchemaString() {
    return allFields.map((f) => f.toString()).join(',');
  }
}
