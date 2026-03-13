import 'package:test/test.dart';
import 'package:location_protocol/src/rpc/http_rpc_service.dart';

void main() {
  group('HttpRpcService', () {
    test('constructs with a valid URL', () {
      final service = HttpRpcService('https://rpc.sepolia.org');
      expect(service.url, equals('https://rpc.sepolia.org'));
    });

    test('constructs with custom timeout', () {
      final service = HttpRpcService(
        'https://rpc.sepolia.org',
        defaultTimeout: const Duration(seconds: 60),
      );
      expect(service.url, equals('https://rpc.sepolia.org'));
    });

    test('throws on empty URL', () {
      expect(() => HttpRpcService(''), throwsArgumentError);
    });
  });
}
