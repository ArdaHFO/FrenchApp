import 'adventure.dart';
import 'level.dart';

/// Her CEFR dünyasının ikinci bölümü. İlk katalog temel bölümleri, bu katalog
/// ise aynı dünyanın devam macerasını taşır.
const List<StoryAdventure> expandedStoryCatalog = <StoryAdventure>[
  StoryAdventure(
    id: 'a1_market',
    level: CefrLevel.a1,
    chapter: 2,
    title: 'Pazardaki Piknik Hazırlığı',
    subtitle: 'Miktar sor, ürün seç ve fiyatı anla.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Marchand',
        text: 'Bonjour ! Qu’est-ce qu’il vous faut pour votre pique-nique ?',
        translation: 'Merhaba! Pikniğiniz için ne gerekiyor?',
        glossary: <StoryGlossary>[
          StoryGlossary('il vous faut', 'size gerekiyor'),
          StoryGlossary('pique-nique', 'piknik'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Il me faut des pommes et du fromage.',
            nextNodeId: 'fruit',
            coach: 'Sayılabilen çoğulda “des”, miktar maddesinde “du” kullandın.',
            preferred: true,
          ),
          StoryChoice(
            label: 'Je veux pomme et fromage.',
            nextNodeId: 'articles',
            coach: 'Anlam açık fakat Fransızcada burada artikel gerekir.',
          ),
        ],
      ),
      StoryNode(
        id: 'fruit',
        speaker: 'Marchand',
        text: 'Très bien. Vous en voulez combien ?',
        translation: 'Pekâlâ. Onlardan kaç tane istiyorsunuz?',
        glossary: <StoryGlossary>[
          StoryGlossary('combien', 'kaç, ne kadar'),
          StoryGlossary('en', 'onlardan'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'J’en voudrais quatre, s’il vous plaît.',
            nextNodeId: 'end',
            coach: '“En” miktarı belirtilen ismin yerini doğal biçimde tuttu.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'articles',
        speaker: 'Marchand',
        text: 'Une pomme ou plusieurs pommes ? Et combien de fromage ?',
        translation: 'Bir elma mı, birkaç elma mı? Peki ne kadar peynir?',
        glossary: <StoryGlossary>[
          StoryGlossary('plusieurs', 'birkaç'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Quatre pommes et deux cents grammes de fromage.',
            nextNodeId: 'end',
            coach: 'Miktardan sonra “de fromage” kullandın; doğru yapı.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Marchand',
        text: 'Cela fait huit euros cinquante. Bon pique-nique !',
        translation: 'Toplam sekiz avro elli sent. İyi piknikler!',
        glossary: <StoryGlossary>[
          StoryGlossary('cela fait', 'toplam tutar'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Satıcı elmaların miktarını nasıl sordu?',
        options: <String>['Vous en voulez combien ?', 'Vous allez où ?', 'Quelle heure est-il ?'],
        correctIndex: 0,
        explanation: '“Combien” miktar sorar; “en” daha önce sözü geçen elmaların yerini tutar.',
      ),
      StoryQuizQuestion(
        prompt: '“Deux cents grammes” sonrasında hangisi gelir?',
        options: <String>['du fromage', 'de fromage', 'des fromages'],
        correctIndex: 1,
        explanation: 'Belirli miktar ifadelerinden sonra “de” kullanılır.',
      ),
    ],
  ),
  StoryAdventure(
    id: 'a2_hotel',
    level: CefrLevel.a2,
    chapter: 2,
    title: 'Otel Odasındaki Sürpriz',
    subtitle: 'Bir sorunu anlat ve çözüm talep et.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Réceptionniste',
        text: 'Bonsoir. Tout se passe bien dans votre chambre ?',
        translation: 'İyi akşamlar. Odanızda her şey yolunda mı?',
        glossary: <StoryGlossary>[
          StoryGlossary('se passe', 'geçiyor, oluyor'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Pas vraiment. Le chauffage ne fonctionne pas.',
            nextNodeId: 'repair',
            coach: 'Sorunu kısa ve doğrudan tarif ettin.',
            preferred: true,
          ),
          StoryChoice(
            label: 'Ma chambre est mauvaise.',
            nextNodeId: 'clarify',
            coach: 'Genel bir yargı verdin; görevlinin çözüm sunması için ayrıntı gerekli.',
          ),
        ],
      ),
      StoryNode(
        id: 'repair',
        speaker: 'Réceptionniste',
        text: 'Je suis désolée. Un technicien peut monter dans dix minutes.',
        translation: 'Üzgünüm. Bir teknisyen on dakika içinde çıkabilir.',
        glossary: <StoryGlossary>[
          StoryGlossary('technicien', 'teknisyen'),
          StoryGlossary('monter', 'yukarı çıkmak'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Merci. Pourrait-il venir un peu plus tôt ?',
            nextNodeId: 'end',
            coach: 'Conditionnel ile talebini nazikçe yumuşattın.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'clarify',
        speaker: 'Réceptionniste',
        text: 'Pouvez-vous préciser ce qui ne va pas ?',
        translation: 'Neyin yolunda olmadığını açıklayabilir misiniz?',
        glossary: <StoryGlossary>[
          StoryGlossary('préciser', 'ayrıntı vermek'),
          StoryGlossary('ce qui', '... olan şey'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Oui, il fait froid parce que le chauffage est en panne.',
            nextNodeId: 'end',
            coach: 'Belirtiyi ve nedenini birlikte açıkladın.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Réceptionniste',
        text: 'Nous allons régler le problème tout de suite.',
        translation: 'Sorunu hemen çözeceğiz.',
        glossary: <StoryGlossary>[
          StoryGlossary('régler', 'çözmek, halletmek'),
          StoryGlossary('tout de suite', 'hemen'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Odadaki asıl sorun neydi?',
        options: <String>['İnternet yoktu', 'Isıtma çalışmıyordu', 'Kapı kilitliydi'],
        correctIndex: 1,
        explanation: 'Konuk “le chauffage ne fonctionne pas” dedi.',
      ),
      StoryQuizQuestion(
        prompt: '“Être en panne” ne demektir?',
        options: <String>['Bozuk olmak', 'Hazır olmak', 'Açık olmak'],
        correctIndex: 0,
        explanation: 'Bir cihaz çalışmıyorsa “être en panne” denir.',
      ),
    ],
  ),
  StoryAdventure(
    id: 'b1_police',
    level: CefrLevel.b1,
    chapter: 2,
    title: 'Yanlış Telefon',
    subtitle: 'Bir karışıklığı geçmiş olaylarla açıkla.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Camille',
        text: 'Attends… ce téléphone ressemble au tien, mais ce n’est pas le même.',
        translation: 'Bekle… bu telefon seninkine benziyor ama aynısı değil.',
        glossary: <StoryGlossary>[
          StoryGlossary('ressemble à', 'benziyor'),
          StoryGlossary('le même', 'aynısı'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Tu as raison. Nous devons le rendre à la boulangère.',
            nextNodeId: 'return',
            coach: 'Nesne zamiri “le” ile telefonu tekrar etmeden belirttin.',
            preferred: true,
          ),
          StoryChoice(
            label: 'Ce n’est pas grave, je le garde.',
            nextNodeId: 'refuse',
            coach: 'Dil doğru; fakat kararın sonucu hikâyeyi zorlaştıracak.',
          ),
        ],
      ),
      StoryNode(
        id: 'return',
        speaker: 'Boulangère',
        text: 'Merci d’être revenus. Son propriétaire vient de m’appeler.',
        translation: 'Geri geldiğiniz için teşekkürler. Sahibi az önce beni aradı.',
        glossary: <StoryGlossary>[
          StoryGlossary('propriétaire', 'sahip'),
          StoryGlossary('vient de', 'az önce yaptı'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Heureusement que nous avons vérifié la coque.',
            nextNodeId: 'end',
            coach: '“Heureusement que” ile sonucu değerlendirdin.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'refuse',
        speaker: 'Camille',
        text: 'Imagine que le propriétaire signale le vol. Il vaut mieux le rapporter.',
        translation: 'Sahibinin hırsızlık ihbarı yaptığını düşün. Geri götürmek daha iyi.',
        glossary: <StoryGlossary>[
          StoryGlossary('signale', 'bildirir'),
          StoryGlossary('il vaut mieux', 'daha iyi olur'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'D’accord, tu m’as convaincu. Retournons-y.',
            nextNodeId: 'end',
            coach: 'Fikrinin değiştiğini doğal bir kalıpla ifade ettin.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Camille',
        text: 'Et ton vrai téléphone était finalement dans la poche de ton manteau !',
        translation: 'Gerçek telefonun da meğer montunun cebindeymiş!',
        glossary: <StoryGlossary>[
          StoryGlossary('finalement', 'sonunda, meğer'),
          StoryGlossary('manteau', 'mont'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Bulunan telefon neden geri götürüldü?',
        options: <String>['Bozuktu', 'Başkasına aitti', 'Şarjı bitmişti'],
        correctIndex: 1,
        explanation: 'Telefon benziyordu fakat anlatıcının telefonu değildi.',
      ),
      StoryQuizQuestion(
        prompt: '“Vient de m’appeler” hangi zamanı anlatır?',
        options: <String>['Yakın gelecek', 'Az önce gerçekleşen geçmiş', 'Süregelen alışkanlık'],
        correctIndex: 1,
        explanation: '“Venir de + infinitif” yakın geçmişi ifade eder.',
      ),
    ],
  ),
  StoryAdventure(
    id: 'b2_first_day',
    level: CefrLevel.b2,
    chapter: 2,
    title: 'İlk Gün Krizi',
    subtitle: 'Öncelikleri belirle ve diplomatik çözüm öner.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Responsable',
        text: 'Deux collègues sont absents et le client exige une livraison ce soir.',
        translation: 'İki çalışma arkadaşı yok ve müşteri bu akşam teslimat istiyor.',
        glossary: <StoryGlossary>[
          StoryGlossary('exige', 'talep ediyor'),
          StoryGlossary('livraison', 'teslimat'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Je propose de livrer l’essentiel ce soir et le reste demain.',
            nextNodeId: 'plan',
            coach: 'Sorunu parçalayan uygulanabilir bir uzlaşma önerdin.',
            preferred: true,
          ),
          StoryChoice(
            label: 'Il faut refuser la demande du client.',
            nextNodeId: 'pushback',
            coach: 'Sınır koydun fakat alternatif sunmadığın için müzakere alanı daraldı.',
          ),
        ],
      ),
      StoryNode(
        id: 'plan',
        speaker: 'Responsable',
        text: 'Comment vous assureriez-vous que la première livraison soit fiable ?',
        translation: 'İlk teslimatın güvenilir olmasını nasıl sağlardınız?',
        glossary: <StoryGlossary>[
          StoryGlossary('s’assurer', 'emin olmak, sağlamak'),
          StoryGlossary('fiable', 'güvenilir'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Je ferais valider les éléments prioritaires par une deuxième personne.',
            nextNodeId: 'end',
            coach: 'Conditionnel ile kontrollü bir süreç önerdin.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'pushback',
        speaker: 'Responsable',
        text: 'Un refus catégorique risque de détériorer la relation. Quelle alternative voyez-vous ?',
        translation: 'Kesin bir ret ilişkiyi bozabilir. Nasıl bir alternatif görüyorsunuz?',
        glossary: <StoryGlossary>[
          StoryGlossary('catégorique', 'kesin, tartışmasız'),
          StoryGlossary('détériorer', 'kötüleştirmek'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Dans ce cas, négocions une livraison partielle.',
            nextNodeId: 'end',
            coach: 'İtirazdan çözüm odaklı müzakereye geçtin.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Responsable',
        text: 'Votre approche est à la fois prudente et orientée vers le client.',
        translation: 'Yaklaşımınız hem temkinli hem müşteri odaklı.',
        glossary: <StoryGlossary>[
          StoryGlossary('à la fois', 'hem ... hem'),
          StoryGlossary('orientée', 'odaklı'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Önerilen ana çözüm neydi?',
        options: <String>['Her şeyi iptal etmek', 'Teslimatı iki aşamaya bölmek', 'Yeni müşteri bulmak'],
        correctIndex: 1,
        explanation: 'Öncelikli bölüm akşam, kalanı ertesi gün teslim edilecekti.',
      ),
      StoryQuizQuestion(
        prompt: '“Je ferais valider” hangi anlamı taşır?',
        options: <String>['Doğrulatırdım', 'Doğrulattım', 'Doğrulatacağım'],
        correctIndex: 0,
        explanation: 'Conditionnel présent varsayımsal çözümü yumuşatarak sunar.',
      ),
    ],
  ),
  StoryAdventure(
    id: 'c1_public_hearing',
    level: CefrLevel.c1,
    chapter: 2,
    title: 'Kamuoyu Önünde Savunma',
    subtitle: 'Uzlaşmayı eleştirilere karşı nüanslı biçimde savun.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Journaliste',
        text: 'Votre compromis ne mécontente-t-il pas finalement tout le monde ?',
        translation: 'Uzlaşmanız sonuçta herkesi memnuniyetsiz etmiyor mu?',
        glossary: <StoryGlossary>[
          StoryGlossary('mécontente', 'memnuniyetsiz ediyor'),
          StoryGlossary('finalement', 'sonuçta'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Il ne satisfait personne entièrement, mais il préserve les intérêts essentiels de chacun.',
            nextNodeId: 'defend',
            coach: 'Eleştiriyi inkâr etmeden uzlaşmanın ölçütünü yeniden tanımladın.',
            preferred: true,
          ),
          StoryChoice(
            label: 'Les opposants n’ont simplement rien compris.',
            nextNodeId: 'attack',
            coach: 'Keskin cevap karşı tarafın kaygılarını geçersizleştiriyor.',
          ),
        ],
      ),
      StoryNode(
        id: 'defend',
        speaker: 'Journaliste',
        text: 'Sur quels résultats concrets jugerez-vous son efficacité ?',
        translation: 'Etkisini hangi somut sonuçlarla değerlendireceksiniz?',
        glossary: <StoryGlossary>[
          StoryGlossary('jugerez', 'değerlendireceksiniz'),
          StoryGlossary('efficacité', 'etkililik'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Nous publierons chaque mois les données de circulation et de fréquentation.',
            nextNodeId: 'end',
            coach: 'Savını ölçülebilir ve şeffaf bir değerlendirmeye bağladın.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'attack',
        speaker: 'Journaliste',
        text: 'N’est-ce pas une manière d’éviter de répondre à leurs objections ?',
        translation: 'Bu, onların itirazlarına cevap vermekten kaçınmanın bir yolu değil mi?',
        glossary: <StoryGlossary>[
          StoryGlossary('éviter de', 'kaçınmak'),
          StoryGlossary('objections', 'itirazlar'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Vous avez raison; leurs objections méritent une réponse fondée sur des données.',
            nextNodeId: 'end',
            coach: 'Üslubu onardın ve tartışmayı kanıta geri getirdin.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Journaliste',
        text: 'Cette transparence permettra au public de se faire sa propre opinion.',
        translation: 'Bu şeffaflık kamuoyunun kendi fikrini oluşturmasını sağlayacak.',
        glossary: <StoryGlossary>[
          StoryGlossary('se faire une opinion', 'bir fikir oluşturmak'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Uzlaşma hangi ölçütle savunuldu?',
        options: <String>['Herkesi tamamen mutlu etmesi', 'Temel çıkarları koruması', 'Eleştirileri susturması'],
        correctIndex: 1,
        explanation: 'Savunma, tam memnuniyet yerine temel çıkarların korunmasına dayanıyordu.',
      ),
      StoryQuizQuestion(
        prompt: 'Etkililik nasıl değerlendirilecek?',
        options: <String>['Aylık verilerle', 'Tek bir röportajla', 'Gizli oylamayla'],
        correctIndex: 0,
        explanation: 'Dolaşım ve ziyaret verileri her ay yayımlanacak.',
      ),
    ],
  ),
  StoryAdventure(
    id: 'c2_review',
    level: CefrLevel.c2,
    chapter: 2,
    title: 'Tartışmalı Eleştiri',
    subtitle: 'Bir edebiyat yazısının ima ve sınırlarını savun.',
    startNodeId: 'start',
    nodes: <StoryNode>[
      StoryNode(
        id: 'start',
        speaker: 'Rédactrice en chef',
        text: 'Votre article est brillant, mais certaines formules pourraient passer pour du mépris.',
        translation: 'Yazınız parlak, ancak bazı ifadeler küçümseme gibi algılanabilir.',
        glossary: <StoryGlossary>[
          StoryGlossary('passer pour', 'gibi algılanmak'),
          StoryGlossary('mépris', 'küçümseme'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Je peux préserver l’ironie tout en écartant ce qui relève de l’attaque personnelle.',
            nextNodeId: 'revise',
            coach: 'Üslubu korurken etik sınırı net biçimde ayırdın.',
            preferred: true,
          ),
          StoryChoice(
            label: 'Quiconque se sent visé manque manifestement d’humour.',
            nextNodeId: 'defensive',
            coach: 'İfade güçlü ama eleştiriyi okurun kusuruna indiriyor.',
          ),
        ],
      ),
      StoryNode(
        id: 'revise',
        speaker: 'Rédactrice en chef',
        text: 'Comment distingueriez-vous alors la satire de la simple raillerie ?',
        translation: 'Öyleyse hicivle basit alayı nasıl ayırırdınız?',
        glossary: <StoryGlossary>[
          StoryGlossary('raillerie', 'alay'),
          StoryGlossary('distinguer', 'ayırt etmek'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'La satire vise un mécanisme de pouvoir; la raillerie, une personne vulnérable.',
            nextNodeId: 'end',
            coach: 'Soyut ayrımı kısa, paralel ve akılda kalıcı kurdun.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'defensive',
        speaker: 'Rédactrice en chef',
        text: 'L’intention humoristique ne nous dispense pas d’examiner l’effet produit.',
        translation: 'Mizah amacı, ortaya çıkan etkiyi inceleme sorumluluğundan bizi kurtarmaz.',
        glossary: <StoryGlossary>[
          StoryGlossary('dispenser de', 'muaf tutmak'),
          StoryGlossary('effet produit', 'ortaya çıkan etki'),
        ],
        choices: <StoryChoice>[
          StoryChoice(
            label: 'Soit. Je reformulerai les passages dont la cible demeure ambiguë.',
            nextNodeId: 'end',
            coach: '“Soit” ile itirazı kabul edip somut bir revizyon sözü verdin.',
            preferred: true,
          ),
        ],
      ),
      StoryNode(
        id: 'end',
        speaker: 'Rédactrice en chef',
        text: 'Le texte y gagnera en justesse sans perdre de son mordant.',
        translation: 'Metin keskinliğini kaybetmeden daha isabetli hâle gelecek.',
        glossary: <StoryGlossary>[
          StoryGlossary('y gagner en', 'bakımından gelişmek'),
          StoryGlossary('mordant', 'keskinlik, iğneleyicilik'),
        ],
      ),
    ],
    quiz: <StoryQuizQuestion>[
      StoryQuizQuestion(
        prompt: 'Hiciv ile alay arasındaki temel ayrım neydi?',
        options: <String>['Metnin uzunluğu', 'Hedef alınan güç mekanizması veya kişi', 'Kullanılan zaman kipi'],
        correctIndex: 1,
        explanation: 'Hiciv güç mekanizmasını, basit alay ise savunmasız kişiyi hedef alabilir.',
      ),
      StoryQuizQuestion(
        prompt: '“Y gagner en justesse” ne anlatır?',
        options: <String>['Metnin kısalması', 'Metnin isabet kazanması', 'Metnin yayımlanmaması'],
        correctIndex: 1,
        explanation: '“Gagner en + nom” belirtilen özellik bakımından gelişmek demektir.',
      ),
    ],
  ),
];

List<StoryAdventure> storiesForLevel(CefrLevel level) {
  final List<StoryAdventure> stories = <StoryAdventure>[
    ...storyCatalog.where((StoryAdventure story) => story.level == level),
    ...expandedStoryCatalog.where((StoryAdventure story) => story.level == level),
  ]..sort((StoryAdventure a, StoryAdventure b) => a.chapter.compareTo(b.chapter));
  return stories;
}
