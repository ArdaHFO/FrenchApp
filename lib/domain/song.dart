import 'level.dart';

/// Bir şarkı sözündeki dokunulabilir kelime.
class SongWord {
  const SongWord(this.text, this.meaningTr, {String? lemma})
      : lemma = lemma ?? text;

  final String text;
  final String lemma;
  final String meaningTr;
}

/// Oynatma zamanına bağlı bir söz satırı.
class SongLyricLine {
  const SongLyricLine({
    required this.start,
    required this.words,
    required this.translationTr,
  });

  final Duration start;
  final List<SongWord> words;
  final String translationTr;

  String get text => words.map((SongWord word) => word.text).join(' ');
}

/// İnternetten oynatılan ve öğrenme verisi yerelde tutulan şarkı.
class LearningSong {
  const LearningSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.level,
    required this.duration,
    required this.audioUrl,
    required this.sourcePageUrl,
    required this.licenseLabel,
    required this.attribution,
    required this.colorValue,
    required this.lyrics,
  });

  final String id;
  final String title;
  final String artist;
  final CefrLevel level;
  final Duration duration;
  final String audioUrl;
  final String sourcePageUrl;
  final String licenseLabel;
  final String attribution;
  final int colorValue;
  final List<SongLyricLine> lyrics;

  List<SongWord> get quizWords {
    final Map<String, SongWord> unique = <String, SongWord>{};
    for (final SongLyricLine line in lyrics) {
      for (final SongWord word in line.words) {
        unique.putIfAbsent(word.lemma.toLowerCase(), () => word);
      }
    }
    return unique.values
        .where((SongWord word) => word.meaningTr.length > 1)
        .toList(growable: false);
  }
}

class SongQuizQuestion {
  const SongQuizQuestion({
    required this.word,
    required this.options,
    required this.correctIndex,
  });

  final SongWord word;
  final List<String> options;
  final int correctIndex;
}

abstract final class SongQuizEngine {
  static List<SongQuizQuestion> build(LearningSong song, {int count = 5}) {
    if (count <= 0) return const <SongQuizQuestion>[];
    final List<SongWord> words = song.quizWords;
    final List<String> meanings = words
        .map((SongWord word) => word.meaningTr)
        .toSet()
        .toList(growable: false);
    final int take = count.clamp(0, words.length).toInt();
    return <SongQuizQuestion>[
      for (int index = 0; index < take; index++)
        _question(words[index], meanings, index),
    ];
  }

  static SongQuizQuestion _question(
    SongWord word,
    List<String> meanings,
    int seed,
  ) {
    final List<String> distractors = meanings
        .where((String meaning) => meaning != word.meaningTr)
        .toList(growable: false);
    final List<String> options = <String>[
      for (int offset = 0; offset < 3 && offset < distractors.length; offset++)
        distractors[(seed + offset) % distractors.length],
    ];
    final int correctIndex = seed % (options.length + 1);
    options.insert(correctIndex, word.meaningTr);
    return SongQuizQuestion(
      word: word,
      options: List<String>.unmodifiable(options),
      correctIndex: correctIndex,
    );
  }
}

/// YouTube üzerinden dinlenen şarkıların ses/video dosyaları uygulamada
/// tutulmaz. Yalnızca video kimliği ve bağımsız kelime notları saklanır.
class PopularSong {
  const PopularSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.videoId,
    required this.level,
    required this.year,
    required this.mood,
    required this.colorValue,
    required this.focusWords,
    this.isTraditional = false,
  });

  final String id;
  final String title;
  final String artist;
  final String videoId;
  final CefrLevel level;
  final int year;
  final String mood;
  final int colorValue;
  final List<SongWord> focusWords;
  final bool isTraditional;

  String get thumbnailUrl =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
}

