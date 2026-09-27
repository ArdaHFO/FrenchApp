import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lexical_models.dart';
import 'lexical_transport.dart';

class WiktApiProvider implements LexicalProvider {
  WiktApiProvider({LexicalTransport? transport, DateTime Function()? clock})
      : _transport = transport ?? IoLexicalTransport(),
        _clock = clock ?? DateTime.now;
  final LexicalTransport _transport;
  final DateTime Function() _clock;
  DateTime? _retryAt;

  @override
  Future<LexicalOutcome> lookup(LexicalLookupKey key) async {
    if (!key.valid) return const LexicalOutcome(LexicalStatus.permanentFailure);
    if (_retryAt != null && _clock().isBefore(_retryAt!)) {
      return LexicalOutcome(LexicalStatus.rateLimited, retryAt: _retryAt);
    }
    try {
      final response = await _transport.get(key.endpoint('definitions'));
      final failure = _failure(response);
      if (failure != null) return failure;
      final root = _root(response, key, 'definitions');
      final senses = <LexicalSense>[];
      for (final value in root['definitions'] as List) {
        final row = value as Map<String, dynamic>;
        if (row['lang_code'] != 'fr') continue;
        final pos = row['pos'] as String;
        for (final value in row['senses'] as List) {
          final sense = value as Map<String, dynamic>;
          final glosses = _strings(sense['glosses']);
          if (glosses.isEmpty) continue;
          final examples = <String>[];
          for (final example in (sense['examples'] as List? ?? [])) {
            final text = (example as Map<String, dynamic>)['text'];
            if (text is String && text.trim().isNotEmpty) examples.add(text);
          }
          senses.add(LexicalSense(
              pos: pos,
              glosses: glosses,
              tags: [..._strings(row['tags']), ..._strings(sense['tags'])],
              examples: examples));
        }
      }
      if (senses.isEmpty) {
        return const LexicalOutcome(LexicalStatus.selectionRequired);
      }
      final sounds = <LexicalPronunciation>[];
      var pronunciationUnavailable = false;
      try {
        final pronunciation =
            await _transport.get(key.endpoint('pronunciations'));
        if (_failure(pronunciation) != null) {
          pronunciationUnavailable = true;
        } else {
          final soundRoot = _root(pronunciation, key, 'pronunciations');
          for (final value in soundRoot['pronunciations'] as List) {
            final row = value as Map<String, dynamic>;
            if (row['lang_code'] != 'fr') continue;
            for (final value in row['sounds'] as List) {
              final sound = value as Map<String, dynamic>;
              final ipa = sound['ipa'] as String?;
              final audio = sound['audio'] as String?;
              if ((ipa?.isNotEmpty ?? false) || (audio?.isNotEmpty ?? false)) {
                sounds.add(LexicalPronunciation(
                    pos: row['pos'] as String,
                    ipa: ipa,
                    audio: audio,
                    tags: _strings(sound['tags'])));
              }
            }
          }
        }
      } catch (_) {
        // Definitions remain usable; the explicit flag exposes partial enrichment.
        pronunciationUnavailable = true;
      }
      final cache = (response.headers['cache-control'] ?? '').toLowerCase();
      return LexicalOutcome(LexicalStatus.found,
          data: LexicalEnrichment(
              word: root['word'] as String,
              senses: senses,
              pronunciations: sounds,
              provenance: LexicalProvenance(
                  requestedLemma: key.lemma,
                  responseUrl: key.endpoint('definitions').toString(),
                  sourceUrl: Uri(
                          scheme: 'https',
                          host: 'en.wiktionary.org',
                          pathSegments: ['wiki', root['word'] as String],
                          fragment: 'French')
                      .toString(),
                  retrievedAt: _clock().toUtc())),
          maxAge: cache.contains('no-cache') ? Duration.zero : _duration(cache, 'max-age', const Duration(hours: 24)),
          staleAge: cache.contains('no-cache') || cache.contains('must-revalidate') ? Duration.zero : _duration(
              cache, 'stale-while-revalidate', const Duration(days: 7)),
          cacheable: !cache.contains('no-store'),
          pronunciationUnavailable: pronunciationUnavailable);
    } on TimeoutException {
      return const LexicalOutcome(LexicalStatus.transientFailure);
    } on SocketException {
      return const LexicalOutcome(LexicalStatus.transientFailure);
    } on HttpException {
      return const LexicalOutcome(LexicalStatus.transientFailure);
    } on LexicalBodyTooLarge {
      return const LexicalOutcome(LexicalStatus.schemaFailure);
    } on FormatException {
      return const LexicalOutcome(LexicalStatus.schemaFailure);
    } on TypeError {
      return const LexicalOutcome(LexicalStatus.schemaFailure);
    }
  }

  LexicalOutcome? _failure(LexicalHttpResponse r) {
    if (r.status == 200) return null;
    if (r.status == 404) {
      final cache = (r.headers['cache-control'] ?? '').toLowerCase();
      return LexicalOutcome(LexicalStatus.notFound,
          maxAge: cache.contains('no-cache') ? Duration.zero : _duration(cache, 'max-age', const Duration(hours: 4)),
          staleAge: Duration.zero,
          cacheable: !cache.contains('no-store'));
    }
    if (r.status == 429) {
      final raw = r.headers['retry-after'];
      final seconds = int.tryParse(raw ?? '');
      DateTime? date;
      try {
        if (raw != null && seconds == null) date = HttpDate.parse(raw);
      } on FormatException {/* fallback */}
      on HttpException {/* malformed HTTP date: retain 429 classification */}
      _retryAt = date ??
          _clock().add(
              Duration(seconds: seconds == null || seconds < 0 ? 60 : seconds));
      return LexicalOutcome(LexicalStatus.rateLimited, retryAt: _retryAt);
    }
    return LexicalOutcome(r.status >= 500 || r.status == 408
        ? LexicalStatus.transientFailure
        : LexicalStatus.permanentFailure);
  }

  Map<String, dynamic> _root(
      LexicalHttpResponse r, LexicalLookupKey key, String field) {
    // Defend even injectable transports that bypass the real transport's bound.
    if (r.body.length > 262144) throw LexicalBodyTooLarge();
    final root = jsonDecode(utf8.decode(r.body)) as Map<String, dynamic>;
    if (root['edition'] != 'en' ||
        root['word'] is! String ||
        root[field] is! List ||
        LexicalLookupKey(root['word'] as String).lemma != key.lemma) {
      throw const FormatException('Unexpected lexical identity/schema');
    }
    return root;
  }

  static List<String> _strings(dynamic value) => value == null
      ? []
      : (value as List)
          .cast<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList();
  static Duration _duration(String header, String name, Duration fallback) {
    final match =
        RegExp('(?:^|,)\\s*$name=(\\d+)').firstMatch(header.toLowerCase());
    return match == null ? fallback : Duration(seconds: int.parse(match[1]!));
  }
}
