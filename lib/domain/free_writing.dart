enum WritingIssueType {
  agreement,
  article,
  conjugation,
  preposition,
  negation,
  elision,
  wordOrder,
  spelling,
  punctuation,
  style,
}

extension WritingIssueTypeX on WritingIssueType {
  String get label => switch (this) {
        WritingIssueType.agreement => 'Uyumluluk',
        WritingIssueType.article => 'Artikel',
        WritingIssueType.conjugation => 'Fiil çekimi',
        WritingIssueType.preposition => 'Edat',
        WritingIssueType.negation => 'Olumsuzluk',
        WritingIssueType.elision => 'Kesme / daralma',
        WritingIssueType.wordOrder => 'Kelime sırası',
        WritingIssueType.spelling => 'Yazım / aksan',
        WritingIssueType.punctuation => 'Noktalama',
        WritingIssueType.style => 'Doğallık',
      };
}

enum WritingIssueSeverity { suggestion, error }

class WritingIssue {
  const WritingIssue({
    required this.type,
    required this.message,
    required this.rule,
    required this.severity,
    this.original,
    this.suggestion,
  });

  final WritingIssueType type;
  final WritingIssueSeverity severity;
  final String message;
  final String rule;
  final String? original;
  final String? suggestion;
}

class WritingEvaluation {
  const WritingEvaluation({
    required this.score,
    required this.correctedText,
    required this.issues,
    required this.strengths,
    required this.wordCount,
    required this.sentenceCount,
  });

  final int score;
  final String correctedText;
  final List<WritingIssue> issues;
  final List<String> strengths;
  final int wordCount;
  final int sentenceCount;

  bool get hasErrors => issues.any(
        (WritingIssue issue) => issue.severity == WritingIssueSeverity.error,
      );
}

class _WritingRule {
  const _WritingRule({
    required this.pattern,
    required this.replacement,
    required this.type,
    required this.message,
    required this.rule,
    this.severity = WritingIssueSeverity.error,
  });

  final RegExp pattern;
  final String Function(Match match) replacement;
  final WritingIssueType type;
  final WritingIssueSeverity severity;
  final String message;
  final String rule;
}

/// Serbest Fransızca metin için çevrimdışı, açıklamalı ön kontrol.
///
/// Bu motor bir üretken yapay zekâ değildir. Sık yapılan ve güvenle
/// açıklanabilen hataları düzeltir; emin olmadığı yapıları yanlış diye
/// işaretlemek yerine olduğu gibi bırakır.
class FreeWritingAnalyzer {
  const FreeWritingAnalyzer._();

