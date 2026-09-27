import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../domain/level.dart';
import '../../domain/word.dart';
import '../../domain/word_search.dart';
import '../../motion/motion_tokens.dart';
import '../../services/tts_service.dart';
import '../../ui/game_ui.dart';

/// Sözlük araması.
///
/// 15 binden fazla kelime bellekte durduğu için arama senkron ve anında. Hem
/// Fransızca hem Türkçe hem İngilizce tarafta arar; aksanlar sadeleştirilir,
/// yani "etre" yazınca "être" bulunur.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  AppState? _app;
  TtsService? _tts;
  bool _ttsRequested = false;
  List<WordSearchResult> _results = const <WordSearchResult>[];
  WordSearchLanguage _language = WordSearchLanguage.all;
  Timer? _searchTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= AppScope.of(context);
    if (_ttsRequested) return;
    _ttsRequested = true;
    TtsService.instance().then((TtsService s) {
      if (mounted) setState(() => _tts = s);
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String raw) {
    setState(() {
      _results = _app!.words.search(
        raw,
        language: _language,
      );
    });
  }

  void _scheduleSearch(String raw) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted) _search(raw);
    });
    setState(() {});
  }

  void _setLanguage(WordSearchLanguage language) {
    _searchTimer?.cancel();
    _language = language;
    _search(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Çift Yönlü Sözlük'),
      ),
      backgroundColor: Colors.transparent,
      body: GameBackdrop(
        accent: theme.colorScheme.primary,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Fransızca ↔ Türkçe',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'İki dilde de yazabilirsin. En uygun karşılık önce gelir.',
                      style: TextStyle(fontSize: 13, color: faint),
                    ),
                    const SizedBox(height: 12),
                    GamePanel(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      radius: 18,
                      child: TextField(
                        key: const ValueKey<String>('dictionary_search'),
                        controller: _controller,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Örn. gitmek, kadın, maison, être…',
                          prefixIcon: const Icon(Icons.manage_search_rounded),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Aramayı temizle',
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    _controller.clear();
                                    _search('');
                                  },
                                ),
                          border: InputBorder.none,
                        ),
                        onChanged: _scheduleSearch,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          _LanguageChip(
                            label: 'Otomatik',
                            icon: Icons.auto_awesome_rounded,
                            selected: _language == WordSearchLanguage.all,
                            onTap: () => _setLanguage(WordSearchLanguage.all),
                          ),
                          const SizedBox(width: 8),
                          _LanguageChip(
                            label: 'Fransızca → Türkçe',
                            icon: Icons.flag_circle_rounded,
                            selected: _language == WordSearchLanguage.french,
                            onTap: () =>
                                _setLanguage(WordSearchLanguage.french),
                          ),
                          const SizedBox(width: 8),
                          _LanguageChip(
                            label: 'Türkçe → Fransızca',
                            icon: Icons.translate_rounded,
                            selected: _language == WordSearchLanguage.turkish,
                            onTap: () =>
                                _setLanguage(WordSearchLanguage.turkish),
                          ),
                        ],
                      ),
                    ),
                    if (_results.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        '${_results.length} sonuç · ${_resultDirectionLabel()}',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _results.isEmpty
                    ? _EmptyDictionaryState(
                        hasQuery: _controller.text.trim().length >= 2,
                        wordCount: _app?.wordCount ?? 0,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 28),
                        itemCount: _results.length,
                        itemBuilder: (BuildContext context, int i) =>
                            AnimatedPadding(
                          duration: MotionTokens.selection,
                          padding: const EdgeInsets.only(bottom: 7),
                          child: _ResultTile(result: _results[i], tts: _tts),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _resultDirectionLabel() {
    if (_language == WordSearchLanguage.french) return 'Fransızca → Türkçe';
    if (_language == WordSearchLanguage.turkish) return 'Türkçe → Fransızca';
    return switch (_results.first.matchLanguage) {
      WordMatchLanguage.turkish => 'Türkçe → Fransızca',
      WordMatchLanguage.french => 'Fransızca → Türkçe',
      WordMatchLanguage.english => 'İngilizce eşleşme',
    };
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        avatar: Icon(icon, size: 17),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      );
}

class _EmptyDictionaryState extends StatelessWidget {
  const _EmptyDictionaryState({
    required this.hasQuery,
    required this.wordCount,
  });

  final bool hasQuery;
  final int wordCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.58);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.11),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasQuery ? Icons.search_off_rounded : Icons.translate_rounded,
                size: 34,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasQuery ? 'Bu ifadeyle sonuç bulamadım' : 'Bir kelime yaz',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              hasQuery
                  ? 'Başka bir anlamı veya daha kısa bir kökü deneyebilirsin.'
                  : '$wordCount kelime içinde iki yönde arama yapıyorum.\n'
                      '“gitmek” → aller · “kadin” → femme · “etre” → être',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.45, color: faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, this.tts});

  final WordSearchResult result;
  final TtsService? tts;

  @override
  Widget build(BuildContext context) {
    final Word word = result.word;
    final ThemeData theme = Theme.of(context);
    final Color color = AppTheme.levelColor(word.level.index);
    final String matched = switch (result.matchLanguage) {
      WordMatchLanguage.french => 'FR eşleşmesi',
      WordMatchLanguage.turkish => 'TR eşleşmesi',
      WordMatchLanguage.english => 'EN eşleşmesi',
    };
    return PressableScale(
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          key: ValueKey<String>('dictionary_result_${word.lemma}'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openSheet(context, word, tts),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[color, GameColors.violet],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'FR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              word.display,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          _MiniTag(label: word.level.code, color: color),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'TR  ${word.meaningTr}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$matched · ${word.posTr}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.48),
                        ),
                      ),
                    ],
                  ),
                ),
                if (tts?.available ?? false)
                  IconButton(
                    tooltip: 'Telaffuzu dinle',
                    icon: const Icon(Icons.volume_up_rounded),
                    onPressed: () => tts!.speak(word.display),
                  ),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      );
}

