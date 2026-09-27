import '../../app/progress_session.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../domain/journey.dart';
import '../../motion/celebration.dart';
import '../../motion/motion_tokens.dart';
import '../quiz/quiz_engine.dart';
import 'station_builder.dart';

/// Bir harita durağının quizi.
///
/// Serbest quizden iki farkı var: sorular durağın kendi kelimelerinden
/// gelir (SRS havuzundan değil, yani daha görmediğin kelime de çıkabilir)
/// ve sonunda geçtin/kaldın hükmü verilir.
class StationQuizScreen extends StatefulWidget {
  const StationQuizScreen({super.key, required this.station});

  final JourneyStation station;

  @override
  State<StationQuizScreen> createState() => _StationQuizScreenState();
}

class _StationQuizScreenState extends State<StationQuizScreen> with ProgressSession<StationQuizScreen> {
  final Random _rng = Random();

  AppState? _app;
  List<QuizQuestion>? _questions;
  int _index = 0;
  int _correct = 0;
  String? _picked;
  bool _loading = true;
  StationResult? _saved;
  int? _attemptStars;
  ({int stars, int correct, int total, int combo, DateTime at})? _finalAttempt;
  bool _saving = false;
  bool _saveFailed = false;

  /// Her yanlış cevapta artar; `Shake` bunu tetikleyici olarak kullanır.
  int _wrongTick = 0;