  static final List<_WritingRule> _rules = <_WritingRule>[
    _literalRule(
      r'\bce est\b',
      "c'est",
      WritingIssueType.elision,
      '“Ce est” yerine “c’est” yazılır.',
      'Ce, est önünde apostrofla daralır.',
    ),
    _literalRule(
      r'\bque il\b',
      "qu'il",
      WritingIssueType.elision,
      '“Que il” yerine “qu’il” yazılır.',
      'Que, sesliyle başlayan il önünde daralır.',
    ),
    _literalRule(
      r'\bsi il\b',
      "s'il",
      WritingIssueType.elision,
      '“Si il” yerine “s’il” yazılır.',
      'Si yalnızca il ve ils önünde daralır.',
    ),
    _literalRule(
      r'\bà le\b',
      'au',
      WritingIssueType.preposition,
      '“À le” birleşerek “au” olur.',
      'à + le = au',
    ),
    _literalRule(
      r'\bà les\b',
      'aux',
      WritingIssueType.preposition,
      '“À les” birleşerek “aux” olur.',
      'à + les = aux',
    ),
    _literalRule(
      r'\bde le\b',
      'du',
      WritingIssueType.preposition,
      '“De le” birleşerek “du” olur.',
      'de + le = du',
    ),
    _literalRule(
      r'\bde les\b',
      'des',
      WritingIssueType.preposition,
      '“De les” birleşerek “des” olur.',
      'de + les = des',
    ),
    _literalRule(
      r'\bbeaucoup des\b',
      'beaucoup de',
      WritingIssueType.preposition,
      'Miktar ifadesinden sonra “de” kullan.',
      'beaucoup de + isim',
    ),
    _literalRule(
      r'\ben paris\b',
      'à Paris',
      WritingIssueType.preposition,
      'Şehir adından önce “à” kullanılır.',
      'à + şehir; en + dişil ülke',
    ),
    _literalRule(
      r'\b(?:à|au) france\b',
      'en France',
      WritingIssueType.preposition,
      'France ile “en France” kullanılır.',
      'Dişil ülke adlarından önce en gelir.',
    ),
    _patternRule(
      r'\bje suis\s+([0-9]{1,3})\s+ans\b',
      (Match match) => "j'ai ${match[1]} ans",
      WritingIssueType.conjugation,
      'Yaş söylerken être değil avoir kullanılır.',
      'je suis 25 ans → j’ai 25 ans',
    ),
    _patternRule(
      r'\b(les|des|mes|tes|ses|ces)\s+([a-zà-ÿ][a-zà-ÿ\-]*)\s+est\b',
      (Match match) => '${match[1]} ${match[2]} sont',
      WritingIssueType.agreement,
      'Çoğul özneyle “être” fiilini çoğul çek.',
      'Çoğul özne + sont',
    ),
    ..._commonConjugationRules,
    _patternRule(
      r'\b(je|tu|il|elle|on|nous|vous|ils|elles)\s+pas\s+([a-zà-ÿ][a-zà-ÿ\-]*)\b',
      (Match match) => '${match[1]} ne ${match[2]} pas',
      WritingIssueType.negation,
      '“Pas” çekimli fiilden sonra gelmeli.',
      'Temel olumsuzluk: özne + ne + fiil + pas.',
    ),
    _patternRule(
      r'\bje\s+(?=[aeiouyéèêëàâîïôöùûü])',
      (_) => "j'",
      WritingIssueType.elision,
      'Je, sesliyle başlayan kelimeden önce “j’” olur.',
      'je aime → j’aime',
    ),
    _patternRule(
      r'\b(le|la)\s+(?=[aeiouyéèêëàâîïôöùûü])',
      (_) => "l'",
      WritingIssueType.elision,
      'Le/la, sesliyle başlayan kelimeden önce “l’” olur.',
      'le ami → l’ami',
    ),
    _patternRule(
      r'\bde\s+(?=[aeiouyéèêëàâîïôöùûü])',
      (_) => "d'",
      WritingIssueType.elision,
      'De, sesliyle başlayan kelimeden önce “d’” olur.',
      'de accord → d’accord',
    ),
    ..._genderRules,
    ..._accentRules,
    _patternRule(
      r'\s+([,.])',
      (Match match) => match[1]!,
      WritingIssueType.punctuation,
      'Virgül ve noktadan önce boşluk bırakılmaz.',
      'Fransızcada virgül ve nokta önceki kelimeye bitişir.',
      severity: WritingIssueSeverity.suggestion,
    ),
  ];

  static WritingEvaluation analyze(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const WritingEvaluation(
        score: 0,
        correctedText: '',
        issues: <WritingIssue>[
          WritingIssue(
            type: WritingIssueType.spelling,
            severity: WritingIssueSeverity.error,
            message: 'İncelemek için Fransızca bir metin yaz.',
            rule: 'Bir veya birkaç tam cümle yazabilirsin.',
          ),
        ],
        strengths: <String>[],
        wordCount: 0,
        sentenceCount: 0,
      );
    }

    String corrected = trimmed.replaceAll('’', "'");
    final List<WritingIssue> issues = <WritingIssue>[];
    for (final _WritingRule rule in _rules) {
      final List<Match> matches = rule.pattern.allMatches(corrected).toList();
      if (matches.isEmpty) continue;
      for (final Match match in matches) {
        final String original = match.group(0)!;
        final String suggestion = rule.replacement(match);
        issues.add(
          WritingIssue(
            type: rule.type,
            severity: rule.severity,
            message: rule.message,
            rule: rule.rule,
            original: original,
            suggestion: suggestion,
          ),
        );
      }
      corrected = corrected.replaceAllMapped(rule.pattern, rule.replacement);
    }

    corrected = _sentenceCapitalization(corrected, issues);
    _checkUnclosedNegation(corrected, issues);
    _checkStyle(corrected, issues);
    if (!RegExp(r'[.!?]$').hasMatch(corrected.trim())) {
      issues.add(const WritingIssue(
        type: WritingIssueType.punctuation,
        severity: WritingIssueSeverity.suggestion,
        message: 'Metni bir cümle sonu işaretiyle tamamla.',
        rule: 'Bildirme cümlesi noktayla, soru soru işaretiyle biter.',
        suggestion: '.',
      ));
      corrected = '${corrected.trim()}.';
    }

