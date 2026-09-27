import 'level.dart';

enum SentenceIssueType { article, conjugation, preposition, wordOrder, vocabulary }

extension SentenceIssueTypeX on SentenceIssueType {
  String get label => switch (this) {
        SentenceIssueType.article => 'Artikel',
        SentenceIssueType.conjugation => 'Fiil çekimi',
        SentenceIssueType.preposition => 'Edat',
        SentenceIssueType.wordOrder => 'Kelime sırası',
        SentenceIssueType.vocabulary => 'Kelime / yazım',
      };
}

class SentenceRequirement {
  const SentenceRequirement({
    required this.type,
    required this.alternatives,
    required this.feedback,
  });

  final SentenceIssueType type;
  final List<String> alternatives;
  final String feedback;
}

class SentencePrompt {
  const SentencePrompt({
    required this.id,
    required this.level,
    required this.situationTr,
    required this.hintTr,
    required this.modelAnswer,
    required this.acceptedAnswers,
    required this.requirements,
    required this.orderAnchors,
  });

  final String id;
  final CefrLevel level;
  final String situationTr;
  final String hintTr;
  final String modelAnswer;
  final List<String> acceptedAnswers;
  final List<SentenceRequirement> requirements;
  final List<List<String>> orderAnchors;
}

class SentenceIssue {
  const SentenceIssue(this.type, this.message);

  final SentenceIssueType type;
  final String message;
}

class SentenceEvaluation {
  const SentenceEvaluation({
    required this.correct,
    required this.score,
    required this.issues,
  });

  final bool correct;
  final int score;
  final List<SentenceIssue> issues;
}

class SentenceEvaluator {
  const SentenceEvaluator._();

  static SentenceEvaluation evaluate(String answer, SentencePrompt prompt) {
    final String normalized = _normalize(answer);
    if (normalized.isEmpty) {
      return const SentenceEvaluation(
        correct: false,
        score: 0,
        issues: <SentenceIssue>[
          SentenceIssue(
            SentenceIssueType.vocabulary,
            'Önce Fransızca bir cümle yaz.',
          ),
        ],
      );
    }

    if (prompt.acceptedAnswers
        .map(_normalize)
        .any((String accepted) => accepted == normalized)) {
      return const SentenceEvaluation(
        correct: true,
        score: 100,
        issues: <SentenceIssue>[],
      );
    }

    final List<SentenceIssue> issues = <SentenceIssue>[];
    int matched = 0;
    for (final SentenceRequirement requirement in prompt.requirements) {
      final bool present = requirement.alternatives
          .map(_normalize)
          .any((String token) => _containsPhrase(normalized, token));
      if (present) {
        matched++;
      } else {
        issues.add(SentenceIssue(requirement.type, requirement.feedback));
      }
    }

    final List<int> positions = <int>[];
    for (final List<String> group in prompt.orderAnchors) {
      int best = -1;
      for (final String raw in group) {
        final int at = normalized.indexOf(_normalize(raw));
        if (at >= 0 && (best < 0 || at < best)) best = at;
      }
      if (best >= 0) positions.add(best);
    }
    bool ordered = true;
    for (int i = 1; i < positions.length; i++) {
      if (positions[i] <= positions[i - 1]) ordered = false;
    }
    if (!ordered) {
      issues.add(const SentenceIssue(
        SentenceIssueType.wordOrder,
        'Gerekli parçalar var fakat Fransızca kelime sırasını kontrol et.',
      ));
    }

    final int denominator = prompt.requirements.length + 1;
    final int score = (((matched + (ordered ? 1 : 0)) / denominator) * 100)
        .round()
        .clamp(0, 100);
    return SentenceEvaluation(
      correct: matched == prompt.requirements.length && ordered,
      score: score,
      issues: issues.isEmpty
          ? const <SentenceIssue>[
              SentenceIssue(
                SentenceIssueType.vocabulary,
                'Anlam doğruya yakın. Model cümleyle yazım ve ifadeyi karşılaştır.',
              ),
            ]
          : issues,
    );
  }

  static bool _containsPhrase(String sentence, String phrase) =>
      ' $sentence '.contains(' $phrase ');

