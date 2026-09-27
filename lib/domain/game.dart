enum QuestKind { cards, quiz, verbs }

extension QuestKindX on QuestKind {
  String get key => name;

  String get title => switch (this) {
        QuestKind.cards => 'Kart avcısı',
        QuestKind.quiz => 'Quiz düellosu',
        QuestKind.verbs => 'Fiil ustası',
      };

  String get description => switch (this) {
        QuestKind.cards => 'kelime veya fiil kartı çalış',
        QuestKind.quiz => 'quiz sorusu çöz',
        QuestKind.verbs => 'fiil çekimi çalış',
      };

  static QuestKind fromKey(String key) => QuestKind.values.firstWhere(
        (QuestKind kind) => kind.key == key,
        orElse: () => QuestKind.cards,
      );
}

class DailyQuest {
  const DailyQuest({
    required this.id,
    required this.kind,
    required this.target,
    required this.progress,
    required this.rewardXp,
    required this.rewardCoins,
    required this.claimed,
  });

  final String id;
  final QuestKind kind;
  final int target;
  final int progress;
  final int rewardXp;
  final int rewardCoins;
  final bool claimed;

  bool get complete => progress >= target;
  double get ratio => target == 0 ? 1 : (progress / target).clamp(0, 1);
}

class GameProfile {
  const GameProfile({
    required this.xp,
    required this.coins,
    required this.bestCombo,
    required this.totalCards,
    required this.totalVerbs,
    required this.totalCorrect,
    required this.totalAnswers,
    required this.stationsPassed,
  });

  const GameProfile.empty()
      : xp = 0,
        coins = 0,
        bestCombo = 0,
        totalCards = 0,
        totalVerbs = 0,
        totalCorrect = 0,
        totalAnswers = 0,
        stationsPassed = 0;

  final int xp;
  final int coins;
  final int bestCombo;
  final int totalCards;
  final int totalVerbs;
  final int totalCorrect;
  final int totalAnswers;
  final int stationsPassed;

  int get playerLevel => levelForXp(xp);
  int get levelStartXp => 100 * (playerLevel - 1) * (playerLevel - 1);
  int get nextLevelXp => 100 * playerLevel * playerLevel;
  double get levelProgress =>
      ((xp - levelStartXp) / (nextLevelXp - levelStartXp)).clamp(0, 1);

  static int levelForXp(int xp) {
    int level = 1;
    while (100 * level * level <= xp) {
      level++;
    }
    return level;
  }
}

class GameReward {
  const GameReward({
    required this.xp,
    required this.coins,
    this.completedQuests = const <String>[],
    this.unlockedAchievements = const <String>[],
    this.levelUp = false,
  });

  const GameReward.none()
      : xp = 0,
        coins = 0,
        completedQuests = const <String>[],
        unlockedAchievements = const <String>[],
        levelUp = false;

  final int xp;
  final int coins;
  final List<String> completedQuests;
  final List<String> unlockedAchievements;
  final bool levelUp;

  bool get isEmpty =>
      xp == 0 &&
      coins == 0 &&
      completedQuests.isEmpty &&
      unlockedAchievements.isEmpty &&
      !levelUp;
}

class AchievementDefinition {
  const AchievementDefinition(this.id, this.title, this.description);

  final String id;
  final String title;
  final String description;
}

const List<AchievementDefinition> gameAchievements = <AchievementDefinition>[
  AchievementDefinition('first_card', 'İlk adım', 'İlk kartını çalıştın.'),
  AchievementDefinition('cards_100', 'Kart avcısı', '100 kart çalıştın.'),
  AchievementDefinition('verbs_50', 'Fiil çırağı', '50 fiil çekimi çalıştın.'),
  AchievementDefinition(
      'combo_10', 'Alev aldı', '10 doğru cevaplık seri yaptın.'),
  AchievementDefinition('station_5', 'Gezgin', '5 yolculuk durağını geçtin.'),
  AchievementDefinition('xp_2500', 'Fransızca savaşçısı', '2.500 XP kazandın.'),
];
