import 'level.dart';

class StoryAdventure {
  const StoryAdventure({
    required this.id,
    required this.level,
    required this.title,
    required this.subtitle,
    required this.startNodeId,
    required this.nodes,
    required this.quiz,
    this.chapter = 1,
  });

  final String id;
  final CefrLevel level;
  final String title;
  final String subtitle;
  final String startNodeId;
  final List<StoryNode> nodes;
  final List<StoryQuizQuestion> quiz;
  final int chapter;

  StoryNode node(String id) => nodes.firstWhere((StoryNode n) => n.id == id);
}

class StoryNode {
  const StoryNode({
    required this.id,
    required this.speaker,
    required this.text,
    required this.translation,
    this.glossary = const <StoryGlossary>[],
    this.choices = const <StoryChoice>[],
  });

  final String id;
  final String speaker;
  final String text;
  final String translation;
  final List<StoryGlossary> glossary;
  final List<StoryChoice> choices;

  bool get isEnding => choices.isEmpty;
}

class StoryChoice {
  const StoryChoice({
    required this.label,
    required this.nextNodeId,
    required this.coach,
    this.preferred = false,
  });

  final String label;
  final String nextNodeId;
  final String coach;
  final bool preferred;
}

class StoryGlossary {
  const StoryGlossary(this.word, this.meaning);

  final String word;
  final String meaning;
}

