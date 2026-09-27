/// Optional dictionary data. These types never own curriculum or SRS identity.
class LexicalLookupKey {
  LexicalLookupKey(String lemma, {this.expectedPos})
      : lemma = lemma.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static const provider = 'wiktapi';
  static const edition = 'en';
  static const language = 'fr';
  static const schemaVersion = 1;
  final String lemma;
  final String? expectedPos;
  bool get valid =>
      lemma.isNotEmpty &&
      lemma.runes.length <= 120 &&
      !RegExp(r'[\x00-\x1f\x7f/\\:#?]').hasMatch(lemma);
  // POS is a presentation hint; the cached response retains every POS group.
  String get cacheKey => '$provider|$edition|$language|$schemaVersion|$lemma';
  Uri endpoint(String projection) => Uri(
      scheme: 'https',
      host: 'api.wiktapi.dev',
      pathSegments: ['v1', 'en', 'word', lemma, projection],
      queryParameters: {'lang': 'fr'});
}

enum LexicalStatus {
  found,
  notFound,
  selectionRequired,
  transientFailure,
  rateLimited,
  schemaFailure,
  permanentFailure,
}

class LexicalProvenance {
  const LexicalProvenance(
      {required this.requestedLemma,
      required this.responseUrl,
      required this.sourceUrl,
      required this.retrievedAt});
  final String requestedLemma, responseUrl, sourceUrl;
  final DateTime retrievedAt;
  String get label => 'WiktApi / English Wiktionary (French entries)';
  Map<String, Object?> toJson() => {
        'provider': LexicalLookupKey.provider,
        'edition': LexicalLookupKey.edition,
        'language': LexicalLookupKey.language,
        'requestedLemma': requestedLemma,
        'responseUrl': responseUrl,
        'sourceUrl': sourceUrl,
        'retrievedAt': retrievedAt.toUtc().toIso8601String(),
        'schemaVersion': LexicalLookupKey.schemaVersion,
        'sourceLabel': label,
        'upstreamGeneration': null,
      };
  factory LexicalProvenance.fromJson(Map<String, dynamic> j) {
    if (j['schemaVersion'] != LexicalLookupKey.schemaVersion ||
        j['provider'] != LexicalLookupKey.provider ||
        j['edition'] != 'en' ||
        j['language'] != 'fr') {
      throw const FormatException('Unsupported provenance');
    }
    return LexicalProvenance(
        requestedLemma: j['requestedLemma'] as String,
        responseUrl: j['responseUrl'] as String,
        sourceUrl: j['sourceUrl'] as String,
        retrievedAt: DateTime.parse(j['retrievedAt'] as String));
  }
}

class LexicalSense {
  LexicalSense(
      {required this.pos,
      required Iterable<String> glosses,
      Iterable<String> tags = const [],
      Iterable<String> examples = const []})
      : glosses = List.unmodifiable(glosses),
        tags = List.unmodifiable(tags),
        examples = List.unmodifiable(examples);
  final String pos;
  final List<String> glosses, tags, examples;
  bool get safeForDefaultDisplay => !tags.any((t) => RegExp(
          r'vulgar|offensive|slur|sexual|obscene|derogatory|pejorative|racist',
          caseSensitive: false)
      .hasMatch(t));
  Map<String, Object?> toJson() =>
      {'pos': pos, 'glosses': glosses, 'tags': tags, 'examples': examples};
  factory LexicalSense.fromJson(Map<String, dynamic> j) => LexicalSense(
      pos: j['pos'] as String,
      glosses: (j['glosses'] as List).cast<String>(),
      tags: (j['tags'] as List).cast<String>(),
      examples: (j['examples'] as List).cast<String>());
}

class LexicalPronunciation {
  LexicalPronunciation(
      {required this.pos,
      this.ipa,
      this.audio,
      Iterable<String> tags = const []})
      : tags = List.unmodifiable(tags);
  final String pos;
  final String? ipa;

  /// Upstream filename/metadata only. Not permission to play unlicensed media.
  final String? audio;
  final List<String> tags;
  Map<String, Object?> toJson() =>
      {'pos': pos, 'ipa': ipa, 'audio': audio, 'tags': tags};
  factory LexicalPronunciation.fromJson(Map<String, dynamic> j) =>
      LexicalPronunciation(
          pos: j['pos'] as String,
          ipa: j['ipa'] as String?,
          audio: j['audio'] as String?,
          tags: (j['tags'] as List).cast<String>());
}

class LexicalEnrichment {
  LexicalEnrichment(
      {required this.word,
      required Iterable<LexicalSense> senses,
      required Iterable<LexicalPronunciation> pronunciations,
      required this.provenance})
      : senses = List.unmodifiable(senses),
        pronunciations = List.unmodifiable(pronunciations);
  final String word;
  final List<LexicalSense> senses;
  final List<LexicalPronunciation> pronunciations;
  final LexicalProvenance provenance;
  Map<String, Object?> toJson() => {
        'word': word,
        'senses': senses.map((s) => s.toJson()).toList(),
        'pronunciations': pronunciations.map((s) => s.toJson()).toList(),
        'provenance': provenance.toJson()
      };
  factory LexicalEnrichment.fromJson(Map<String, dynamic> j) =>
      LexicalEnrichment(
          word: j['word'] as String,
          senses: (j['senses'] as List)
              .map((s) => LexicalSense.fromJson(s as Map<String, dynamic>)),
          pronunciations: (j['pronunciations'] as List).map(
              (s) => LexicalPronunciation.fromJson(s as Map<String, dynamic>)),
          provenance: LexicalProvenance.fromJson(
              j['provenance'] as Map<String, dynamic>));
}

class LexicalOutcome {
  const LexicalOutcome(this.status,
      {this.data,
      this.retryAt,
      this.maxAge = const Duration(hours: 24),
      this.staleAge = const Duration(days: 7),
      this.cacheable = true,
      this.fromCache = false,
      this.stale = false,
      this.cacheUnavailable = false,
      this.pronunciationUnavailable = false});
  final LexicalStatus status;
  final LexicalEnrichment? data;
  final DateTime? retryAt;
  final Duration maxAge, staleAge;
  final bool cacheable,
      fromCache,
      stale,
      cacheUnavailable,
      pronunciationUnavailable;
  LexicalOutcome cached({required bool isStale}) => LexicalOutcome(status,
      data: data,
      retryAt: retryAt,
      maxAge: maxAge,
      staleAge: staleAge,
      cacheable: cacheable,
      fromCache: true,
      stale: isStale,
      pronunciationUnavailable: pronunciationUnavailable);
}

abstract interface class LexicalProvider {
  Future<LexicalOutcome> lookup(LexicalLookupKey key);
}
