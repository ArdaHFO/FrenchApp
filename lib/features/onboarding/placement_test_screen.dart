import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/level.dart';
import '../../motion/motion_tokens.dart';

/// Yerleştirme testi. PLAN.md bölüm 3.2.
///
/// A2'den başlar. Üst üste üç doğru bir üst seviyeye çıkarır, iki yanlış bir
/// alt seviyeye indirir. Sonuçta doğru oranı yüzde 60'ın üzerinde olan en
/// yüksek seviye atanır.
///
/// Soru havuzu, otomatik çeviri hatalarının yerleştirme sonucunu bozmaması için
/// elle doğrulanmış 30 kelimeden oluşur.
class PlacementTestScreen extends StatefulWidget {
  const PlacementTestScreen({super.key});

  @override
  State<PlacementTestScreen> createState() => _PlacementTestScreenState();
}

class _PlacementWord {
  const _PlacementWord(this.fr, this.tr, this.level);
  final String fr;
  final String tr;
  final CefrLevel level;
}

const List<_PlacementWord> _bank = <_PlacementWord>[
  _PlacementWord('le pain', 'ekmek', CefrLevel.a1),
  _PlacementWord('la maison', 'ev', CefrLevel.a1),
  _PlacementWord('boire', 'içmek', CefrLevel.a1),
  _PlacementWord('rouge', 'kırmızı', CefrLevel.a1),
  _PlacementWord('demain', 'yarın', CefrLevel.a1),
  _PlacementWord('la gare', 'tren istasyonu', CefrLevel.a2),
  _PlacementWord('oublier', 'unutmak', CefrLevel.a2),
  _PlacementWord('lourd', 'ağır', CefrLevel.a2),
  _PlacementWord('la santé', 'sağlık', CefrLevel.a2),
  _PlacementWord('la cuisine', 'mutfak', CefrLevel.a2),
  _PlacementWord('le témoin', 'tanık', CefrLevel.b1),
  _PlacementWord('aboutir', 'sonuçlanmak', CefrLevel.b1),
  _PlacementWord('méfiant', 'şüpheci', CefrLevel.b1),
  _PlacementWord('désormais', 'bundan böyle', CefrLevel.b1),
  _PlacementWord("l'échec", 'başarısızlık', CefrLevel.b1),
  _PlacementWord('entériner', 'onaylamak', CefrLevel.b2),
  _PlacementWord('sournois', 'sinsi', CefrLevel.b2),
  _PlacementWord('néanmoins', 'yine de', CefrLevel.b2),
  _PlacementWord("l'essor", 'atılım', CefrLevel.b2),
  _PlacementWord('le remous', 'çalkantı', CefrLevel.b2),
  _PlacementWord("l'accalmie", 'dinginlik', CefrLevel.c1),
  _PlacementWord('atermoyer', 'ertelemek', CefrLevel.c1),
  _PlacementWord('velléitaire', 'kararsız', CefrLevel.c1),
  _PlacementWord('nonobstant', 'buna rağmen', CefrLevel.c1),
  _PlacementWord('la mansuétude', 'hoşgörü', CefrLevel.c1),
  _PlacementWord('obvier', 'önlemek', CefrLevel.c2),
  _PlacementWord('pusillanime', 'korkak', CefrLevel.c2),
  _PlacementWord("l'incurie", 'aymazlık', CefrLevel.c2),
  _PlacementWord('séant', 'uygun', CefrLevel.c2),
  _PlacementWord("l'oripeau", 'gösterişli paçavra', CefrLevel.c2),
];

const int _questionCount = 20;

/// Yetersiz kanıtla üst seviye atanmasını önler. Bir seviyede tek doğru cevap
/// artık kullanıcıyı o seviyeye yerleştiremez.
CefrLevel resolvePlacementLevel(
  Map<CefrLevel, int> asked,
  Map<CefrLevel, int> correct, {
  int minimumEvidence = 3,
}) {
  CefrLevel best = CefrLevel.a1;
  for (final CefrLevel level in CefrLevel.values) {
    final int count = asked[level] ?? 0;
    if (count < minimumEvidence) continue;
    if ((correct[level] ?? 0) / count >= 0.6) best = level;
  }
  return best;
}

class _PlacementTestScreenState extends State<PlacementTestScreen> {
  final Random _rng = Random();
  final Map<CefrLevel, int> _asked = <CefrLevel, int>{};
  final Map<CefrLevel, int> _correct = <CefrLevel, int>{};
  final Set<String> _used = <String>{};