abstract final class PopularSongCatalog {
  static const List<PopularSong> songs = <PopularSong>[
    PopularSong(
      id: 'stromae_papaoutai',
      title: 'Papaoutai',
      artist: 'Stromae',
      videoId: 'oiKj0Z_Xnjc',
      level: CefrLevel.a2,
      year: 2013,
      mood: 'Ritimli · Hikâyeli',
      colorValue: 0xFFF2A93B,
      focusWords: <SongWord>[
        SongWord('papa', 'baba'),
        SongWord('où', 'nerede'),
        SongWord('chercher', 'aramak'),
        SongWord('absent', 'yok / uzakta'),
      ],
    ),
    PopularSong(
      id: 'indila_derniere_danse',
      title: 'Dernière danse',
      artist: 'Indila',
      videoId: 'K5KAc5CoCuk',
      level: CefrLevel.a2,
      year: 2013,
      mood: 'Duygusal · Sinematik',
      colorValue: 0xFF6C63FF,
      focusWords: <SongWord>[
        SongWord('dernière', 'son / en sonuncu', lemma: 'dernier'),
        SongWord('danse', 'dans', lemma: 'danse'),
        SongWord('douleur', 'acı'),
        SongWord('espoir', 'umut'),
      ],
    ),
    PopularSong(
      id: 'zaz_je_veux',
      title: 'Je veux',
      artist: 'ZAZ',
      videoId: '0TFNGRYMz1U',
      level: CefrLevel.a2,
      year: 2010,
      mood: 'Neşeli · Akustik',
      colorValue: 0xFFE85D75,
      focusWords: <SongWord>[
        SongWord('je', 'ben'),
        SongWord('veux', 'istiyorum', lemma: 'vouloir'),
        SongWord('joie', 'neşe'),
        SongWord('amour', 'aşk / sevgi'),
      ],
    ),
    PopularSong(
      id: 'angele_balance_ton_quoi',
      title: 'Balance ton quoi',
      artist: 'Angèle',
      videoId: 'Hi7Rx3En7-k',
      level: CefrLevel.b1,
      year: 2019,
      mood: 'Modern pop · Toplumsal',
      colorValue: 0xFFFF7AA2,
      focusWords: <SongWord>[
        SongWord('balance', 'söyle / ortaya dök', lemma: 'balancer'),
        SongWord('quoi', 'ne / neyi'),
        SongWord('égalité', 'eşitlik'),
        SongWord('respect', 'saygı'),
      ],
    ),
    PopularSong(
      id: 'aya_nakamura_djadja',
      title: 'Djadja',
      artist: 'Aya Nakamura',
      videoId: 'iPGgnzc34tY',
      level: CefrLevel.b1,
      year: 2018,
      mood: 'Urban pop · Argo',
      colorValue: 0xFFB45CE0,
      focusWords: <SongWord>[
        SongWord('djadja', 'adam / erkek (argo)'),
        SongWord('parler', 'konuşmak'),
        SongWord('mensonge', 'yalan'),
        SongWord('confiance', 'güven'),
      ],
    ),
    PopularSong(
      id: 'clara_luciani_la_grenade',
      title: 'La grenade',
      artist: 'Clara Luciani',
      videoId: '85m-Qgo9_nE',
      level: CefrLevel.b1,
      year: 2018,
      mood: 'Pop-rock · Güçlü',
      colorValue: 0xFFE04444,
      focusWords: <SongWord>[
        SongWord('grenade', 'el bombası / nar'),
        SongWord('force', 'güç'),
        SongWord('cœur', 'kalp'),
        SongWord('courage', 'cesaret'),
      ],
    ),
    PopularSong(
      id: 'trad_au_clair_de_la_lune',
      title: 'Au clair de la lune',
      artist: 'Les comptines de Gabriel',
      videoId: 'yN38P4DypUo',
      level: CefrLevel.a1,
      year: 0,
      mood: 'Ninni · Karaoke',
      colorValue: 0xFF5865D8,
      isTraditional: true,
      focusWords: <SongWord>[
        SongWord('clair', 'aydınlık / açık'),
        SongWord('lune', 'ay'),
        SongWord('plume', 'tüy / eski tip kalem'),
        SongWord('porte', 'kapı'),
      ],
    ),
    PopularSong(
      id: 'trad_une_souris_verte',
      title: 'Une souris verte',
      artist: 'Didier Jeunesse',
      videoId: 'XvTQJM7mh28',
      level: CefrLevel.a1,
      year: 0,
      mood: 'Neşeli · Kelime oyunu',
      colorValue: 0xFF38A66B,
      isTraditional: true,
      focusWords: <SongWord>[
        SongWord('souris', 'fare'),
        SongWord('verte', 'yeşil', lemma: 'vert'),
        SongWord('courir', 'koşmak'),
        SongWord('queue', 'kuyruk'),
      ],
    ),
    PopularSong(
      id: 'trad_meunier_tu_dors',
      title: 'Meunier, tu dors',
      artist: 'HeyKids France',
      videoId: 'H5MmRUPOKGE',
      level: CefrLevel.a1,
      year: 0,
      mood: 'Ritimli · Tekrarlı',
      colorValue: 0xFFE9A23B,
      isTraditional: true,
      focusWords: <SongWord>[
        SongWord('meunier', 'değirmenci'),
        SongWord('dors', 'uyuyorsun', lemma: 'dormir'),
        SongWord('moulin', 'değirmen'),
        SongWord('vent', 'rüzgâr'),
      ],
    ),
    PopularSong(
      id: 'trad_plante_les_choux',
      title: 'Savez-vous planter les choux ?',
      artist: 'Titounis',
      videoId: 'N1VASpNwqO8',
      level: CefrLevel.a1,
      year: 0,
      mood: 'Hareketli · Vücut kelimeleri',
      colorValue: 0xFF63AA45,
      isTraditional: true,
      focusWords: <SongWord>[
        SongWord('planter', 'ekmek / dikmek'),
        SongWord('choux', 'lahanalar', lemma: 'chou'),
        SongWord('doigt', 'parmak'),
        SongWord('genou', 'diz'),
      ],
    ),
    PopularSong(
      id: 'trad_vous_dirai_je_maman',
      title: 'Ah ! Vous dirai-je, maman',
      artist: 'HeyKids France',
      videoId: 'KVhCuCiX1Pc',
      level: CefrLevel.a1,
      year: 0,
      mood: 'Ninni · Karaoke',
      colorValue: 0xFFE16A97,
      isTraditional: true,
      focusWords: <SongWord>[
        SongWord('maman', 'anne'),
        SongWord('dirai', 'söyleyeceğim', lemma: 'dire'),
        SongWord('raison', 'sebep / akıl'),
        SongWord('leçon', 'ders'),
      ],
    ),
    PopularSong(
      id: 'trad_cadet_rousselle',
      title: 'Cadet Rousselle',
      artist: 'Comptines françaises',
      videoId: 'C5npydhILjQ',
      level: CefrLevel.a2,
      year: 0,
      mood: 'Hikâyeli · Tekrarlı',
      colorValue: 0xFFCB655A,
      isTraditional: true,
      focusWords: <SongWord>[
        SongWord('maison', 'ev'),
        SongWord('poutre', 'kiriş'),
        SongWord('hirondelle', 'kırlangıç'),
        SongWord('enfant', 'çocuk'),
      ],
    ),
    PopularSong(
      id: 'trad_a_la_claire_fontaine',
      title: 'À la claire fontaine',
      artist: 'HeyKids France',
      videoId: 'gVJ2R2ssFvo',
      level: CefrLevel.a2,
      year: 0,
      mood: 'Sakin · Şiirsel',
      colorValue: 0xFF3D91C8,
      isTraditional: true,
      focusWords: <SongWord>[
        SongWord('fontaine', 'çeşme / kaynak'),
        SongWord('promener', 'gezmek'),
        SongWord('feuille', 'yaprak'),
        SongWord("oublierai", 'unutacağım', lemma: 'oublier'),
      ],
    ),
  ];
}

