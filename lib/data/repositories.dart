import 'progress_coordinator.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/adventure.dart';
import '../domain/game.dart';
import '../domain/journey.dart';
import '../domain/journey_aliases.dart';
import '../domain/lesson.dart';
import '../domain/level.dart';
import '../domain/srs/srs_card.dart';
import '../domain/verb.dart';
import '../domain/word.dart';
import '../domain/word_search.dart';

/// Kelime kaynağı.
abstract class WordRepository {
  List<Word> all();

  Word? byId(String id);

  List<WordSearchResult> search(
    String raw, {
    WordSearchLanguage language = WordSearchLanguage.all,
    int limit = 80,
  });

  /// Seviye ve tema filtresinden geçmiş, sıklık sırasına göre dizilmiş
  /// kimlikler. Oturum kurucu bu listeyi bekler.
  List<String> candidateIds({
    required List<CefrLevel> levels,
    WordTheme? theme,
    bool idiomsOnly = false,
    bool includeFunctionWords = false,
    bool includeNeedsReview = false,
    int? limit,
  });

  /// Quiz çeldiricileri. Aynı seviye ve türden, farklı anlamlı kelimeler.
  List<Word> distractorsFor(Word word, {int count = 3});

  /// Aynı kökten gelen kelimeler. Sıklık sırasında, en tanıdık olan başta.
  List<Word> relativesOf(String wordId);

  Set<WordTheme> availableThemes();
}

/// Content eligibility only. Dictionary access and saved progress stay intact;
/// each caller retains its own level, theme, archive and SRS rules.
extension LearningWordRepository on WordRepository {
  Word? learningWordById(String id) {
    final Word? word = byId(id);
    return word == null || word.needsReview ? null : word;
  }

  List<String> learningIds(Iterable<String> ids) => ids
      .where((String id) => learningWordById(id) != null)
      .toList();
}

/// `content.db` içindeki kelimeleri açılışta belleğe alır.
///
/// 9.670 kelime yaklaşık 3 MB tutuyor; bunu bellekte tutmak her sorguyu
/// senkron ve anında yapıyor. Fiil çekimleri ve dersler ise büyük olduğu
/// için istendiğinde okunur.
class SqliteWordRepository implements WordRepository {
  SqliteWordRepository._(
    this._words,
    this._byId,
    this._themes,
    this._kin,
  );

  final List<Word> _words;
  final Map<String, Word> _byId;
  final Set<WordTheme> _themes;
  WordSearchIndex? _searchIndex;
  final Map<String, List<String>> _candidateCache = <String, List<String>>{};

  /// Kelime kimliği -> aynı kökten gelen kelimelerin kimlikleri.
  /// 7.560 bağ, birkaç yüz kilobayt; tamamı bellekte durur.
  final Map<String, List<String>> _kin;

