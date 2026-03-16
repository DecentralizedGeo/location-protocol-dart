import 'package:test/test.dart';
import 'package:location_protocol/src/eas/schema_registry.dart';
import 'package:location_protocol/src/models/register_result.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import '../rpc/fake_rpc_provider.dart';

void main() {
  group('SchemaRegistryClient.register (offline)', () {
    test('registers new schema and returns transaction hash', () async {
      final provider = FakeRpcProvider();
      // No contractCallMocks for 'getSchema' — returns empty list → null (schema not found)
      final registry = SchemaRegistryClient(provider: provider);
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'string', name: 'testField')],
      );

      final result = await registry.register(schema);

      expect(result, isA<RegisterResult>());
      expect(result.txHash, equals('0xFakeTxHash'));
      expect(result.uid, equals(SchemaRegistryClient.computeSchemaUID(schema)));
      expect(result.alreadyExisted, isFalse);
    });

    test('skips registration when schema already exists on-chain', () async {
      final provider = FakeRpcProvider();
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'string', name: 'testField')],
      );
      final uid = SchemaRegistryClient.computeSchemaUID(schema);

      // Mock getSchema to return an existing record with a non-zero UID
      provider.contractCallMocks['getSchema'] = [
        [uid, '0x0000000000000000000000000000000000000000', true, schema.toEASSchemaString()],
      ];

      final registry = SchemaRegistryClient(provider: provider);
      final result = await registry.register(schema);

      expect(result.alreadyExisted, isTrue);
      expect(result.txHash, isNull);
      expect(result.uid, equals(uid));
      // No transaction should have been sent
      expect(provider.lastTransactionTo, isNull);
    });
  });
}
