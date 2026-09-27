import 'dart:async';
import 'dart:io';

class LexicalHttpResponse {
  const LexicalHttpResponse(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers;
  final List<int> body;
}

abstract interface class LexicalTransport {
  Future<LexicalHttpResponse> get(Uri uri);
}

class LexicalBodyTooLarge implements Exception {}

/// One bounded request. Redirects are not followed to unrelated hosts.
class IoLexicalTransport implements LexicalTransport {
  IoLexicalTransport(
      {HttpClient Function()? clientFactory,
      this.timeout = const Duration(seconds: 15),
      this.maxBytes = 262144})
      : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;
  final Duration timeout;
  final int maxBytes;
  @override
  Future<LexicalHttpResponse> get(Uri uri) async {
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader,
            'FrenchApp/0.1 (+https://github.com/ArdaHFO/FrenchApp)');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (response.contentLength > maxBytes) throw LexicalBodyTooLarge();
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxBytes) {
            throw LexicalBodyTooLarge();
          }
          bytes.addAll(chunk);
        }
        final headers = <String, String>{};
        response.headers.forEach(
            (name, values) => headers[name.toLowerCase()] = values.join(','));
        return LexicalHttpResponse(response.statusCode, headers, bytes);
      })()
          .timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }
}
