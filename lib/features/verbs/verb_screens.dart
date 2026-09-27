import '../../app/progress_session.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../domain/level.dart';
import '../../domain/srs/session_builder.dart';
import '../../domain/srs/srs_card.dart';
import '../../domain/verb.dart';
import '../../motion/card_stack.dart';
import '../../motion/flip_card.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/swipe_direction.dart';
import '../../motion/transitions.dart';
import 'verb_tables_screen.dart';
import '../../services/tts_service.dart';
import 'reflexive_arena_screen.dart';

/// Fiil çekimi deste seçimi. PLAN.md bölüm 4, ikinci sekme.
class VerbDeckScreen extends StatefulWidget {
  const VerbDeckScreen({super.key, this.initialTense});

  final VerbTense? initialTense;

  @override
  State<VerbDeckScreen> createState() => _VerbDeckScreenState();
}

class _VerbDeckScreenState extends State<VerbDeckScreen> {
  late VerbTense _tense;
  bool _irregularOnly = false;
  bool _starting = false;

  /// hepsi · sadece dönüşlü · dönüşlü hariç
  _VerbFilter _filter = _VerbFilter.all;

  @override
  void initState() {
    super.initState();
    _tense = widget.initialTense ?? VerbTense.present;
  }

  Future<void> _start(AppState app) async {
    if (_starting) return;
    final int generation = app.progressGeneration;
    if (!allowProgress(context, app, generation)) return;
    setState(() => _starting = true);
    // One preparation uses one selection, even if controls change during IO.
    final VerbTense tense = _tense;
    final _VerbFilter filter = _filter;
    final bool irregularOnly = _irregularOnly;
    final List<CefrLevel> levels = app.activeLevels;
    final int size = app.dailyGoal;
    try {
      final List<Verb> verbs = await app.verbs.byLevels(levels);
      final List<Verb> filtered = verbs.where((Verb v) {
        if (irregularOnly && !v.isIrregular) return false;
        return switch (filter) {
          _VerbFilter.all => true,
          _VerbFilter.reflexiveOnly => v.isReflexive,
          _VerbFilter.plainOnly => !v.isReflexive,
        };
      }).toList();
      if (!mounted) return;
      if (filtered.isEmpty) {
        _showEmptyDeck();
        return;
      }

      final List<String> candidates =
          await app.verbs.conjugationRefIdsForTense(filtered, tense);
      if (!mounted) return;
      final List<String> selected = SessionBuilder.build(
        candidateRefIds: candidates,
        states: app.verbCards.snapshot(),
        now: DateTime.now(),
        size: size,
      );
      if (selected.isEmpty) {
        _showEmptyDeck();
        return;
      }
      final Set<String> selectedVerbIds =
          selected.map((String ref) => ref.split(':').first).toSet();
      final List<Conjugation> cards =
          await app.verbs.conjugationsForTense(
        filtered.where((Verb v) => selectedVerbIds.contains(v.id)).toList(),
        tense,
      );
      if (!mounted) return;
      if (cards.isEmpty) {
        _showEmptyDeck();
        return;
      }

      if (!allowProgress(context, app, generation)) return;
      await Navigator.of(context).push(
        fadeSlideRoute<void>(
          VerbSessionScreen(
            tense: tense, conjugations: cards, selectedRefIds: selected,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _showEmptyDeck() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bu filtre ve zaman için çalışılabilir fiil yok.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final List<VerbTense> tenses = VerbTense.values
        // Bir zaman öğrenildiğinde sonraki seviyelerde de çalışılabilir.
        // "Alt seviyeleri karıştır" kelime/fiil havuzunu sınırlar; B2-C2
        // kullanıcısının bütün çekim zamanlarını yok etmemelidir.
        .where((VerbTense t) => t.level.index <= app.level.index)
        .toList();

    return Scaffold(
      body: SafeArea(
        // Asıl eylem düğmesi listenin içinde değil, altta sabit duruyor.
        // Liste uzadıkça (zamanlar, tür süzgeci, düzensiz anahtarı)
        // düğme ekrandan çıkıyordu; artık her zaman görünür.
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                children: <Widget>[
                  Text(
                    'Fiil çekimi',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kart sana bir fiil ve bir şahıs verir, sen çekimi hatırlarsın.',
                    style: TextStyle(fontSize: 13, color: faint),
                  ),
                  const SizedBox(height: 22),
                  Text('Zaman', style: _section(theme)),
                  const SizedBox(height: 10),
                  for (int i = 0; i < tenses.length; i++)
                    StaggeredEntry(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _TenseTile(
                          tense: tenses[i],
                          selected: _tense == tenses[i],
                          onTap: () => setState(() => _tense = tenses[i]),
                        ),
                      ),
                    ),
                  if (tenses.isEmpty)
                    Text(
                      'Seviyende çalışılacak zaman yok. Ayarlardan seviyeni '
                      'yükseltebilirsin.',
                      style: TextStyle(fontSize: 13, color: faint),
                    ),
                  const SizedBox(height: 14),
                  Text('Fiil türü', style: _section(theme)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final _VerbFilter f in _VerbFilter.values)
                        ChoiceChip(
                          label: Text(f.label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: AnimatedSwitcher(
                      duration: MotionTokens.selection,
                      switchInCurve: MotionTokens.settle,
                      switchOutCurve: Curves.easeIn,
                      child: Text(
                        _filter.description,
                        key: ValueKey<String>(
                          'verb_filter_description_${_filter.name}',
                        ),
                        style: TextStyle(fontSize: 12, color: faint),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ArenaLaunchTile(
                    tense: _tense,
                    onTap: () => Navigator.of(context).push(
                      fadeSlideRoute<void>(
                        ReflexiveArenaScreen(tense: _tense),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sadece düzensiz fiiller'),
                    subtitle: Text(
                      '3. grup fiiller, kalıbı olmayanlar',
                      style: TextStyle(fontSize: 12, color: faint),
                    ),
                    value: _irregularOnly,
                    onChanged: (bool v) => setState(() => _irregularOnly = v),
                  ),
                  const SizedBox(height: 18),
                  const VerbTablesTile(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      tenses.isEmpty || _starting ? null : () => _start(app),
                  icon: _starting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label:
                      Text(_starting ? 'Deste hazırlanıyor' : 'Oturumu başlat'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static TextStyle _section(ThemeData t) => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: t.colorScheme.onSurface,
      );
}

/// Fiil destesinde tür süzgeci.
enum _VerbFilter { all, reflexiveOnly, plainOnly }

class _ArenaLaunchTile extends StatelessWidget {
  const _ArenaLaunchTile({required this.tense, required this.onTap});

  final VerbTense tense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.colorScheme.primary;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.94, end: 1),
      duration: MotionTokens.cardSettle,
      curve: MotionTokens.badge,
      builder: (BuildContext context, double scale, Widget? child) =>
          Transform.scale(scale: scale, child: child),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              accent.withValues(alpha: 0.22),
              const Color(0xFFFFC247).withValues(alpha: 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child:
                        Icon(Icons.sports_martial_arts_rounded, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Dönüşlü Fiil Arenası',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${tense.label} · zamir, çekim ve combo savaşı',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.56),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension _VerbFilterX on _VerbFilter {
  String get label => switch (this) {
        _VerbFilter.all => 'Hepsi',
        _VerbFilter.reflexiveOnly => 'Dönüşlü',
        _VerbFilter.plainOnly => 'Dönüşsüz',
      };

  String get description => switch (this) {
        _VerbFilter.all =>
          'Dönüşlü ve dönüşsüz fiiller aynı oturumda karışık gelir.',
        _VerbFilter.reflexiveOnly =>
          'Yalnızca "se / s\'" ile kurulan dönüşlü fiiller gelir. '
              'Bileşik zamanlarda être kullanırlar.',
        _VerbFilter.plainOnly =>
          'Yalnızca "se / s\'" almayan dönüşsüz fiiller gelir.',
      };
}

class _TenseTile extends StatelessWidget {
  const _TenseTile({
    required this.tense,
    required this.selected,
    required this.onTap,
  });

  final VerbTense tense;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.colorScheme.primary;
    return AnimatedContainer(
      duration: MotionTokens.selection,
      curve: MotionTokens.settle,
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? accent
              : theme.colorScheme.onSurface.withValues(alpha: 0.08),
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        tense.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        tense.labelTr,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tense.level.code,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ oturum

class VerbSessionScreen extends StatefulWidget {
  const VerbSessionScreen({
    super.key,
    required this.tense,
    required this.conjugations,
    required this.selectedRefIds,
  });

  final VerbTense tense;
  final List<Conjugation> conjugations;
  final List<String> selectedRefIds;

  @override
  State<VerbSessionScreen> createState() => _VerbSessionScreenState();
}

class _VerbSessionScreenState extends State<VerbSessionScreen> with ProgressSession<VerbSessionScreen> {
  final CardStackController _stack = CardStackController();

  late AppState _app;
  late Map<String, Conjugation> _byRef;
  List<String> _deck = <String>[];
  int _completed = 0;
  int _right = 0;
  int _startXp = 0;
  int _startCoins = 0;
  bool _built = false;
  TtsService? _tts;
  bool _ttsRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    _built = true;
    _app = AppScope.of(context);
    _startXp = _app.game.profile.xp;
    _startCoins = _app.game.profile.coins;
    _byRef = <String, Conjugation>{
      for (final Conjugation c in widget.conjugations) c.refId: c,
    };
    _deck = widget.selectedRefIds.where(_byRef.containsKey).toList();
    if (!_ttsRequested) {
      _ttsRequested = true;
      TtsService.instance().then((TtsService s) {
        if (mounted) setState(() => _tts = s);
      });
    }
  }

  SwipeAction _toAction(SwipeDirection d) => switch (d) {
        SwipeDirection.right => SwipeAction.know,
        SwipeDirection.left => SwipeAction.dontKnow,
        SwipeDirection.up => SwipeAction.hard,
        SwipeDirection.down => SwipeAction.skip,
      };

  bool _saving = false;

  Future<bool> _onSwiped(int index, SwipeDirection direction) async {
    if (!progressReady) return false;
    if (_saving) return false;
    _saving = true;
    final String refId = _deck[index];
    final SwipeAction action = _toAction(direction);
    final DateTime now = DateTime.now();
    try {
      await _app.recordAnswer(
          cardType: AnswerCardType.conjugation,
          refId: refId,
          action: action,
          now: now);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Cevap kaydedilemedi. Kartı yeniden yanıtlayabilir veya geri çıkabilirsiniz.'),
        ));
      }
      return false;
    } finally {
      _saving = false;
    }
    if (!mounted) return true;
    setState(() {
      _completed++;
      if (action == SwipeAction.know) _right++;
      if (action == SwipeAction.dontKnow) {
        final int target = index + SessionBuilder.reinsertAfter;
        _deck.insert(target > _deck.length ? _deck.length : target, refId);
      }
    });
    return true;
  }

  bool get _isDone => _deck.isEmpty || _completed >= _deck.length;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double progress =
        _deck.isEmpty ? 1 : (_completed / _deck.length).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tense.label),
        actions: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '$_completed / ${_deck.length}',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress),
                duration: MotionTokens.progressFill,
                curve: MotionTokens.progress,
                builder: (BuildContext c, double v, Widget? _) => ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: v, minHeight: 6),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: _isDone
                    ? _VerbSummary(
                        total: _completed,
                        right: _right,
                        earnedXp: _app.game.profile.xp - _startXp,
                        earnedCoins: _app.game.profile.coins - _startCoins,
                        onClose: () {
                          _app.notifyProgressChanged();
                          Navigator.of(context).pop();
                        },
                      )
                    : CardStack(
                        controller: _stack,
                        itemCount: _deck.length,
                        onSwipeAccepted: _onSwiped,
                        itemBuilder: (BuildContext c, int i) {
                          final Conjugation? conj = _byRef[_deck[i]];
                          if (conj == null) return const SizedBox.shrink();
                          return ConjugationCard(
                            conjugation: conj,
                            tableFor: _tableFor,
                            onSpeak: _tts?.speak,
                          );
                        },
                      ),
              ),
            ),
            if (!_isDone)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (final (SwipeDirection d, IconData icon)
                      in <(SwipeDirection, IconData)>[
                    (SwipeDirection.left, Icons.close_rounded),
                    (
                      SwipeDirection.down,
                      Icons.keyboard_double_arrow_down_rounded
                    ),
                    (SwipeDirection.up, Icons.star_rounded),
                    (SwipeDirection.right, Icons.check_rounded),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: IconButton.filledTonal(
                        onPressed: () => _stack.swipe(d),
                        icon: Icon(icon, color: d.color),
                        tooltip: d.label,
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// Kartın arkasındaki tam çekim tablosu için.
  Map<String, String>? _tableFor(Verb verb, VerbTense tense) {
    final Map<String, String> row = <String, String>{};
    for (final Conjugation c in widget.conjugations) {
      if (c.verb.id == verb.id && c.tense == tense) {
        row[c.person] = c.form;
      }
    }
    return row.isEmpty ? null : row;
  }
}

class _VerbSummary extends StatelessWidget {
  const _VerbSummary({
    required this.total,
    required this.right,
    required this.earnedXp,
    required this.earnedCoins,
    required this.onClose,
  });

  final int total;
  final int right;
  final int earnedXp;
  final int earnedCoins;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int pct = total == 0 ? 0 : (100 * right / total).round();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Oturum bitti',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: pct.toDouble()),
            duration: MotionTokens.counterRise,
            curve: MotionTokens.counter,
            builder: (BuildContext c, double v, Widget? _) => Text(
              '%${v.round()}',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Text(
            '$right / $total çekimi bildin',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '+$earnedXp XP   +$earnedCoins coin',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 30),
          FilledButton(onPressed: onClose, child: const Text('Bitir')),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- kart

class ConjugationCard extends StatelessWidget {
  const ConjugationCard({
    super.key,
    required this.conjugation,
    required this.tableFor,
    this.onSpeak,
  });

  final Conjugation conjugation;
  final Map<String, String>? Function(Verb verb, VerbTense tense) tableFor;
  final Future<void> Function(String text)? onSpeak;

  @override
  Widget build(BuildContext context) {
    return FlipCard(
      front: _Shell(child: _Front(conjugation: conjugation)),
      back: _Shell(
        child: _Back(
          conjugation: conjugation,
          table: tableFor(conjugation.verb, conjugation.tense),
          onSpeak: onSpeak,
        ),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.cardColor(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: MotionTokens.shadowBlur,
            offset: const Offset(0, MotionTokens.shadowRestOffsetY),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        child: child,
      ),
    );
  }
}

class _Front extends StatelessWidget {
  const _Front({required this.conjugation});

  final Conjugation conjugation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.45);
    final Verb v = conjugation.verb;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 6,
          children: <Widget>[
            _Tag(conjugation.tense.label),
            _Tag('${v.group}. grup', color: faint),
            _Tag(v.level.code, color: faint),
            if (v.takesEtre) _Tag('être', color: theme.colorScheme.tertiary),
            if (v.isReflexive) const _Tag('dönüşlü', color: Color(0xFFD9A21B)),
          ],
        ),
        const Spacer(),
        Center(
          child: Column(
            children: <Widget>[
              Text(
                v.infinitive,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '(${v.meaningTr})',
                style: TextStyle(fontSize: 14, color: faint),
              ),
              const SizedBox(height: 32),
              Text(
                conjugation.person,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '?',
                style: TextStyle(fontSize: 30, color: faint),
              ),
            ],
          ),
        ),
        const Spacer(),
        Center(
          child: Text(
            'Çevirmek için dokun',
            style: TextStyle(fontSize: 12, color: faint),
          ),
        ),
      ],
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({
    required this.conjugation,
    required this.table,
    this.onSpeak,
  });

  final Conjugation conjugation;
  final Map<String, String>? table;
  final Future<void> Function(String text)? onSpeak;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Column(
            children: <Widget>[
              Text(
                conjugation.display,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (onSpeak != null)
                IconButton(
                  onPressed: () => onSpeak!(conjugation.display),
                  icon: const Icon(Icons.volume_up_rounded),
                  color: faint,
                  tooltip: 'Seslendir',
                ),
            ],
          ),
        ),
        // Dönüşlü fiilin türü ve temel fiille anlam farkı. Bu kartın en
        // önemli bilgisi: "se rendre" ile "rendre" aynı fiil değildir.
        if (conjugation.verb.isReflexive) ...<Widget>[
          const SizedBox(height: 10),
          Builder(
            builder: (BuildContext context) {
              final Verb v = conjugation.verb;
              final ({String label, String hint})? kind = v.reflexiveLabel;
              const Color amber = Color(0xFFD9A21B);
              return Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: amber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    left: BorderSide(
                      color: amber.withValues(alpha: 0.6),
                      width: 3,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (kind != null)
                      Text(
                        '${kind.label} — ${kind.hint}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: amber,
                        ),
                      ),
                    if (v.noteTr != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        v.noteTr!,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 8),
        Divider(color: theme.colorScheme.onSurface.withValues(alpha: 0.12)),
        const SizedBox(height: 10),
        Text(
          'Tam çekim · ${conjugation.tense.label}',
          style: TextStyle(fontSize: 12, color: faint),
        ),
        const SizedBox(height: 10),
        if (table != null)
          Column(
            children: <Widget>[
              for (int i = 0; i < kPersons.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _Cell(
                          person: kPersons[i],
                          form: table![kPersons[i]],
                          highlight: kPersons[i] == conjugation.person,
                          aspiratedH: conjugation.verb.aspiratedH,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: i + 1 < kPersons.length
                            ? _Cell(
                                person: kPersons[i + 1],
                                form: table![kPersons[i + 1]],
                                highlight:
                                    kPersons[i + 1] == conjugation.person,
                                aspiratedH: conjugation.verb.aspiratedH,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const Spacer(),
        if (conjugation.verb.takesEtre)
          Text(
            'Not: bileşik zamanlarda "être" ile çekilir, ortaç özneye uyar.',
            style: TextStyle(fontSize: 11, height: 1.3, color: faint),
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.person,
    required this.form,
    required this.highlight,
    required this.aspiratedH,
  });

  final String person;
  final String? form;
  final bool highlight;
  final bool aspiratedH;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (form == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        conjugationDisplay(person, form!, aspiratedH: aspiratedH),
        style: TextStyle(
          fontSize: 14,
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
          color: theme.colorScheme.onSurface
              .withValues(alpha: highlight ? 1.0 : 0.75),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