    final List<String> words = RegExp(r"[A-Za-zÀ-ÿŒœ'’-]+")
        .allMatches(trimmed)
        .map((Match match) => match.group(0)!)
        .toList();
    final int sentenceCount = RegExp(r'[^.!?]+[.!?]?')
        .allMatches(trimmed)
        .where((Match match) => match.group(0)!.trim().isNotEmpty)
        .length;
    final int penalty = issues.fold<int>(
      0,
      (int sum, WritingIssue issue) =>
          sum + (issue.severity == WritingIssueSeverity.error ? 11 : 4),
    );
    final int score = (100 - penalty).clamp(0, 100);
    final Set<WritingIssueType> types =
        issues.map((WritingIssue issue) => issue.type).toSet();
    final List<String> strengths = <String>[
      if (!types.contains(WritingIssueType.conjugation))
        'Temel özne-fiil çekimlerinde belirgin hata görünmüyor.',
      if (!types.contains(WritingIssueType.article) &&
          !types.contains(WritingIssueType.agreement))
        'Artikel ve isim uyumu temiz görünüyor.',
      if (RegExp(
        r'\b(parce que|mais|donc|cependant|pourtant|puisque|bien que)\b',
        caseSensitive: false,
      ).hasMatch(corrected))
        'Fikirleri bir bağlaçla birbirine bağlamışsın.',
      if (words.length >= 12) 'Tek cümlenin ötesinde ayrıntı vermişsin.',
      if (issues.isEmpty) 'Kontrol edilen yaygın kurallarda hata bulunmadı.',
    ];

