import '../../app/progress_session.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../domain/verb.dart';
import '../../motion/celebration.dart';
import '../../motion/motion_tokens.dart';

class ReflexiveArenaScreen extends StatefulWidget {
  const ReflexiveArenaScreen({super.key, required this.tense});

  final VerbTense tense;

  @override
  State<ReflexiveArenaScreen> createState() => _ReflexiveArenaScreenState();
}

class _ReflexiveArenaScreenState extends State<ReflexiveArenaScreen> with ProgressSession<ReflexiveArenaScreen> {
  final Random _random = Random();
  AppState? _app;
  List<_ArenaQuestion>? _questions;
  int _index = 0;
  int _correct = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _wrongTick = 0;
  String? _picked;
  bool _saving = false;
  bool _saveFailed = false;
  ({bool right, int correct, int combo, int bestCombo, int wrongTick})? _pending;
  int _startXp = 0;
  int _startCoins = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_app != null) return;
    _app = AppScope.of(context);
    _startXp = _app!.game.profile.xp;
    _startCoins = _app!.game.profile.coins;
    _load();
  }

  Future<void> _load() async {
    final AppState app = _app!;
    final List<Verb> verbs = (await app.verbs.byLevels(app.activeLevels))
        .where((Verb verb) => verb.isReflexive)
        .toList()
      ..shuffle(_random);
    final List<_ArenaQuestion> questions = <_ArenaQuestion>[];
    for (final Verb verb in verbs.take(24)) {
      final Map<VerbTense, Map<String, String>> tables =
          await app.verbs.tablesFor(verb);
      final Map<String, String>? table = tables[widget.tense];
      if (table == null || table.length < 4) continue;
      final List<String> persons = <String>[
        for (final String person in kPersons)
          if ((table[person] ?? '').isNotEmpty) person,
      ];
      if (persons.length < 4) continue;
      final String person = persons[_random.nextInt(persons.length)];
      final String correct = conjugationDisplay(
        person,
        table[person]!,
        tense: widget.tense,
        aspiratedH: verb.aspiratedH,
      );
      final List<String> options = <String>[correct];
      for (final String other in persons..shuffle(_random)) {
        final String option = conjugationDisplay(
          other,
          table[other]!,
          tense: widget.tense,
          aspiratedH: verb.aspiratedH,
        );
        if (!options.contains(option)) options.add(option);
        if (options.length == 4) break;
      }
      if (options.length < 4) continue;
      options.shuffle(_random);
      questions.add(
        _ArenaQuestion(
          verb: verb,
          person: person,
          correct: correct,
          options: options,
        ),
      );
      if (questions.length == 12) break;
    }
    if (!mounted) return;
    setState(() => _questions = questions);
  }

  Future<void> _answer(String option) async {
    if (!progressReady) return;
    final List<_ArenaQuestion>? questions = _questions;
    if (questions == null || _picked != null || _index >= questions.length) {
      return;
    }
    final bool right = option == questions[_index].correct;
    final combo = right ? _combo + 1 : 0;
    _pending = (right: right, correct: _correct + (right ? 1 : 0),
        combo: combo, bestCombo: combo > _bestCombo ? combo : _bestCombo,
        wrongTick: _wrongTick + (right ? 0 : 1));
    setState(() => _picked = option);
    right ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    await _saveAnswer();
  }

  Future<void> _saveAnswer() async {
    final pending = _pending;
    if (_saving || pending == null || !progressReady) return;
    setState(() { _saving = true; _saveFailed = false; });
    try {
      await _app!.recordActivity(quizTotal: 1, quizCorrect: pending.right ? 1 : 0,
          verbSwiped: 1, combo: pending.bestCombo);
    } catch (_) {
      if (mounted) setState(() { _saving = false; _saveFailed = true; });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (!progressReady) return;
    setState(() {
      _correct = pending.correct;
      _combo = pending.combo;
      _bestCombo = pending.bestCombo;
      _wrongTick = pending.wrongTick;
      _pending = null;
    });
    await Future<void>.delayed(MotionTokens.quizReveal);
    if (!progressReady) return;
    setState(() {
      _index++;
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<_ArenaQuestion>? questions = _questions;
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dönüşlü Fiil Arenası'),
        actions: <Widget>[
          if (questions != null && _index < questions.length)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${_index + 1} / ${questions.length}'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: questions == null
            ? const Center(child: CircularProgressIndicator())
            : questions.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Bu seviye ve zaman için yeterli güvenli dönüşlü fiil yok.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _index >= questions.length
                    ? _result(theme, questions.length)
                    : _question(theme, questions[_index]),
      ),
    );
  }

  Widget _question(ThemeData theme, _ArenaQuestion question) {
    final double progress = (_index + 1) / _questions!.length;
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: progress),
              duration: MotionTokens.progressFill,
              curve: MotionTokens.progress,
              builder: (BuildContext context, double value, _) =>
                  LinearProgressIndicator(value: value, minHeight: 7),
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: MotionTokens.pageTransition,
            transitionBuilder: (Widget child, Animation<double> animation) {
              final Animation<Offset> slide = Tween<Offset>(
                begin: const Offset(0.12, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: Padding(
              key: ValueKey<int>(_index),
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(widget.tense.label, style: TextStyle(color: faint)),
                      const Spacer(),
                      if (_combo >= 3) _ArenaCombo(combo: _combo),
                    ],
                  ),
                  const Spacer(),
                  Icon(
                    Icons.change_circle_rounded,
                    size: 46,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    question.verb.infinitive,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    question.verb.meaningTr,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: faint),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    '“${question.person}” için doğru çekimi seç',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  for (final String option in question.options) ...<Widget>[
                    Shake(
                      trigger: option == _picked && option != question.correct
                          ? _wrongTick
                          : null,
                      child: _ArenaOption(
                        label: option,
                        selected: option == _picked,
                        correct: _picked != null && option == question.correct,
                        wrong: option == _picked && option != question.correct,
                        onTap: () => _answer(option),
                      ),
                    ),
                    const SizedBox(height: 9),
                  ],
                  if (_saving) const LinearProgressIndicator(),
                  if (_saveFailed) ...<Widget>[
                    const Text('Sonuç kaydedilemedi. Tekrar deneyin.'),
                    FilledButton(key: const ValueKey('arena_save_retry'),
                        onPressed: _saveAnswer, child: const Text('Kaydetmeyi tekrar dene')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _result(ThemeData theme, int total) {
    final int xp = _app!.game.profile.xp - _startXp;
    final int coins = _app!.game.profile.coins - _startCoins;
    final bool strong = _correct / total >= 0.75;
    return Celebration(
      play: strong && !_app!.reducedMotion,
      colors: <Color>[
        theme.colorScheme.primary,
        const Color(0xFFFFC247),
        Colors.white,
      ],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                strong ? Icons.emoji_events_rounded : Icons.fitness_center,
                size: 68,
                color: strong
                    ? const Color(0xFFFFC247)
                    : theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                strong ? 'Arena kazanıldı!' : 'Bir tur daha güçlen',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text('$_correct / $total doğru · en iyi seri $_bestCombo'),
              const SizedBox(height: 16),
              Text(
                '+$xp XP   +$coins coin',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.flag_rounded),
                label: const Text('Arenayı bitir'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArenaQuestion {
  const _ArenaQuestion({
    required this.verb,
    required this.person,
    required this.correct,
    required this.options,
  });

  final Verb verb;
  final String person;
  final String correct;
  final List<String> options;
}

class _ArenaCombo extends StatelessWidget {
  const _ArenaCombo({required this.combo});

  final int combo;

  @override
  Widget build(BuildContext context) {
    final Color color = combo >= 8
        ? const Color(0xFFFF6534)
        : combo >= 5
            ? const Color(0xFFFFC247)
            : Theme.of(context).colorScheme.primary;
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(combo),
      tween: Tween<double>(begin: 0.65, end: 1),
      duration: MotionTokens.selection,
      curve: MotionTokens.badge,
      builder: (BuildContext context, double scale, Widget? child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          '⚡ $combo combo',
          style: TextStyle(fontWeight: FontWeight.w800, color: color),
        ),
      ),
    );
  }
}

class _ArenaOption extends StatelessWidget {
  const _ArenaOption({
    required this.label,
    required this.selected,
    required this.correct,
    required this.wrong,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool correct;
  final bool wrong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = correct
        ? const Color(0xFF2E9E5B)
        : wrong
            ? const Color(0xFFC0392B)
            : theme.colorScheme.onSurface.withValues(alpha: 0.15);
    return AnimatedContainer(
      duration: MotionTokens.selection,
      decoration: BoxDecoration(
        color: (correct || wrong)
            ? color.withValues(alpha: 0.16)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color, width: correct || wrong ? 2 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AnimatedScale(
                  scale: selected || correct ? 1 : 0,
                  duration: MotionTokens.selection,
                  child: Icon(
                    wrong ? Icons.close_rounded : Icons.check_rounded,
                    color: color,
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
