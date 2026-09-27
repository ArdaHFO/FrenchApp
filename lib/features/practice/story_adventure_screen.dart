import '../../app/progress_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../domain/adventure.dart';
import '../../domain/level.dart';
import '../../motion/celebration.dart';
import '../../motion/motion_tokens.dart';
import '../../services/tts_service.dart';
import '../../ui/game_ui.dart';

class StoryAdventureScreen extends StatefulWidget {
  const StoryAdventureScreen({super.key, required this.story});

  final StoryAdventure story;

  @override
  State<StoryAdventureScreen> createState() => _StoryAdventureScreenState();
}

class _StoryAdventureScreenState extends State<StoryAdventureScreen> with ProgressSession<StoryAdventureScreen> {
  AppState? _app;
  late String _nodeId;
  StoryChoice? _choice;
  bool _translationVisible = false;
  bool _listeningMode = false;
  bool _quizMode = false;
  bool _resultMode = false;
  int _quizIndex = 0;
  int _correct = 0;
  int? _quizPick;
  bool _completionSaved = false;
  bool _savingCompletion = false;
  bool _savingNode = false;

  void _saveError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Sonuç kaydedilemedi. Tekrar deneyin.'),
    ));
  }

  StoryNode get _node => widget.story.node(_nodeId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_app != null) return;
    _app = AppScope.of(context);
    final StoryProgress? progress = _app!.practice.story(widget.story.id);
    final bool validResume = progress != null &&
        !progress.completed &&
        widget.story.nodes.any((StoryNode n) => n.id == progress.nodeId);
    _nodeId = validResume ? progress.nodeId : widget.story.startNodeId;
  }

  Future<void> _speak({required bool slow}) async {
    final TtsService tts = await TtsService.instance();
    await tts.speak(_node.text, rate: slow ? 0.32 : 0.48);
  }

  void _selectChoice(StoryChoice choice) {
    if (_choice != null) return;
    HapticFeedback.selectionClick();
    setState(() => _choice = choice);
  }

  Future<void> _continueChoice() async {
    if (_savingNode || !progressReady) return;
    final StoryChoice? choice = _choice;
    if (choice == null) return;
    setState(() => _savingNode = true);
    try {
      await _app!.saveStoryNode(widget.story.id, choice.nextNodeId);
    } catch (_) {
      _saveError();
      return;
    } finally {
      if (mounted) setState(() => _savingNode = false);
    }
    if (!progressReady) return;
    setState(() {
      _nodeId = choice.nextNodeId;
      _choice = null;
      _translationVisible = false;
      _listeningMode = false;
    });
  }

  void _startQuiz() {
    setState(() {
      _quizMode = true;
      _quizIndex = 0;
      _correct = 0;
      _quizPick = null;
    });
  }

  void _answerQuiz(int index) {
    if (_quizPick != null) return;
    final bool right = index == widget.story.quiz[_quizIndex].correctIndex;
    right ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    setState(() {
      _quizPick = index;
      if (right) _correct++;
    });
  }

  Future<void> _nextQuiz() async {
    if (!progressReady) return;
    if (_quizPick == null || _savingCompletion) return;
    if (_quizIndex + 1 < widget.story.quiz.length) {
      setState(() {
        _quizIndex++;
        _quizPick = null;
      });
      return;
    }
    if (!_completionSaved) {
      setState(() => _savingCompletion = true);
      try {
        await _app!.completeStory(
          storyId: widget.story.id,
          nodeId: _nodeId,
          correct: _correct,
          total: widget.story.quiz.length,
        );
        _completionSaved = true;
      } catch (_) {
        _saveError();
        return;
      } finally {
        if (mounted) setState(() => _savingCompletion = false);
      }
    }
    if (!progressReady) return;
    setState(() => _resultMode = true);
  }

  @override
  Widget build(BuildContext context) {
    final Color levelColor = AppTheme.levelColor(widget.story.level.index);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Bölüm ${widget.story.chapter} · ${widget.story.title}'),
        actions: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                widget.story.level.code,
                style:
                    TextStyle(color: levelColor, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
      body: GameBackdrop(
        accent: levelColor,
        child: SafeArea(
          child: _resultMode
              ? _result(levelColor)
              : _quizMode
                  ? _quiz(levelColor)
                  : _story(levelColor),
        ),
      ),
    );
  }

  Widget _story(Color color) {
    final ThemeData theme = Theme.of(context);
    final int nodeIndex = widget.story.nodes.indexOf(_node);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: JuicyProgressBar(
            value: (nodeIndex + 1) / widget.story.nodes.length,
            color: color,
            height: 9,
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: MotionTokens.pageTransition,
            transitionBuilder: (Widget child, Animation<double> animation) =>
                FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: ListView(
              key: ValueKey<String>(_node.id),
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.16),
                      child: Icon(Icons.person_rounded, color: color),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _node.speaker,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    IconButton.filledTonal(
                      tooltip: 'Normal hızda dinle',
                      onPressed: () => _speak(slow: false),
                      icon: const Icon(Icons.volume_up_rounded),
                    ),
                    IconButton(
                      tooltip: 'Yavaş dinle',
                      onPressed: () => _speak(slow: true),
                      icon: const Icon(Icons.slow_motion_video_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GamePanel(
                  color: color.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.16 : 0.08,
                  ),
                  borderColor: color.withValues(alpha: 0.18),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AnimatedCrossFade(
                        duration: MotionTokens.cardSettle,
                        crossFadeState: _listeningMode
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: Text(
                          _node.text,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        secondChild: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              children: <Widget>[
                                Icon(Icons.hearing_rounded,
                                    size: 40, color: color),
                                const SizedBox(height: 8),
                                const Text(
                                    'Metin gizli · önce dinleyip anlamaya çalış'),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          FilterChip(
                            label: const Text('Dinleme modu'),
                            avatar: const Icon(Icons.hearing_rounded, size: 18),
                            selected: _listeningMode,
                            onSelected: (bool value) =>
                                setState(() => _listeningMode = value),
                          ),
                          ActionChip(
                            label: Text(_translationVisible
                                ? 'Çeviriyi gizle'
                                : 'Türkçeyi göster'),
                            onPressed: () => setState(() =>
                                _translationVisible = !_translationVisible),
                          ),
                        ],
                      ),
                      AnimatedSize(
                        duration: MotionTokens.cardSettle,
                        child: _translationVisible
                            ? Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(
                                  _node.translation,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.68),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                if (_node.glossary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  Text('BİLMEDİĞİN KELİMEYE DOKUN',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      )),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final StoryGlossary item in _node.glossary)
                        ActionChip(
                          avatar: const Icon(Icons.touch_app_rounded, size: 17),
                          label: Text(item.word),
                          onPressed: () => _showGlossary(item, color),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                if (_choice != null)
                  _coachCard(_choice!, color)
                else if (_node.isEnding)
                  FilledButton.icon(
                    onPressed: _startQuiz,
                    icon: const Icon(Icons.quiz_rounded),
                    label: const Text('Bölüm sınavına geç'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: color,
                    ),
                  )
                else ...<Widget>[
                  Text('Ne söylersin?',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  for (final StoryChoice choice in _node.choices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: PressableScale(
                        child: Material(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            onTap: () => _selectChoice(choice),
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.chat_bubble_rounded,
                                      size: 17,
                                      color: color,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(choice.label)),
                                  Icon(Icons.chevron_right_rounded,
                                      color: color),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _coachCard(StoryChoice choice, Color color) => GamePanel(
        color: (choice.preferred ? GameColors.mint : Colors.orange)
            .withValues(alpha: 0.11),
        borderColor: (choice.preferred ? GameColors.mint : Colors.orange)
            .withValues(alpha: 0.24),
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  choice.preferred
                      ? Icons.check_circle_rounded
                      : Icons.tips_and_updates_rounded,
                  color: choice.preferred ? GameColors.mint : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  choice.preferred ? 'Doğal seçim' : 'Koç notu',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(choice.coach),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _savingNode ? null : _continueChoice,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Hikâyeye devam et'),
              style: FilledButton.styleFrom(backgroundColor: color),
            ),
          ],
        ),
      );

  void _showGlossary(StoryGlossary item, Color color) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(item.word,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    )),
            const SizedBox(height: 8),
            Text(item.meaning, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () async {
                final TtsService tts = await TtsService.instance();
                await tts.speak(item.word);
              },
              icon: const Icon(Icons.volume_up_rounded),
              label: const Text('Dinle'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quiz(Color color) {
    final StoryQuizQuestion question = widget.story.quiz[_quizIndex];
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          JuicyProgressBar(
            value: (_quizIndex + 1) / widget.story.quiz.length,
            color: color,
            height: 9,
          ),
          const SizedBox(height: 28),
          Text('BÖLÜM SINAVI',
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              )),
          const SizedBox(height: 10),
          Text(question.prompt,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 22),
          for (int i = 0; i < question.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _QuizOption(
                label: question.options[i],
                picked: _quizPick == i,
                reveal: _quizPick != null,
                correct: i == question.correctIndex,
                onTap: () => _answerQuiz(i),
              ),
            ),
          if (_quizPick != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(question.explanation),
            const Spacer(),
            FilledButton(
              onPressed: _savingCompletion ? null : _nextQuiz,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: color,
              ),
              child: _savingCompletion
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_quizIndex + 1 == widget.story.quiz.length
                      ? 'Sonucu gör'
                      : 'Sonraki soru'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _result(Color color) {
    final bool perfect = _correct == widget.story.quiz.length;
    return Celebration(
      play: !MotionTokens.reducedMotion,
      colors: <Color>[color, Colors.amber, Colors.white],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.4, end: 1),
                duration: MotionTokens.rewardPop,
                curve: MotionTokens.badge,
                builder: (BuildContext context, double value, Widget? child) =>
                    Transform.scale(
                  scale: value,
                  child: Transform.rotate(
                    angle: (1 - value) * -0.18,
                    child: child,
                  ),
                ),
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
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Icon(
                    perfect ? Icons.emoji_events_rounded : Icons.flag_rounded,
                    size: 62,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                perfect ? 'Mükemmel macera!' : 'Bölüm tamamlandı!',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '$_correct / ${widget.story.quiz.length} doğru · İlk tamamlamada +40 XP ve +8 coin',
                textAlign: TextAlign.center,
              ),
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
}

class _QuizOption extends StatelessWidget {
  const _QuizOption({
    required this.label,
    required this.picked,
    required this.reveal,
    required this.correct,
    required this.onTap,
  });

  final String label;
  final bool picked;
  final bool reveal;
  final bool correct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color? color;
    if (reveal && correct) color = Colors.green;
    if (reveal && picked && !correct) color = Colors.red;
    return PressableScale(
      child: OutlinedButton(
        onPressed: reveal ? null : onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.centerLeft,
          backgroundColor: color?.withValues(alpha: 0.08),
          foregroundColor: color,
          side: color == null ? null : BorderSide(color: color, width: 2),
        ),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            if (color != null)
              Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: color),
          ],
        ),
      ),
    );
  }
}
