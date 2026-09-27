import '../../app/progress_session.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../data/repositories.dart';
import '../../domain/srs/session_builder.dart';
import '../../domain/srs/srs_card.dart';
import '../../domain/word.dart';
import '../../motion/card_stack.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/swipe_direction.dart';
import '../../services/tts_service.dart';
import 'word_card.dart';

/// Kelime kaydırma oturumu. PLAN.md bölüm 4 ve 7.
class SwipeSessionScreen extends StatefulWidget {
  const SwipeSessionScreen({
    super.key,
    required this.title,
    required this.candidateIds,
    this.includeNotDue = false,
  });

  final String title;
  final List<String> candidateIds;
  final bool includeNotDue;

  @override
  State<SwipeSessionScreen> createState() => _SwipeSessionScreenState();
}

class _SwipeSessionScreenState extends State<SwipeSessionScreen> with ProgressSession<SwipeSessionScreen> {
  final CardStackController _stack = CardStackController();

  late AppState _app;
  List<String> _deck = <String>[];
  int _completed = 0;
  bool _built = false;

  final Map<SwipeAction, int> _counts = <SwipeAction, int>{
    SwipeAction.know: 0,
    SwipeAction.dontKnow: 0,
    SwipeAction.hard: 0,
    SwipeAction.skip: 0,
  };
  int _newlyLearned = 0;
  int _startXp = 0;
  int _startCoins = 0;
  TtsService? _tts;
  bool _ttsRequested = false;
  final Set<String> _flagPending = {};

  Future<void> _toggleFlag(Word word) async {
    if (!progressReady || !_flagPending.add(word.id)) return;
    try {
      await _app.toggleFlag(refId: word.id, cardType: 'word', lemma: word.lemma);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sonuç kaydedilemedi. Tekrar deneyin.'),
        ));
      }
    } finally {
      _flagPending.remove(word.id);
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    _built = true;
    _app = AppScope.of(context);
    _startXp = _app.game.profile.xp;
    _startCoins = _app.game.profile.coins;
    _deck = SessionBuilder.build(
      candidateRefIds: _app.words.learningIds(widget.candidateIds),
      states: _app.cards.snapshot(),
      now: DateTime.now(),
      size: _app.dailyGoal,
      includeNotDue: widget.includeNotDue,
    );
    if (!_ttsRequested) {
      _ttsRequested = true;
      TtsService.instance().then((TtsService s) {
        if (mounted) setState(() => _tts = s);
      });
    }
  }

  SwipeAction _toAction(SwipeDirection direction) => switch (direction) {
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
    late final AnswerResult result;
    try {
      result = await _app.recordAnswer(
          cardType: AnswerCardType.word,
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
      _counts[action] = (_counts[action] ?? 0) + 1;
      if (result.newLearned) _newlyLearned++;

      // Sola kaydırılan kart aynı oturumda tekrar gelir.
      // Mevcut konumun ilerisine eklendiği için deste bozulmaz.
      if (action == SwipeAction.dontKnow) {
        final int target = math.min(
          index + SessionBuilder.reinsertAfter,
          _deck.length,
        );
        _deck.insert(target, refId);
      }
    });
    return true;
  }

  bool get _isDone => _deck.isEmpty || _completed >= _deck.length;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double progress =
        _deck.isEmpty ? 0 : (_completed / _deck.length).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
                builder: (BuildContext context, double v, Widget? _) =>
                    ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: v, minHeight: 6),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: _deck.isEmpty
                    ? const Center(
                        child: Text(
                          'Bu oturum için çalışılabilir kart yok.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : _isDone
                    ? _SessionSummary(
                        counts: _counts,
                        newlyLearned: _newlyLearned,
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
                        itemBuilder: (BuildContext context, int index) {
                          final Word? word = _app.words.byId(_deck[index]);
                          if (word == null) {
                            return const SizedBox.shrink();
                          }
                          return WordCard(
                            word: word,
                            mastery: _app.cards.stateFor(word.id).box,
                            relatives: _app.words.relativesOf(word.id),
                            showSentenceOnFront: _app.showSentenceOnFront,
                            onSpeak: (String text) => _tts?.speak(text),
                            isFlagged: _app.flags.isFlagged(word.id),
                            onFlag: () => _toggleFlag(word),
                          );
                        },
                      ),
              ),
            ),
            if (!_isDone) _SwipeActionBar(controller: _stack),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _SwipeActionBar extends StatelessWidget {
  const _SwipeActionBar({required this.controller});

  final CardStackController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _ActionButton(
          direction: SwipeDirection.left,
          icon: Icons.close_rounded,
          controller: controller,
        ),
        _ActionButton(
          direction: SwipeDirection.down,
          icon: Icons.keyboard_double_arrow_down_rounded,
          controller: controller,
        ),
        _ActionButton(
          direction: SwipeDirection.up,
          icon: Icons.star_rounded,
          controller: controller,
        ),
        _ActionButton(
          direction: SwipeDirection.right,
          icon: Icons.check_rounded,
          controller: controller,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.direction,
    required this.icon,
    required this.controller,
  });

  final SwipeDirection direction;
  final IconData icon;
  final CardStackController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: IconButton.filledTonal(
        onPressed: () => controller.swipe(direction),
        icon: Icon(icon, color: direction.color),
        tooltip: direction.label,
      ),
    );
  }
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({
    required this.counts,
    required this.newlyLearned,
    required this.earnedXp,
    required this.earnedCoins,
    required this.onClose,
  });

  final Map<SwipeAction, int> counts;
  final int newlyLearned;
  final int earnedXp;
  final int earnedCoins;
  final VoidCallback onClose;

  static const Map<SwipeAction, SwipeDirection> _mirror =
      <SwipeAction, SwipeDirection>{
    SwipeAction.know: SwipeDirection.right,
    SwipeAction.dontKnow: SwipeDirection.left,
    SwipeAction.hard: SwipeDirection.up,
    SwipeAction.skip: SwipeDirection.down,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
          const SizedBox(height: 8),
          Text(
            newlyLearned > 0
                ? '$newlyLearned yeni kelime öğrenmeye başladın'
                : 'Tekrar tamamlandı',
            style: TextStyle(
              fontSize: 14,
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
          const SizedBox(height: 28),
          Wrap(
            spacing: 22,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final MapEntry<SwipeAction, SwipeDirection> e
                  in _mirror.entries)
                _CountTile(
                  direction: e.value,
                  value: counts[e.key] ?? 0,
                ),
            ],
          ),
          const SizedBox(height: 34),
          FilledButton(onPressed: onClose, child: const Text('Bitir')),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.direction, required this.value});

  final SwipeDirection direction;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: value.toDouble()),
          duration: MotionTokens.counterRise,
          curve: MotionTokens.counter,
          builder: (BuildContext context, double v, Widget? _) => Text(
            '${v.round()}',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: direction.color,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          direction.label,
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.6,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
