import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../data/repositories.dart';
import '../data/backup.dart';
import '../data/progress_coordinator.dart';
import '../domain/companion.dart';
import '../domain/game.dart';
import '../domain/level.dart';
import '../domain/srs/box_scheduler.dart';
import '../domain/srs/srs_card.dart';
import '../motion/motion_tokens.dart';

enum AnswerCardType { word, conjugation }

class AnswerResult {
  const AnswerResult(this.before, this.after, this.reward, this.newLearned);
  final SrsCard before;
  final SrsCard after;
  final GameReward reward;
  final bool newLearned;
}

/// Uygulama genelindeki durum ve ayarlar.
///
/// Ayarlar ve kart ilerlemesi `progress.db` içinde kalıcıdır; uygulama
/// kapanıp açıldığında kaldığı yerden devam eder.
class AppState extends ChangeNotifier {
  AppState._({
    required this.db,
    required this.words,
    required SqliteCardStateStore cards,
    required SqliteCardStateStore verbCards,
    required this.verbs,
    required this.lessons,
    required SettingsStore settings,
    required DailyStatsStore stats,
    required FlagStore flags,
    required JourneyStore journey,
    required GameStore game,
    required PracticeStore practice,
    required this.contentMeta,
  }) : _cards = cards,
       _verbCards = verbCards,
       _settings = settings,
       _stats = stats,
       _flags = flags,
       _journey = journey,
       _game = game,
       _practice = practice {
    for (final store in <CoordinatedProgressStore>[cards, verbCards, settings, stats, flags, journey, game, practice]) {
      store.bindProgress(progress);
    }
    _applySettings();
  }

  static const String _kLevel = 'level';
  static const String _kGoal = 'daily_goal';
  static const String _kMix = 'mix_lower_levels';
  static const String _kOnboarding = 'onboarding_done';
  static const String _kSentence = 'sentence_on_front';
  static const String _kSpeed = 'speed_index';
  static const String _kReducedMotion = 'reduced_motion';
  static const String _kCompanion = 'companion_kind';
  static const String _kCompanionAccessory = 'companion_accessory';
  static const String _kCompanionPalette = 'companion_palette';

  final AppDatabase db;
  final SqliteWordRepository words;
  SqliteCardStateStore _cards;
  SqliteCardStateStore get cards => _cards;
  set cards(SqliteCardStateStore value) {
    value.bindProgress(progress);
    _cards = value;
  }
  SqliteCardStateStore _verbCards;
  SqliteCardStateStore get verbCards => _verbCards;
  set verbCards(SqliteCardStateStore value) {
    value.bindProgress(progress);
    _verbCards = value;
  }
  final VerbRepository verbs;
  final LessonRepository lessons;
  SettingsStore _settings;
  SettingsStore get settings => _settings;
  set settings(SettingsStore value) {
    value.bindProgress(progress);
    _settings = value;
  }
  DailyStatsStore _stats;
  DailyStatsStore get stats => _stats;
  set stats(DailyStatsStore value) {
    value.bindProgress(progress);
    _stats = value;
  }
  FlagStore _flags;
  FlagStore get flags => _flags;
  set flags(FlagStore value) {
    value.bindProgress(progress);
    _flags = value;
  }
  JourneyStore _journey;
  JourneyStore get journey => _journey;
  set journey(JourneyStore value) {
    value.bindProgress(progress);
    _journey = value;
  }
  GameStore _game;
  GameStore get game => _game;
  set game(GameStore value) {
    value.bindProgress(progress);
    _game = value;
  }
  PracticeStore _practice;
  PracticeStore get practice => _practice;
  set practice(PracticeStore value) {
    value.bindProgress(progress);
    _practice = value;
  }
  final Map<String, String> contentMeta;

  static const List<double> speeds = <double>[0.75, 1.0, 1.25];

  late CefrLevel _level;
  late int _dailyGoal;
  late bool _mixLowerLevels;
  late bool _onboardingDone;
  late bool _showSentenceOnFront;
  late int _speedIndex;
  late bool _reducedMotion;
  late CompanionKind _companion;
  late CompanionAccessory _companionAccessory;
  late CompanionPalette _companionPalette;
  GameReward _lastReward = const GameReward.none();
  int _rewardSerial = 0;
  final ProgressCoordinator progress = ProgressCoordinator();
  int get progressGeneration => progress.generation;
  bool get recoveryRequired => progress.recoveryRequired;
  Future<void>? _closeFuture;
  bool _disposed = false;

