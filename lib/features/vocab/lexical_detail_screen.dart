import 'package:flutter/material.dart';

import '../../domain/word.dart';
import '../../services/lexical/lexical_models.dart';
import '../../services/lexical/lexical_service.dart';

/// View-only dictionary enrichment. No progress actions or provider-owned IDs.
class LexicalDetailScreen extends StatefulWidget {
  const LexicalDetailScreen(
      {super.key, required this.lemma, required this.provider, this.localWord});
  final String lemma;
  final LexicalProvider provider;
  final Word? localWord;
  @override
  State<LexicalDetailScreen> createState() => _LexicalDetailScreenState();
}

class _LexicalDetailScreenState extends State<LexicalDetailScreen> {
  int _request = 0;
  bool _pending = false;
  LexicalOutcome? _result;
  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(covariant LexicalDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lemma != widget.lemma ||
        oldWidget.provider != widget.provider ||
        oldWidget.localWord?.id != widget.localWord?.id) {
      _lookup(replace: true);
    }
  }

  Future<void> _lookup({bool replace = false, bool refresh = false}) async {
    if (_pending && !replace) return;
    final request = ++_request;
    setState(() {
      _pending = true;
      _result = null;
    });
    final key =
        LexicalLookupKey(widget.lemma, expectedPos: widget.localWord?.pos);
    LexicalOutcome result;
    try {
      final provider = widget.provider;
      result = provider is LexicalService
          ? await provider.lookupWithPolicy(key, refresh: refresh)
          : await provider.lookup(key);
    } catch (_) {
      result = const LexicalOutcome(LexicalStatus.transientFailure);
    }
    if (!mounted || request != _request) return;
    setState(() {
      _pending = false;
      _result = result;
    });
  }

  String _message(LexicalOutcome result) => switch (result.status) {
        LexicalStatus.notFound => 'Bu kelime için çevrimiçi kayıt bulunamadı.',
        LexicalStatus.selectionRequired =>
          'Bu kayıt için uygun Fransızca anlam seçilemedi.',
        LexicalStatus.rateLimited =>
          'Sözlük şu anda meşgul. Biraz sonra tekrar deneyin.',
        LexicalStatus.permanentFailure =>
          'Bu sorgu kullanılamıyor. Kısa bir Fransızca kelime yazın.',
        LexicalStatus.schemaFailure =>
          'Sözlük bilgisi şu anda okunamıyor. Daha sonra tekrar deneyin.',
        _ => 'Çevrimiçi sözlüğe ulaşılamadı. Yerel sözlük kullanılabilir.',
      };

  @override
  Widget build(BuildContext context) {
    final local = widget.localWord;
    final result = _result;
    final data = result?.data;
    final safe =
        data?.senses.where((s) => s.safeForDefaultDisplay).toList() ?? [];
    // Prefer local POS without inventing a relation between provider sense indexes.
    final expected = switch (local?.pos.toLowerCase()) {
      'n' || 'nom' || 'noun' => 'noun',
      'v' || 'ver' || 'verb' => 'verb',
      'adj' || 'adjective' => 'adj',
      'adv' || 'adverb' => 'adv',
      final String value => value,
      _ => null,
    };
    final matching = safe.where((s) => s.pos == expected).toList();
    final senses = matching.isNotEmpty ? matching : safe;
    return Scaffold(
      appBar: AppBar(title: const Text('Ek sözlük bilgisi')),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        Text(widget.lemma, style: Theme.of(context).textTheme.headlineSmall),
        if (local != null) ...[
          const SizedBox(height: 12),
          const Text('Yerel öğrenme içeriği',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Text(local.meaningTr),
          Text(local.meaningEn),
          if (local.ipa != null) Text(local.ipa!),
        ],
        const Divider(height: 32),
        const Text('Çevrimiçi ek bilgiler · öğrenme içeriğini değiştirmez'),
        if (local == null)
          const Text('Yalnızca sözlük görünümü. Öğrenme destesine eklenmez.'),
        const SizedBox(height: 16),
        if (_pending)
          const Center(
              child:
                  CircularProgressIndicator(key: ValueKey('lexical_pending'))),
        if (result != null && data == null)
          Text(_message(result), key: const ValueKey('lexical_error')),
        if (data != null) ...[
          if (result!.fromCache)
            Text(result.stale
                ? 'Önbellekteki bilgi · güncelliği doğrulanamadı'
                : 'Önbellekteki bilgi'),
          if (result.cacheUnavailable)
            const Text('Bilgi çevrimdışı kullanım için saklanamadı.'),
          if (result.pronunciationUnavailable)
            const Text('Ek telaffuz bilgisi şu anda kullanılamıyor.'),
          if (senses.isEmpty)
            const Text('Gösterilebilecek ek anlam bulunamadı.'),
          if (expected != null && matching.isEmpty && senses.isNotEmpty)
            const Text('Yerel kelime türüyle eşleşmeyen sözlük anlamları:'),
          for (final sense in senses)
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sense.pos,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      for (final gloss in sense.glosses) Text(gloss),
                      if (sense.tags.isNotEmpty)
                        Text(sense.tags.join(', '),
                            style: Theme.of(context).textTheme.bodySmall),
                    ])),
          for (final pronunciation
              in data.pronunciations.where((p) => p.ipa != null))
            Text(
                '${pronunciation.pos} · ${pronunciation.ipa} ${pronunciation.tags.join(', ')}'),
          const SizedBox(height: 16),
          Text(data.provenance.label),
          const Text(
              'Wiktionary kaynaklı ek içerik · CC BY-SA; kaynak geçmişine bakın.'),
          SelectableText(data.provenance.sourceUrl),
        ],
        const SizedBox(height: 16),
        if (!_pending)
          OutlinedButton(
              key: const ValueKey('lexical_retry'),
              onPressed: () => _lookup(refresh: true),
              child: Text(data == null ? 'Tekrar dene' : 'Güncelle')),
      ])),
    );
  }
}
