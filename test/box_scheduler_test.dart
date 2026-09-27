import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/domain/srs/box_scheduler.dart';
import 'package:french_app/domain/srs/session_builder.dart';
import 'package:french_app/domain/srs/srs_card.dart';

/// Kutu ilerletme mantığı uygulamanın en kritik parçası.
/// PLAN.md bölüm 10.3: saf fonksiyon olarak yazılır, testleri ilk gün yazılır.
void main() {
  final DateTime now = DateTime(2026, 8, 9, 12);

  SrsCard card({
    int box = 0,
    bool starred = false,
    int lapses = 0,
    int timesSeen = 0,
    CardStatus status = CardStatus.fresh,
    DateTime? dueAt,
  }) {
    return SrsCard(
      refId: 'w1',
      box: box,
      starred: starred,
      lapses: lapses,
      timesSeen: timesSeen,
      status: status,
      dueAt: dueAt,
    );
  }

  group('sağa kaydırma (biliyorum)', () {
    test('kartı bir üst kutuya çıkarır', () {
      final SrsCard out =
          BoxScheduler.apply(card(), SwipeAction.know, now: now);
      expect(out.box, 1);
      expect(out.status, CardStatus.learning);
      expect(out.timesRight, 1);
      expect(out.timesSeen, 1);
    });

    test('tekrar aralığını kutuya göre belirler', () {
      expect(
        BoxScheduler.apply(card(box: 2), SwipeAction.know, now: now).dueAt,
        now.add(const Duration(days: 7)),
      );
    });

    test('en üst kutuda kalır ve pekişmiş sayılır', () {
      final SrsCard out = BoxScheduler.apply(
        card(box: BoxSchedulerConfig.maxBox),
        SwipeAction.know,
        now: now,
      );
      expect(out.box, BoxSchedulerConfig.maxBox);
      expect(out.status, CardStatus.mastered);
    });

    test('yıldızlı kartın aralığı yarıya iner', () {
      final SrsCard out = BoxScheduler.apply(
        card(box: 1, starred: true),
        SwipeAction.know,
        now: now,
      );
      // kutu 2 -> 3 gün, yıldızlı olduğu için 1.5 gün
      expect(out.dueAt, now.add(const Duration(hours: 36)));
    });
  });

  group('sola kaydırma (bilmiyorum)', () {
    test('bir kutu geri değil doğrudan kutu 0a düşürür', () {
      final SrsCard out = BoxScheduler.apply(
        card(box: 4, status: CardStatus.known),
        SwipeAction.dontKnow,
        now: now,
      );
      expect(out.box, 0);
      expect(out.status, CardStatus.fresh);
    });

    test('lapses sayacını artırır', () {
      final SrsCard out = BoxScheduler.apply(
        card(lapses: 2),
        SwipeAction.dontKnow,
        now: now,
      );
      expect(out.lapses, 3);
      expect(out.isLeech, isFalse);
    });

    test('altıncı düşüşte zorlandıklarım listesine girer', () {
      SrsCard c = card(lapses: 5);
      c = BoxScheduler.apply(c, SwipeAction.dontKnow, now: now);
      expect(c.lapses, BoxSchedulerConfig.leechThreshold);
      expect(c.isLeech, isTrue);
    });
  });

  group('yukarı kaydırma (zor)', () {
    test('yıldızı açar ve kutuyu değiştirmez', () {
      final SrsCard out =
          BoxScheduler.apply(card(box: 3), SwipeAction.hard, now: now);
      expect(out.starred, isTrue);
      expect(out.box, 3);
    });

    test('zaten yıldızlı kartı yıldızlı bırakır', () {
      final SrsCard out = BoxScheduler.apply(
        card(box: 3, starred: true),
        SwipeAction.hard,
        now: now,
      );
      expect(out.starred, isTrue);
    });
  });

  group('aşağı kaydırma (atla)', () {
    test('kartı arşivler ve tekrar zamanını kaldırır', () {
      final SrsCard out = BoxScheduler.apply(
        card(dueAt: now.add(const Duration(days: 3))),
        SwipeAction.skip,
        now: now,
      );
      expect(out.status, CardStatus.archived);
      expect(out.dueAt, isNull);
      expect(out.isDue(now), isFalse);
    });
  });

  group('quiz', () {
    test('sadece kutu 1 ve üzeri kart quize girer', () {
      expect(card().isQuizEligible, isFalse);
      expect(card(box: 1).isQuizEligible, isTrue);
    });

    test('doğru cevap kutuyu yükseltir', () {
      final SrsCard out = BoxScheduler.applyQuizResult(
        card(box: 2),
        correct: true,
        now: now,
      );
      expect(out.box, 3);
    });

    test('yanlış cevap kutu 0a düşürür', () {
      final SrsCard out = BoxScheduler.applyQuizResult(
        card(box: 4),
        correct: false,
        now: now,
      );
      expect(out.box, 0);
    });

    test('arşivlenmiş kart quizden etkilenmez', () {
      final SrsCard archived = card(status: CardStatus.archived, box: 5);
      final SrsCard out = BoxScheduler.applyQuizResult(
        archived,
        correct: false,
        now: now,
      );
      expect(out.status, CardStatus.archived);
      expect(out.box, 5);
    });
  });

  group('oturum kurucu', () {
    List<String> ids(int n) =>
        List<String>.generate(n, (int i) => 'w${i.toString().padLeft(3, '0')}');

    test('hiç geçmiş yoksa oturumu yeni kartlarla doldurur', () {
      final List<String> deck = SessionBuilder.build(
        candidateRefIds: ids(50),
        states: <String, SrsCard>{},
        now: now,
        size: 20,
      );
      expect(deck.length, 20);
      expect(deck.toSet().length, 20, reason: 'kart tekrar etmemeli');
    });

    test('yeterli tekrar varsa oranı korur', () {
      final List<String> candidates = ids(50);
      final Map<String, SrsCard> states = <String, SrsCard>{};
      // ilk 30 kart zamanı gelmiş tekrar
      for (int i = 0; i < 30; i++) {
        states[candidates[i]] = SrsCard(
          refId: candidates[i],
          box: 2,
          timesSeen: 3,
          dueAt: now.subtract(Duration(days: i + 1)),
        );
      }
      final List<String> deck = SessionBuilder.build(
        candidateRefIds: candidates,
        states: states,
        now: now,
        size: 20,
      );
      expect(deck.length, 20);
      final int reviewsInDeck =
          deck.where((String id) => states.containsKey(id)).length;
      expect(reviewsInDeck, 14);
    });

    test('arşivlenmiş kart desteye girmez', () {
      final List<String> candidates = ids(5);
      final Map<String, SrsCard> states = <String, SrsCard>{
        for (final String id in candidates)
          id: SrsCard(refId: id, status: CardStatus.archived, timesSeen: 1),
      };
      final List<String> deck = SessionBuilder.build(
        candidateRefIds: candidates,
        states: states,
        now: now,
        size: 20,
      );
      expect(deck, isEmpty);
    });

    test('özel deste zamanı gelmemiş kartları isteğe bağlı açar', () {
      final List<String> candidates = ids(3);
      final Map<String, SrsCard> states = <String, SrsCard>{
        for (final String id in candidates)
          id: SrsCard(
            refId: id,
            box: 3,
            status: CardStatus.known,
            timesSeen: 2,
            dueAt: now.add(const Duration(days: 7)),
          ),
      };
      expect(
        SessionBuilder.build(
          candidateRefIds: candidates,
          states: states,
          now: now,
          size: 20,
        ),
        isEmpty,
      );
      expect(
        SessionBuilder.build(
          candidateRefIds: candidates,
          states: states,
          now: now,
          size: 20,
          includeNotDue: true,
        ),
        hasLength(3),
      );
    });

    test('sola kaydırılan kart on kart sonraya taşınır', () {
      final List<String> deck = ids(20);
      final List<String> out = SessionBuilder.reinsert(deck, 0);
      expect(out.indexOf('w000'), 10);
      expect(out.length, 20);
    });

    test('deste sonuna yakın kart en sona eklenir', () {
      final List<String> deck = ids(5);
      final List<String> out = SessionBuilder.reinsert(deck, 3);
      expect(out.last, 'w003');
      expect(out.length, 5);
    });
  });
}