  static String _normalize(String input) {
    const Map<String, String> accents = <String, String>{
      'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a',
      'ç': 'c',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'î': 'i', 'ï': 'i', 'í': 'i',
      'ô': 'o', 'ö': 'o', 'ó': 'o',
      'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
      'ÿ': 'y',
      'œ': 'oe',
    };
    String out = input.toLowerCase().replaceAll('’', "'");
    for (final MapEntry<String, String> entry in accents.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }
    out = out.replaceAll(RegExp(r"[^a-z0-9'\- ]"), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }
}

const List<SentencePrompt> sentencePromptCatalog = <SentencePrompt>[
  SentencePrompt(
    id: 'a1_coffee', level: CefrLevel.a1,
    situationTr: 'Kafede nazikçe bir kahve iste.',
    hintTr: 'je voudrais · un café · s’il vous plaît',
    modelAnswer: 'Je voudrais un café, s’il vous plaît.',
    acceptedAnswers: <String>['Je voudrais un café, s’il vous plaît.', 'Je voudrais un café.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['je voudrais'], feedback: 'İstek için “je voudrais” kullan.'),
      SentenceRequirement(type: SentenceIssueType.article, alternatives: <String>['un café'], feedback: '“Café” eril: “un café”.'),
    ],
    orderAnchors: <List<String>>[<String>['je voudrais'], <String>['un café']],
  ),
  SentencePrompt(
    id: 'a1_home', level: CefrLevel.a1,
    situationTr: 'Lüksemburg’da yaşadığını söyle.',
    hintTr: 'habiter · à Luxembourg',
    modelAnswer: 'J’habite à Luxembourg.',
    acceptedAnswers: <String>['J’habite à Luxembourg.', 'Je vis à Luxembourg.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>["j'habite", 'je vis'], feedback: '“Habiter” fiilini “j’habite” olarak çek.'),
      SentenceRequirement(type: SentenceIssueType.preposition, alternatives: <String>['à luxembourg'], feedback: 'Şehirlerden önce “à” kullan.'),
    ],
    orderAnchors: <List<String>>[<String>["j'habite", 'je vis'], <String>['à luxembourg']],
  ),
  SentencePrompt(
    id: 'a1_age', level: CefrLevel.a1,
    situationTr: 'Yirmi altı yaşında olduğunu söyle.',
    hintTr: 'avoir · vingt-six ans',
    modelAnswer: 'J’ai vingt-six ans.',
    acceptedAnswers: <String>['J’ai vingt-six ans.', 'J’ai 26 ans.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>["j'ai"], feedback: 'Fransızcada yaş “avoir” ile söylenir: “j’ai”.'),
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['vingt-six ans', '26 ans'], feedback: 'Yaştan sonra “ans” kelimesini ekle.'),
    ],
    orderAnchors: <List<String>>[<String>["j'ai"], <String>['vingt-six', '26'], <String>['ans']],
  ),
  SentencePrompt(
    id: 'a2_wakeup', level: CefrLevel.a2,
    situationTr: 'Dün saat yedide kalktığını söyle.',
    hintTr: 'hier · se lever · à sept heures',
    modelAnswer: 'Hier, je me suis levé à sept heures.',
    acceptedAnswers: <String>['Hier, je me suis levé à sept heures.', 'Je me suis levé à sept heures hier.', 'Hier, je me suis levée à sept heures.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['je me suis levé', 'je me suis levée'], feedback: 'Dönüşlü fiilin passé composé çekimi: “je me suis levé(e)”.'),
      SentenceRequirement(type: SentenceIssueType.preposition, alternatives: <String>['à sept heures'], feedback: 'Saatten önce “à” kullan.'),
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['hier'], feedback: '“Dün” için “hier” ekle.'),
    ],
    orderAnchors: <List<String>>[<String>['hier'], <String>['je me suis levé', 'je me suis levée'], <String>['à sept heures']],
  ),
  SentencePrompt(
    id: 'a2_ticket', level: CefrLevel.a2,
    situationTr: 'Yarın Paris’e gitmek istediğini söyle.',
    hintTr: 'vouloir · aller à Paris · demain',
    modelAnswer: 'Je voudrais aller à Paris demain.',
    acceptedAnswers: <String>['Je voudrais aller à Paris demain.', 'Je veux aller à Paris demain.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['je voudrais', 'je veux'], feedback: '“Vouloir” fiilini özneye göre çek.'),
      SentenceRequirement(type: SentenceIssueType.preposition, alternatives: <String>['aller à paris'], feedback: 'Şehir için “aller à Paris” kullan.'),
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['demain'], feedback: '“Yarın” için “demain” ekle.'),
    ],
    orderAnchors: <List<String>>[<String>['je voudrais', 'je veux'], <String>['aller à paris'], <String>['demain']],
  ),
  SentencePrompt(
    id: 'a2_rain', level: CefrLevel.a2,
    situationTr: 'Yağmur yağdığı için şemsiyeni aldığını söyle.',
    hintTr: 'comme · pleuvoir · prendre mon parapluie',
    modelAnswer: 'Comme il pleut, je prends mon parapluie.',
    acceptedAnswers: <String>['Comme il pleut, je prends mon parapluie.', 'Il pleut, donc je prends mon parapluie.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['il pleut'], feedback: 'Hava ifadesi “il pleut” şeklindedir.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['je prends'], feedback: '“Prendre” → “je prends”.'),
      SentenceRequirement(type: SentenceIssueType.article, alternatives: <String>['mon parapluie'], feedback: 'Sahiplik için “mon parapluie” kullan.'),
    ],
    orderAnchors: <List<String>>[<String>['il pleut'], <String>['je prends'], <String>['mon parapluie']],
  ),
  SentencePrompt(
    id: 'b1_future', level: CefrLevel.b1,
    situationTr: 'Hava güzel olursa hafta sonu yürüyüşe çıkacağını söyle.',
    hintTr: 's’il fait beau · faire une randonnée',
    modelAnswer: 'S’il fait beau, je ferai une randonnée ce week-end.',
    acceptedAnswers: <String>['S’il fait beau, je ferai une randonnée ce week-end.', 'S’il fait beau, je vais faire une randonnée ce week-end.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>["s'il fait beau"], feedback: '“Si” yan cümlesinde présent kullan: “s’il fait beau”.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['je ferai', 'je vais faire'], feedback: 'Sonuç için futur simple veya futur proche kullan.'),
      SentenceRequirement(type: SentenceIssueType.article, alternatives: <String>['une randonnée'], feedback: '“Randonnée” dişil: “une randonnée”.'),
    ],
    orderAnchors: <List<String>>[<String>["s'il fait beau"], <String>['je ferai', 'je vais faire'], <String>['une randonnée']],
  ),
  SentencePrompt(
    id: 'b1_opinion', level: CefrLevel.b1,
    situationTr: 'Toplu taşımanın daha ucuz olması gerektiğini düşündüğünü söyle.',
    hintTr: 'penser que · devoir · moins cher',
    modelAnswer: 'Je pense que les transports en commun devraient être moins chers.',
    acceptedAnswers: <String>['Je pense que les transports en commun devraient être moins chers.', 'À mon avis, les transports en commun devraient coûter moins cher.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['je pense que', 'à mon avis'], feedback: 'Görüşünü “je pense que” veya “à mon avis” ile başlat.'),
      SentenceRequirement(type: SentenceIssueType.article, alternatives: <String>['les transports en commun'], feedback: 'Genel çoğul isim için “les transports en commun”.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['devraient être', 'devraient coûter'], feedback: 'Öneri için conditionnel “devraient” kullan.'),
    ],
    orderAnchors: <List<String>>[<String>['je pense que', 'à mon avis'], <String>['les transports en commun'], <String>['devraient']],
  ),
  SentencePrompt(
    id: 'b1_lost', level: CefrLevel.b1,
    situationTr: 'Telefonunu kaybettiğini ama birinin bulduğunu anlat.',
    hintTr: 'perdre · quelqu’un · retrouver',
    modelAnswer: 'J’avais perdu mon téléphone, mais quelqu’un l’a retrouvé.',
    acceptedAnswers: <String>['J’avais perdu mon téléphone, mais quelqu’un l’a retrouvé.', 'J’ai perdu mon téléphone, mais quelqu’un l’a retrouvé.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>["j'avais perdu", "j'ai perdu"], feedback: 'Kaybetme olayını geçmiş zamanda çek.'),
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['mon téléphone'], feedback: 'Kaybolan nesneyi “mon téléphone” ile belirt.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>["quelqu'un l'a retrouvé"], feedback: 'Bulma eylemi için “quelqu’un l’a retrouvé” kullan.'),
    ],
    orderAnchors: <List<String>>[<String>['perdu'], <String>['mais'], <String>['retrouvé']],
  ),
  SentencePrompt(
    id: 'b2_subjunctive', level: CefrLevel.b2,
    situationTr: 'Süre kısa olmasına rağmen projeyi zamanında teslim ettiğinizi söyle.',
    hintTr: 'bien que · délai · livrer à temps',
    modelAnswer: 'Bien que le délai soit court, nous avons livré le projet à temps.',
    acceptedAnswers: <String>['Bien que le délai soit court, nous avons livré le projet à temps.', 'Nous avons livré le projet à temps bien que le délai ait été court.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['bien que le délai soit court', 'bien que le délai ait été court'], feedback: '“Bien que” sonrasında subjonctif kullan: “soit” veya “ait été”.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['nous avons livré'], feedback: '“Livrer” fiilini passé composé ile çek.'),
      SentenceRequirement(type: SentenceIssueType.preposition, alternatives: <String>['à temps'], feedback: '“Zamanında” için “à temps”.'),
    ],
    orderAnchors: <List<String>>[<String>['bien que'], <String>['soit', 'ait été'], <String>['livré']],
  ),
  SentencePrompt(
    id: 'b2_regret', level: CefrLevel.b2,
    situationTr: 'Daha önce bilseydin farklı davranacağını söyle.',
    hintTr: 'si · savoir · agir autrement',
    modelAnswer: 'Si je l’avais su plus tôt, j’aurais agi autrement.',
    acceptedAnswers: <String>['Si je l’avais su plus tôt, j’aurais agi autrement.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>["si je l'avais su"], feedback: 'Gerçekleşmemiş geçmiş koşulda “si + plus-que-parfait” kullan.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>["j'aurais agi"], feedback: 'Sonuçta conditionnel passé kullan: “j’aurais agi”.'),
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['autrement'], feedback: '“Farklı biçimde” için “autrement”.'),
    ],
    orderAnchors: <List<String>>[<String>["si je l'avais su"], <String>["j'aurais agi"], <String>['autrement']],
  ),
  SentencePrompt(
    id: 'b2_report', level: CefrLevel.b2,
    situationTr: 'Müdürün toplantının ertelendiğini söylediğini aktar.',
    hintTr: 'directeur · annoncer · réunion reportée',
    modelAnswer: 'Le directeur a annoncé que la réunion avait été reportée.',
    acceptedAnswers: <String>['Le directeur a annoncé que la réunion avait été reportée.', 'La directrice a annoncé que la réunion avait été reportée.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.article, alternatives: <String>['le directeur', 'la directrice'], feedback: 'Kişiyi uygun artikel ile belirt.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['a annoncé'], feedback: 'Aktarma fiilini passé composé ile kur: “a annoncé”.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['avait été reportée'], feedback: 'Önce gerçekleşen edilgen olay: “avait été reportée”.'),
    ],
    orderAnchors: <List<String>>[<String>['directeur', 'directrice'], <String>['a annoncé'], <String>['réunion'], <String>['avait été reportée']],
  ),
  SentencePrompt(
    id: 'c1_compromise', level: CefrLevel.c1,
    situationTr: 'Çözümün kusursuz olmadan uygulanabilir olduğunu nüanslı biçimde söyle.',
    hintTr: 'sans être · avoir le mérite de',
    modelAnswer: 'Sans être parfaite, cette solution a le mérite d’être réalisable.',
    acceptedAnswers: <String>['Sans être parfaite, cette solution a le mérite d’être réalisable.', 'Cette solution, sans être parfaite, a le mérite d’être réalisable.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['sans être parfaite'], feedback: 'Çekinceyi “sans être parfaite” ile kur.'),
      SentenceRequirement(type: SentenceIssueType.article, alternatives: <String>['cette solution'], feedback: 'Belirli çözüm için “cette solution”.'),
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>["a le mérite d'être réalisable"], feedback: 'Olumlu yanı “a le mérite d’être réalisable” ile belirt.'),
    ],
    orderAnchors: <List<String>>[<String>['sans être parfaite', 'cette solution'], <String>["a le mérite d'être réalisable"]],
  ),
  SentencePrompt(
    id: 'c1_relative', level: CefrLevel.c1,
    situationTr: 'Sözünü ettiğin raporun varsayımlarını sorguladığını söyle.',
    hintTr: 'rapport · dont · remettre en question',
    modelAnswer: 'Le rapport dont je vous ai parlé remet en question plusieurs hypothèses.',
    acceptedAnswers: <String>['Le rapport dont je vous ai parlé remet en question plusieurs hypothèses.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.article, alternatives: <String>['le rapport'], feedback: 'Belirli rapor için “le rapport”.'),
      SentenceRequirement(type: SentenceIssueType.preposition, alternatives: <String>['dont je vous ai parlé'], feedback: '“Parler de” tamamlayıcısını “dont” ile bağla.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['remet en question'], feedback: '“Remettre” → “remet en question”.'),
    ],
    orderAnchors: <List<String>>[<String>['le rapport'], <String>['dont'], <String>['remet en question']],
  ),
  SentencePrompt(
    id: 'c1_concession', level: CefrLevel.c1,
    situationTr: 'İtirazların meşru olduğunu kabul et ama kararın gerekli olduğunu savun.',
    hintTr: 'certes · néanmoins',
    modelAnswer: 'Certes, leurs objections sont légitimes; néanmoins, cette décision demeure nécessaire.',
    acceptedAnswers: <String>['Certes, leurs objections sont légitimes; néanmoins, cette décision demeure nécessaire.', 'Leurs objections sont certes légitimes, mais cette décision reste nécessaire.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['certes'], feedback: 'Önce ödün vermek için “certes” kullan.'),
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['objections sont légitimes'], feedback: 'İtirazların meşruluğunu açıkça kabul et.'),
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['néanmoins', 'mais'], feedback: 'Karşı savı “néanmoins” veya “mais” ile bağla.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['demeure nécessaire', 'reste nécessaire'], feedback: 'Kararın gerekli kaldığını belirt.'),
    ],
    orderAnchors: <List<String>>[<String>['certes'], <String>['objections'], <String>['néanmoins', 'mais'], <String>['nécessaire']],
  ),
  SentencePrompt(
    id: 'c2_inversion', level: CefrLevel.c2,
    situationTr: 'Teklif cazip görünse bile ciddi çekinceler doğurduğunu resmî biçimde söyle.',
    hintTr: 'aussi séduisante soit-elle · susciter des réserves',
    modelAnswer: 'Aussi séduisante soit-elle, cette proposition suscite de sérieuses réserves.',
    acceptedAnswers: <String>['Aussi séduisante soit-elle, cette proposition suscite de sérieuses réserves.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['aussi séduisante soit-elle'], feedback: 'Ödün yapısını subjonctif devrik biçimde kur: “aussi… soit-elle”.'),
      SentenceRequirement(type: SentenceIssueType.article, alternatives: <String>['cette proposition'], feedback: 'Belirli teklif için “cette proposition”.'),
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['suscite de sérieuses réserves'], feedback: 'Resmî ifade: “suscite de sérieuses réserves”.'),
    ],
    orderAnchors: <List<String>>[<String>['aussi séduisante soit-elle'], <String>['cette proposition'], <String>['suscite']],
  ),
  SentencePrompt(
    id: 'c2_ne_expletif', level: CefrLevel.c2,
    situationTr: 'Durumun kötüleşmesinden korktuğunu seçkin bir üslupla söyle.',
    hintTr: 'craindre que · ne explétif · se détériorer',
    modelAnswer: 'Je crains que la situation ne se détériore davantage.',
    acceptedAnswers: <String>['Je crains que la situation ne se détériore davantage.', 'Je crains que la situation se détériore davantage.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['je crains que'], feedback: 'Korkuyu “je crains que” ile ifade et.'),
      SentenceRequirement(type: SentenceIssueType.article, alternatives: <String>['la situation'], feedback: '“Situation” dişildir: “la situation”.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['ne se détériore', 'se détériore'], feedback: '“Craindre que” sonrasında subjonctif: “se détériore”.'),
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>['davantage'], feedback: '“Daha da” nüansı için “davantage”.'),
    ],
    orderAnchors: <List<String>>[<String>['je crains'], <String>['la situation'], <String>['se détériore'], <String>['davantage']],
  ),
  SentencePrompt(
    id: 'c2_literary', level: CefrLevel.c2,
    situationTr: 'Kararın çok az farkla felakete yol açmadığını edebî biçimde söyle.',
    hintTr: 'il s’en est fallu de peu que · tourner au désastre',
    modelAnswer: 'Il s’en est fallu de peu que cette décision ne tourne au désastre.',
    acceptedAnswers: <String>['Il s’en est fallu de peu que cette décision ne tourne au désastre.'],
    requirements: <SentenceRequirement>[
      SentenceRequirement(type: SentenceIssueType.vocabulary, alternatives: <String>["il s'en est fallu de peu"], feedback: '“Az kalsın” için “il s’en est fallu de peu”.'),
      SentenceRequirement(type: SentenceIssueType.article, alternatives: <String>['cette décision'], feedback: 'Belirli karar için “cette décision”.'),
      SentenceRequirement(type: SentenceIssueType.conjugation, alternatives: <String>['ne tourne'], feedback: 'Bu yapıda subjonctif “ne tourne” kullan.'),
      SentenceRequirement(type: SentenceIssueType.preposition, alternatives: <String>['au désastre'], feedback: '“Tourner à” birleşir: “au désastre”.'),
    ],
    orderAnchors: <List<String>>[<String>["il s'en est fallu"], <String>['cette décision'], <String>['ne tourne'], <String>['au désastre']],
  ),
];

List<SentencePrompt> promptsForLevel(CefrLevel level) => sentencePromptCatalog
    .where((SentencePrompt prompt) => prompt.level == level)
    .toList(growable: false);
