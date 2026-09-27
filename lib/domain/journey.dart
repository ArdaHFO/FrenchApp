import 'level.dart';

/// Haritadaki bir durağın türü.
enum StationKind { words, idioms, verbs, boss }

extension StationKindX on StationKind {
  String get labelTr => switch (this) {
        StationKind.words => 'Kelime',
        StationKind.idioms => 'Deyim',
        StationKind.verbs => 'Fiil',
        StationKind.boss => 'Seviye sınavı',
      };
}

/// Yolculuk haritasında tek bir durak.
///
/// Duraklar veritabanında saklanmaz; içerikten **deterministik** olarak
/// üretilir. Sebebi: kelime havuzu sıralaması sabit (önce doğrulanmış
/// karşılıklar, sonra sıklık), dolayısıyla aynı içerik hep aynı durakları
/// verir. Tek saklanan şey ilerlemedir — hangi durak kaç yıldızla geçildi.
class JourneyStation {
  const JourneyStation({
    required this.id,
    required this.level,
    required this.indexInLevel,
    required this.kind,
    required this.title,
    required this.wordIds,
    required this.verbRefIds,
    required this.questionCount,
  });

  final String id;
  final CefrLevel level;
  final int indexInLevel;
  final StationKind kind;
  final String title;
  final List<String> wordIds;
  final List<String> verbRefIds;
  final int questionCount;

  bool get isBoss => kind == StationKind.boss;

  /// Geçme eşiği. Sınav durakları daha zorlu.
  double get passRatio => isBoss ? 0.8 : 0.7;

  /// Kaç yıldız kazanıldığı. Üç yıldız hatasız demek.
  static int starsFor(int correct, int total, double passRatio) {
    if (total == 0) return 0;
    final double ratio = correct / total;
    if (ratio < passRatio) return 0;
    // Üç yıldız yalnızca hatasız turda. İkinci yıldız için %85 yeter:
    // sekiz soruda bir hata hâlâ iyi bir tur sayılmalı.
    if (correct == total) return 3;
    if (ratio >= 0.85) return 2;
    return 1;
  }
}

/// Bir durağın kaydedilmiş sonucu.
class StationResult {
  const StationResult({
    required this.stationId,
    required this.stars,
    required this.bestCorrect,
    required this.bestTotal,
  });

  final String stationId;
  final int stars;
  final int bestCorrect;
  final int bestTotal;

  bool get passed => stars > 0;

  /// Stars are the primary ranking. For equal stars, compare score ratios so
  /// the numerator and denominator always describe the same attempt.
  static StationResult bestOf(StationResult? old, StationResult attempt) {
    if (old == null || attempt.stars > old.stars) return attempt;
    if (attempt.stars < old.stars || attempt.bestTotal == 0) return old;
    if (old.bestTotal == 0 ||
        attempt.bestCorrect * old.bestTotal >
            old.bestCorrect * attempt.bestTotal) {
      return attempt;
    }
    return old;
  }
}
