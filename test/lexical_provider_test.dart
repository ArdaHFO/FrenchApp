import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/services/lexical/lexical_models.dart';
import 'package:french_app/services/lexical/lexical_transport.dart';
import 'package:french_app/services/lexical/wiktapi_provider.dart';

class FakeTransport implements LexicalTransport {
  FakeTransport(this.respond);
  final FutureOr<LexicalHttpResponse> Function(Uri) respond;
  final requests = <Uri>[];
  @override
  Future<LexicalHttpResponse> get(Uri uri) async {
    requests.add(uri);
    return respond(uri);
  }
}

LexicalHttpResponse fixture(Uri uri, {String? word}) {
  final lemma = word ?? uri.pathSegments[3];
  final definitions = uri.pathSegments.last == 'definitions';
  return LexicalHttpResponse(
      200,
      {'cache-control': 'public, max-age=86400, stale-while-revalidate=604800'},
      utf8.encode(jsonEncode({
        'word': lemma,
        'edition': 'en',
        if (definitions)
          'definitions': [
            {
              'lang_code': 'en',
              'pos': 'noun',
              'senses': [
                {
                  'glosses': ['noise']
                }
              ]
            },
            {
              'lang_code': 'fr',
              'pos': 'noun',
              'senses': [
                {
                  'glosses': ['cat', 'feline'],
                  'tags': ['masculine'],
                  'examples': [
                    {'text': 'Un chat.'}
                  ]
                },
                {
                  'glosses': ['unsafe'],
                  'tags': ['vulgar']
                }
              ]
            },
            {
              'lang_code': 'fr',
              'pos': 'verb',
              'senses': [
                {
                  'glosses': ['to chat']
                }
              ]
            }
          ],
        if (!definitions)
          'pronunciations': [
            {
              'lang_code': 'fr',
              'pos': 'noun',
              'sounds': [
                {'ipa': '/ʃa/', 'audio': null, 'tags': []},
                {
                  'ipa': null,
                  'audio': 'Fr-chat.ogg',
                  'tags': ['France']
                }
              ]
            }
          ],
      })));
}

