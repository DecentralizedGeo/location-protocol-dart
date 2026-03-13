import 'dart:async';
import 'dart:io';

import 'package:on_chain/on_chain.dart';

/// HTTP-based JSON-RPC service for communicating with Ethereum nodes.
///
/// Implements `EthereumServiceProvider` using `dart:io`'s [HttpClient]
/// so that `on_chain`'s [EthereumProvider] can issue JSON-RPC calls
/// to any standard Ethereum RPC endpoint.
///
/// Usage:
/// ```dart
/// final service = HttpRpcService('https://rpc.sepolia.org');
/// final provider = EthereumProvider(service);
/// ```
class HttpRpcService with EthereumServiceProvider {
  /// The JSON-RPC endpoint URL.
  final String url;

  /// Default timeout for HTTP requests.
  final Duration defaultTimeout;

  final HttpClient _client;

  HttpRpcService(
    this.url, {
    this.defaultTimeout = const Duration(seconds: 30),
  }) : _client = HttpClient() {
    if (url.isEmpty) {
      throw ArgumentError('RPC URL must not be empty');
    }
  }

  @override
  Future<EthereumServiceResponse<T>> doRequest<T>(
    EthereumRequestDetails params, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? defaultTimeout;
    final uri = params.toUri(url);
    final body = params.body();

    final request = await _client.postUrl(uri);
    request.headers.set('Content-Type', 'application/json');
    if (body != null) {
      request.add(body);
    }

    final response = await request.close().timeout(effectiveTimeout);
    final responseBytes = await _collectBytes(response);

    final statusCode = response.statusCode;
    return params.toResponse(responseBytes, statusCode);
  }

  Future<List<int>> _collectBytes(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    return builder.toBytes();
  }

  /// Closes the underlying HTTP client.
  void close() {
    _client.close();
  }
}
