/// Kullanıcının bir karta verdiği tepki.
///
/// Arayüzdeki [SwipeDirection] burada bilinmez. Eşleme UI sınırında yapılır,
/// böylece SRS mantığı Flutter'dan tamamen bağımsız kalır ve saf Dart olarak
/// test edilebilir.
enum SwipeAction {
  /// Sağa: biliyorum.
  know,

  /// Sola: henüz bilmiyorum.
  dontKnow,

  /// Yukarı: zor, yıldızla.
  hard,

  /// Aşağı: zaten biliyorum, bir daha gösterme.
  skip,
}

enum CardStatus { fresh, learning, known, mastered, archived }

/// Bir kartın öğrenme durumu. Değişmez (immutable).
class SrsCard {
  static const Object _unchanged = Object();

  const SrsCard({
    required this.refId,
    this.box = 0,
    this.status = CardStatus.fresh,
    this.starred = false,
    this.dueAt,
    this.lastSeenAt,
    this.timesSeen = 0,
    this.timesRight = 0,
    this.lapses = 0,
  });

  final String refId;

  /// 0 ile 5 arası. Bakınız [BoxScheduler.intervals].
  final int box;
  final CardStatus status;
  final bool starred;
  final DateTime? dueAt;
  final DateTime? lastSeenAt;
  final int timesSeen;
  final int timesRight;
  final int lapses;

  /// Altı kez sola kaydırılan kart "zorlandıklarım" listesine düşer.
  bool get isLeech => lapses >= BoxSchedulerConfig.leechThreshold;

  /// Quiz sorusu sadece kutu 1 ve üzeri kartlardan gelir.
  /// Hiç görülmemiş kelimeyi sormak öğretmez.
  bool get isQuizEligible => box >= 1 && status != CardStatus.archived;

  bool isDue(DateTime now) {
    if (status == CardStatus.archived) return false;
    final DateTime? due = dueAt;
    return due == null || !due.isAfter(now);
  }

  SrsCard copyWith({
    int? box,
    CardStatus? status,
    bool? starred,
    Object? dueAt = _unchanged,
    Object? lastSeenAt = _unchanged,
    int? timesSeen,
    int? timesRight,
    int? lapses,
  }) {
    return SrsCard(
      refId: refId,
      box: box ?? this.box,
      status: status ?? this.status,
      starred: starred ?? this.starred,
      dueAt: identical(dueAt, _unchanged) ? this.dueAt : dueAt as DateTime?,
      lastSeenAt: identical(lastSeenAt, _unchanged)
          ? this.lastSeenAt
          : lastSeenAt as DateTime?,
      timesSeen: timesSeen ?? this.timesSeen,
      timesRight: timesRight ?? this.timesRight,
      lapses: lapses ?? this.lapses,
    );
  }

  @override
  String toString() =>
      'SrsCard($refId, kutu $box, $status, lapses $lapses, yildiz $starred)';
}

class BoxSchedulerConfig {
  BoxSchedulerConfig._();

  /// Bu kadar kez sola kaydırılan kart zorlandıklarım listesine girer.
  static const int leechThreshold = 6;

  /// En üst kutu.
  static const int maxBox = 5;
}
