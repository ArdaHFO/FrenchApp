import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../motion/transitions.dart';

/// Kaynaklar ve içerik künyesi.
///
/// Buradaki liste `content.db` içindeki `meta` tablosundan ve kaynakların
/// dağıtım koşullarından gelir.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const List<({String name, String what, String license, String url})>
      _sources = <({String name, String what, String license, String url})>[
    (
      name: 'WiktApi / Wiktionary contributors',
      what: 'İsteğe bağlı çevrimiçi ek anlamlar ve IPA; yerel öğrenme içeriğini değiştirmez',
      license: 'Sözlük verisi: CC BY-SA / GFDL · servis yazılımı: MIT',
      url: 'wiktapi.dev · en.wiktionary.org/wiki/Wiktionary:Copyrights',
    ),
    (
      name: 'Lexique 3.83',
      what: 'Kelime listesi, kelime türü, cinsiyet, fonetik, sıklık',
      license: 'CC BY-SA',
      url: 'lexique.org',
    ),
    (
      name: 'FLELex',
      what: 'CEFR seviye etiketleri (A1–C2)',
      license: 'Araştırma için serbest',
      url: 'cental.uclouvain.be/cefrlex',
    ),
    (
      name: 'Wiktionary — kaikki.org',
      what: 'İngilizce tanımlar, IPA, fiil çekim formları',
      license: 'CC BY-SA',
      url: 'kaikki.org',
    ),
    (
      name: 'Wiktionary — DBnary',
      what: 'Türkçe karşılıklar (fr/tr/en sürümleri)',
      license: 'CC BY-SA 3.0',
      url: 'kaiko.getalp.org',
    ),
    (
      name: 'Tatoeba',
      what: 'Üç dilli örnek cümleler',
      license: 'CC BY 2.0 FR',
      url: 'tatoeba.org',
    ),
    (
      name: 'FrequencyWords',
      what: 'Konuşma dili sıklık listeleri (OpenSubtitles)',
      license: 'CC BY-SA 4.0',
      url: 'github.com/hermitdave/FrequencyWords',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final Map<String, String> meta = app.contentMeta;

    return Scaffold(
      appBar: AppBar(title: const Text('Kaynaklar')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            Text('İçerik', style: _section(theme)),
            const SizedBox(height: 10),
            _MetaRow(label: 'Kelime', value: meta['word_count']),
            _MetaRow(label: 'Örnek cümle', value: meta['example_count']),
            _MetaRow(label: 'Fiil', value: meta['verb_count']),
            _MetaRow(label: 'Çekim', value: meta['conjugation_count']),
            _MetaRow(label: 'Dilbilgisi dersi', value: meta['lesson_count']),
            _MetaRow(label: 'Üretim tarihi', value: meta['built_at']),
            const SizedBox(height: 26),
            Text('Veri kaynakları', style: _section(theme)),
            const SizedBox(height: 6),
            Text(
              'Bu uygulamadaki içerik aşağıdaki harici veri '
              'kümelerinden türetilmiştir.',
              style: TextStyle(fontSize: 13, height: 1.4, color: faint),
            ),
            const SizedBox(height: 14),
            for (int i = 0; i < _sources.length; i++)
              StaggeredEntry(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SourceTile(source: _sources[i]),
                ),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Dağıtımdan önce kaynak atıfları, Tatoeba cümle yazarları ve '
                'paylaşım koşulları korunmalıdır. FLELex için amaçlanan '
                'dağıtım ayrıca izin/uygunluk kontrolü gerektirir.',
                style: TextStyle(fontSize: 12, height: 1.45, color: faint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static TextStyle _section(ThemeData t) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: t.colorScheme.onSurface,
      );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Text(
            value!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final ({String name, String what, String license, String url}) source;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            Text(
                source.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                source.license,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          source.what,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Text(
          source.url,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}