/// Kelime ayrıntısı. Aile kelimelerine dokunulunca aynı sayfa o kelime
/// için yeniden açılır, böylece kök boyunca gezinebiliyorsun.
void _openSheet(BuildContext context, Word word, TtsService? tts) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) => _WordSheet(word: word, tts: tts),
  );
}

class _WordSheet extends StatelessWidget {
  const _WordSheet({required this.word, this.tts});

  final Word word;
  final TtsService? tts;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final List<Word> kin = AppScope.of(context).words.relativesOf(word.id);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        32 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  word.display,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (tts?.available ?? false)
                IconButton(
                  icon: const Icon(Icons.volume_up_rounded),
                  onPressed: () => tts!.speak(word.display),
                ),
            ],
          ),
          if (word.ipa != null)
            Text(word.ipa!, style: TextStyle(fontSize: 14, color: faint)),
          const SizedBox(height: 14),
          Text(
            word.meaningTr,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(word.meaningEn, style: TextStyle(fontSize: 14, color: faint)),
          if (word.hasExample) ...<Widget>[
            const SizedBox(height: 16),
            Divider(color: theme.colorScheme.onSurface.withValues(alpha: 0.12)),
            const SizedBox(height: 10),
            Text(
              word.sentenceFr!,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
            if (word.sentenceTr != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                word.sentenceTr!,
                style: TextStyle(fontSize: 13, height: 1.35, color: faint),
              ),
            ],
          ],
          if (kin.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Divider(color: theme.colorScheme.onSurface.withValues(alpha: 0.12)),
            const SizedBox(height: 10),
            Text(
              'Aynı kökten gelenler',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: faint,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final Word r in kin)
                  ActionChip(
                    label: Text('${r.lemma}  ·  ${r.meaningTr}'),
                    labelStyle: const TextStyle(fontSize: 12),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openSheet(context, r, tts);
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _Meta(label: word.level.code),
              _Meta(label: word.posTr),
              if (word.genderTr != null) _Meta(label: word.genderTr!),
              if (word.isIdiom) const _Meta(label: 'deyim'),
              _Meta(label: 'sıklık ${word.freqRank}'),
              if (word.needsReview)
                const _Meta(label: 'gözden geçirilmedi', warn: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, this.warn = false});

  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color c =
        warn ? const Color(0xFFD9A21B) : theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