  static Future<SqliteWordRepository> load(Database db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT w.*, e.sentence_fr, e.sentence_en, e.sentence_tr,
             e.sentence_fr_id, e.author_fr,
             e.sentence_en_id, e.author_en,
             e.sentence_tr_id, e.author_tr
      FROM words w
      LEFT JOIN examples e
        ON e.word_id = w.id AND e.ordinal = 0
      ORDER BY w.freq_rank
    ''');

    final List<Word> words = <Word>[];
    final Map<String, Word> byId = <String, Word>{};
    final Set<WordTheme> themes = <WordTheme>{};

    for (final Map<String, Object?> r in rows) {
      final Word w = _fromRow(r);
      words.add(w);
      byId[w.id] = w;
      themes.add(w.theme);
    }

    final Map<String, List<String>> kin = <String, List<String>>{};
    final List<Map<String, Object?>> relRows = await db.query(
      'word_relations',
      columns: <String>['word_id', 'related_id'],
      orderBy: 'word_id, ordinal',
    );
    for (final Map<String, Object?> r in relRows) {
      kin
          .putIfAbsent(r['word_id']! as String, () => <String>[])
          .add(r['related_id']! as String);
    }

    return SqliteWordRepository._(words, byId, themes, kin);
  }

  static Word _fromRow(Map<String, Object?> r) {
    return Word(
      id: r['id']! as String,
      lemma: r['lemma_fr']! as String,
      article: r['article'] as String?,
      pos: r['pos']! as String,
      gender: r['gender'] as String?,
      level: _levelFrom(r['level']! as String),
      theme: _themeFrom(r['theme']! as String),
      ipa: r['ipa'] as String?,
      meaningEn: (r['meaning_en'] as String?) ?? '',
      meaningEn2: r['meaning_en_2'] as String?,
      meaningTr: (r['meaning_tr'] as String?) ?? '',
      literalTr: r['literal_tr'] as String?,
      noteTr: r['note_tr'] as String?,
      register: r['register'] as String?,
      sentenceFr: r['sentence_fr'] as String?,
      sentenceEn: r['sentence_en'] as String?,
      sentenceTr: r['sentence_tr'] as String?,
      sentenceFrId: r['sentence_fr_id'] as int?,
      sentenceFrAuthor: r['author_fr'] as String?,
      sentenceEnId: r['sentence_en_id'] as int?,
      sentenceEnAuthor: r['author_en'] as String?,
      sentenceTrId: r['sentence_tr_id'] as int?,
      sentenceTrAuthor: r['author_tr'] as String?,
      freqRank: (r['freq_rank'] as int?) ?? 999999,
      confidence: (r['confidence'] as num?)?.toDouble() ?? 1.0,
      isIdiom: (r['is_idiom'] as int?) == 1,
      isFunctionWord: (r['is_function'] as int?) == 1,
      needsReview: (r['needs_review'] as int?) == 1,
    );
  }

  @override
  List<Word> all() => _words;

  @override
  Word? byId(String id) => _byId[id];

  @override
  List<WordSearchResult> search(
    String raw, {
    WordSearchLanguage language = WordSearchLanguage.all,
    int limit = 80,
  }) =>
      WordSearchEngine.searchIndex(
        _searchIndex ??= WordSearchEngine.buildIndex(_words),
        raw,
        language: language,
        limit: limit,
      );

  @override
  Set<WordTheme> availableThemes() => _themes;

  @override
  List<Word> relativesOf(String wordId) {
    final List<String>? ids = _kin[wordId];
    if (ids == null) return const <Word>[];
    return <Word>[
      for (final String id in ids)
        if (_byId[id] != null && !_byId[id]!.needsReview) _byId[id]!,
    ];
  }

  @override
  List<String> candidateIds({
    required List<CefrLevel> levels,
    WordTheme? theme,
    bool idiomsOnly = false,
    bool includeFunctionWords = false,
    bool includeNeedsReview = false,
    int? limit,
  }) {
    final String cacheKey = <Object?>[
      levels.map((CefrLevel level) => level.name).join(','),
      theme?.name,
      idiomsOnly,
      includeFunctionWords,
      includeNeedsReview,
      limit,
    ].join('|');
    final List<String>? cached = _candidateCache[cacheKey];
    if (cached != null) return cached;

    final Set<CefrLevel> levelSet = levels.toSet();
    final List<Word> hits = <Word>[];
    for (final Word w in _words) {
      if (!levelSet.contains(w.level)) continue;
      if (theme != null && w.theme != theme) continue;
      if (idiomsOnly && !w.isIdiom) continue;
      if (!includeFunctionWords && w.isFunctionWord) continue;
      if (!includeNeedsReview && learningWordById(w.id) == null) continue;
      hits.add(w);
    }

    // Doğrulanmış karşılıklar öne alınır, kendi içlerinde sıklık sırası
    // korunur. İçeriğin bir kısmı tek kaynağa dayanıyor; yeni başlayan
    // kişi önce güvenilir kelimeleri görsün, şüpheliler sonra gelsin.
    if (includeNeedsReview) {
      hits.sort((Word a, Word b) {
        final int ra = a.needsReview ? 1 : 0;
        final int rb = b.needsReview ? 1 : 0;
        if (ra != rb) return ra - rb;
        return a.freqRank.compareTo(b.freqRank);
      });
    }

    final List<String> out = <String>[
      for (final Word w in hits) w.id,
    ];
    final List<String> result =
        limit != null && out.length > limit ? out.sublist(0, limit) : out;
    return _candidateCache[cacheKey] = List<String>.unmodifiable(result);
  }

  @override
  List<Word> distractorsFor(Word word, {int count = 3}) {
    bool sameShape(Word w) => w.level == word.level && w.pos == word.pos;

    final List<Word> pool = _words
        .where(
          (Word w) =>
              w.id != word.id &&
              learningWordById(w.id) != null &&
              w.meaningTr != word.meaningTr,
        )
        .toList();

    // Kurala göre sırala: aynı seviye + tür, sonra aynı seviye, sonra kalan.
    final List<Word> tiered = <Word>[
      ...pool.where(sameShape),
      ...pool.where((Word w) => w.level == word.level && !sameShape(w)),
      ...pool.where((Word w) => w.level != word.level),
    ];

    final List<Word> out = <Word>[];
    final Set<String> seen = <String>{word.meaningTr};
    for (final Word w in tiered) {
      if (out.length >= count) break;
      if (seen.add(w.meaningTr)) out.add(w);
    }
    return out;
  }
}

CefrLevel _levelFrom(String code) => switch (code.toUpperCase()) {
      'A1' => CefrLevel.a1,
      'A2' => CefrLevel.a2,
      'B1' => CefrLevel.b1,
      'B2' => CefrLevel.b2,
      'C1' => CefrLevel.c1,
      _ => CefrLevel.c2,
    };

WordTheme _themeFrom(String name) {
  for (final WordTheme t in WordTheme.values) {
    if (t.name == name) return t;
  }
  return WordTheme.general;
}

// ---------------------------------------------------------------- fiiller

/// Fiil ve çekim erişimi. Çekim tablosu 66 bin satır olduğu için
/// açılışta yüklenmez, istendiğinde okunur ve önbelleğe alınır.
class VerbRepository {
  VerbRepository(this._db);

  final Database _db;
  final Map<String, List<Conjugation>> _cache = <String, List<Conjugation>>{};
  List<Verb>? _verbs;

  Future<List<Verb>> all() async {
    if (_verbs != null) return _verbs!;
    final List<Map<String, Object?>> rows =
        await _db.query('verbs', orderBy: 'freq_rank');
    _verbs = rows
        .map(
          (Map<String, Object?> r) => Verb(
            id: r['id']! as String,
            infinitive: r['infinitive']! as String,
            auxiliary: r['auxiliary']! as String,
            pastParticiple: r['past_participle'] as String?,
            level: _levelFrom(r['level']! as String),
            ipa: r['ipa'] as String?,
            meaningEn: (r['meaning_en'] as String?) ?? '',
            meaningTr: (r['meaning_tr'] as String?) ?? '',
            freqRank: (r['freq_rank'] as int?) ?? 999999,
            isReflexive: (r['is_reflexive'] as int?) == 1,
            baseInfinitive: r['base_infinitive'] as String?,
            reflexiveKind: r['reflexive_kind'] as String?,
            noteTr: r['note_tr'] as String?,
            group: (r['group_no'] as int?) ?? 3,
            aspiratedH: (r['aspirated_h'] as int?) == 1,
            needsReview: (r['needs_review'] as int?) == 1,
          ),
        )
        .toList();
    return _verbs!;
  }

  Future<List<Verb>> byLevels(List<CefrLevel> levels, {int? limit}) async {
    final Set<CefrLevel> set = levels.toSet();
    final List<Verb> out = (await all())
        .where((Verb v) => set.contains(v.level) && !v.needsReview)
        .toList();
    if (limit != null && out.length > limit) return out.sublist(0, limit);
    return out;
  }

  /// Bir fiilin tüm çekimleri, zamana göre gruplu.
  Future<Map<VerbTense, Map<String, String>>> tablesFor(Verb verb) async {
    final List<Conjugation> list = await conjugationsFor(verb);
    final Map<VerbTense, Map<String, String>> out =
        <VerbTense, Map<String, String>>{};
    for (final Conjugation c in list) {
      out.putIfAbsent(c.tense, () => <String, String>{})[c.person] = c.form;
    }
    return out;
  }

  Future<List<Conjugation>> conjugationsFor(Verb verb) async {
    final List<Conjugation>? cached = _cache[verb.id];
    if (cached != null) return cached;

    final List<Map<String, Object?>> rows = await _db.query(
      'conjugations',
      where: 'verb_id = ?',
      whereArgs: <Object?>[verb.id],
    );
    final List<Conjugation> out = <Conjugation>[];
    for (final Map<String, Object?> r in rows) {
      final VerbTense? tense = VerbTenseX.fromKey(r['tense']! as String);
      if (tense == null) continue;
      out.add(
        Conjugation(
          verb: verb,
          tense: tense,
          person: r['person']! as String,
          form: r['form']! as String,
        ),
      );
    }
    _cache[verb.id] = out;
    return out;
  }

  /// Filtered verbs arrive in frequency order; only existing, supported
  /// persons become SRS candidates. No conjugation text is loaded here.
  Future<List<String>> conjugationRefIdsForTense(
    List<Verb> verbs,
    VerbTense tense,
  ) async {
    final List<Map<String, Object?>> rows = await _tenseRows(
      verbs.map((Verb verb) => verb.id), tense, withForms: false,
    );
    final Set<String> present = <String>{
      for (final Map<String, Object?> row in rows)
        '${row['verb_id']}:${tense.key}:${row['person']}',
    };
    return <String>[
      for (final String id in verbs.map((Verb v) => v.id).toSet())
        for (final String person in kPersons)
          if (present.contains('$id:${tense.key}:$person'))
            '$id:${tense.key}:$person',
    ];
  }

  // At most 401 SQLite parameters including the tense. This bounds each
  // query, not the candidate pool; every batch is visited.
  static const int _tenseBatchSize = 400;

  Future<List<Map<String, Object?>>> _tenseRows(
    Iterable<String> verbIds,
    VerbTense tense, {
    required bool withForms,
  }) async {
    final List<String> ids = verbIds.toSet().toList();
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (int start = 0; start < ids.length; start += _tenseBatchSize) {
      final List<String> batch = ids.sublist(
        start, (start + _tenseBatchSize).clamp(0, ids.length),
      );
      final String placeholders = List<String>.filled(batch.length, '?').join(',');
      rows.addAll(await _db.rawQuery(
        'SELECT verb_id, person${withForms ? ', form' : ''} FROM conjugations '
        'WHERE tense = ? AND verb_id IN ($placeholders) AND form IS NOT NULL',
        <Object?>[tense.key, ...batch],
      ));
    }
    return rows;
  }

  /// Loads only the requested tense, in bounded queries. Keeps the full
  /// available person table for each selected verb's card back.
  Future<List<Conjugation>> conjugationsForTense(
    List<Verb> verbs,
    VerbTense tense,
  ) async {
    final List<Map<String, Object?>> rows = await _tenseRows(
      verbs.map((Verb verb) => verb.id), tense, withForms: true,
    );
    final Map<String, Map<String, String>> grouped =
        <String, Map<String, String>>{};
    for (final Map<String, Object?> row in rows) {
      grouped.putIfAbsent(
        row['verb_id']! as String,
        () => <String, String>{},
      )[row['person']! as String] = row['form']! as String;
    }

    return <Conjugation>[
      for (final Verb verb in <String, Verb>{
        for (final Verb verb in verbs) verb.id: verb,
      }.values)
        for (final String person in kPersons)
          if (grouped[verb.id]?[person] case final String form)
            Conjugation(
              verb: verb,
              tense: tense,
              person: person,
              form: form,
            ),
    ];
  }
}

// ---------------------------------------------------------------- dersler

class LessonRepository {
  LessonRepository(this._db);

  final Database _db;
  List<GrammarLesson>? _cache;

  Future<List<GrammarLesson>> all() async {
    if (_cache != null) return _cache!;
    final List<Map<String, Object?>> rows =
        await _db.query('grammar_lessons', orderBy: 'sort_order');
    _cache = rows
        .map(
          (Map<String, Object?> r) => GrammarLesson(
            id: r['id']! as String,
            slug: r['slug']! as String,
            title: r['title_tr']! as String,
            level: _levelFrom(r['level']! as String),
            tenseKey: r['tense_key'] as String?,
            sortOrder: (r['sort_order'] as int?) ?? 0,
            bodyMd: r['body_md']! as String,
          ),
        )
        .toList();
    return _cache!;
  }
}

// ------------------------------------------------------------ ilerleme

abstract class CardStateStore {
  Map<String, SrsCard> snapshot();

  SrsCard stateFor(String refId);

  Future<void> save(SrsCard card);

  Future<void> reset();
}

/// Kart durumlarını `progress.db` içinde saklar.
/// Bellekte bir kopya tutar, böylece okuma senkron kalır.
class SqliteCardStateStore with CoordinatedProgressStore implements CardStateStore {
  SqliteCardStateStore._(this._db, this._cardType, this._states);

  final Database _db;
  final String _cardType;
  final Map<String, SrsCard> _states;

  static Future<SqliteCardStateStore> load(
    Database db, {
    String cardType = 'word',
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      'card_state',
      where: 'card_type = ?',
      whereArgs: <Object?>[cardType],
    );
    final Map<String, SrsCard> states = <String, SrsCard>{};
    for (final Map<String, Object?> r in rows) {
      final String refId = r['ref_id']! as String;
      states[refId] = _fromRow(r);
    }
    return SqliteCardStateStore._(db, cardType, states);
  }

  static SrsCard _fromRow(Map<String, Object?> r) {
    final String refId = r['ref_id']! as String;
    return SrsCard(
      refId: refId,
      box: (r['box'] as int?) ?? 0,
      status: _statusFrom(r['status'] as String?),
      starred: (r['starred'] as int?) == 1,
      dueAt: _dateFrom(r['due_at'] as int?),
      lastSeenAt: _dateFrom(r['last_seen_at'] as int?),
      timesSeen: (r['times_seen'] as int?) ?? 0,
      timesRight: (r['times_right'] as int?) ?? 0,
      lapses: (r['lapses'] as int?) ?? 0,
    );
  }

  Future<SrsCard> readState(DatabaseExecutor executor, String refId) async {
    final rows = await executor.query('card_state',
        where: 'card_type = ? AND ref_id = ?',
        whereArgs: <Object?>[_cardType, refId]);
    return rows.isEmpty ? SrsCard(refId: refId) : _fromRow(rows.single);
  }

  void publish(SrsCard card) => _states[card.refId] = card;

  @override
  Map<String, SrsCard> snapshot() => Map<String, SrsCard>.unmodifiable(_states);

  @override
  SrsCard stateFor(String refId) => _states[refId] ?? SrsCard(refId: refId);

  @override
  Future<void> save(SrsCard card) => coordinate(() async {
    await writeState(_db, card, now: DateTime.now());
    publish(card);
  });

  /// Stars the latest committed card without replacing newer SRS progress.
  Future<SrsCard> star(String refId) => coordinate(() async {
    final card = await _db.transaction((txn) async {
      final current = await readState(txn, refId);
      final starred = current.copyWith(starred: true);
      await writeState(txn, starred, now: DateTime.now());
      return starred;
    });
    publish(card);
    return card;
  });

  Future<void> writeState(DatabaseExecutor executor, SrsCard card,
      {required DateTime now}) async {
    await executor.insert(
      'card_state',
      <String, Object?>{
        'card_type': _cardType,
        'ref_id': card.refId,
        'box': card.box,
        'status': card.status.name,
        'starred': card.starred ? 1 : 0,
        'due_at': card.dueAt?.millisecondsSinceEpoch,
        'last_seen_at': card.lastSeenAt?.millisecondsSinceEpoch,
        'times_seen': card.timesSeen,
        'times_right': card.timesRight,
        'lapses': card.lapses,
        'updated_at': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> reset() => coordinate(() async {
    await _db.delete(
      'card_state',
      where: 'card_type = ?',
      whereArgs: <Object?>[_cardType],
    );
    _states.clear();
  });

  Map<int, int> boxHistogram() {
    final Map<int, int> out = <int, int>{};
    for (final SrsCard c in _states.values) {
      if (c.status == CardStatus.archived) continue;
      out[c.box] = (out[c.box] ?? 0) + 1;
    }
    return out;
  }

  List<SrsCard> leeches() => _states.values
      .where((SrsCard c) => c.status != CardStatus.archived && c.isLeech)
      .toList();

  List<SrsCard> starred() => _states.values
      .where((SrsCard c) => c.status != CardStatus.archived && c.starred)
      .toList();

  /// Quiz havuzu: kutu 1 ve üzeri, arşivlenmemiş kartlar.
  List<SrsCard> quizPool() =>
      _states.values.where((SrsCard c) => c.isQuizEligible).toList();
}

CardStatus _statusFrom(String? name) {
  for (final CardStatus s in CardStatus.values) {
    if (s.name == name) return s;
  }
  return CardStatus.fresh;
}

DateTime? _dateFrom(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

/// Basit anahtar-değer ayar deposu.
class SettingsStore with CoordinatedProgressStore {
  SettingsStore(this._db, this._cache);

  final Database _db;
  final Map<String, String> _cache;

  static Future<SettingsStore> load(Database db) async {
    final List<Map<String, Object?>> rows = await db.query('app_settings');
    return SettingsStore(db, <String, String>{
      for (final Map<String, Object?> r in rows)
        r['key']! as String: r['value']! as String,
    });
  }

  String? get(String key) => _cache[key];

  int? getInt(String key) => int.tryParse(_cache[key] ?? '');

  bool getBool(String key, {bool fallback = false}) {
    final String? v = _cache[key];
    if (v == null) return fallback;
    return v == '1';
  }

  Future<void> set(String key, String value) => coordinate(() async {
    await _db.insert(
      'app_settings',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _cache[key] = value;
  });

  Future<void> setBool(String key, bool value) => set(key, value ? '1' : '0');

  Future<void> setInt(String key, int value) => set(key, '$value');
}

// ------------------------------------------------------------ gunluk istatistik

/// Günlük kart ve quiz sayaçları. Seri (streak) buradan hesaplanır.
class DailyStatsStore with CoordinatedProgressStore {
  DailyStatsStore(this._db, this._days);

  final Database _db;

  /// gün (YYYY-MM-DD) -> satır
  final Map<String, Map<String, int>> _days;

  static String keyFor(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static Future<DailyStatsStore> load(Database db) async {
    final List<Map<String, Object?>> rows =
        await db.query('daily_stats', orderBy: 'day DESC', limit: 400);
    final Map<String, Map<String, int>> days = <String, Map<String, int>>{};
    for (final Map<String, Object?> r in rows) {
      days[r['day']! as String] = <String, int>{
        'cards_swiped': (r['cards_swiped'] as int?) ?? 0,
        'new_learned': (r['new_learned'] as int?) ?? 0,
        'quiz_total': (r['quiz_total'] as int?) ?? 0,
        'quiz_correct': (r['quiz_correct'] as int?) ?? 0,
      };
    }
    return DailyStatsStore(db, days);
  }

  Map<String, int> today() =>
      _days[keyFor(DateTime.now())] ??
      <String, int>{
        'cards_swiped': 0,
        'new_learned': 0,
        'quiz_total': 0,
        'quiz_correct': 0,
      };

  Map<String, int>? forDay(DateTime d) => _days[keyFor(d)];

  /// Bugünden geriye doğru kesintisiz gün sayısı.
  /// Bugün henüz çalışılmadıysa dünden başlar, böylece gün ortasında
  /// seri sıfırlanmış gibi görünmez.
  int streak() {
    final DateTime now = DateTime.now();
    int count = 0;
    for (int i = 0; i < 400; i++) {
      final DateTime day = DateTime(now.year, now.month, now.day - i);
      final Map<String, int>? row = _days[keyFor(day)];
      final bool active = row != null && (row['cards_swiped'] ?? 0) > 0;
      if (active) {
        count++;
      } else if (i > 0) {
        break;
      }
    }
    return count;
  }

  Future<void> add({
    int swiped = 0,
    int newLearned = 0,
    int quizTotal = 0,
    int quizCorrect = 0,
    DateTime? now,
  }) => coordinate(() async {
    final DateTime at = (now ?? DateTime.now()).toLocal();
    final row = await _db.transaction((txn) => writeAdd(txn,
        now: at,
        swiped: swiped,
        newLearned: newLearned,
        quizTotal: quizTotal,
        quizCorrect: quizCorrect));
    publish(at, row);
  });

  static Future<Map<String, int>> writeAdd(
    DatabaseExecutor executor, {
    required DateTime now,
    int swiped = 0,
    int newLearned = 0,
    int quizTotal = 0,
    int quizCorrect = 0,
  }) async {
    final String day = keyFor(now);
    final rows = await executor
        .query('daily_stats', where: 'day = ?', whereArgs: <Object?>[day]);
    final Map<String, Object?> before =
        rows.isEmpty ? <String, Object?>{} : rows.single;
    final row = <String, int>{
      'cards_swiped': (before['cards_swiped'] as int? ?? 0) + swiped,
      'new_learned': (before['new_learned'] as int? ?? 0) + newLearned,
      'quiz_total': (before['quiz_total'] as int? ?? 0) + quizTotal,
      'quiz_correct': (before['quiz_correct'] as int? ?? 0) + quizCorrect,
    };
    await executor.insert('daily_stats', <String, Object?>{'day': day, ...row},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return row;
  }

  void publish(DateTime now, Map<String, int> row) {
    _days[keyFor(now)] = Map<String, int>.of(row);
  }

  /// Son [days] günün kart sayısı, eskiden yeniye.
  List<int> recent(int days) {
    final DateTime now = DateTime.now();
    return <int>[
      for (int i = days - 1; i >= 0; i--)
        _days[keyFor(DateTime(now.year, now.month, now.day - i))]
                ?['cards_swiped'] ??
            0,
    ];
  }
}

// -------------------------------------------------------- hata bildirimleri

/// Kullanıcının "bu kartta hata var" dediği kayıtlar.
///
/// Otomatik üretilen içerikte hata kaçınılmaz. Bu düğme temizliği zamana
/// yayar: işaretlenen kelimeler `content/overrides/manual.json` dosyasına
/// eklenecek adayların listesidir.
class FlagStore with CoordinatedProgressStore {
  FlagStore(this._db, this._flagged);

  final Database _db;
  final Set<String> _flagged;

  static Future<FlagStore> load(Database db) async {
    final List<Map<String, Object?>> rows =
        await db.query('flagged_cards', columns: <String>['ref_id']);
    return FlagStore(
      db,
      <String>{
        for (final Map<String, Object?> r in rows) r['ref_id']! as String
      },
    );
  }

  bool isFlagged(String refId) => _flagged.contains(refId);

  int get count => _flagged.length;

  Future<void> toggle({
    required String refId,
    required String cardType,
    String? lemma,
    String? reason,
  }) => coordinate(() async {
    if (_flagged.contains(refId)) {
      await _db.delete(
        'flagged_cards',
        where: 'ref_id = ?',
        whereArgs: <Object?>[refId],
      );
      _flagged.remove(refId);
      return;
    }
    await _db.insert('flagged_cards', <String, Object?>{
      'card_type': cardType,
      'ref_id': refId,
      'lemma': lemma,
      'reason': reason,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    _flagged.add(refId);
  });

  /// Dışa aktarma için: işaretli kayıtların listesi.
  Future<List<Map<String, Object?>>> all() =>
      _db.query('flagged_cards', orderBy: 'created_at DESC');
}

// --------------------------------------------------------------- yolculuk

/// Prepared canonical result; no cache is changed until publication.
class JourneyRecordPlan {
  const JourneyRecordPlan(this.previous, this.next);
  final StationResult? previous;
  final StationResult next;
}

/// Harita ilerlemesi. Durak tanımları içerikten üretilir, burada yalnızca
/// sonuç durur: hangi durak kaç yıldızla geçildi.
class JourneyStore with CoordinatedProgressStore {
  JourneyStore(this._db, Map<String, StationResult> results)
      : _results = _canonicalResults(results.values);

  static Map<String, StationResult> _canonicalResults(
      Iterable<StationResult> results) {
    // Canonical rows win exact ties. The raw-ID tie-breaker makes this
    // independent of SQLite row order; bestOf keeps each attempt's score pair.
    final List<StationResult> ordered = results.toList()
      ..sort((StationResult a, StationResult b) {
        final bool aAlias =
            canonicalJourneyStationId(a.stationId) != a.stationId;
        final bool bAlias =
            canonicalJourneyStationId(b.stationId) != b.stationId;
        if (aAlias != bAlias) return aAlias ? 1 : -1;
        return a.stationId.compareTo(b.stationId);
      });
    final Map<String, StationResult> canonical = <String, StationResult>{};
    for (final StationResult result in ordered) {
      final String id = canonicalJourneyStationId(result.stationId);
      final StationResult attempt = StationResult(
        stationId: id,
        stars: result.stars,
        bestCorrect: result.bestCorrect,
        bestTotal: result.bestTotal,
      );
      canonical[id] = StationResult.bestOf(canonical[id], attempt);
    }
    // Only the in-memory view is deduplicated. Raw backup rows and historical
    // profile counters are deliberately not rewritten or reconciled here.
    return canonical;
  }

  final Database _db;
  final Map<String, StationResult> _results;

  static Future<JourneyStore> load(Database db) async {
    final List<Map<String, Object?>> rows = await db.query('journey_progress');
    return JourneyStore(db, <String, StationResult>{
      for (final Map<String, Object?> r in rows)
        r['station_id']! as String: StationResult(
          stationId: r['station_id']! as String,
          stars: (r['stars'] as int?) ?? 0,
          bestCorrect: (r['best_correct'] as int?) ?? 0,
          bestTotal: (r['best_total'] as int?) ?? 0,
        ),
    });
  }

  StationResult? resultFor(String stationId) =>
      _results[canonicalJourneyStationId(stationId)];

  int get passedCount =>
      _results.values.where((StationResult r) => r.passed).length;

  int get totalStars =>
      _results.values.fold(0, (int sum, StationResult r) => sum + r.stars);

  /// Sonucu kaydeder. Daha kötü bir sonuç öncekini silmez: bir durağı
  /// tekrar oynayıp düşük skor almak kazanılanı geri almamalı.
  Future<StationResult> record({
    required String stationId,
    required int stars,
    required int correct,
    required int total,
  }) => coordinate(() async {
    final plan = prepareRecord(
        stationId: stationId, stars: stars, correct: correct, total: total);
    await writeRecord(_db, plan);
    publishRecord(plan);
    return plan.next;
  });

  /// Prepare under coordinator admission; publish only after persistence.
  JourneyRecordPlan prepareRecord({
    required String stationId,
    required int stars,
    required int correct,
    required int total,
  }) {
    stationId = canonicalJourneyStationId(stationId);
    final StationResult? old = _results[stationId];
    final StationResult next = StationResult.bestOf(
      old,
      StationResult(
        stationId: stationId,
        stars: stars,
        bestCorrect: correct,
        bestTotal: total,
      ),
    );
    return JourneyRecordPlan(old, next);
  }

  Future<void> writeRecord(
      DatabaseExecutor executor, JourneyRecordPlan plan, {DateTime? now}) async {
    final next = plan.next;
    await executor.insert(
      'journey_progress',
      <String, Object?>{
        'station_id': next.stationId,
        'stars': next.stars,
        'best_correct': next.bestCorrect,
        'best_total': next.bestTotal,
        'updated_at': (now ?? DateTime.now()).millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Caller must await the enclosing transaction before publishing.
  void publishRecord(JourneyRecordPlan plan) =>
      _results[plan.next.stationId] = plan.next;
}

// ------------------------------------------------------------ oyun profili

/// Transaction içinde hazırlanır; yalnız commit sonrası cache'e yayımlanır.
class GameSnapshot {
  GameSnapshot(this.profile, List<DailyQuest> quests, Set<String> unlocked)
      : quests = List.unmodifiable(quests),
        unlocked = Set.unmodifiable(unlocked);
  final GameProfile profile;
  final List<DailyQuest> quests;
  final Set<String> unlocked;
}

class GameUpdate {
  const GameUpdate(this.snapshot, this.reward);
  final GameSnapshot snapshot;
  final GameReward reward;
}

/// XP, coin, günlük görev ve başarımların ortak yazma hesapları.
/// Standalone record veya çağıranın transaction executor'ı ile çalışır.
class GameStore with CoordinatedProgressStore {
  GameStore._(
    this._db,
    this._profile,
    this._quests,
    this._unlocked,
  );

  final Database _db;
  GameProfile _profile;
  List<DailyQuest> _quests;
  final Set<String> _unlocked;

  static Future<GameStore> load(Database db) async {
    final String day = DailyStatsStore.keyFor(DateTime.now());
    await db.insert(
      'game_profile',
      <String, Object?>{
        'id': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _seedDay(db, day);
    final GameStore store = GameStore._(
      db,
      const GameProfile.empty(),
      const <DailyQuest>[],
      <String>{},
    );
    await store._reload();
    return store;
  }

  static Future<void> _seedDay(DatabaseExecutor db, String day) async {
    const List<(String, QuestKind, int, int, int)> seeds =
        <(String, QuestKind, int, int, int)>[
      ('cards', QuestKind.cards, 12, 80, 8),
      ('quiz', QuestKind.quiz, 8, 100, 10),
      ('verbs', QuestKind.verbs, 6, 90, 9),
    ];
    for (final (String id, QuestKind kind, int target, int xp, int coins)
        in seeds) {
      await db.insert(
        'daily_quests',
        <String, Object?>{
          'day': day,
          'quest_id': id,
          'kind': kind.key,
          'target': target,
          'progress': 0,
          'reward_xp': xp,
          'reward_coins': coins,
          'claimed': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  GameProfile get profile => _profile;
  List<DailyQuest> get quests => List<DailyQuest>.unmodifiable(_quests);
  Set<String> get unlockedAchievements => Set<String>.unmodifiable(_unlocked);

  Future<void> _reload() async =>
      publish(await readSnapshot(_db, DateTime.now()));

  void publish(GameSnapshot snapshot) {
    _profile = snapshot.profile;
    _quests = snapshot.quests;
    _unlocked
      ..clear()
      ..addAll(snapshot.unlocked);
  }

  /// Runs one progress transaction; callers must use its executor throughout.
  Future<T> transaction<T>(Future<T> Function(Transaction) action) =>
      _db.transaction(action);

  static Future<GameSnapshot> readSnapshot(
      DatabaseExecutor executor, DateTime now) async {
    final Map<String, Object?> row =
        (await executor.query('game_profile', where: 'id = 1')).single;
    final profile = _profileFrom(row);
    final String day = DailyStatsStore.keyFor(now);
    final List<Map<String, Object?>> questRows = await executor.query(
      'daily_quests',
      where: 'day = ?',
      whereArgs: <Object?>[day],
      orderBy: 'quest_id',
    );
    final quests = <DailyQuest>[
      for (final Map<String, Object?> q in questRows)
        DailyQuest(
          id: q['quest_id']! as String,
          kind: QuestKindX.fromKey(q['kind']! as String),
          target: q['target']! as int,
          progress: q['progress']! as int,
          rewardXp: q['reward_xp']! as int,
          rewardCoins: q['reward_coins']! as int,
          claimed: (q['claimed']! as int) == 1,
        ),
    ];
    final List<Map<String, Object?>> achievementRows =
        await executor.query('achievements');
    return GameSnapshot(profile, quests,
        achievementRows.map((a) => a['achievement_id']! as String).toSet());
  }

  Future<GameReward> record({
    int cards = 0,
    int newLearned = 0,
    int quizTotal = 0,
    int quizCorrect = 0,
    int verbs = 0,
    int combo = 0,
    int stationStars = 0,
    bool stationPassed = false,
    int bonusXp = 0,
    int bonusCoins = 0,
    DateTime? now,
  }) => coordinate(() async {
    final DateTime at = (now ?? DateTime.now()).toLocal();
    final GameUpdate update = await transaction((txn) => writeRecord(txn,
        now: at,
        cards: cards,
        newLearned: newLearned,
        quizTotal: quizTotal,
        quizCorrect: quizCorrect,
        verbs: verbs,
        combo: combo,
        stationStars: stationStars,
        stationPassed: stationPassed,
        bonusXp: bonusXp,
        bonusCoins: bonusCoins));
    publish(update.snapshot);
    return update.reward;
  });

  static Future<GameUpdate> writeRecord(
    DatabaseExecutor txn, {
    required DateTime now,
    int cards = 0,
    int newLearned = 0,
    int quizTotal = 0,
    int quizCorrect = 0,
    int verbs = 0,
    int combo = 0,
    int stationStars = 0,
    bool stationPassed = false,
    int bonusXp = 0,
    int bonusCoins = 0,
  }) async {
    if (cards == 0 &&
        newLearned == 0 &&
        quizTotal == 0 &&
        verbs == 0 &&
        stationStars == 0 &&
        !stationPassed &&
        bonusXp == 0 &&
        bonusCoins == 0) {
      return GameUpdate(await readSnapshot(txn, now), const GameReward.none());
    }

    final GameSnapshot before = await readSnapshot(txn, now);
    final int oldLevel = before.profile.playerLevel;
    final String today = DailyStatsStore.keyFor(now);
    await _seedDay(txn, today);
    int earnedXp = bonusXp +
        cards * 4 +
        newLearned * 8 +
        quizCorrect * 12 +
        (quizTotal - quizCorrect).clamp(0, quizTotal) * 2 +
        verbs * 3 +
        stationStars * 20;
    int earnedCoins =
        bonusCoins + newLearned * 2 + quizCorrect + stationStars * 8;
    final List<String> completed = <String>[];
    final List<String> achievements = <String>[];

    final Map<String, Object?> row =
        (await txn.query('game_profile', where: 'id = 1')).single;
    int xp = row['xp']! as int;
    int coins = row['coins']! as int;
    final int totalCards = (row['total_cards']! as int) + cards;
    final int totalVerbs = (row['total_verbs']! as int) + verbs;
    final int totalCorrect = (row['total_correct']! as int) + quizCorrect;
    final int totalAnswers = (row['total_answers']! as int) + quizTotal;
    final int bestCombo =
        combo > (row['best_combo']! as int) ? combo : row['best_combo']! as int;
    final int stationsPassed =
        (row['stations_passed']! as int) + (stationPassed ? 1 : 0);

    final List<Map<String, Object?>> questRows = await txn.query(
      'daily_quests',
      where: 'day = ?',
      whereArgs: <Object?>[today],
    );
    for (final Map<String, Object?> quest in questRows) {
      final QuestKind kind = QuestKindX.fromKey(quest['kind']! as String);
      final int delta = switch (kind) {
        QuestKind.cards => cards,
        QuestKind.quiz => quizTotal,
        QuestKind.verbs => verbs,
      };
      if (delta == 0) continue;
      final int progress = (quest['progress']! as int) + delta;
      bool claimed = (quest['claimed']! as int) == 1;
      if (!claimed && progress >= (quest['target']! as int)) {
        claimed = true;
        final int questXp = quest['reward_xp']! as int;
        final int questCoins = quest['reward_coins']! as int;
        earnedXp += questXp;
        earnedCoins += questCoins;
        completed.add(kind.title);
      }
      await txn.update(
        'daily_quests',
        <String, Object?>{
          'progress': progress,
          'claimed': claimed ? 1 : 0,
        },
        where: 'day = ? AND quest_id = ?',
        whereArgs: <Object?>[today, quest['quest_id']],
      );
    }

    xp += earnedXp;
    coins += earnedCoins;
    final GameProfile next = GameProfile(
      xp: xp,
      coins: coins,
      bestCombo: bestCombo,
      totalCards: totalCards,
      totalVerbs: totalVerbs,
      totalCorrect: totalCorrect,
      totalAnswers: totalAnswers,
      stationsPassed: stationsPassed,
    );
    for (final AchievementDefinition achievement in gameAchievements) {
      if (before.unlocked.contains(achievement.id) ||
          !_achievementReached(achievement.id, next)) {
        continue;
      }
      await txn.insert(
        'achievements',
        <String, Object?>{
          'achievement_id': achievement.id,
          'unlocked_at': now.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      achievements.add(achievement.title);
    }

    await txn.update(
      'game_profile',
      <String, Object?>{
        'xp': xp,
        'coins': coins,
        'best_combo': bestCombo,
        'total_cards': totalCards,
        'total_verbs': totalVerbs,
        'total_correct': totalCorrect,
        'total_answers': totalAnswers,
        'stations_passed': stationsPassed,
        'updated_at': now.millisecondsSinceEpoch,
      },
      where: 'id = 1',
    );
    final GameSnapshot snapshot = await readSnapshot(txn, now);
    return GameUpdate(
        snapshot,
        GameReward(
          xp: earnedXp,
          coins: earnedCoins,
          completedQuests: completed,
          unlockedAchievements: achievements,
          levelUp: snapshot.profile.playerLevel > oldLevel,
        ));
  }

  static GameProfile _profileFrom(Map<String, Object?> row) => GameProfile(
        xp: row['xp']! as int,
        coins: row['coins']! as int,
        bestCombo: row['best_combo']! as int,
        totalCards: row['total_cards']! as int,
        totalVerbs: row['total_verbs']! as int,
        totalCorrect: row['total_correct']! as int,
        totalAnswers: row['total_answers']! as int,
        stationsPassed: row['stations_passed']! as int,
      );

  static bool _achievementReached(String id, GameProfile profile) =>
      switch (id) {
        'first_card' => profile.totalCards >= 1,
        'cards_100' => profile.totalCards >= 100,
        'verbs_50' => profile.totalVerbs >= 50,
        'combo_10' => profile.bestCombo >= 10,
        'station_5' => profile.stationsPassed >= 5,
        'xp_2500' => profile.xp >= 2500,
        _ => false,
      };
}

// ------------------------------------------------------------ pratik ilerlemesi

/// Prepared completion and its still-unconsumed first-completion result.
class StoryCompletionPlan {
  const StoryCompletionPlan(this.previous, this.next, this.firstCompletion);
  final StoryProgress? previous;
  final StoryProgress next;
  final bool firstCompletion;
}

/// Prepared attempt and its still-unconsumed first-solve result.
class SentenceRecordPlan {
  const SentenceRecordPlan(this.previous, this.next, this.firstSolve);
  final SentenceProgress? previous;
  final SentenceProgress next;
  final bool firstSolve;
}

/// Hikâye ve serbest cümle çalışmalarının kalıcı ilerlemesi.
class PracticeStore with CoordinatedProgressStore {
  PracticeStore._(this._db, this._stories, this._sentences);

  final Database _db;
  final Map<String, StoryProgress> _stories;
  final Map<String, SentenceProgress> _sentences;

  static Future<PracticeStore> load(Database db) async {
    final List<Map<String, Object?>> storyRows =
        await db.query('story_progress');
    final List<Map<String, Object?>> sentenceRows =
        await db.query('sentence_progress');
    return PracticeStore._(
      db,
      <String, StoryProgress>{
        for (final Map<String, Object?> row in storyRows)
          row['story_id']! as String: StoryProgress(
            storyId: row['story_id']! as String,
            nodeId: row['node_id']! as String,
            completed: (row['completed']! as int) == 1,
            bestCorrect: row['best_correct']! as int,
            bestTotal: row['best_total']! as int,
          ),
      },
      <String, SentenceProgress>{
        for (final Map<String, Object?> row in sentenceRows)
          row['prompt_id']! as String: SentenceProgress(
            promptId: row['prompt_id']! as String,
            attempts: row['attempts']! as int,
            solved: (row['solved']! as int) == 1,
            bestScore: row['best_score']! as int,
          ),
      },
    );
  }

  Map<String, StoryProgress> get stories =>
      Map<String, StoryProgress>.unmodifiable(_stories);
  Map<String, SentenceProgress> get sentences =>
      Map<String, SentenceProgress>.unmodifiable(_sentences);

  StoryProgress? story(String id) => _stories[id];
  SentenceProgress? sentence(String id) => _sentences[id];

  Future<void> saveStoryNode(String storyId, String nodeId) => coordinate(() async {
    final StoryProgress old = _stories[storyId] ??
        StoryProgress(
          storyId: storyId,
          nodeId: nodeId,
          completed: false,
          bestCorrect: 0,
          bestTotal: 0,
        );
    final StoryProgress next = StoryProgress(
      storyId: storyId,
      nodeId: nodeId,
      completed: old.completed,
      bestCorrect: old.bestCorrect,
      bestTotal: old.bestTotal,
    );
    await writeStory(_db, next);
    _stories[storyId] = next;
  });

  /// İlk tamamlamada true döner. Daha düşük tekrar skoru en iyi skoru silmez.
  Future<bool> completeStory({
    required String storyId,
    required String nodeId,
    required int correct,
    required int total,
  }) => coordinate(() async {
    final plan = prepareStoryCompletion(
        storyId: storyId, nodeId: nodeId, correct: correct, total: total);
    await writeStory(_db, plan.next);
    publishStory(plan.next);
    return plan.firstCompletion;
  });

  /// Prepare under coordinator admission without changing the cache.
  StoryCompletionPlan prepareStoryCompletion({
    required String storyId,
    required String nodeId,
    required int correct,
    required int total,
  }) {
    final StoryProgress? old = _stories[storyId];
    final bool first = !(old?.completed ?? false);
    final bool better = old == null ||
        total > 0 &&
            correct / total >
                old.bestCorrect / (old.bestTotal == 0 ? 1 : old.bestTotal);
    final StoryProgress next = StoryProgress(
      storyId: storyId,
      nodeId: nodeId,
      completed: true,
      bestCorrect: better ? correct : old.bestCorrect,
      bestTotal: better ? total : old.bestTotal,
    );
    return StoryCompletionPlan(old, next, first);
  }

  Future<void> writeStory(
      DatabaseExecutor executor, StoryProgress progress) async {
    await executor.insert(
      'story_progress',
      <String, Object?>{
        'story_id': progress.storyId,
        'node_id': progress.nodeId,
        'completed': progress.completed ? 1 : 0,
        'best_correct': progress.bestCorrect,
        'best_total': progress.bestTotal,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// İlk doğru çözümde true döner; bonus ödül böylece tekrar oynanarak çoğalmaz.
  Future<bool> recordSentence({
    required String promptId,
    required bool solved,
    required int score,
  }) => coordinate(() async {
    final plan = prepareSentenceRecord(
        promptId: promptId, solved: solved, score: score);
    await writeSentence(_db, plan.next);
    publishSentence(plan.next);
    return plan.firstSolve;
  });

  /// Prepare under coordinator admission without consuming an attempt/bonus.
  SentenceRecordPlan prepareSentenceRecord({
    required String promptId,
    required bool solved,
    required int score,
  }) {
    final SentenceProgress? old = _sentences[promptId];
    final bool firstSolve = solved && !(old?.solved ?? false);
    final SentenceProgress next = SentenceProgress(
      promptId: promptId,
      attempts: (old?.attempts ?? 0) + 1,
      solved: (old?.solved ?? false) || solved,
      bestScore: score > (old?.bestScore ?? 0) ? score : (old?.bestScore ?? 0),
    );
    return SentenceRecordPlan(old, next, firstSolve);
  }

  Future<void> writeSentence(
      DatabaseExecutor executor, SentenceProgress next) async {
    await executor.insert(
      'sentence_progress',
      <String, Object?>{
        'prompt_id': next.promptId,
        'attempts': next.attempts,
        'solved': next.solved ? 1 : 0,
        'best_score': next.bestScore,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Call only after the enclosing persistence operation has succeeded.
  void publishStory(StoryProgress next) => _stories[next.storyId] = next;
  void publishSentence(SentenceProgress next) => _sentences[next.promptId] = next;
}
