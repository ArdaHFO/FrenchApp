import 'level.dart';

/// Fransızca fiil zamanları. `content.db` içindeki `conjugations.tense`
/// değerleriyle birebir aynı.
enum VerbTense {
  present,
  passeCompose,
  imparfait,
  futurSimple,
  conditionnel,
  subjonctif,
  imperatif,
  plusQueParfait,
}

extension VerbTenseX on VerbTense {
  String get key => switch (this) {
        VerbTense.present => 'present',
        VerbTense.passeCompose => 'passe_compose',
        VerbTense.imparfait => 'imparfait',
        VerbTense.futurSimple => 'futur_simple',
        VerbTense.conditionnel => 'conditionnel',
        VerbTense.subjonctif => 'subjonctif',
        VerbTense.imperatif => 'imperatif',
        VerbTense.plusQueParfait => 'plus_que_parfait',
      };

  String get label => switch (this) {
        VerbTense.present => 'Présent',
        VerbTense.passeCompose => 'Passé composé',
        VerbTense.imparfait => 'Imparfait',
        VerbTense.futurSimple => 'Futur simple',
        VerbTense.conditionnel => 'Conditionnel',
        VerbTense.subjonctif => 'Subjonctif',
        VerbTense.imperatif => 'Impératif',
        VerbTense.plusQueParfait => 'Plus-que-parfait',
      };

  String get labelTr => switch (this) {
        VerbTense.present => 'Geniş / şimdiki zaman',
        VerbTense.passeCompose => 'Bitmiş geçmiş zaman',
        VerbTense.imparfait => 'Süregelen geçmiş zaman',
        VerbTense.futurSimple => 'Gelecek zaman',
        VerbTense.conditionnel => 'Şart kipi',
        VerbTense.subjonctif => 'İstek kipi',
        VerbTense.imperatif => 'Emir kipi',
        VerbTense.plusQueParfait => 'Miş\'li geçmiş',
      };

  CefrLevel get level => switch (this) {
        VerbTense.present ||
        VerbTense.passeCompose ||
        VerbTense.imparfait ||
        VerbTense.imperatif =>
          CefrLevel.a1,
        VerbTense.futurSimple ||
        VerbTense.conditionnel ||
        VerbTense.plusQueParfait =>
          CefrLevel.a2,
        VerbTense.subjonctif => CefrLevel.b1,
      };

  static VerbTense? fromKey(String key) {
    for (final VerbTense t in VerbTense.values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

const List<String> kPersons = <String>['je', 'tu', 'il', 'nous', 'vous', 'ils'];

/// Şahıs zamiri ile çekimi birleştirir, elizyonu uygular.
///
/// "je" + "ai" -> "j'ai".  Sesli harf veya sessiz h ile başlayan çekimlerde
/// zamir kısalır. Bu bir sunum kuralıdır, veritabanında çekimler yalın durur.
String conjugationDisplay(
  String person,
  String form, {
  VerbTense? tense,
  bool aspiratedH = false,
}) {
  if (form.isEmpty) return person;

  // Emir kipinde özne zamiri söylenmez: "lave-toi", "tu lave-toi" değil.
  if (tense == VerbTense.imperatif) return form;

  final String subject = _elide(person, form, aspiratedH: aspiratedH);

  // Subjonctif tek başına kullanılmaz, hep "que" ile gelir.
  if (tense == VerbTense.subjonctif) {
    return person == 'il' || person == 'ils' ? "qu'$subject" : 'que $subject';
  }
  return subject;
}

String _elide(String person, String form, {required bool aspiratedH}) {
  if (person == 'je') {
    const String vowels = 'aàâeéèêëiîïoôöuùûüy';
    final String first = form[0].toLowerCase();
    if (vowels.contains(first) || (first == 'h' && !aspiratedH)) {
      return "j'$form";
    }
  }
  return '$person $form';
}

class Verb {
  const Verb({
    required this.id,
    required this.infinitive,
    required this.auxiliary,
    required this.level,
    required this.meaningEn,
    required this.meaningTr,
    required this.freqRank,
    required this.group,
    this.ipa,
    this.pastParticiple,
    this.isReflexive = false,
    this.baseInfinitive,
    this.reflexiveKind,
    this.noteTr,
    this.aspiratedH = false,
    this.needsReview = false,
  });

  final String id;
  final String infinitive;
  final String auxiliary;
  final String? pastParticiple;
  final CefrLevel level;
  final String? ipa;
  final String meaningEn;
  final String meaningTr;
  final int freqRank;
  final int group;
  final bool aspiratedH;
  final bool needsReview;

  /// Dönüşlü fiil (verbe pronominal): se laver, s'appeler…
  final bool isReflexive;

  /// Dönüşlünün türediği temel fiil. "se rendre" için "rendre".
  /// Anlam çoğu zaman farklıdır; bu alan sadece bağlantı kurmak için.
  final String? baseInfinitive;

  /// reflechi · reciproque · essentiel · sens
  final String? reflexiveKind;

  /// Temel fiille arasındaki anlam farkının açıklaması.
  final String? noteTr;

  /// Dönüşlü fiil türünün Türkçe adı ve kısa tanımı.
  ({String label, String hint})? get reflexiveLabel => switch (reflexiveKind) {
        'reflechi' => (
            label: 'dönüşlü',
            hint: 'Eylem öznenin kendisine dönüyor.',
          ),
        'reciproque' => (
            label: 'karşılıklı',
            hint: 'Birbirlerine yapıyorlar.',
          ),
        'essentiel' => (
            label: 'yalnızca dönüşlü',
            hint: 'Bu fiil "se" olmadan kullanılmaz.',
          ),
        'sens' => (
            label: 'anlamı değişir',
            hint: 'Temel fiilden farklı bir anlama gelir.',
          ),
        _ => null,
      };

  bool get takesEtre => auxiliary == 'être';

  bool get isIrregular => group == 3;
}

/// Tek bir çekim: fiil + zaman + şahıs.
class Conjugation {
  const Conjugation({
    required this.verb,
    required this.tense,
    required this.person,
    required this.form,
  });

  final Verb verb;
  final VerbTense tense;
  final String person;
  final String form;

  /// Kart kimliği. SRS bunu `ref_id` olarak kullanır.
  String get refId => '${verb.id}:${tense.key}:$person';

  String get display => conjugationDisplay(
        person,
        form,
        tense: tense,
        aspiratedH: verb.aspiratedH,
      );
}
