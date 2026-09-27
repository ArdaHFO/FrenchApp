/// CEFR seviyeleri. Uygulamanın tamamı bu altı seviyeyi kapsar,
/// kullanıcı hangisinde çalışacağını kendisi seçer.
enum CefrLevel { a1, a2, b1, b2, c1, c2 }

extension CefrLevelX on CefrLevel {
  /// "A1", "B2" gibi.
  String get code => name.toUpperCase();

  /// Seviye seçim ekranında görünen açıklama.
  String get descriptionTr => switch (this) {
        CefrLevel.a1 => 'Hiç bilmiyorum, sıfırdan başlıyorum',
        CefrLevel.a2 => 'Temel kalıpları biliyorum, basit cümle kurabiliyorum',
        CefrLevel.b1 => 'Günlük konuları anlıyorum, kendimi ifade edebiliyorum',
        CefrLevel.b2 => 'Karmaşık metinleri takip edebiliyorum',
        CefrLevel.c1 => 'Akıcıyım, nüansları öğrenmek istiyorum',
        CefrLevel.c2 => 'Neredeyse anadil düzeyi',
      };

  String get worldName => switch (this) {
        CefrLevel.a1 => 'Başlangıç Köyü',
        CefrLevel.a2 => 'Günlük Hayat Şehri',
        CefrLevel.b1 => 'Macera Bölgesi',
        CefrLevel.b2 => 'Bağımsızlık Kalesi',
        CefrLevel.c1 => 'Ustalık Akademisi',
        CefrLevel.c2 => 'Fransızca Arenası',
      };

  /// Seviyenin kaba kelime hedefi. İlerleme ekranında kullanılır.
  int get targetWordCount => switch (this) {
        CefrLevel.a1 => 800,
        CefrLevel.a2 => 1200,
        CefrLevel.b1 => 2000,
        CefrLevel.b2 => 2500,
        CefrLevel.c1 => 2500,
        CefrLevel.c2 => 1000,
      };

  CefrLevel? get next =>
      index + 1 < CefrLevel.values.length ? CefrLevel.values[index + 1] : null;

  CefrLevel? get previous => index > 0 ? CefrLevel.values[index - 1] : null;

  /// Bu seviye ve altındakiler. "Alt seviyeleri karıştır" ayarı bunu kullanır.
  List<CefrLevel> get thisAndBelow => CefrLevel.values.sublist(0, index + 1);
}

/// Kelime temaları. Deste seçiminde seviyeyle birlikte filtre olur.
enum WordTheme {
  general,
  food,
  travel,
  home,
  work,
  emotions,
  daily,
  time,
  health,
  nature
}

extension WordThemeX on WordTheme {
  String get labelTr => switch (this) {
        WordTheme.general => 'Genel',
        WordTheme.food => 'Yemek',
        WordTheme.travel => 'Seyahat',
        WordTheme.home => 'Ev',
        WordTheme.work => 'İş',
        WordTheme.emotions => 'Duygular',
        WordTheme.daily => 'Günlük konuşma',
        WordTheme.time => 'Sayı ve zaman',
        WordTheme.health => 'Sağlık',
        WordTheme.nature => 'Doğa',
      };
}
