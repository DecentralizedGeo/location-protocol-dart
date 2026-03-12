import 'package:test/test.dart';
import 'package:location_protocol/src/schema/schema_field.dart';

void main() {
  group('SchemaField', () {
    test('creates a field with type and name', () {
      final field = SchemaField(type: 'uint256', name: 'timestamp');
      expect(field.type, equals('uint256'));
      expect(field.name, equals('timestamp'));
    });

    test('toString returns ABI-formatted string', () {
      final field = SchemaField(type: 'uint256', name: 'timestamp');
      expect(field.toString(), equals('uint256 timestamp'));
    });

    test('toString for string type', () {
      final field = SchemaField(type: 'string', name: 'memo');
      expect(field.toString(), equals('string memo'));
    });

    test('toString for bytes32 type', () {
      final field = SchemaField(type: 'bytes32', name: 'document_hash');
      expect(field.toString(), equals('bytes32 document_hash'));
    });

    test('toString for address type', () {
      final field = SchemaField(type: 'address', name: 'recipient');
      expect(field.toString(), equals('address recipient'));
    });

    test('toString for array type', () {
      final field = SchemaField(type: 'string[]', name: 'tags');
      expect(field.toString(), equals('string[] tags'));
    });

    test('equality works for identical fields', () {
      final a = SchemaField(type: 'uint256', name: 'timestamp');
      final b = SchemaField(type: 'uint256', name: 'timestamp');
      expect(a, equals(b));
    });

    test('rejects empty type', () {
      expect(
        () => SchemaField(type: '', name: 'timestamp'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects empty name', () {
      expect(
        () => SchemaField(type: 'uint256', name: ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
