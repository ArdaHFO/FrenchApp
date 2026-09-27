import '../../app/progress_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../domain/level.dart';
import '../../domain/sentence_practice.dart';
import '../../motion/celebration.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/transitions.dart';
import '../../ui/game_ui.dart';
import 'free_writing_screen.dart';

class SentencePracticeScreen extends StatefulWidget {
  const SentencePracticeScreen({super.key, required this.level});

  final CefrLevel level;

  @override
  State<SentencePracticeScreen> createState() => _SentencePracticeScreenState();
}

class _SentencePracticeScreenState extends State<SentencePracticeScreen> with ProgressSession<SentencePracticeScreen> {
  final TextEditingController _controller = TextEditingController();
  late final List<SentencePrompt> _prompts = promptsForLevel(widget.level);
  AppState? _app;
  int _index = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _correct = 0;
  SentenceEvaluation? _evaluation;
  bool _saving = false;
  bool _saveFailed = false;
  ({String promptId, SentenceEvaluation evaluation, int correct, int combo, int bestCombo})? _pending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= AppScope.of(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (!progressReady) return;
    if (_saving || _evaluation != null) return;
    final SentencePrompt prompt = _prompts[_index];
    final SentenceEvaluation evaluation =
        SentenceEvaluator.evaluate(_controller.text, prompt);
    final combo = evaluation.correct ? _combo + 1 : 0;
    _pending = (promptId: prompt.id, evaluation: evaluation,
        correct: _correct + (evaluation.correct ? 1 : 0), combo: combo,
        bestCombo: combo > _bestCombo ? combo : _bestCombo);
    setState(() => _evaluation = evaluation);
    evaluation.correct
        ? HapticFeedback.lightImpact()
        : HapticFeedback.heavyImpact();
    await _saveEvaluation();
  }

