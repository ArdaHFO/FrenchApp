import '../../app/progress_session.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import 'quiz_engine.dart';
import '../../app/app_state.dart';
import '../../data/repositories.dart';
import '../../domain/srs/srs_card.dart';
import '../../motion/celebration.dart';
import '../../motion/motion_tokens.dart';
import '../../services/tts_service.dart';

/// Quiz soru tipleri. PLAN.md bölüm 2.2 (e).
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with ProgressSession<QuizScreen> {
  final Random _rng = Random();

  AppState? _app;
  List<QuizQuestion>? _questions;
  int _index = 0;
  int _correct = 0;
  String? _picked;
  bool _saving = false;
  String? _saveError;
  int _wrongTick = 0;
  int _combo = 0;
  int _bestCombo = 0;
  Timer? _timer;
  TtsService? _tts;
  bool _ttsRequested = false;
  bool _started = false;

  static const int _questionCount = 12;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

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

  Future<void> _build() async {
    final AppState app = _app!;
    setState(() => _started = true);

    // Havuz SRS'ten geliyor: yalnizca bir kez dogru bilinmis kartlar.
    final List<String> wordIds = <String>[
      for (final SrsCard c in app.cards.quizPool()..shuffle(_rng)) c.refId,
    ];
    final List<String> verbIds = <String>[
      for (final SrsCard c in (app.verbCards.quizPool()..shuffle(_rng)).take(6))
        c.refId,
    ];

    final List<QuizQuestion> out = await QuizEngine.build(
      app: app,
      wordIds: wordIds,
      verbRefIds: verbIds,
      count: _questionCount,
      rng: _rng,
    );

    if (!mounted) return;
    setState(() {
      _questions = out;
      _index = 0;
      _correct = 0;
      _combo = 0;
      _bestCombo = 0;
      _picked = null;
      _saving = false;
      _saveError = null;
    });
  }

  Future<void> _answer(String option) async {
    if (!progressReady) return;
    final List<QuizQuestion>? qs = _questions;
    if (qs == null || _index >= qs.length || _picked != null || _saving) return;
    final QuizQuestion q = qs[_index];
    final bool right = option == q.correct;
    final int nextCombo = right ? _combo + 1 : 0;
    final int nextBestCombo = max(_bestCombo, nextCombo);
    final DateTime at = DateTime.now();

    setState(() {
      _picked = option;
      _saving = true;
      _saveError = null;
    });

    try {
      await _app!.recordQuizAnswer(
        cardType: q.isVerbCard ? AnswerCardType.conjugation : AnswerCardType.word,
        refId: q.refId,
        correct: right,
        combo: nextBestCombo,
        now: at,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picked = null;
        _saving = false;
        _saveError = 'Cevap kaydedilemedi. Tekrar deneyin.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      if (right) {
        _correct++;
      } else {
        _wrongTick++;
      }
      _combo = nextCombo;
      _bestCombo = nextBestCombo;
    });

    _timer?.cancel();
    _timer = Timer(MotionTokens.quizReveal, () {
      if (!mounted) return;
      setState(() {
        _picked = null;
        _index++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppState app = _app!;
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    final int poolSize = app.words
            .learningIds(app.cards.quizPool().map((SrsCard c) => c.refId))
            .length +
        app.verbCards.quizPool().length;

    if (!_started) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.quiz_rounded, size: 44, color: faint),
                  const SizedBox(height: 18),
                  Text(
                    'Quiz',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    poolSize == 0
                        ? 'Henüz soru havuzu yok. Sorular sadece bir kez '
                            'doğru bildiğin kartlardan gelir, önce biraz '
                            'kelime veya fiil çalış.'
                        : 'Havuzda $poolSize kart var. Sorular kelimelerden '
                            've fiil çekimlerinden karışık gelir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.4, color: faint),
                  ),
                  const SizedBox(height: 26),
                  FilledButton.icon(
                    onPressed: poolSize == 0 ? null : _build,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Başla'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final List<QuizQuestion>? qs = _questions;
    if (qs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (qs.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Soru üretilemedi. Çeldirici bulmak için biraz daha kelime '
              'çalışman gerekiyor.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: faint),
            ),
          ),
        ),
      );
    }
    if (_index >= qs.length) {
      return _Result(
        total: qs.length,
        correct: _correct,
        onAgain: () {
          setState(() {
            _started = false;
            _questions = null;
          });
          app.notifyProgressChanged();
        },
      );
    }

    final QuizQuestion q = qs[_index];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _index / qs.length),
                duration: MotionTokens.progressFill,
                curve: MotionTokens.progress,
                builder: (BuildContext c, double v, Widget? _) => ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: v, minHeight: 6),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Text(
                    q.kind.labelTr,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (_combo >= 3) ...<Widget>[
                    const SizedBox(width: 8),
                    TweenAnimationBuilder<double>(
                      key: ValueKey<int>(_combo),
                      tween: Tween<double>(begin: 0.7, end: 1),
                      duration: MotionTokens.selection,
                      curve: MotionTokens.badge,
                      builder: (BuildContext context, double scale, _) =>
                          Transform.scale(
                        scale: scale,
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.bolt_rounded, size: 16),
                          label: Text('$_combo combo'),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${_index + 1} / ${qs.length}',
                    style: TextStyle(fontSize: 12, color: faint),
                  ),
                ],
              ),
              if (_saving)
                const Text('Kaydediliyor…', textAlign: TextAlign.center),
              if (_saveError != null)
                Text(_saveError!, textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error)),
              const Spacer(),
              Text(
                q.prompt,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: q.prompt.length > 40 ? 20 : 30,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (q.subPrompt != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  q.subPrompt!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: faint),
                ),
              ],
              if (q.speakText != null && (_tts?.available ?? false))
                IconButton(
                  onPressed: () => _tts!.speak(q.speakText!),
                  icon: const Icon(Icons.volume_up_rounded),
                  color: faint,
                ),
              const Spacer(),
              for (final String option in q.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Shake(
                    trigger: option == _picked && option != q.correct
                        ? _wrongTick
                        : null,
                    child: _Option(
                      label: option,
                      state: _picked == null || _saving
                          ? _OptState.idle
                          : option == q.correct
                              ? _OptState.correct
                              : (option == _picked
                                  ? _OptState.wrong
                                  : _OptState.idle),
                      onTap: () => _answer(option),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _OptState { idle, correct, wrong }

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String label;
  final _OptState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color bg = switch (state) {
      _OptState.idle =>
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      _OptState.correct => const Color(0xFF2E9E5B).withValues(alpha: 0.25),
      _OptState.wrong => const Color(0xFFC0392B).withValues(alpha: 0.25),
    };
    final Color border = switch (state) {
      _OptState.idle => theme.colorScheme.onSurface.withValues(alpha: 0.12),
      _OptState.correct => const Color(0xFF2E9E5B),
      _OptState.wrong => const Color(0xFFC0392B),
    };

    return AnimatedContainer(
      duration: MotionTokens.selection,
      curve: MotionTokens.settle,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: border,
          width: state == _OptState.idle ? 1 : 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: state == _OptState.idle
                          ? FontWeight.w400
                          : FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                // Sonuç işareti belirirken büyüyerek gelir; doğru/yanlış
                // rengi tek başına yeterli değil, simge de destekliyor.
                AnimatedScale(
                  scale: state == _OptState.idle ? 0.0 : 1.0,
                  duration: MotionTokens.selection,
                  curve: MotionTokens.settle,
                  child: Icon(
                    state == _OptState.wrong
                        ? Icons.close_rounded
                        : Icons.check_rounded,
                    size: 20,
                    color: border,
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

class _Result extends StatelessWidget {
  const _Result({
    required this.total,
    required this.correct,
    required this.onAgain,
  });

  final int total;
  final int correct;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int pct = total == 0 ? 0 : (100 * correct / total).round();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Quiz bitti',
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
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Text(
                '$correct / $total doğru',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 30),
              FilledButton(
                onPressed: onAgain,
                child: const Text('Tekrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