  static Future<AppState> create() async {
    final AppDatabase database = await AppDatabase.open();
    try {
      final SqliteWordRepository words =
          await SqliteWordRepository.load(database.content);
      final SqliteCardStateStore cards =
          await SqliteCardStateStore.load(database.progress);
      final SqliteCardStateStore verbCards = await SqliteCardStateStore.load(
        database.progress,
        cardType: 'conjugation',
      );
      final SettingsStore settings =
          await SettingsStore.load(database.progress);
      final DailyStatsStore stats =
          await DailyStatsStore.load(database.progress);
      final FlagStore flags = await FlagStore.load(database.progress);
      final JourneyStore journey = await JourneyStore.load(database.progress);
      final GameStore game = await GameStore.load(database.progress);
      final PracticeStore practice =
          await PracticeStore.load(database.progress);
      final Map<String, String> meta = await database.meta();

      return AppState._(
        db: database,
        words: words,
        cards: cards,
        verbCards: verbCards,
        verbs: VerbRepository(database.content),
        lessons: LessonRepository(database.content),
        settings: settings,
        stats: stats,
        flags: flags,
        journey: journey,
        game: game,
        practice: practice,
        contentMeta: meta,
      );
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  CefrLevel get level => _level;
  int get dailyGoal => _dailyGoal;
  bool get mixLowerLevels => _mixLowerLevels;
  bool get onboardingDone => _onboardingDone;
  bool get showSentenceOnFront => _showSentenceOnFront;
  double get speed => speeds[_speedIndex];
  String get speedLabel => '${speeds[_speedIndex]}x';
  bool get reducedMotion => _reducedMotion;
  GameReward get lastReward => _lastReward;
  int get rewardSerial => _rewardSerial;
  CompanionKind get companion => _companion;
  CompanionAccessory get companionAccessory => _companionAccessory;
  CompanionPalette get companionPalette => _companionPalette;
  CompanionGrowth get companionGrowth => CompanionGrowth.forXp(game.profile.xp);

  /// Deste kurulurken kullanılacak seviyeler.
  List<CefrLevel> get activeLevels =>
      _mixLowerLevels ? _level.thisAndBelow : <CefrLevel>[_level];

  int get wordCount => words.all().length;

  Future<void> setLevel(CefrLevel value) => _enqueueProgressWrite(() async {
    if (_level == value) return;
    await settings.set(_kLevel, value.code);
    _level = value;
    _notify();
  
  });

  Future<void> setDailyGoal(int value) => _enqueueProgressWrite(() async {
    final int safeValue = value.clamp(5, 100);
    if (_dailyGoal == safeValue) return;
    await settings.setInt(_kGoal, safeValue);
    _dailyGoal = safeValue;
    _notify();
  
  });

  Future<void> setMixLowerLevels(bool value) => _enqueueProgressWrite(() async {
    if (_mixLowerLevels == value) return;
    await settings.setBool(_kMix, value);
    _mixLowerLevels = value;
    _notify();
  
  });

  Future<void> setShowSentenceOnFront(bool value) => _enqueueProgressWrite(() async {
    if (_showSentenceOnFront == value) return;
    await settings.setBool(_kSentence, value);
    _showSentenceOnFront = value;
    _notify();
  
  });

  Future<void> completeOnboarding() => _enqueueProgressWrite(() async {
    await settings.setBool(_kOnboarding, true);
    _onboardingDone = true;
    _notify();
  
  });

  Future<void> cycleSpeed() => _enqueueProgressWrite(() async {
    final next = (_speedIndex + 1) % speeds.length;
    await settings.setInt(_kSpeed, next);
    _speedIndex = next;
    MotionTokens.speedScale = speeds[next];
    _notify();
  });

  Future<void> setReducedMotion(bool value) => _enqueueProgressWrite(() async {
    if (_reducedMotion == value) return;
    await settings.setBool(_kReducedMotion, value);
    _reducedMotion = value;
    MotionTokens.reducedMotion = value;
    _notify();
  
  });

  Future<void> setCompanion(CompanionKind value) => _enqueueProgressWrite(() async {
    if (value.unlockLevel > game.profile.playerLevel || _companion == value) {
      return;
    }
    await settings.set(_kCompanion, value.name);
    _companion = value;
    _notify();
  
  });

  Future<void> setCompanionAccessory(CompanionAccessory value) => _enqueueProgressWrite(() async {
    if (value.unlockLevel > game.profile.playerLevel ||
        _companionAccessory == value) {
      return;
    }
    await settings.set(_kCompanionAccessory, value.name);
    _companionAccessory = value;
    _notify();
  
  });

  Future<void> setCompanionPalette(CompanionPalette value) => _enqueueProgressWrite(() async {
    if (_companionPalette == value) return;
    await settings.set(_kCompanionPalette, value.name);
    _companionPalette = value;
    _notify();
  
  });

  /// Oturum bittiğinde ilerleme ekranının tazelenmesi için.
  void notifyProgressChanged() => _notify();

  /// Kaydırma ve quiz sonuçlarını günlük sayaca işler.
  Future<AnswerResult> recordAnswer({
    required AnswerCardType cardType,
    required String refId,
    required SwipeAction action,
    required DateTime now,
  }) {
    final DateTime at = now.toLocal();
    return _enqueueProgressWrite(() async {
      final store = cardType == AnswerCardType.word ? cards : verbCards;
      final result = await game.transaction((txn) async {
        final before = await store.readState(txn, refId);
        final after = BoxScheduler.apply(before, action, now: at);
        final learned = cardType == AnswerCardType.word &&
            before.timesSeen == 0 &&
            after.box == 1;
        await store.writeState(txn, after, now: at);
        final daily = await DailyStatsStore.writeAdd(txn,
            now: at, swiped: 1, newLearned: learned ? 1 : 0);
        final update = await GameStore.writeRecord(txn,
            now: at,
            cards: 1,
            newLearned: learned ? 1 : 0,
            verbs: cardType == AnswerCardType.conjugation ? 1 : 0);
        return (
          AnswerResult(before, after, update.reward, learned),
          daily,
          update
        );
      });
      // No reads or awaited work after COMMIT: publish prepared values only.
      store.publish(result.$1.after);
      stats.publish(at, result.$2);
      game.publish(result.$3.snapshot);
      _publishReward(result.$1.reward);
      return result.$1;
    });
  }

  /// Free quiz reads the latest committed card, then persists one whole answer.
  Future<SrsCard> recordQuizAnswer({
    required AnswerCardType cardType,
    required String refId,
    required bool correct,
    required int combo,
    required DateTime now,
  }) {
    final DateTime at = now.toLocal();
    return _enqueueProgressWrite(() async {
      final store = cardType == AnswerCardType.word ? cards : verbCards;
      final result = await game.transaction((txn) async {
        final before = await store.readState(txn, refId);
        final after = BoxScheduler.applyQuizResult(before,
            correct: correct, now: at);
        await store.writeState(txn, after, now: at);
        final daily = await DailyStatsStore.writeAdd(txn,
            now: at, quizTotal: 1, quizCorrect: correct ? 1 : 0);
        final update = await GameStore.writeRecord(txn,
            now: at, quizTotal: 1, quizCorrect: correct ? 1 : 0, combo: combo);
        return (after, daily, update);
      });
      store.publish(result.$1);
      stats.publish(at, result.$2);
      game.publish(result.$3.snapshot);
      _publishReward(result.$3.reward);
      return result.$1;
    });
  }

  Future<void> recordActivity({
    int swiped = 0,
    int newLearned = 0,
    int quizTotal = 0,
    int quizCorrect = 0,
    int verbSwiped = 0,
    int combo = 0,
    DateTime? now,
  }) {
    final DateTime at = (now ?? DateTime.now()).toLocal();
    return _enqueueProgressWrite(() async {
      final result = await game.transaction((txn) async {
        final daily = await DailyStatsStore.writeAdd(txn,
            now: at,
            swiped: swiped,
            newLearned: newLearned,
            quizTotal: quizTotal,
            quizCorrect: quizCorrect);
        final update = await GameStore.writeRecord(txn,
            now: at,
            cards: swiped,
            newLearned: newLearned,
            quizTotal: quizTotal,
            quizCorrect: quizCorrect,
            verbs: verbSwiped,
            combo: combo);
        return (daily, update);
      });
      stats.publish(at, result.$1);
      game.publish(result.$2.snapshot);
      _publishReward(result.$2.reward);
    });
  }

  /// Harita durağı sonucu kaydedildikten sonra ekranlar tazelensin.
  Future<void> recordStation({
    required String stationId,
    required int stars,
    required int correct,
    required int total,
  }) =>
      _enqueueProgressWrite(() async {
        final plan = journey.prepareRecord(
          stationId: stationId,
          stars: stars,
          correct: correct,
          total: total,
        );
        final update = await game.transaction((txn) async {
          await journey.writeRecord(txn, plan);
          return GameStore.writeRecord(txn,
            now: DateTime.now().toLocal(),
            stationStars: (plan.next.stars - (plan.previous?.stars ?? 0))
                .clamp(0, 3).toInt(),
            stationPassed: !(plan.previous?.passed ?? false) && plan.next.passed,
          );
        });
        journey.publishRecord(plan);
        game.publish(update.snapshot);
        _publishReward(update.reward, notify: false);
        _notify();
      });

  /// Final station attempt: result, station reward and quiz activity commit together.
  Future<void> completeStationQuiz({
    required String stationId,
    required int stars,
    required int correct,
    required int total,
    required int combo,
    DateTime? now,
  }) {
    final DateTime at = (now ?? DateTime.now()).toLocal();
    return _enqueueProgressWrite(() async {
      final plan = journey.prepareRecord(
        stationId: stationId, stars: stars, correct: correct, total: total,
      );
      final result = await game.transaction((txn) async {
        await journey.writeRecord(txn, plan, now: at);
        // Preserve the two existing game mutations and their reward ordering.
        // The second reads the first's writes through this same transaction.
        final station = await GameStore.writeRecord(txn,
          now: at,
          stationStars: (plan.next.stars - (plan.previous?.stars ?? 0))
              .clamp(0, 3).toInt(),
          stationPassed: !(plan.previous?.passed ?? false) && plan.next.passed,
        );
        final daily = await DailyStatsStore.writeAdd(txn,
          now: at, quizTotal: total, quizCorrect: correct,
        );
        final quiz = await GameStore.writeRecord(txn,
          now: at, quizTotal: total, quizCorrect: correct, combo: combo,
        );
        return (daily, station, quiz);
      });
      journey.publishRecord(plan);
      stats.publish(at, result.$1);
      game.publish(result.$3.snapshot);
      // Both notifications see all final caches, including the final game state.
      _publishReward(result.$2.reward);
      _publishReward(result.$3.reward);
    });
  }

  void _publishReward(GameReward reward, {bool notify = true}) {
    if (!reward.isEmpty) {
      _lastReward = reward;
      _rewardSerial++;
    }
    if (notify && !_disposed) _notify();
  }

  Future<void> saveStoryNode(String storyId, String nodeId) => _enqueueProgressWrite(() async {
    await practice.saveStoryNode(storyId, nodeId);
    _notify();
  });

  Future<void> completeStory({
    required String storyId,
    required String nodeId,
    required int correct,
    required int total,
  }) =>
      _enqueueProgressWrite(() async {
        final plan = practice.prepareStoryCompletion(
          storyId: storyId,
          nodeId: nodeId,
          correct: correct,
          total: total,
        );
        final result = await game.transaction((txn) async {
          await practice.writeStory(txn, plan.next);
          final at = DateTime.now().toLocal();
          final daily = await DailyStatsStore.writeAdd(txn,
              now: at, quizTotal: total, quizCorrect: correct);
          final update = await GameStore.writeRecord(txn,
            now: DateTime.now().toLocal(),
            quizTotal: total,
            quizCorrect: correct,
            bonusXp: plan.firstCompletion ? 40 : 0,
            bonusCoins: plan.firstCompletion ? 8 : 0,
          );
          return (at, daily, update);
        });
        practice.publishStory(plan.next);
        stats.publish(result.$1, result.$2);
        game.publish(result.$3.snapshot);
        _publishReward(result.$3.reward);
      });

  Future<void> recordSentenceAttempt({
    required String promptId,
    required bool correct,
    required int score,
    required int combo,
  }) =>
      _enqueueProgressWrite(() async {
        final plan = practice.prepareSentenceRecord(
          promptId: promptId,
          solved: correct,
          score: score,
        );
        final result = await game.transaction((txn) async {
          await practice.writeSentence(txn, plan.next);
          final at = DateTime.now().toLocal();
          final daily = await DailyStatsStore.writeAdd(txn,
              now: at, quizTotal: 1, quizCorrect: correct ? 1 : 0);
          final update = await GameStore.writeRecord(txn,
            now: DateTime.now().toLocal(),
            quizTotal: 1,
            quizCorrect: correct ? 1 : 0,
            combo: combo,
            bonusXp: plan.firstSolve ? 15 : 0,
            bonusCoins: plan.firstSolve ? 3 : 0,
          );
          return (at, daily, update);
        });
        practice.publishSentence(plan.next);
        stats.publish(result.$1, result.$2);
        game.publish(result.$3.snapshot);
        _publishReward(result.$3.reward);
      });

  Future<String> exportProgress() =>
      _enqueueProgressWrite(() => ProgressBackup.export(db.progress));

  Future<ImportReport> restoreProgress(String json) => progress.restore(() async {
        final report = await ProgressBackup.import(db.progress, json);
        // Import has committed. Never expose old caches for new writes if
        // migration or preparation now fails.
        progress.recoveryRequired = true;
        try {
          await _prepareProgress();
          progress.recoveryRequired = false;
          return report;
        } catch (error) {
          throw ProgressUnavailable(
              'Yedek veritabanına yazıldı, bellek yüklenemedi. '
              'Yeniden yükleyin veya uygulamayı yeniden açın. ($error)');
        } finally {
          _notify();
        }
      });

  Future<void> recoverProgress() => progress.recover(() async {
        await _prepareProgress();
        _notify();
      });

  Future<void> reloadProgress() => progress.restore(() async {
        // Migration can itself commit before a later cache read fails.
        progress.recoveryRequired = true;
        try {
          await _prepareProgress();
          progress.recoveryRequired = false;
        } finally {
          _notify();
        }
      });

  Future<void> _prepareProgress() async {
    await db.migrateContentIds();
    // Prepare all stores on the live Database, never retain a Transaction.
    final nextCards = await SqliteCardStateStore.load(db.progress);
    final nextVerbs = await SqliteCardStateStore.load(
        db.progress, cardType: 'conjugation');
    final nextSettings = await SettingsStore.load(db.progress);
    final nextStats = await DailyStatsStore.load(db.progress);
    final nextFlags = await FlagStore.load(db.progress);
    final nextJourney = await JourneyStore.load(db.progress);
    final nextGame = await GameStore.load(db.progress);
    final nextPractice = await PracticeStore.load(db.progress);
    // No awaits after this point: publish a single generation.
    progress.generation++;
    cards = nextCards;
    verbCards = nextVerbs;
    settings = nextSettings;
    stats = nextStats;
    flags = nextFlags;
    journey = nextJourney;
    game = nextGame;
    practice = nextPractice;
    _applySettings();
    _lastReward = const GameReward.none();
    _notify();
  }

  Future<T> _enqueueProgressWrite<T>(Future<T> Function() operation) =>
      progress.run(operation);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> close() {
    if (!_disposed) dispose();
    return _closeFuture!;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closeFuture = progress.close(db.close);
    unawaited(_closeFuture);
    super.dispose();
  }

  void _applySettings() {
    _level = _levelFromCode(settings.get(_kLevel)) ?? CefrLevel.a1;
    _dailyGoal = (settings.getInt(_kGoal) ?? 20).clamp(5, 100);
    _mixLowerLevels = settings.getBool(_kMix, fallback: true);
    _onboardingDone = settings.getBool(_kOnboarding);
    _showSentenceOnFront = settings.getBool(_kSentence, fallback: true);
    _speedIndex = (settings.getInt(_kSpeed) ?? 1).clamp(0, speeds.length - 1);
    _reducedMotion = settings.getBool(_kReducedMotion);
    _companion = CompanionKindX.fromKey(settings.get(_kCompanion));
    _companionAccessory = CompanionAccessoryX.fromKey(
      settings.get(_kCompanionAccessory),
    );
    _companionPalette = CompanionPaletteX.fromKey(
      settings.get(_kCompanionPalette),
    );
    if (_companion.unlockLevel > game.profile.playerLevel) {
      _companion = CompanionKind.lumi;
    }
    if (_companionAccessory.unlockLevel > game.profile.playerLevel) {
      _companionAccessory = CompanionAccessory.beret;
    }
    MotionTokens.speedScale = speeds[_speedIndex];
    MotionTokens.reducedMotion = _reducedMotion;
  }

  /// Kartta hata bildir / bildirimi geri al.
  Future<void> toggleFlag({
    required String refId,
    required String cardType,
    String? lemma,
  }) => _enqueueProgressWrite(() async {
    await flags.toggle(refId: refId, cardType: cardType, lemma: lemma);
    _notify();
  });

  int get streak => stats.streak();

  int get swipedToday => stats.today()['cards_swiped'] ?? 0;

  bool get goalReachedToday => swipedToday >= _dailyGoal;

  static CefrLevel? _levelFromCode(String? code) {
    if (code == null) return null;
    for (final CefrLevel l in CefrLevel.values) {
      if (l.code == code) return l;
    }
    return null;
  }
}
