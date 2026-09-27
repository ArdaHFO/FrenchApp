import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../domain/level.dart';
import '../../domain/verb.dart';
import '../../motion/transitions.dart';

/// Bir fiilin bütün zamanları tek ekranda.
///
/// Kaydırma kartları bir seferde tek bir çekim sorar; bu ekran bunun
/// tersini yapar ve fiilin tamamını gösterir. Düzensiz fiillerde asıl
/// zorluk tek tek biçimler değil, zamanlar arasındaki gövde değişimidir
/// (`aller` → je vais / j'irai / j'allais); yan yana görünce oturuyor.
class VerbTablesScreen extends StatefulWidget {
  const VerbTablesScreen({super.key, this.initial});

  /// Doğrudan bir fiille açılabilir (arama sonucundan gelirken).
  final String? initial;

  @override
  State<VerbTablesScreen> createState() => _VerbTablesScreenState();
}

class _VerbTablesScreenState extends State<VerbTablesScreen> {
  final TextEditingController _controller = TextEditingController();

  AppState? _app;
  List<Verb> _all = const <Verb>[];
  List<Verb> _results = const <Verb>[];
  Verb? _selected;
  Map<VerbTense, Map<String, String>> _tables =
      const <VerbTense, Map<String, String>>{};
  _VerbPickerFilter _filter = _VerbPickerFilter.all;
  bool _loading = true;
  Timer? _searchTimer;
  final Map<String,
          ({String infinitive, String searchable, String tr, String en})>
      _searchIndex = <String,
          ({String infinitive, String searchable, String tr, String en})>{};

  static const int _initialResultLimit = 40;

  static const Map<String, String> _foldMap = <String, String>{
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
  };

  static String _fold(String s) {
    final StringBuffer b = StringBuffer();
    for (final int rune in s.toLowerCase().replaceAll('’', "'").runes) {
      final String ch = String.fromCharCode(rune);
      b.write(_foldMap[ch] ?? ch);
    }
    return b.toString();
  }

  static String _searchableInfinitive(Verb verb) {
    final String folded = _fold(verb.infinitive);
    // Kullanıcılar dönüşlü fiilleri çoğunlukla "se" ile arıyor. Fransızca
    // yazımda ünlü önünde s' kullanıldığı için aramada iki biçimi eşit say.
    return folded.startsWith("s'") ? 'se ${folded.substring(2)}' : folded;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_app != null) return;
    _app = AppScope.of(context);
    _load();
  }

  Future<void> _load() async {
    final List<Verb> verbs = await _app!.verbs.all();
    if (!mounted) return;
    for (final Verb verb in verbs) {
      _searchIndex[verb.id] = (
        infinitive: _fold(verb.infinitive),
        searchable: _searchableInfinitive(verb),
        tr: _fold(verb.meaningTr),
        en: _fold(verb.meaningEn),
      );
    }
    setState(() {
      _all = verbs;
      _results = verbs.take(_initialResultLimit).toList();
      _loading = false;
    });
    final String? wanted = widget.initial;
    if (wanted != null) {
      for (final Verb v in verbs) {
        if (v.infinitive == wanted) {
          await _select(v);
          return;
        }
      }
    }
  }

  Future<void> _select(Verb verb) async {
    final Map<VerbTense, Map<String, String>> tables =
        await _app!.verbs.tablesFor(verb);
    if (!mounted) return;
    setState(() {
      _selected = verb;
      _tables = tables;
    });
  }

  void _search(String raw) {
    final String q = _fold(raw.trim());
    setState(() {
      final bool asksForReflexives = <String>{
        'se',
        "s'",
        'donuslu',
        'pronominal',
        'reflexive',
      }.contains(q);
      final Iterable<Verb> candidates = _all.where(
        (Verb verb) =>
            (_filter == _VerbPickerFilter.all || verb.isReflexive) &&
            (!asksForReflexives || verb.isReflexive),
      );

      if (q.isEmpty) {
        _results = (_filter == _VerbPickerFilter.all
                ? candidates.take(_initialResultLimit)
                : candidates)
            .toList();
        return;
      }
      if (asksForReflexives) {
        _results = candidates.toList();
        return;
      }

      final List<Verb> exact = <Verb>[];
      final List<Verb> starts = <Verb>[];
      final List<Verb> contains = <Verb>[];
      for (final Verb v in candidates) {
        final terms = _searchIndex[v.id]!;
        if (terms.infinitive == q || terms.searchable == q) {
          exact.add(v);
        } else if (terms.infinitive.startsWith(q) ||
            terms.searchable.startsWith(q)) {
          starts.add(v);
        } else if (terms.infinitive.contains(q) ||
            terms.searchable.contains(q) ||
            terms.tr.contains(q) ||
            terms.en.contains(q)) {
          contains.add(v);
        }
      }
      _results = <Verb>[...exact, ...starts, ...contains];
    });
  }

  void _scheduleSearch(String raw) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted) _search(raw);
    });
  }

  void _setFilter(_VerbPickerFilter filter) {
    _searchTimer?.cancel();
    _filter = filter;
    _search(_controller.text);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Verb? verb = _selected;
    return Scaffold(
      appBar: AppBar(
        title: Text(verb?.infinitive ?? 'Çekim tablosu'),
        actions: <Widget>[
          if (verb != null)
            IconButton(
              tooltip: 'Başka fiil seç',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => setState(() => _selected = null),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : verb == null
                ? _picker(context)
                : _tableView(context, verb),
      ),
    );
  }

  /// Dönüşlünün temel fiiline geç: "se rendre" → "rendre".
  Future<void> _openBase(String infinitive) async {
    for (final Verb v in _all) {
      if (v.infinitive == infinitive && !v.isReflexive) {
        await _select(v);
        return;
      }
    }
  }

  Widget _picker(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int reflexiveCount = _all.where((Verb v) => v.isReflexive).length;
    final int visibleReflexives =
        _results.where((Verb v) => v.isReflexive).length;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '${_all.length} fiil içinde ara',
              prefixIcon: const Icon(Icons.search_rounded),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _scheduleSearch,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('Tümü'),
                    selected: _filter == _VerbPickerFilter.all,
                    onSelected: (_) => _setFilter(_VerbPickerFilter.all),
                  ),
                  ChoiceChip(
                    label: Text('Dönüşlü ($reflexiveCount)'),
                    selected: _filter == _VerbPickerFilter.reflexive,
                    avatar: const Icon(Icons.autorenew_rounded, size: 17),
                    onSelected: (_) => _setFilter(_VerbPickerFilter.reflexive),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_results.length} sonuç'
                  '${visibleReflexives == 0 ? '' : ' · $visibleReflexives dönüşlü'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (BuildContext context, int i) {
              final Verb v = _results[i];
              return ListTile(
                title: Text(v.infinitive),
                subtitle: Text(
                  v.meaningTr.isEmpty ? v.meaningEn : v.meaningTr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  v.level.code,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.levelColor(v.level.index),
                  ),
                ),
                onTap: () => _select(v),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tableView(BuildContext context, Verb verb) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final Color accent = AppTheme.levelColor(verb.level.index);
    final List<VerbTense> tenses = VerbTense.values
        .where((VerbTense t) =>
            (_tables[t] ?? const <String, String>{}).isNotEmpty)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                verb.meaningTr.isEmpty ? verb.meaningEn : verb.meaningTr,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                verb.level.code,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Yardımcı fiil: ${verb.auxiliary}'
          '${verb.pastParticiple == null ? '' : '  ·  ortaç: ${verb.pastParticiple}'}'
          '  ·  ${verb.group}. grup',
          style: TextStyle(fontSize: 12, color: faint),
        ),
        if (verb.isReflexive) ...<Widget>[
          const SizedBox(height: 12),
          _ReflexiveNote(verb: verb, onOpenBase: _openBase),
        ],
        const SizedBox(height: 18),
        for (final VerbTense t in tenses) ...<Widget>[
          _TenseTable(
            tense: t,
            forms: _tables[t]!,
            accent: accent,
            aspiratedH: verb.aspiratedH,
          ),
          const SizedBox(height: 16),
        ],
        if (tenses.isEmpty)
          Text(
            'Bu fiilin çekim tablosu yok.',
            style: TextStyle(fontSize: 13, color: faint),
          ),
      ],
    );
  }
}