/// İlk katalog yalnızca sözleri kamu malı olan geleneksel eserleri ve açık
/// lisanslı / kamu malı kayıtları kullanır. Ses APK'ya eklenmez.
abstract final class SongCatalog {
  static const List<LearningSong> songs = <LearningSong>[
    LearningSong(
      id: 'frere_jacques',
      title: 'Frère Jacques',
      artist: 'Geleneksel Fransız ezgisi',
      level: CefrLevel.a1,
      duration: Duration(seconds: 16),
      audioUrl:
          'https://upload.wikimedia.org/wikipedia/commons/e/ef/Fr%C3%A8re_Jacques.ogg',
      sourcePageUrl:
          'https://commons.wikimedia.org/wiki/File:Fr%C3%A8re_Jacques.ogg',
      licenseLabel: 'CC BY-SA 3.0',
      attribution: 'Kayıt: CambridgeBayWeather · Wikimedia Commons',
      colorValue: 0xFF6C63FF,
      lyrics: <SongLyricLine>[
        SongLyricLine(
          start: Duration.zero,
          translationTr: 'Jacques kardeş, Jacques kardeş',
          words: <SongWord>[
            SongWord('Frère', 'erkek kardeş', lemma: 'frère'),
            SongWord('Jacques,', 'Jacques (özel isim)', lemma: 'Jacques'),
            SongWord('frère', 'erkek kardeş', lemma: 'frère'),
            SongWord('Jacques', 'Jacques (özel isim)', lemma: 'Jacques'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 4),
          translationTr: 'Uyuyor musunuz? Uyuyor musunuz?',
          words: <SongWord>[
            SongWord('Dormez-vous?', 'uyuyor musunuz?', lemma: 'dormir'),
            SongWord('Dormez-vous?', 'uyuyor musunuz?', lemma: 'dormir'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 8),
          translationTr: 'Sabah çanlarını çalın!',
          words: <SongWord>[
            SongWord('Sonnez', 'çalın', lemma: 'sonner'),
            SongWord('les', 'belirli çoğul tanımlık', lemma: 'le'),
            SongWord('matines!', 'sabah duaları / çanları', lemma: 'matines'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 12),
          translationTr: 'Ding, dang, dong.',
          words: <SongWord>[
            SongWord('Ding,', 'çan sesi', lemma: 'ding'),
            SongWord('dang,', 'çan sesi', lemma: 'dang'),
            SongWord('dong', 'çan sesi', lemma: 'dong'),
          ],
        ),
      ],
    ),
    LearningSong(
      id: 'pont_avignon',
      title: "Sur le pont d'Avignon",
      artist: 'Geleneksel Fransız ezgisi',
      level: CefrLevel.a1,
      duration: Duration(seconds: 38),
      audioUrl:
          'https://upload.wikimedia.org/wikipedia/commons/a/a3/Sur_le_pont_d%27Avignon.ogg',
      sourcePageUrl:
          'https://commons.wikimedia.org/wiki/File:Sur_le_pont_d%27Avignon.ogg',
      licenseLabel: 'CC BY 3.0',
      attribution: 'Kayıt: CambridgeBayWeather · Wikimedia Commons',
      colorValue: 0xFFEF6C8F,
      lyrics: <SongLyricLine>[
        SongLyricLine(
          start: Duration.zero,
          translationTr: "Avignon Köprüsü'nün üzerinde",
          words: <SongWord>[
            SongWord('Sur', 'üzerinde', lemma: 'sur'),
            SongWord('le', 'belirli eril tanımlık', lemma: 'le'),
            SongWord('pont', 'köprü', lemma: 'pont'),
            SongWord("d'Avignon", "Avignon'un", lemma: 'Avignon'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 5),
          translationTr: 'Orada dans ederiz, orada dans ederiz',
          words: <SongWord>[
            SongWord("L'on", 'insan / biz (genel özne)', lemma: 'on'),
            SongWord('y', 'orada', lemma: 'y'),
            SongWord('danse,', 'dans eder', lemma: 'danser'),
            SongWord("l'on", 'insan / biz (genel özne)', lemma: 'on'),
            SongWord('y', 'orada', lemma: 'y'),
            SongWord('danse', 'dans eder', lemma: 'danser'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 11),
          translationTr: "Avignon Köprüsü'nün üzerinde",
          words: <SongWord>[
            SongWord('Sur', 'üzerinde', lemma: 'sur'),
            SongWord('le', 'belirli eril tanımlık', lemma: 'le'),
            SongWord('pont', 'köprü', lemma: 'pont'),
            SongWord("d'Avignon", "Avignon'un", lemma: 'Avignon'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 16),
          translationTr: 'Orada hep birlikte halka şeklinde dans ederiz',
          words: <SongWord>[
            SongWord("L'on", 'insan / biz (genel özne)', lemma: 'on'),
            SongWord('y', 'orada', lemma: 'y'),
            SongWord('danse', 'dans eder', lemma: 'danser'),
            SongWord('tous', 'hepimiz / herkes', lemma: 'tous'),
            SongWord('en', 'olarak / içinde', lemma: 'en'),
            SongWord('rond', 'halka / daire', lemma: 'rond'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 23),
          translationTr: 'Yakışıklı beyler böyle yapar',
          words: <SongWord>[
            SongWord('Les', 'belirli çoğul tanımlık', lemma: 'le'),
            SongWord('beaux', 'yakışıklı / güzel', lemma: 'beau'),
            SongWord('messieurs', 'beyler', lemma: 'monsieur'),
            SongWord('font', 'yaparlar', lemma: 'faire'),
            SongWord('comme', 'gibi', lemma: 'comme'),
            SongWord('ça', 'bu / böyle', lemma: 'ça'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 30),
          translationTr: 'Ve sonra yine böyle',
          words: <SongWord>[
            SongWord('Et', 've', lemma: 'et'),
            SongWord('puis', 'sonra', lemma: 'puis'),
            SongWord('encore', 'yine / tekrar', lemma: 'encore'),
            SongWord('comme', 'gibi', lemma: 'comme'),
            SongWord('ça', 'bu / böyle', lemma: 'ça'),
          ],
        ),
      ],
    ),
    LearningSong(
      id: 'alouette',
      title: 'Alouette',
      artist: 'Geleneksel Fransız-Kanada ezgisi',
      level: CefrLevel.a2,
      duration: Duration(seconds: 50),
      audioUrl:
          'https://upload.wikimedia.org/wikipedia/commons/4/47/Alouette_%28song%29.ogg',
      sourcePageUrl:
          'https://commons.wikimedia.org/wiki/File:Alouette_(song).ogg',
      licenseLabel: 'Kamu malı kayıt',
      attribution: 'Düzenleme: Ixnay · Wikimedia Commons',
      colorValue: 0xFF20B486,
      lyrics: <SongLyricLine>[
        SongLyricLine(
          start: Duration.zero,
          translationTr: 'Tarla kuşu, sevimli tarla kuşu',
          words: <SongWord>[
            SongWord('Alouette,', 'tarla kuşu', lemma: 'alouette'),
            SongWord('gentille', 'sevimli / nazik', lemma: 'gentil'),
            SongWord('alouette', 'tarla kuşu', lemma: 'alouette'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 6),
          translationTr: 'Tarla kuşu, tüylerini yolacağım',
          words: <SongWord>[
            SongWord('Alouette,', 'tarla kuşu', lemma: 'alouette'),
            SongWord('je', 'ben', lemma: 'je'),
            SongWord('te', 'seni / sana', lemma: 'te'),
            SongWord('plumerai', 'tüylerini yolacağım', lemma: 'plumer'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 13),
          translationTr: 'Başındaki tüyleri yolacağım',
          words: <SongWord>[
            SongWord('Je', 'ben', lemma: 'je'),
            SongWord('te', 'seni / sana', lemma: 'te'),
            SongWord('plumerai', 'tüylerini yolacağım', lemma: 'plumer'),
            SongWord('la', 'belirli dişil tanımlık', lemma: 'la'),
            SongWord('tête', 'baş', lemma: 'tête'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 20),
          translationTr: 'Başındaki tüyleri yolacağım',
          words: <SongWord>[
            SongWord('Je', 'ben', lemma: 'je'),
            SongWord('te', 'seni / sana', lemma: 'te'),
            SongWord('plumerai', 'tüylerini yolacağım', lemma: 'plumer'),
            SongWord('la', 'belirli dişil tanımlık', lemma: 'la'),
            SongWord('tête', 'baş', lemma: 'tête'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 27),
          translationTr: 'Ve başı, ve başı',
          words: <SongWord>[
            SongWord('Et', 've', lemma: 'et'),
            SongWord('la', 'belirli dişil tanımlık', lemma: 'la'),
            SongWord('tête,', 'baş', lemma: 'tête'),
            SongWord('et', 've', lemma: 'et'),
            SongWord('la', 'belirli dişil tanımlık', lemma: 'la'),
            SongWord('tête', 'baş', lemma: 'tête'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 34),
          translationTr: 'Tarla kuşu, tarla kuşu',
          words: <SongWord>[
            SongWord('Alouette,', 'tarla kuşu', lemma: 'alouette'),
            SongWord('alouette', 'tarla kuşu', lemma: 'alouette'),
          ],
        ),
        SongLyricLine(
          start: Duration(seconds: 41),
          translationTr: 'Ah, ah, ah, ah',
          words: <SongWord>[
            SongWord('Ah,', 'ünlem', lemma: 'ah'),
            SongWord('ah,', 'ünlem', lemma: 'ah'),
            SongWord('ah,', 'ünlem', lemma: 'ah'),
            SongWord('ah', 'ünlem', lemma: 'ah'),
          ],
        ),
      ],
    ),
  ];
}