class StoryQuizQuestion {
  const StoryQuizQuestion({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String explanation;
}

const List<StoryAdventure> storyCatalog = <StoryAdventure>[
  StoryAdventure(
    id: 'a1_cafe',
    level: CefrLevel.a1,
    title: 'Kafedeki İlk Sipariş',
    subtitle: 'Selamlaş, sipariş ver ve hesabı iste.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Serveuse',
        text: 'Bonjour ! Vous désirez ?',
        translation: 'Merhaba! Ne arzu edersiniz?',
        glossary: <StoryGlossary>[
          StoryGlossary('désirez', 'arzu ediyorsunuz'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Je voudrais un café, s\'il vous plaît.',
            nextNodeId: 'polite',
            coach: 'Harika. “Je voudrais” nazik bir istek kalıbıdır.',
            preferred: true,
          ),
          StoryChoice(
            label: 'Donnez-moi un café.',
            nextNodeId: 'direct',
            coach: 'Anlaşılır ama emir gibi duyulur. Kafede “je voudrais” daha doğaldır.',
          ),
        ],
      ),
      StoryNode(
        id: 'polite',
        speaker: 'Serveuse',
        text: 'Bien sûr. Un café avec du lait ?',
        translation: 'Elbette. Sütlü bir kahve mi?',
        glossary: <StoryGlossary>[
          StoryGlossary('bien sûr', 'elbette'),
          StoryGlossary('lait', 'süt'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Non merci, sans lait.',
            nextNodeId: 'end',
            coach: '“Sans” bir şeyin olmadığını belirtir.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'direct',
        speaker: 'Serveuse',
        text: 'D’accord… Vous pouvez dire « je voudrais ».',
        translation: 'Peki… “Je voudrais” diyebilirsiniz.',
        glossary: <StoryGlossary>[
          StoryGlossary('pouvez', 'yapabilirsiniz'),
          StoryGlossary('dire', 'söylemek'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Pardon. Je voudrais un café.',
            nextNodeId: 'end',
            coach: 'Güzel düzeltme. Durumu nazikçe toparladın.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Serveuse',
        text: 'Voilà votre café. Bonne dégustation !',
        translation: 'Kahveniz burada. Afiyet olsun!',
        glossary: <StoryGlossary>[
          StoryGlossary('voilà', 'işte, burada'),
          StoryGlossary('dégustation', 'tadım'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Kibarca sipariş vermek için hangi kalıp kullanıldı?',
        options: <String>['Je voudrais…', 'Donnez-moi…', 'Je suis…'],
        correctIndex: 0,
        explanation: '“Je voudrais…” istekleri kibarca ifade eder.',
      ),
      StoryQuizQuestion(
        prompt: '“Sans lait” ne demektir?',
        options: <String>['Az sütlü', 'Sütsüz', 'Sıcak sütlü'],
        correctIndex: 1,
        explanation: '“Sans”, Türkçedeki “-siz/-sız” anlamını verir.',
      ),
    ],
  ),
  StoryAdventure(
    id: 'a2_train',
    level: CefrLevel.a2,
    title: 'Kaçırılan Tren',
    subtitle: 'Biletini değiştir ve doğru peronu bul.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Agent',
        text: 'Votre train est déjà parti. Que voulez-vous faire ?',
        translation: 'Treniniz çoktan kalktı. Ne yapmak istiyorsunuz?',
        glossary: <StoryGlossary>[
          StoryGlossary('déjà', 'çoktan'),
          StoryGlossary('parti', 'kalktı, ayrıldı'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Puis-je prendre le prochain train ?',
            nextNodeId: 'change',
            coach: '“Puis-je… ?” nazik ve doğru bir soru yapısıdır.',
            preferred: true,
          ),
          StoryChoice(
            label: 'Où est mon train ?',
            nextNodeId: 'clarify',
            coach: 'Soru doğru ama görevli trenin kalktığını söyledi. Ayrıntıyı dinlemek önemli.',
          ),
        ],
      ),
      StoryNode(
        id: 'change',
        speaker: 'Agent',
        text: 'Oui, mais il faut modifier votre billet.',
        translation: 'Evet, fakat biletinizi değiştirmeniz gerekiyor.',
        glossary: <StoryGlossary>[
          StoryGlossary('il faut', 'gerekiyor'),
          StoryGlossary('modifier', 'değiştirmek'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Très bien. Quel est le quai ?',
            nextNodeId: 'end',
            coach: '“Quai” istasyondaki perondur.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'clarify',
        speaker: 'Agent',
        text: 'Il est parti à neuf heures. Le prochain part à dix heures.',
        translation: 'Saat dokuzda kalktı. Sonraki saat onda kalkıyor.',
        glossary: <StoryGlossary>[
          StoryGlossary('prochain', 'sonraki'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Je comprends. Je prends le prochain.',
            nextNodeId: 'end',
            coach: 'Bağlamı düzelttin ve kararını açıkça söyledin.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Agent',
        text: 'Le train partira du quai six. Ne soyez pas en retard !',
        translation: 'Tren altıncı perondan kalkacak. Geç kalmayın!',
        glossary: <StoryGlossary>[
          StoryGlossary('partira', 'kalkacak'),
          StoryGlossary('en retard', 'geç kalmış'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Yolcunun ne yapması gerekiyor?',
        options: <String>['Bileti değiştirmek', 'Yeni bilet basmak', 'Taksiye binmek'],
        correctIndex: 0,
        explanation: 'Görevli “il faut modifier votre billet” dedi.',
      ),
      StoryQuizQuestion(
        prompt: 'Yeni tren nereden kalkacak?',
        options: <String>['Saat altıda', 'Altıncı perondan', 'Dokuzuncu perondan'],
        correctIndex: 1,
        explanation: '“Du quai six” altıncı perondan demektir.',
      ),
    ],
  ),
  StoryAdventure(
    id: 'b1_phone',
    level: CefrLevel.b1,
    title: 'Kayıp Telefonun İzinde',
    subtitle: 'Olayları anlat, ipuçlarını değerlendir.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Camille',
        text: 'Tu avais encore ton téléphone quand nous avons quitté le café ?',
        translation: 'Kafeden çıktığımızda telefonun hâlâ yanında mıydı?',
        glossary: <StoryGlossary>[
          StoryGlossary('quitté', 'ayrıldık'),
          StoryGlossary('encore', 'hâlâ'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Oui, je l’ai utilisé devant la boulangerie.',
            nextNodeId: 'bakery',
            coach: 'Nesne zamiri “l’”, telefonu tekrar etmeden belirtir.',
            preferred: true,
          ),
          StoryChoice(
            label: 'Je ne sais plus. Retournons au café.',
            nextNodeId: 'cafe',
            coach: '“Ne… plus” artık hatırlamama durumunu ifade ediyor.',
          ),
        ],
      ),
      StoryNode(
        id: 'bakery',
        speaker: 'Boulangère',
        text: 'J’ai trouvé un téléphone près de la vitrine. Pouvez-vous le décrire ?',
        translation: 'Vitrinin yanında bir telefon buldum. Onu tarif edebilir misiniz?',
        glossary: <StoryGlossary>[
          StoryGlossary('près', 'yakınında'),
          StoryGlossary('décrire', 'tarif etmek'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Il a une coque bleue et l’écran est cassé.',
            nextNodeId: 'end',
            coach: 'Ayırt edici iki özellik verdin; etkili bir tarif.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'cafe',
        speaker: 'Serveur',
        text: 'Je n’ai rien trouvé, mais demandez à la boulangerie d’à côté.',
        translation: 'Hiçbir şey bulmadım ama yan taraftaki fırına sorun.',
        glossary: <StoryGlossary>[
          StoryGlossary('rien', 'hiçbir şey'),
          StoryGlossary('à côté', 'yan tarafta'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Bonne idée, allons-y tout de suite.',
            nextNodeId: 'end',
            coach: '“Allons-y” birlikte harekete geçmeyi önerir.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Camille',
        text: 'On l’a retrouvé ! La prochaine fois, vérifie tes poches.',
        translation: 'Onu bulduk! Bir dahaki sefere ceplerini kontrol et.',
        glossary: <StoryGlossary>[
          StoryGlossary('retrouvé', 'yeniden bulduk'),
          StoryGlossary('poches', 'cepler'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Telefonun ayırt edici özelliği neydi?',
        options: <String>['Kırmızı kılıf', 'Mavi kılıf ve kırık ekran', 'Yeni ekran'],
        correctIndex: 1,
        explanation: 'Telefon “une coque bleue” ve kırık ekranla tarif edildi.',
      ),
      StoryQuizQuestion(
        prompt: '“On l’a retrouvé” cümlesindeki “l’” neyin yerini tutar?',
        options: <String>['Camille', 'Kafe', 'Telefon'],
        correctIndex: 2,
        explanation: 'Doğrudan nesne zamiri daha önce sözü geçen telefonu temsil eder.',
      ),
    ],
  ),
  StoryAdventure(
    id: 'b2_interview',
    level: CefrLevel.b2,
    title: 'Beklenmedik Mülakat',
    subtitle: 'Deneyimini savun ve bir sorunu çöz.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Recruteuse',
        text: 'Parlez-moi d’une difficulté que vous avez réussi à surmonter.',
        translation: 'Üstesinden gelmeyi başardığınız bir zorluktan söz edin.',
        glossary: <StoryGlossary>[
          StoryGlossary('surmonter', 'üstesinden gelmek'),
          StoryGlossary('réussi', 'başardınız'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Notre projet prenait du retard, j’ai donc réorganisé les priorités.',
            nextNodeId: 'specific',
            coach: 'Somut sorun ve eylem verdin; güçlü bir mülakat cevabı.',
            preferred: true,
          ),
          StoryChoice(
            label: 'Je travaille toujours très bien.',
            nextNodeId: 'vague',
            coach: 'Dilbilgisi doğru fakat soru somut bir örnek istiyor.',
          ),
        ],
      ),
      StoryNode(
        id: 'specific',
        speaker: 'Recruteuse',
        text: 'Quel a été le résultat de cette réorganisation ?',
        translation: 'Bu yeniden düzenlemenin sonucu ne oldu?',
        glossary: <StoryGlossary>[
          StoryGlossary('résultat', 'sonuç'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Bien que le délai soit court, nous avons livré à temps.',
            nextNodeId: 'end',
            coach: '“Bien que” sonrasında subjonctif “soit” kullandın.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'vague',
        speaker: 'Recruteuse',
        text: 'Pourriez-vous me donner un exemple concret ?',
        translation: 'Bana somut bir örnek verebilir misiniz?',
        glossary: <StoryGlossary>[
          StoryGlossary('concret', 'somut'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Oui. J’ai réorganisé un projet qui prenait du retard.',
            nextNodeId: 'end',
            coach: 'İkinci denemede kanıtlanabilir bir örnek verdin.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Recruteuse',
        text: 'Votre réponse est précise et convaincante. Merci.',
        translation: 'Cevabınız açık ve ikna edici. Teşekkürler.',
        glossary: <StoryGlossary>[
          StoryGlossary('convaincante', 'ikna edici'),
          StoryGlossary('précise', 'açık, kesin'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Güçlü cevabı etkili yapan neydi?',
        options: <String>['Çok uzun olması', 'Somut sorun, eylem ve sonuç', 'Sadece olumlu sıfatlar'],
        correctIndex: 1,
        explanation: 'Cevap bir problemi, yapılan eylemi ve ölçülebilir sonucu birbirine bağladı.',
      ),
      StoryQuizQuestion(
        prompt: '“Bien que” sonrasında hangi kip kullanıldı?',
        options: <String>['Impératif', 'Subjonctif', 'Conditionnel passé'],
        correctIndex: 1,
        explanation: '“Bien que” genellikle subjonctif gerektirir: soit.',
      ),
    ],
  ),
  StoryAdventure(
    id: 'c1_meeting',
    level: CefrLevel.c1,
    title: 'Mahalle Toplantısı',
    subtitle: 'Karşıt görüşleri uzlaştır ve nüanslı konuş.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Présidente',
        text: 'Les habitants sont divisés quant à la piétonnisation du quartier.',
        translation: 'Mahalle sakinleri bölgenin yayalaştırılması konusunda bölünmüş durumda.',
        glossary: <StoryGlossary>[
          StoryGlossary('quant à', 'konusunda, gelince'),
          StoryGlossary('piétonnisation', 'yayalaştırma'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Il faudrait concilier la tranquillité des riverains et l’accès aux commerces.',
            nextNodeId: 'balance',
            coach: 'İki meşru ihtiyacı aynı cümlede dengeledin.',
            preferred: true,
          ),
          StoryChoice(
            label: 'Il suffit d’interdire toutes les voitures.',
            nextNodeId: 'absolute',
            coach: 'Kesin bir öneri ama paydaşların kaygılarını dışarıda bırakıyor.',
          ),
        ],
      ),
      StoryNode(
        id: 'balance',
        speaker: 'Commerçante',
        text: 'À condition que les livraisons restent possibles, je pourrais l’accepter.',
        translation: 'Teslimatlar mümkün kaldığı sürece bunu kabul edebilirim.',
        glossary: <StoryGlossary>[
          StoryGlossary('à condition que', 'şartıyla'),
          StoryGlossary('livraisons', 'teslimatlar'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Prévoyons donc des créneaux réservés aux livraisons.',
            nextNodeId: 'end',
            coach: 'Kaygıyı doğrudan uygulanabilir bir uzlaşmaya çevirdin.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'absolute',
        speaker: 'Commerçante',
        text: 'Cette mesure risquerait pourtant de fragiliser les petits commerces.',
        translation: 'Ancak bu önlem küçük işletmeleri zayıflatma riski taşıyabilir.',
        glossary: <StoryGlossary>[
          StoryGlossary('pourtant', 'ancak, bununla birlikte'),
          StoryGlossary('fragiliser', 'zayıflatmak'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Vous avez raison; cherchons une exception pour les livraisons.',
            nextNodeId: 'end',
            coach: 'İtirazı kabul edip önerini esnettin.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Présidente',
        text: 'Ce compromis, auquel chacun a contribué, sera testé pendant trois mois.',
        translation: 'Herkesin katkıda bulunduğu bu uzlaşma üç ay boyunca denenecek.',
        glossary: <StoryGlossary>[
          StoryGlossary('auquel', '-e katkıda bulunduğu'),
          StoryGlossary('compromis', 'uzlaşma'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Toplantıda bulunan uzlaşma neydi?',
        options: <String>['Tüm araçları serbest bırakmak', 'Teslimat saatleri ayırmak', 'Dükkânları kapatmak'],
        correctIndex: 1,
        explanation: 'Yayalaştırma korunurken teslimatlar için özel zaman aralıkları önerildi.',
      ),
      StoryQuizQuestion(
        prompt: '“Auquel” hangi isme gönderme yapıyor?',
        options: <String>['Trois mois', 'Chacun', 'Compromis'],
        correctIndex: 2,
        explanation: 'Contribuer à quelque chose → le compromis auquel chacun a contribué.',
      ),
    ],
  ),
  StoryAdventure(
    id: 'c2_festival',
    level: CefrLevel.c2,
    title: 'Edebiyat Festivalindeki Tartışma',
    subtitle: 'İma, ironi ve üslup üzerine görüş bildir.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Critique',
        text: 'D’aucuns reprochent au roman son ambiguïté; n’est-ce pas précisément sa force ?',
        translation: 'Bazıları romanı belirsizliği nedeniyle eleştiriyor; bu tam da onun gücü değil mi?',
        glossary: <StoryGlossary>[
          StoryGlossary('d’aucuns', 'bazıları'),
          StoryGlossary('reprochent', 'eleştiriyorlar, kusur buluyorlar'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'L’équivoque contraint le lecteur à remettre en cause ses propres certitudes.',
            nextNodeId: 'nuance',
            coach: 'Soyut bir iddiayı metnin okur üzerindeki etkisiyle gerekçelendirdin.',
            preferred: true,
          ),
          StoryChoice(
            label: 'L’auteur aurait simplement dû être plus clair.',
            nextNodeId: 'challenge',
            coach: 'Savunulabilir fakat metnin bilinçli belirsizlik ihtimalini kapatıyor.',
          ),
        ],
      ),
      StoryNode(
        id: 'nuance',
        speaker: 'Autrice',
        text: 'Encore faut-il que cette ambiguïté ouvre des pistes plutôt qu’elle ne masque une faiblesse.',
        translation: 'Yine de bu belirsizliğin bir zayıflığı gizlemek yerine yeni yollar açması gerekir.',
        glossary: <StoryGlossary>[
          StoryGlossary('encore faut-il', 'yine de ... gerekir'),
          StoryGlossary('pistes', 'yorum yolları, ipuçları'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Certes; sa fécondité se mesure à la pluralité des lectures qu’elle suscite.',
            nextNodeId: 'end',
            coach: '“Certes” ile ödün verip ardından ölçüt önerdin.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'challenge',
        speaker: 'Critique',
        text: 'La clarté est-elle toujours une vertu lorsque le sujet lui-même se dérobe ?',
        translation: 'Konunun kendisi ele avuca sığmazken açıklık her zaman bir erdem midir?',
        glossary: <StoryGlossary>[
          StoryGlossary('vertu', 'erdem'),
          StoryGlossary('se dérobe', 'kaçıyor, ele gelmiyor'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Non; une part d’indétermination peut alors être plus fidèle au réel.',
            nextNodeId: 'end',
            coach: 'Görüşünü karşı argüman ışığında nüanslandırdın.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Modératrice',
        text: 'Vous avez déplacé le débat: il ne s’agit plus de trancher, mais de définir une ambiguïté féconde.',
        translation: 'Tartışmanın eksenini değiştirdiniz: artık hüküm vermek değil, üretken belirsizliği tanımlamak söz konusu.',
        glossary: <StoryGlossary>[
          StoryGlossary('trancher', 'kesin hüküm vermek'),
          StoryGlossary('féconde', 'üretken, verimli'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Tartışmanın sonunda hangi ölçüt öne çıktı?',
        options: <String>['Metnin uzunluğu', 'Belirsizliğin farklı okumalar üretmesi', 'Yazarın niyetini açıklaması'],
        correctIndex: 1,
        explanation: 'Belirsizliğin değeri, doğurduğu yorumların çoğulluğuyla ilişkilendirildi.',
      ),
      StoryQuizQuestion(
        prompt: '“Encore faut-il que” yapısı burada ne yapıyor?',
        options: <String>['Koşul ve çekince getiriyor', 'Geçmiş zamanı bildiriyor', 'Kesinlik bildiriyor'],
        correctIndex: 0,
        explanation: 'Önceki savı kabul ederken onun geçerli olması için bir koşul ekliyor.',
      ),
    ],
  ),
];

StoryAdventure storyForLevel(CefrLevel level) =>
    storyCatalog.firstWhere((StoryAdventure story) => story.level == level);

class StoryProgress {
  const StoryProgress({
    required this.storyId,
    required this.nodeId,
    required this.completed,
    required this.bestCorrect,
    required this.bestTotal,
  });

  final String storyId;
  final String nodeId;
  final bool completed;
  final int bestCorrect;
  final int bestTotal;

  double get ratio => bestTotal == 0 ? 0 : bestCorrect / bestTotal;
}

class SentenceProgress {
  const SentenceProgress({
    required this.promptId,
    required this.attempts,
    required this.solved,
    required this.bestScore,
  });

  final String promptId;
  final int attempts;
  final bool solved;
  final int bestScore;
}
