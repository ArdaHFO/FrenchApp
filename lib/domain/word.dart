import 'level.dart';

/// Bir kelime, deyim veya kalıp ifade.
/// `content.db` içindeki `words` + `examples` tablolarına karşılık gelir.
class Word {
  const Word({
    required this.id,
    required this.lemma,
    required this.pos,
    required this.level,
    required this.theme,
    required this.meaningEn,
    required this.meaningTr,
    required this.freqRank,
    this.article,
    this.gender,
    this.ipa,
    this.meaningEn2,
    this.sentenceFr,
    this.sentenceEn,
    this.sentenceTr,
    this.sentenceFrId,
    this.sentenceFrAuthor,
    this.sentenceEnId,
    this.sentenceEnAuthor,
    this.sentenceTrId,
    this.sentenceTrAuthor,
    this.literalTr,
    this.noteTr,
    this.register,
    this.confidence = 1.0,
    this.isIdiom = false,
    this.isFunctionWord = false,
    this.needsReview = false,
  });

  final String id;
  final String lemma;
  final String? article;
  final String pos;
  final String? gender;
  final CefrLevel level;
  final WordTheme theme;
  final String? ipa;

  final String meaningEn;
  final String? meaningEn2;
  final String meaningTr;

  final String? literalTr;
  final String? noteTr;
  final String? register;

  /// Örnek cümle her kelimede yok (ölçüm: %68'inde var).
  final String? sentenceFr;
  final String? sentenceEn;
  final String? sentenceTr;
  final int? sentenceFrId;
  final String? sentenceFrAuthor;
  final int? sentenceEnId;
  final String? sentenceEnAuthor;
  final int? sentenceTrId;
  final String? sentenceTrAuthor;

  String? get sentenceAttribution {
    if (sentenceFrAuthor == null || sentenceEnAuthor == null) return null;
    final languages = <(String, String?, int?)>[
      ('FR', sentenceFrAuthor, sentenceFrId),
      ('EN', sentenceEnAuthor, sentenceEnId),
      if (sentenceTrAuthor != null) ('TR', sentenceTrAuthor, sentenceTrId),
    ];
    bool isLocal((String, String?, int?) language) =>
        (language.$3 != null && language.$3! < 0) ||
        (language.$2?.startsWith('FrenchApp') ?? false);
    if (languages.every(isLocal)) {
      return 'FrenchApp kürasyonu · öğretim örneği';
    }
    if (languages.any(isLocal)) {
      return languages.map((language) {
        final source = isLocal(language) ? 'yerel editoryal' : 'Tatoeba';
        return '${language.$1} $source · ${language.$2}';
      }).join(' · ');
    }
    final String tr = sentenceTrAuthor == null ? '' : ' · TR $sentenceTrAuthor';
    return 'Tatoeba · FR $sentenceFrAuthor · EN $sentenceEnAuthor$tr';
  }

  final int freqRank;
  final double confidence;
  final bool isIdiom;

  /// Edat, bağlaç, zamir. Kelime kartı olmaz, dilbilgisine aittir.
  final bool isFunctionWord;

  final bool needsReview;

  bool get hasExample => sentenceFr != null && sentenceFr!.isNotEmpty;

  /// "la voiture" ama kesme işaretinde boşluksuz: "l'eau".
  String get display {
    final String? a = article;
    if (a == null) return lemma;
    return a.endsWith("'") ? '$a$lemma' : '$a $lemma';
  }

  /// Türkçe kelime türü etiketi.
  String get posTr => switch (pos) {
        'NOM' => 'isim',
        'VER' => 'fiil',
        'ADJ' => 'sıfat',
        'ADV' => 'zarf',
        'PRE' => 'edat',
        'CON' => 'bağlaç',
        'ADJ:num' => 'sayı',
        'PHR' => 'kalıp',
        _ when pos.startsWith('PRO') => 'zamir',
        _ => pos.toLowerCase(),
      };

  String? get genderTr => switch (gender) {
        'm' => 'eril',
        'f' => 'dişil',
        _ => null,
      };
}