  CefrLevel _current = CefrLevel.a2;
  int _streakRight = 0;
  int _streakWrong = 0;
  int _index = 0;

  late _PlacementWord _question;
  late List<String> _options;
  String? _picked;
  Timer? _advanceTimer;

  @override
  void initState() {
    super.initState();
    _nextQuestion();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  void _nextQuestion() {
    final List<_PlacementWord> pool = _bank
        .where((w) => w.level == _current && !_used.contains(w.fr))
        .toList();
    final List<_PlacementWord> remaining =
        _bank.where((w) => !_used.contains(w.fr)).toList();
    final int nearestDistance = remaining.isEmpty
        ? 0
        : remaining
            .map((w) => (w.level.index - _current.index).abs())
            .reduce(min);
    final List<_PlacementWord> nearest = remaining
        .where(
          (w) => (w.level.index - _current.index).abs() == nearestDistance,
        )
        .toList();
    final List<_PlacementWord> from = pool.isNotEmpty ? pool : nearest;
    if (from.isEmpty) {
      _finish();
      return;
    }

    _question = from[_rng.nextInt(from.length)];
    _used.add(_question.fr);

    // Çeldiriciler aynı seviyeden gelir, yoksa havuzun tamamından.
    final List<String> distractors = _bank
        .where((w) => w.tr != _question.tr && w.level == _question.level)
        .map((w) => w.tr)
        .toList();
    if (distractors.length < 3) {
      distractors.addAll(
        _bank.where((w) => w.tr != _question.tr).map((w) => w.tr),
      );
    }
    distractors.shuffle(_rng);

    _options = <String>[_question.tr, ...distractors.take(3)]..shuffle(_rng);
    _picked = null;
  }

  void _answer(String option) {
    if (_picked != null) return;
    final bool right = option == _question.tr;

    setState(() {
      _picked = option;
      _asked[_question.level] = (_asked[_question.level] ?? 0) + 1;
      if (right) {
        _correct[_question.level] = (_correct[_question.level] ?? 0) + 1;
        _streakRight++;
        _streakWrong = 0;
      } else {
        _streakWrong++;
        _streakRight = 0;
      }

      if (_streakRight >= 3 && _current.next != null) {
        _current = _current.next!;
        _streakRight = 0;
      } else if (_streakWrong >= 2 && _current.previous != null) {
        _current = _current.previous!;
        _streakWrong = 0;
      }
    });

    _advanceTimer = Timer(MotionTokens.quizReveal, () {
      if (!mounted) return;
      _index++;
      if (_index >= _questionCount) {
        _finish();
      } else {
        setState(_nextQuestion);
      }
    });
  }

  /// Doğru oranı yüzde 60'ın üzerinde olan en yüksek seviye.
  void _finish() {
    if (!mounted) return;
    Navigator.of(context).pop<CefrLevel>(
      resolvePlacementLevel(_asked, _correct),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yerleştirme testi'),
        actions: <Widget>[
          TextButton(
            onPressed: _finish,
            child: const Text('Atla'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _index / _questionCount),
                duration: MotionTokens.progressFill,
                curve: MotionTokens.progress,
                builder: (BuildContext context, double v, Widget? _) =>
                    ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: v, minHeight: 6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Soru ${_index + 1} / $_questionCount',
                style: TextStyle(fontSize: 12, color: faint),
              ),
              const Spacer(),
              Text(
                _question.fr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Türkçe karşılığı hangisi?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: faint),
              ),
              const Spacer(),
              for (final String option in _options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OptionButton(
                    label: option,
                    state: _picked == null
                        ? _OptionState.idle
                        : option == _question.tr
                            ? _OptionState.correct
                            : (option == _picked
                                ? _OptionState.wrong
                                : _OptionState.idle),
                    onTap: () => _answer(option),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _OptionState { idle, correct, wrong }

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String label;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color base =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
    final Color color = switch (state) {
      _OptionState.idle => base,
      _OptionState.correct => const Color(0xFF2E9E5B).withValues(alpha: 0.25),
      _OptionState.wrong => const Color(0xFFC0392B).withValues(alpha: 0.25),
    };
    final Color border = switch (state) {
      _OptionState.idle => theme.colorScheme.onSurface.withValues(alpha: 0.12),
      _OptionState.correct => const Color(0xFF2E9E5B),
      _OptionState.wrong => const Color(0xFFC0392B),
    };

    return AnimatedContainer(
      duration: MotionTokens.selection,
      curve: MotionTokens.settle,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: border, width: state == _OptionState.idle ? 1 : 2),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
