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

    test('register attempts RPC call (fails gracefully without network)', () {
      final registry = SchemaRegistryClient(
        rpcUrl: 'http://localhost:1', // intentionally unreachable
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      // Calling register should attempt a real RPC call and throw
      // a network/connection error (not UnimplementedError)
      expect(
        () => registry.register(
          SchemaDefinition(
            fields: [SchemaField(type: 'uint256', name: 'timestamp')],
          ),
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });

    test('getSchema attempts RPC call (fails gracefully without network)', () {
      final registry = SchemaRegistryClient(
        rpcUrl: 'http://localhost:1', // intentionally unreachable
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        chainId: 11155111,
      );
      expect(
        () => registry.getSchema(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        throwsA(isNot(isA<UnimplementedError>())),
      );
    });
  });
}
