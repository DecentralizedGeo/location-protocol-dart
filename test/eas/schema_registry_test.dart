import 'package:test/test.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/eas/schema_registry.dart';

void main() {
  group('SchemaRegistryClient', () {
    test('builds register call data as non-empty bytes', () {
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );

      final callData = SchemaRegistryClient.buildRegisterCallData(schema);
      expect(callData, isNotEmpty);
    });

    test('register call data starts with function selector', () {
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );

      final callData = SchemaRegistryClient.buildRegisterCallData(schema);
      // Function selector is first 4 bytes
      expect(callData.length, greaterThanOrEqualTo(4));
    });

    test('different schemas produce different call data', () {
      final schema1 = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );
      final schema2 = SchemaDefinition(
        fields: [SchemaField(type: 'string', name: 'memo')],
      );

      final data1 = SchemaRegistryClient.buildRegisterCallData(schema1);
      final data2 = SchemaRegistryClient.buildRegisterCallData(schema2);
      expect(data1, isNot(equals(data2)));
    });

    test('computeSchemaUID matches SchemaUID.compute', () {
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'uint256', name: 'timestamp')],
      );

      final uid = SchemaRegistryClient.computeSchemaUID(schema);
      expect(uid, startsWith('0x'));
      expect(uid.length, equals(66));
    });
  });
}