void main() {
  test('BUG-006 no-cache forbids fresh and stale reuse without validation', () async {
    final transport = FakeTransport((uri) {
      final r = fixture(uri);
      return LexicalHttpResponse(r.status, {'cache-control': 'no-cache, max-age=86400'}, r.body);
    });
    final result = await WiktApiProvider(transport: transport).lookup(LexicalLookupKey('chat'));
    expect(result.maxAge, Duration.zero);
    expect(result.staleAge, Duration.zero);
  });
  test('BUG-006 malformed Retry-After retains rate-limited outcome', () async {
    final result = await WiktApiProvider(transport: FakeTransport((_) =>
      const LexicalHttpResponse(429, {'retry-after': 'not a date'}, []))).lookup(LexicalLookupKey('chat'));
    expect(result.status, LexicalStatus.rateLimited);
    expect(result.retryAt, isNotNull);
  });
  test(
      'normalization retains POS groups tags provenance and optional sound metadata',
      () async {
    final transport = FakeTransport(fixture);
    final now = DateTime.utc(2026, 9, 27);
    final result = await WiktApiProvider(transport: transport, clock: () => now)
        .lookup(LexicalLookupKey('chat'));
    expect(result.status, LexicalStatus.found);
    expect(result.data!.senses, hasLength(3));
    expect(result.data!.senses.where((s) => s.safeForDefaultDisplay),
        hasLength(2));
    expect(result.data!.pronunciations.first.ipa, '/ʃa/');
    expect(result.data!.provenance.retrievedAt, now);
    expect(result.data!.provenance.toJson()['upstreamGeneration'], isNull);
    expect(result.maxAge, const Duration(days: 1));
    expect(result.staleAge, const Duration(days: 7));
    expect(
        LexicalEnrichment.fromJson(
                jsonDecode(jsonEncode(result.data!.toJson())))
            .toJson(),
        result.data!.toJson());
    expect(transport.requests.length, 2);
  });

  for (final lemma in [
    'être',
    "aujourd'hui",
    'arc-en-ciel',
    'à bientôt',
    '100%'
  ]) {
    test('query is encoded exactly once: $lemma', () async {
      final transport = FakeTransport(fixture);
      final result = await WiktApiProvider(transport: transport)
          .lookup(LexicalLookupKey(lemma));
      expect(transport.requests.first.pathSegments,
          ['v1', 'en', 'word', lemma, 'definitions']);
      expect(transport.requests.first.queryParameters, {'lang': 'fr'});
      expect(result.status, LexicalStatus.found);
      expect(Uri.parse(result.data!.provenance.sourceUrl).pathSegments.last,
          lemma);
    });
  }
  test('invalid explicit queries never leave device', () async {
    final transport = FakeTransport(fixture);
    final provider = WiktApiProvider(transport: transport);
    for (final word in [
      '',
      'https://evil.test',
      '../word',
      'a' * 121,
      'a\u0000b'
    ]) {
      expect((await provider.lookup(LexicalLookupKey(word))).status,
          LexicalStatus.permanentFailure);
    }
    expect(transport.requests, isEmpty);
  });
  for (final status in [403, 404, 429, 500, 502, 503]) {
    test('HTTP $status has explicit outcome', () async {
      final transport = FakeTransport(
          (_) => LexicalHttpResponse(status, {'retry-after': '120'}, []));
      final now = DateTime.utc(2026);
      final provider = WiktApiProvider(transport: transport, clock: () => now);
      final result = await provider.lookup(LexicalLookupKey('chat'));
      expect(
          result.status,
          status == 404
              ? LexicalStatus.notFound
              : status == 429
                  ? LexicalStatus.rateLimited
                  : status >= 500
                      ? LexicalStatus.transientFailure
                      : LexicalStatus.permanentFailure);
      if (status == 429) {
        expect(result.retryAt, now.add(const Duration(seconds: 120)));
        await provider.lookup(LexicalLookupKey('chien'));
        expect(transport.requests.length, 1);
      }
    });
  }
  test('Retry-After date is honored', () async {
    final now = DateTime.utc(2026);
    final target = now.add(const Duration(minutes: 3));
    final provider = WiktApiProvider(
        clock: () => now,
        transport: FakeTransport((_) => LexicalHttpResponse(
            429, {'retry-after': HttpDate.format(target)}, [])));
    expect((await provider.lookup(LexicalLookupKey('chat'))).retryAt, target);
  });
  for (final body in [
    '{',
    '{}',
    '{"word":"chat","edition":"en","definitions":"changed"}',
    '{"word":"other","edition":"en","definitions":[]}',
    'x' * 262145
  ]) {
    test(
        'malformed or unexpected payload ${body.length} is explicit schema failure',
        () async {
      final provider = WiktApiProvider(
          transport: FakeTransport(
              (_) => LexicalHttpResponse(200, {}, utf8.encode(body))));
      expect((await provider.lookup(LexicalLookupKey('chat'))).status,
          LexicalStatus.schemaFailure);
    });
  }
  test('invalid UTF8 is rejected', () async {
    final provider = WiktApiProvider(
        transport:
            FakeTransport((_) => const LexicalHttpResponse(200, {}, [255])));
    expect((await provider.lookup(LexicalLookupKey('chat'))).status,
        LexicalStatus.schemaFailure);
  });
  for (final error in [
    TimeoutException('bounded'),
    const SocketException('offline'),
    const HttpException('closed')
  ]) {
    test('transport ${error.runtimeType} is transient', () async {
      final provider =
          WiktApiProvider(transport: FakeTransport((_) => throw error));
      expect((await provider.lookup(LexicalLookupKey('chat'))).status,
          LexicalStatus.transientFailure);
    });
  }
  test('missing optional fields and failed pronunciation preserve definitions',
      () async {
    final provider = WiktApiProvider(
        transport:
            FakeTransport((uri) => uri.pathSegments.last == 'pronunciations'
                ? throw const SocketException('offline')
                : LexicalHttpResponse(
                    200,
                    {'cache-control': 'no-store'},
                    utf8.encode(jsonEncode({
                      'word': 'chat',
                      'edition': 'en',
                      'definitions': [
                        {
                          'lang_code': 'fr',
                          'pos': 'noun',
                          'senses': [
                            {
                              'glosses': ['cat']
                            }
                          ]
                        }
                      ]
                    })))));
    final result = await provider.lookup(LexicalLookupKey('chat'));
    expect(result.status, LexicalStatus.found);
    expect(result.pronunciationUnavailable, isTrue);
    expect(result.cacheable, isFalse);
    expect(result.data!.senses.single.tags, isEmpty);
  });
  test('empty French senses require selection rather than false success',
      () async {
    final provider = WiktApiProvider(
        transport: FakeTransport((_) => LexicalHttpResponse(200, {},
            utf8.encode('{"word":"chat","edition":"en","definitions":[]}'))));
    expect((await provider.lookup(LexicalLookupKey('chat'))).status,
        LexicalStatus.selectionRequired);
  });

  test('real transport sends headers and enforces streamed response bound',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final headers = Completer<Map<String, String?>>();
    server.listen((r) async {
      headers.complete({
        'agent': r.headers.value('user-agent'),
        'accept': r.headers.value('accept')
      });
      r.response.add(List.filled(100, 65));
      await r.response.close();
    });
    await expectLater(
        IoLexicalTransport(maxBytes: 20)
            .get(Uri.parse('http://127.0.0.1:${server.port}/')),
        throwsA(isA<LexicalBodyTooLarge>()));
    final sent = await headers.future;
    expect(sent['agent'], contains('FrenchApp'));
    expect(sent['accept'], 'application/json');
  });
  test('real transport timeout closes stalled request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((_) {});
    await expectLater(
        IoLexicalTransport(timeout: const Duration(milliseconds: 50))
            .get(Uri.parse('http://127.0.0.1:${server.port}/')),
        throwsA(isA<TimeoutException>()));
  });
}
