/// A single field in an EAS schema definition.
///
/// Each field has a Solidity [type] (e.g. `uint256`, `string`, `address`)
/// and a [name] (e.g. `timestamp`, `memo`).
class SchemaField {
  final String type;
  final String name;

  /// Creates a schema field.
  ///
  /// Both [type] and [name] must be non-empty strings.
  SchemaField({required this.type, required this.name}) {
    if (type.isEmpty) {
      throw ArgumentError.value(type, 'type', 'Must be non-empty.');
    }
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must be non-empty.');
    }
  }

  /// Returns the ABI-formatted field string, e.g. `uint256 timestamp`.
  @override
  String toString() => '$type $name';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SchemaField && type == other.type && name == other.name;

  @override
  int get hashCode => Object.hash(type, name);
}
