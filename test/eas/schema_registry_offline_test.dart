import 'package:test/test.dart';
import 'package:location_protocol/src/eas/schema_registry.dart';
import 'package:location_protocol/src/models/register_result.dart';
import 'package:location_protocol/src/schema/schema_definition.dart';
import 'package:location_protocol/src/schema/schema_field.dart';
import '../rpc/fake_rpc_provider.dart';

void main() {
  group('SchemaRegistryClient.register (offline)', () {
    test('returns RegisterResult with txHash and locally-computed uid', () async {
      final provider = FakeRpcProvider();
      final registry = SchemaRegistryClient(provider: provider);
      final schema = SchemaDefinition(
        fields: [SchemaField(type: 'string', name: 'testField')],
      );

      final result = await registry.register(schema);

      expect(result, isA<RegisterResult>());
      expect(result.txHash, equals('0xFakeTxHash'));
      expect(result.uid, equals(SchemaRegistryClient.computeSchemaUID(schema)));
    });
  });
}