    return WritingEvaluation(
      score: score,
      correctedText: corrected.replaceAll("'", '’'),
      issues: List<WritingIssue>.unmodifiable(issues),
      strengths: List<String>.unmodifiable(strengths),
      wordCount: words.length,
      sentenceCount: sentenceCount,
    );
  }

  static String _sentenceCapitalization(
    String text,
    List<WritingIssue> issues,
  ) {
    final StringBuffer output = StringBuffer();
    bool capitalize = true;
    bool changed = false;
    for (int i = 0; i < text.length; i++) {
      final String char = text[i];
      if (capitalize && RegExp(r'[a-zà-ÿ]').hasMatch(char)) {
        output.write(char.toUpperCase());
        capitalize = false;
        changed = true;
      } else {
        output.write(char);
        if (RegExp(r'[A-ZÀ-Ÿ]').hasMatch(char)) capitalize = false;
      }
      if (char == '.' || char == '!' || char == '?') capitalize = true;
    }
    if (changed) {
      issues.add(const WritingIssue(
        type: WritingIssueType.punctuation,
        severity: WritingIssueSeverity.suggestion,
        message: 'Cümleye büyük harfle başla.',
        rule: 'Her yeni cümle büyük harfle başlar.',
      ));
    }
    return output.toString();
  }

  static void _checkUnclosedNegation(
    String text,
    List<WritingIssue> issues,
  ) {
    for (final String sentence in text.split(RegExp(r'[.!?]+'))) {
      final String lower = sentence.toLowerCase();
      final bool beginsNegation =
          RegExp(r"\b(ne|n')\b").hasMatch(lower) || lower.contains("n'");
      final bool closesNegation = RegExp(
        r'\b(pas|plus|jamais|rien|personne)\b',
      ).hasMatch(lower);
      if (beginsNegation && !closesNegation) {
        issues.add(const WritingIssue(
          type: WritingIssueType.negation,
          severity: WritingIssueSeverity.error,
          message: 'Olumsuzluk ikinci parçasını kaybetmiş olabilir.',
          rule: 'Genellikle ne/n’ + fiil + pas, plus veya jamais kullanılır.',
          suggestion: 'ne … pas',
        ));
      }
    }
  }

  static void _checkStyle(String text, List<WritingIssue> issues) {
    final int veryCount =
        RegExp(r'\btrès\b', caseSensitive: false).allMatches(text).length;
    if (veryCount >= 3) {
      issues.add(const WritingIssue(
        type: WritingIssueType.style,
        severity: WritingIssueSeverity.suggestion,
        message: '“Très” sık tekrarlanıyor; daha özel sıfatlar deneyebilirsin.',
        rule: 'Örn. très fatigué → épuisé; très content → ravi.',
      ));
    }
    for (final String sentence in text.split(RegExp(r'[.!?]+'))) {
      final int count =
          RegExp(r"[A-Za-zÀ-ÿŒœ'’-]+").allMatches(sentence).length;
      if (count > 28) {
        issues.add(const WritingIssue(
          type: WritingIssueType.style,
          severity: WritingIssueSeverity.suggestion,
          message: 'Bu cümle oldukça uzun; iki cümleye bölmek daha doğal olur.',
          rule: '28 kelimeyi aşan cümlelerde ana fikri görünür tut.',
        ));
      }
    }
  }

  static _WritingRule _literalRule(
    String pattern,
    String replacement,
    WritingIssueType type,
    String message,
    String rule,
  ) =>
      _patternRule(
        pattern,
        (_) => replacement,
        type,
        message,
        rule,
      );

  static _WritingRule _patternRule(
    String pattern,
    String Function(Match match) replacement,
    WritingIssueType type,
    String message,
    String rule, {
    WritingIssueSeverity severity = WritingIssueSeverity.error,
  }) =>
      _WritingRule(
        pattern: RegExp(pattern, caseSensitive: false),
        replacement: replacement,
        type: type,
        message: message,
        rule: rule,
        severity: severity,
      );

  static List<_WritingRule> get _commonConjugationRules {
    const Map<String, String> corrections = <String, String>{
      'je est': 'je suis',
      'tu est': 'tu es',
      'nous êtes': 'nous sommes',
      'vous sont': 'vous êtes',
      'ils est': 'ils sont',
      'elles est': 'elles sont',
      'je a': "j'ai",
      'tu a': 'tu as',
      'nous avez': 'nous avons',
      'vous avons': 'vous avez',
      'ils a': 'ils ont',
      'elles a': 'elles ont',
      'je va': 'je vais',
      'tu va': 'tu vas',
      'nous allez': 'nous allons',
      'vous allons': 'vous allez',
      'ils va': 'ils vont',
      'elles va': 'elles vont',
      'je fait': 'je fais',
      'nous faites': 'nous faisons',
      'vous faisons': 'vous faites',
      'ils fait': 'ils font',
      'je peut': 'je peux',
      'nous pouvez': 'nous pouvons',
      'vous pouvons': 'vous pouvez',
      'ils peut': 'ils peuvent',
      'je veut': 'je veux',
      'nous voulez': 'nous voulons',
      'vous voulons': 'vous voulez',
      'ils veut': 'ils veulent',
      'je suis faim': "j'ai faim",
      'je suis soif': "j'ai soif",
      'je suis froid': "j'ai froid",
      'je suis chaud': "j'ai chaud",
    };
    return corrections.entries
        .map(
          (MapEntry<String, String> entry) => _literalRule(
            '\\b${RegExp.escape(entry.key)}\\b',
            entry.value,
            WritingIssueType.conjugation,
            'Özneyle uyuşan fiil biçimini kullan.',
            '${entry.key} → ${entry.value}',
          ),
        )
        .toList(growable: false);
  }

  static List<_WritingRule> get _genderRules {
    const Map<String, String> corrections = <String, String>{
      'un maison': 'une maison',
      'un voiture': 'une voiture',
      'un question': 'une question',
      'un langue': 'une langue',
      'un idée': 'une idée',
      'un chose': 'une chose',
      'un personne': 'une personne',
      'un ville': 'une ville',
      'un journée': 'une journée',
      'une café': 'un café',
      'une problème': 'un problème',
      'une travail': 'un travail',
      'une téléphone': 'un téléphone',
      'une voyage': 'un voyage',
      'une fromage': 'un fromage',
    };
    return corrections.entries
        .map(
          (MapEntry<String, String> entry) => _literalRule(
            '\\b${RegExp.escape(entry.key)}\\b',
            entry.value,
            WritingIssueType.article,
            'İsmin cinsiyetine uygun artikeli kullan.',
            '${entry.key} → ${entry.value}',
          ),
        )
        .toList(growable: false);
  }

  static List<_WritingRule> get _accentRules {
    const Map<String, String> corrections = <String, String>{
      'tres': 'très',
      'apres': 'après',
      'deja': 'déjà',
      'meme': 'même',
      'francais': 'français',
      'francaise': 'française',
      'garcon': 'garçon',
      'lecon': 'leçon',
      'ecole': 'école',
      'etudiant': 'étudiant',
      'etudiante': 'étudiante',
      'cafe': 'café',
    };
    return corrections.entries
        .map(
          (MapEntry<String, String> entry) => _literalRule(
            '\\b${entry.key}\\b',
            entry.value,
            WritingIssueType.spelling,
            'Fransızca aksanı ekle.',
            '${entry.key} → ${entry.value}',
          ),
        )
        .toList(growable: false);
  }
}
