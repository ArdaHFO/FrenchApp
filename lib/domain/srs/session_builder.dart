import 'srs_card.dart';

/// Bir oturumun kart sırasını kurar. PLAN.md bölüm 7, "Oturum kompozisyonu".
///
/// Varsayılan 20 kartlık oturumda 14 kart zamanı gelmiş tekrar, 6 kart yeni
/// kelimedir. Yeni kartlar sıklık sırasına göre gelir. Zamanı gelmiş kart
/// kalmadıysa boşluk yeni kartla doldurulur, tersi de geçerlidir.
class SessionBuilder {
  SessionBuilder._();

  static const double defaultReviewRatio = 0.7;

  /// [candidateRefIds] seviye ve tema filtresinden geçmiş, sıklık sırasına
  /// göre dizilmiş kimlikler olmalıdır.
  static List<String> build({
    required List<String> candidateRefIds,
    required Map<String, SrsCard> states,
    required DateTime now,
    required int size,
    double reviewRatio = defaultReviewRatio,
    bool includeNotDue = false,
  }) {
    if (size <= 0 || candidateRefIds.isEmpty) return const <String>[];

    final List<String> due = <String>[];
    final List<String> fresh = <String>[];

    for (final String id in candidateRefIds) {
      final SrsCard? state = states[id];
      if (state == null) {
        fresh.add(id);
        continue;
      }
      if (state.status == CardStatus.archived) continue;
      if (state.timesSeen == 0) {
        fresh.add(id);
      } else if (includeNotDue || state.isDue(now)) {
        due.add(id);
      }
    }

    // Yıldızlılar önce, kendi gruplarında zamanı en çok geçmiş kart önce.
    due.sort((String a, String b) {
      final bool sa = states[a]?.starred ?? false;
      final bool sb = states[b]?.starred ?? false;
      if (sa != sb) return sa ? -1 : 1;
      final DateTime? da = states[a]?.dueAt;
      final DateTime? db = states[b]?.dueAt;
      if (da == null && db == null) return 0;
      if (da == null) return -1;
      if (db == null) return 1;
      return da.compareTo(db);
    });

    int reviewCount = (size * reviewRatio).round();
    int freshCount = size - reviewCount;

    if (due.length < reviewCount) {
      freshCount += reviewCount - due.length;
      reviewCount = due.length;
    }
    if (fresh.length < freshCount) {
      final int spare = freshCount - fresh.length;
      freshCount = fresh.length;
      reviewCount = (reviewCount + spare).clamp(0, due.length);
    }

    final List<String> reviews = due.take(reviewCount).toList();
    final List<String> news = fresh.take(freshCount).toList();

    return _interleave(reviews, news);
  }

  /// Yeni kartları tekrarların arasına eşit dağıtır.
  /// Hepsi başta veya sonda toplanırsa oturum tekdüze hissettirir.
  static List<String> _interleave(List<String> reviews, List<String> news) {
    if (news.isEmpty) return reviews;
    if (reviews.isEmpty) return news;

    final List<String> out = <String>[];
    final double step = (reviews.length + news.length) / news.length;
    int reviewIndex = 0;
    int newIndex = 0;
    double nextNewAt = step - 1;

    for (int i = 0; i < reviews.length + news.length; i++) {
      final bool placeNew = newIndex < news.length && i >= nextNewAt;
      if (placeNew) {
        out.add(news[newIndex++]);
        nextNewAt += step;
      } else if (reviewIndex < reviews.length) {
        out.add(reviews[reviewIndex++]);
      } else if (newIndex < news.length) {
        out.add(news[newIndex++]);
      }
    }
    return out;
  }

  /// Sola kaydırılan kart aynı oturumda kaç kart sonra tekrar gelir.
  static const int reinsertAfter = 10;

  /// [deck] içindeki [position] konumundaki kartı 10 kart sonraya taşır.
  /// Deste sonuna yakınsa en sona eklenir.
  static List<String> reinsert(
    List<String> deck,
    int position, {
    int after = reinsertAfter,
  }) {
    if (position < 0 || position >= deck.length) return deck;
    final List<String> out = List<String>.of(deck);
    final String id = out.removeAt(position);
    final int target = (position + after).clamp(0, out.length);
    out.insert(target, id);
    return out;
  }
}
