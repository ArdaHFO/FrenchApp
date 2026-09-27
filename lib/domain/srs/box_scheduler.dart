import 'srs_card.dart';

/// Aralıklı tekrar kutu sistemi. PLAN.md bölüm 7.
///
/// Bilerek saf: Flutter'a, veritabanına, saate bağlı değil. `now` dışarıdan
/// verilir. Uygulamanın en kritik mantığı burada durduğu için testi kolay
/// olmalı — bu dosyanın testleri `test/box_scheduler_test.dart` içinde.
class BoxScheduler {
  BoxScheduler._();

  /// Kutu numarasına karşılık gelen tekrar aralığı.
  ///
  /// Kutu 0 aynı oturumda tekrar gelir, o yüzden sıfır süre.
  static const List<Duration> intervals = <Duration>[
    Duration.zero, // 0 - yeni veya unutulmuş
    Duration(days: 1), // 1 - öğreniliyor
    Duration(days: 3), // 2 - öğreniliyor
    Duration(days: 7), // 3 - biliniyor
    Duration(days: 16), // 4 - biliniyor
    Duration(days: 35), // 5 - pekişmiş
  ];

  static CardStatus statusForBox(int box) => switch (box) {
        <= 0 => CardStatus.fresh,
        1 || 2 => CardStatus.learning,
        3 || 4 => CardStatus.known,
        _ => CardStatus.mastered,
      };

  /// Kartın bir sonraki tekrar zamanı.
  /// Yıldızlı kartların aralığı yarıya iner.
  static DateTime dueAfter(int box, DateTime now, {required bool starred}) {
    final int clamped = box.clamp(0, BoxSchedulerConfig.maxBox);
    Duration interval = intervals[clamped];
    if (starred && interval > Duration.zero) {
      interval = Duration(microseconds: interval.inMicroseconds ~/ 2);
    }
    return now.add(interval);
  }

  /// Kaydırma sonucunda kartın yeni durumu.
  static SrsCard apply(
    SrsCard card,
    SwipeAction action, {
    required DateTime now,
  }) {
    final int seen = card.timesSeen + 1;

    switch (action) {
      case SwipeAction.know:
        final int box = (card.box + 1).clamp(0, BoxSchedulerConfig.maxBox);
        return card.copyWith(
          box: box,
          status: statusForBox(box),
          dueAt: dueAfter(box, now, starred: card.starred),
          lastSeenAt: now,
          timesSeen: seen,
          timesRight: card.timesRight + 1,
        );

      case SwipeAction.dontKnow:
        // Doğrudan kutu 0'a düşer. Bir kutu geri değil — bilinmeyen kelime
        // baştan öğrenilir.
        return card.copyWith(
          box: 0,
          status: CardStatus.fresh,
          dueAt: dueAfter(0, now, starred: card.starred),
          lastSeenAt: now,
          timesSeen: seen,
          lapses: card.lapses + 1,
        );

      case SwipeAction.hard:
        // Yıldız kartı bir üst kutuya taşımaz, sadece daha sık getirir.
        const bool starred = true;
        return card.copyWith(
          starred: starred,
          dueAt: dueAfter(card.box, now, starred: starred),
          lastSeenAt: now,
          timesSeen: seen,
        );

      case SwipeAction.skip:
        return card.copyWith(
          status: CardStatus.archived,
          box: BoxSchedulerConfig.maxBox,
          dueAt: null,
          lastSeenAt: now,
          timesSeen: seen,
        );
    }
  }

  /// Quiz cevabının kart üzerindeki etkisi.
  ///
  /// Doğru cevap kartı bir üst kutuya çıkarır, yanlış cevap kutu 0'a düşürür.
  /// Kaydırmayla aynı mantık, ama arşivlenmiş kart etkilenmez.
  static SrsCard applyQuizResult(
    SrsCard card, {
    required bool correct,
    required DateTime now,
  }) {
    if (card.status == CardStatus.archived) return card;
    return apply(
      card,
      correct ? SwipeAction.know : SwipeAction.dontKnow,
      now: now,
    );
  }
}