enum _VerbPickerFilter { all, reflexive }

/// Dönüşlü fiilin türü, anlam farkı ve temel fiile geçiş.
///
/// Bu kutu uygulamanın dönüşlü fiillerde anlam kaymasına karşı aldığı
/// asıl önlem: kullanıcı "se rendre"in "rendre" olmadığını burada görür.
class _ReflexiveNote extends StatelessWidget {
  const _ReflexiveNote({required this.verb, required this.onOpenBase});

  final Verb verb;
  final Future<void> Function(String infinitive) onOpenBase;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const Color amber = Color(0xFFD9A21B);
    final ({String label, String hint})? kind = verb.reflexiveLabel;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.autorenew_rounded, size: 16, color: amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  kind == null ? 'Dönüşlü fiil' : 'Dönüşlü · ${kind.label}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: amber,
                  ),
                ),
              ),
            ],
          ),
          if (kind != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              kind.hint,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
          if (verb.noteTr != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              verb.noteTr!,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Bileşik zamanlarda her zaman être alır: '
            "j'ai lavé ama je me suis lavé.",
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          if (verb.baseInfinitive != null) ...<Widget>[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onOpenBase(verb.baseInfinitive!),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text('Temel fiil: ${verb.baseInfinitive}'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TenseTable extends StatelessWidget {
  const _TenseTable({
    required this.tense,
    required this.forms,
    required this.accent,
    required this.aspiratedH,
  });

  final VerbTense tense;
  final Map<String, String> forms;
  final Color accent;
  final bool aspiratedH;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Container(
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    tense.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
                Text(
                  tense.labelTr,
                  style: TextStyle(fontSize: 11, color: faint),
                ),
              ],
            ),
          ),
          for (final String person in kPersons)
            if (forms[person] != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 3, 14, 3),
                child: Text(
                  // Elizyon burada uygulanır: veritabanında çekimler
                  // yalın durur, "je" + "ai" ekranda "j'ai" olur.
                  conjugationDisplay(
                    person,
                    forms[person]!,
                    tense: tense,
                    aspiratedH: aspiratedH,
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// Fiil listesine giden kısayol. Fiiller sekmesinin başında durur.
class VerbTablesTile extends StatelessWidget {
  const VerbTablesTile({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          fadeSlideRoute<void>(const VerbTablesScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.table_chart_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Çekim tabloları',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Bir fiilin sekiz zamanı yan yana',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
