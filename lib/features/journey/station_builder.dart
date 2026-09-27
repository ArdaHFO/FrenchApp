import '../../app/app_state.dart';
import '../../domain/journey.dart';
import '../../domain/level.dart';
import '../../domain/verb.dart';

/// Haritayı içerikten kurar.
///
/// Duraklar veritabanında durmaz, her açılışta aynı şekilde üretilir.
/// Bu mümkün çünkü `candidateIds` sıralaması sabit: önce elle doğrulanmış
/// karşılıklar, sonra sıklık. Aynı içerik hep aynı haritayı verir, ama
/// içerik güncellendiğinde harita da kendiliğinden büyür.
class StationBuilder {
  StationBuilder._();

  /// Bir kelime durağındaki kelime sayısı. Soru sayısı bunun altında
  /// tutuluyor ki her turda farklı kelimeler sorulsun.
  static const int wordsPerStation = 14;
  static const int questionsPerStation = 8;

  /// Her seviyede kaç kelime durağı olacağı. Seviyenin tamamını duraklara
  /// bölmek 150'den fazla durak üretiyordu; harita okunmaz oluyordu.
  static const int wordStationsPerLevel = 8;

  static List<JourneyStation> build(AppState app) {
    final List<JourneyStation> out = <JourneyStation>[];

    for (final CefrLevel level in CefrLevel.values) {
      final String revision =
          app.contentMeta['journey_revision_${level.code}'] ?? 'unknown';
      String stationId(String kind) => '${level.code}-$kind-$revision';
      final List<String> pool = app.words.candidateIds(
        levels: <CefrLevel>[level],
      );
      if (pool.isEmpty) continue;

      int index = 0;

      // --- kelime durakları
      final int stations = <int>[
        wordStationsPerLevel,
        pool.length ~/ wordsPerStation,
      ].reduce((int a, int b) => a < b ? a : b);

      for (int i = 0; i < stations; i++) {
        final int start = i * wordsPerStation;
        final List<String> ids = pool.sublist(start, start + wordsPerStation);
        out.add(
          JourneyStation(
            id: stationId('w$i'),
            level: level,
            indexInLevel: index++,
            kind: StationKind.words,
            title: '${level.code} kelime ${i + 1}',
            wordIds: ids,
            verbRefIds: const <String>[],
            questionCount: questionsPerStation,
          ),
        );

        // Üçüncü kelime durağından sonra bir fiil durağı araya girer,
        // böylece harita tek düze kalmıyor.
        if (i == 2) {
          out.add(
            JourneyStation(
              id: stationId('v0'),
              level: level,
              indexInLevel: index++,
              kind: StationKind.verbs,
              title: '${level.code} fiil çekimi',
              wordIds: const <String>[],
              verbRefIds: const <String>[],
              questionCount: questionsPerStation,
            ),
          );
        }
      }

      // --- deyim durağı
      final List<String> idioms =
          app.words.candidateIds(levels: <CefrLevel>[level], idiomsOnly: true);
      if (idioms.length >= 6) {
        out.add(
          JourneyStation(
            id: stationId('i0'),
            level: level,
            indexInLevel: index++,
            kind: StationKind.idioms,
            title: '${level.code} deyimler',
            wordIds: idioms.take(wordsPerStation).toList(),
            verbRefIds: const <String>[],
            questionCount: idioms.length < questionsPerStation
                ? idioms.length
                : questionsPerStation,
          ),
        );
      }

      // --- seviye sınavı: o seviyenin her yerinden
      if (pool.length >= 40) {
        final List<String> mixed = <String>[];
        final int step = pool.length ~/ 24;
        for (int i = 0; i < pool.length && mixed.length < 24; i += step) {
          mixed.add(pool[i]);
        }
        out.add(
          JourneyStation(
            id: stationId('boss'),
            level: level,
            indexInLevel: index++,
            kind: StationKind.boss,
            title: '${level.code} sınavı',
            wordIds: mixed,
            verbRefIds: const <String>[],
            questionCount: 12,
          ),
        );
      }
    }

    return out;
  }

  /// Fiil durağının sorularını üretmek için gereken çekim kimlikleri.
  /// Kelime durakları bunu kullanmaz.
  static Future<List<String>> verbRefIdsFor(
    AppState app,
    JourneyStation station,
  ) async {
    if (station.kind != StationKind.verbs) return const <String>[];
    final List<Verb> verbs = await app.verbs.byLevels(
      <CefrLevel>[station.level],
      limit: 8,
    );
    final List<VerbTense> eligibleTenses = VerbTense.values
        .where(
          (VerbTense tense) => tense.level.index <= station.level.index,
        )
        .toList()
      ..sort((VerbTense a, VerbTense b) {
        final int byLevel = b.level.index.compareTo(a.level.index);
        return byLevel != 0 ? byLevel : a.index.compareTo(b.index);
      });
    final List<String> out = <String>[];
    for (final Verb v in verbs) {
      final Map<VerbTense, Map<String, String>> tables =
          await app.verbs.tablesFor(v);
      for (final VerbTense t in eligibleTenses) {
        final Map<String, String>? row = tables[t];
        if (row == null) continue;
        for (final String person in kPersons) {
          if (row[person] != null) out.add('${v.id}:${t.key}:$person');
        }
        break;
      }
      if (out.length >= 24) break;
    }
    return out;
  }
}
