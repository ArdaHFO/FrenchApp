import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/data/repositories.dart';
import 'package:french_app/domain/game.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE game_profile (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      xp INTEGER NOT NULL DEFAULT 0,
      coins INTEGER NOT NULL DEFAULT 0,
      best_combo INTEGER NOT NULL DEFAULT 0,
      total_cards INTEGER NOT NULL DEFAULT 0,
      total_verbs INTEGER NOT NULL DEFAULT 0,
      total_correct INTEGER NOT NULL DEFAULT 0,
      total_answers INTEGER NOT NULL DEFAULT 0,
      stations_passed INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE daily_quests (
      day TEXT NOT NULL,
      quest_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      target INTEGER NOT NULL,
      progress INTEGER NOT NULL DEFAULT 0,
      reward_xp INTEGER NOT NULL,
      reward_coins INTEGER NOT NULL,
      claimed INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (day, quest_id)
    )''');
    await db.execute('''CREATE TABLE achievements (
      achievement_id TEXT PRIMARY KEY,
      unlocked_at INTEGER NOT NULL
    )''');
  });

  tearDown(() => db.close());

  test('oyuncu seviyesi karesel XP eşiklerini kullanır', () {
    expect(const GameProfile.empty().playerLevel, 1);
    expect(_profile(99).playerLevel, 1);
    expect(_profile(100).playerLevel, 2);
    expect(_profile(399).playerLevel, 2);
    expect(_profile(400).playerLevel, 3);
  });

  test('günlük görev ödülü yalnız bir kez verilir ve kalıcıdır', () async {
    final GameStore game = await GameStore.load(db);
    expect(game.quests, hasLength(3));

    final GameReward first = await game.record(cards: 12, newLearned: 1);
    expect(first.completedQuests, contains('Kart avcısı'));
    expect(first.xp, 136); // 12*4 + 1*8 + 80 görev ödülü
    expect(first.coins, 10); // 2 yeni kelime ödülü + 8 görev coin'i
    expect(game.unlockedAchievements, contains('first_card'));

    final GameReward second = await game.record(cards: 1);
    expect(second.completedQuests, isEmpty);
    expect(second.xp, 4);

    final GameStore reopened = await GameStore.load(db);
    expect(reopened.profile.xp, 140);
    expect(reopened.profile.coins, 10);
    expect(
      reopened.quests.singleWhere((DailyQuest q) => q.id == 'cards').claimed,
      isTrue,
    );
  });

  test('fiil ve combo ilerlemesi profil ile göreve yazılır', () async {
    final GameStore game = await GameStore.load(db);
    final GameReward reward = await game.record(
      verbs: 6,
      quizTotal: 6,
      quizCorrect: 6,
      combo: 10,
    );

    expect(reward.completedQuests, containsAll(<String>['Fiil ustası']));
    expect(game.profile.totalVerbs, 6);
    expect(game.profile.bestCombo, 10);
    expect(game.unlockedAchievements, contains('combo_10'));
  });
}

GameProfile _profile(int xp) => GameProfile(
      xp: xp,
      coins: 0,
      bestCombo: 0,
      totalCards: 0,
      totalVerbs: 0,
      totalCorrect: 0,
      totalAnswers: 0,
      stationsPassed: 0,
    );