  /// Arka arkaya doğru sayısı. Yanlışta sıfırlanır.
  int _combo = 0;
  int _bestCombo = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_app != null) return;
    _app = AppScope.of(context);
    _load();
  }

  Future<void> _load() async {
    final AppState app = _app!;
    final JourneyStation s = widget.station;
    final List<String> verbIds =
        List<String>.of(await StationBuilder.verbRefIdsFor(app, s))
          ..shuffle(_rng);
    final List<String> wordIds = List<String>.of(s.wordIds)..shuffle(_rng);

    final List<QuizQuestion> qs = await QuizEngine.build(
      app: app,
      wordIds: wordIds,
      verbRefIds: verbIds,
      count: s.questionCount,
      rng: _rng,
    );
    if (!mounted) return;
    setState(() {
      _questions = qs;
      _loading = false;
    });
  }

  void _answer(String option) {
    if (!progressReady) return;
    final List<QuizQuestion>? qs = _questions;
    if (qs == null || _picked != null) return;
    final QuizQuestion q = qs[_index];
    final bool right = option == q.correct;

    setState(() {
      _picked = option;
      if (right) {
        _correct++;
        _combo++;
        if (_combo > _bestCombo) _bestCombo = _combo;
      } else {
        _wrongTick++;
        _combo = 0;
      }
    });

    // Dokunsal geri bildirim: doğru hafif, yanlış belirgin. Ekrana
    // bakmadan da cevabın tutup tutmadığı anlaşılıyor.
    if (right) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }

    Future<void>.delayed(MotionTokens.quizReveal, () async {
      if (!progressReady) return;
      if (_index + 1 < qs.length) {
        setState(() {
          _index++;
          _picked = null;
        });
        return;
      }
      // Bitti: sonucu kaydet.
      final int stars = JourneyStation.starsFor(
        _correct,
        qs.length,
        widget.station.passRatio,
      );
      _finalAttempt = (stars: stars, correct: _correct, total: qs.length,
          combo: _bestCombo, at: DateTime.now());
      await _saveFinalAttempt();
    });
  }

  Future<void> _saveFinalAttempt() async {
    final attempt = _finalAttempt;
    if (_saving || _saved != null || attempt == null || !progressReady) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await _app!.completeStationQuiz(
        stationId: widget.station.id,
        stars: attempt.stars,
        correct: attempt.correct,
        total: attempt.total,
        combo: attempt.combo,
        now: attempt.at,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (!progressReady) return;
    setState(() {
      _attemptStars = attempt.stars;
      _saved = _app!.journey.resultFor(widget.station.id);
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final JourneyStation s = widget.station;
    final Color accent = AppTheme.levelColor(s.level.index);
    final List<QuizQuestion>? qs = _questions;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: <Widget>[
          if (qs != null && _saved == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${_index + 1} / ${qs.length}',
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : qs == null || qs.isEmpty
                ? _empty(context)
                : _saved != null
                    ? _result(context, qs.length, accent)
                    : _question(context, qs[_index], accent),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'Bu durak için yeterli soru üretilemedi. '
          'İçerik güncellendiğinde açılacak.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _question(BuildContext context, QuizQuestion q, Color accent) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final List<QuizQuestion> qs = _questions!;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: (_index + 1) / qs.length),
              duration: MotionTokens.progressFill,
              curve: MotionTokens.progress,
              builder: (BuildContext context, double v, Widget? _) =>
                  LinearProgressIndicator(
                value: v,
                color: accent,
                minHeight: 6,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        q.kind.labelTr,
                        style: TextStyle(fontSize: 12, color: faint),
                      ),
                    ),
                    _ComboBadge(combo: _combo, accent: accent),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  q.prompt,
                  style: TextStyle(
                    fontSize: q.prompt.length > 40 ? 20 : 28,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (q.subPrompt != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    q.subPrompt!,
                    style: TextStyle(fontSize: 13, color: faint),
                  ),
                ],
                const Spacer(),
                for (final String option in q.options) ...<Widget>[
                  Shake(
                    trigger: option == _picked && option != q.correct
                        ? _wrongTick
                        : null,
                    child: _Option(
                      label: option,
                      state: _picked == null
                          ? _OptState.idle
                          : option == q.correct
                              ? _OptState.correct
                              : option == _picked
                                  ? _OptState.wrong
                                  : _OptState.idle,
                      onTap: () => _answer(option),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_saving) const LinearProgressIndicator(),
                if (_saveFailed) ...<Widget>[
                  const Text('Sonuç kaydedilemedi. Tekrar deneyin.'),
                  FilledButton(
                    key: const ValueKey('station_save_retry'),
                    onPressed: _saveFinalAttempt,
                    child: const Text('Kaydetmeyi tekrar dene'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _result(BuildContext context, int total, Color accent) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final int attemptStars = _attemptStars ?? 0;
    final bool passed = attemptStars > 0;

    return Celebration(
      // Kutlama yalnızca geçince oynar. Kaybedince parti yapmak
      // sonucu anlamsızlaştırır.
      play: passed,
      colors: <Color>[
        accent,
        const Color(0xFFD9A21B),
        Colors.white,
        accent.withValues(alpha: 0.6),
      ],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Yıldızlar sırayla, birer birer belirir.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (int i = 0; i < 3; i++)
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0,
                        end: i < attemptStars ? 1 : 0,
                      ),
                      duration: Duration(milliseconds: 420 + i * 220),
                      curve: Curves.elasticOut,
                      builder: (BuildContext context, double v, Widget? _) =>
                          Transform.scale(
                        scale: 0.6 + 0.4 * v,
                        child: Icon(
                          i < attemptStars
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 52,
                          color: i < attemptStars
                              ? const Color(0xFFD9A21B)
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                passed ? 'Durak geçildi' : 'Bu sefer olmadı',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              if (_bestCombo >= 3) ...<Widget>[
                Text(
                  'En uzun seri: $_bestCombo doğru',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                '$_correct / $total doğru'
                '${passed ? '' : ' · geçmek için '
                    '${(widget.station.passRatio * 100).round()}% gerekiyor'}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: faint),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(passed ? 'Haritaya dön' : 'Haritaya dön'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _saved = null;
                      _attemptStars = null;
                      _finalAttempt = null;
                      _saveFailed = false;
                      _index = 0;
                      _correct = 0;
                      _picked = null;
                      _loading = true;
                    });
                    _load();
                  },
                  child: const Text('Tekrar dene'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Arka arkaya doğru sayacı.
///
/// Üçten önce görünmez: her doğruda rozet çıkarsa anlamı kalmıyor.
/// Sayı büyüdükçe rozet ısınıyor ve her artışta bir kez zıplıyor.
class _ComboBadge extends StatelessWidget {
  const _ComboBadge({required this.combo, required this.accent});

  final int combo;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (combo < 3) return const SizedBox(height: 26);
    final Color color = combo >= 8
        ? const Color(0xFFD9531B)
        : combo >= 5
            ? const Color(0xFFD9A21B)
            : accent;

    return TweenAnimationBuilder<double>(
      // Anahtar combo: sayı her değiştiğinde animasyon baştan oynar.
      key: ValueKey<int>(combo),
      tween: Tween<double>(begin: 0, end: 1),
      duration: MotionTokens.selection,
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double v, Widget? child) =>
          Transform.scale(scale: 0.7 + 0.3 * v, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.bolt_rounded, size: 14, color: color),
            const SizedBox(width: 3),
            Text(
              '$combo',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
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