  Future<void> _saveEvaluation() async {
    final pending = _pending;
    if (_saving || pending == null || !progressReady) return;
    setState(() { _saving = true; _saveFailed = false; });
    try {
      await _app!.recordSentenceAttempt(promptId: pending.promptId,
          correct: pending.evaluation.correct, score: pending.evaluation.score,
          combo: pending.bestCombo);
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
      _pending = null;
    });
  }

  void _retry() {
    if (!progressReady || _pending != null) return;
    setState(() => _evaluation = null);
  }

  void _next() {
    if (!progressReady || _pending != null) return;
    if (_index + 1 >= _prompts.length) {
      setState(() => _index = _prompts.length);
      return;
    }
    setState(() {
      _index++;
      _evaluation = null;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color color = AppTheme.levelColor(widget.level.index);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Cümle Atölyesi'),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('open_free_writing'),
            tooltip: 'Serbest yazı koçu',
            onPressed: () => Navigator.of(context).push(
              fadeSlideRoute<void>(const FreeWritingScreen()),
            ),
            icon: const Icon(Icons.rate_review_rounded),
          ),
          if (_index < _prompts.length)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${_index + 1} / ${_prompts.length}'),
              ),
            ),
        ],
      ),
      body: GameBackdrop(
        accent: color,
        child: SafeArea(
          child: _index >= _prompts.length ? _result(color) : _exercise(color),
        ),
      ),
    );
  }

  Widget _exercise(Color color) {
    final SentencePrompt prompt = _prompts[_index];
    final SentenceEvaluation? evaluation = _evaluation;
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        JuicyProgressBar(
          value: (_index + 1) / _prompts.length,
          color: color,
          height: 9,
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: <Widget>[
            GamePill(
              icon: Icons.translate_rounded,
              label: widget.level.code,
              color: color,
            ),
            AnimatedSwitcher(
              duration: MotionTokens.rewardPop,
              transitionBuilder: (Widget child, Animation<double> animation) =>
                  ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: MotionTokens.badge,
                ),
                child: RotationTransition(
                  turns: Tween<double>(begin: -0.04, end: 0).animate(animation),
                  child: child,
                ),
              ),
              child: GamePill(
                key: ValueKey<int>(_combo),
                icon: Icons.local_fire_department_rounded,
                label: 'Combo $_combo',
                color: _combo >= 2 ? GameColors.coral : Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GamePanel(
          color: color.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.17 : 0.08,
          ),
          borderColor: color.withValues(alpha: 0.18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[color, GameColors.violet],
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.flag_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(child: Text(
                    'GÜNÜN GÖREVİ',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.9,
                    ),
                  )),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                prompt.situationTr,
                style: theme.textTheme.headlineSmall?.copyWith(height: 1.25),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GamePanel(
          shadow: false,
          color: GameColors.gold.withValues(alpha: 0.09),
          borderColor: GameColors.gold.withValues(alpha: 0.20),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Icon(Icons.lightbulb_rounded, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(prompt.hintTr)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey<String>('sentence_input'),
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          enabled: evaluation == null,
          textCapitalization: TextCapitalization.sentences,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Fransızca cümlen',
            hintText: 'Écris ta phrase ici…',
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            suffixIcon: evaluation == null
                ? IconButton(
                    tooltip: 'Temizle',
                    onPressed: _controller.clear,
                    icon: const Icon(Icons.clear_rounded),
                  )
                : null,
          ),
          onSubmitted: (_) => _check(),
        ),
        const SizedBox(height: 14),
        if (evaluation == null)
          PressableScale(
            child: FilledButton.icon(
              key: const ValueKey<String>('check_sentence'),
              onPressed: _saving ? null : _check,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Cümleyi değerlendir'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: color,
                foregroundColor: Colors.white,
                shadowColor: color.withValues(alpha: 0.35),
              ),
            ),
          )
        else
          _feedback(prompt, evaluation, color),
      ],
    );
  }

  Widget _feedback(
    SentencePrompt prompt,
    SentenceEvaluation evaluation,
    Color color,
  ) {
    final Color status = evaluation.correct ? Colors.green : Colors.orange;
    return Shake(
      trigger: evaluation.correct ? null : '${prompt.id}_${evaluation.score}',
      child: AnimatedScale(
        scale: 1,
        duration: MotionTokens.rewardPop,
        curve: MotionTokens.badge,
        child: GamePanel(
          color: status.withValues(alpha: 0.10),
          borderColor: status.withValues(alpha: 0.24),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        CircularProgressIndicator(
                          value: evaluation.score / 100,
                          color: status,
                          backgroundColor: status.withValues(alpha: 0.15),
                        ),
                        Text('${evaluation.score}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      evaluation.correct
                          ? 'Doğru ve doğal bir cümle!'
                          : 'Yaklaştın · şu noktaları düzelt',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              if (!evaluation.correct) ...<Widget>[
                const SizedBox(height: 14),
                for (final SentenceIssue issue in evaluation.issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(issue.type.label),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Text(issue.message),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const Divider(height: 24),
              const Text('Model cevap',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              SelectableText(prompt.modelAnswer),
              const SizedBox(height: 16),
              if (_saving) const LinearProgressIndicator(),
              if (_saveFailed) ...<Widget>[
                const Text('Sonuç kaydedilemedi. Tekrar deneyin.'),
                FilledButton(key: const ValueKey('sentence_save_retry'),
                    onPressed: _saveEvaluation, child: const Text('Kaydetmeyi tekrar dene')),
              ],
              if (!evaluation.correct)
                FilledButton.tonalIcon(
                  onPressed: _saving || _pending != null ? null : _retry,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Düzelt ve yeniden dene'),
                ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _saving || _pending != null ? null : _next,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(_index + 1 == _prompts.length
                    ? 'Sonucu gör'
                    : 'Sonraki senaryo'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _result(Color color) => Celebration(
        play: !MotionTokens.reducedMotion,
        colors: <Color>[color, Colors.amber, Colors.white],
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.35, end: 1),
                  duration: MotionTokens.rewardPop,
                  curve: MotionTokens.badge,
                  builder:
                      (BuildContext context, double value, Widget? child) =>
                          Transform.scale(scale: value, child: child),
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[color, GameColors.violet],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: color.withValues(alpha: 0.34),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Atölye tamamlandı!',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Text(
                    '$_correct/${_prompts.length} doğru · En iyi combo $_bestCombo'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Macera merkezine dön'),
                  style: FilledButton.styleFrom(backgroundColor: color),
                ),
              ],
            ),
          ),
        ),
      );
}
