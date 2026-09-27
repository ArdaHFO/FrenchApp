import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../motion/card_stack.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/swipe_direction.dart';
import '../../domain/word.dart';
import '../vocab/word_card.dart';

/// Faz 0.5 hareket prototipi.
///
/// Veritabanı yok, içerik yok, mimari yok. Tek amaç hareketin doğru
/// hissettirilmesi ve gerçek telefonda kare düşmediğinin doğrulanması.
///
/// Bitiş ölçütü: on kart üst üste hızlıca kaydırıldığında tek kare düşmemesi.
/// Alttaki "stres testi" düğmesi bunu 120 ms aralıkla tetikler, yani her kart
/// bir öncekinin uçma animasyonu bitmeden gelir.
class PrototypeScreen extends StatefulWidget {
  const PrototypeScreen({super.key});

  @override
  State<PrototypeScreen> createState() => _PrototypeScreenState();
}

class _PrototypeScreenState extends State<PrototypeScreen> {
  final CardStackController _stack = CardStackController();

  List<Word> _deck = const <Word>[];
  bool _deckLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_deckLoaded) return;
    _deckLoaded = true;
    final List<Word> sample = AppScope.of(context)
        .words
        .all()
        .where((Word w) => !w.isFunctionWord && w.hasExample)
        .take(24)
        .toList();
    setState(() {
      _deck = <Word>[for (int i = 0; i < 3; i++) ...sample];
    });
  }

  final Map<SwipeDirection, int> _counts = <SwipeDirection, int>{
    SwipeDirection.right: 0,
    SwipeDirection.left: 0,
    SwipeDirection.up: 0,
    SwipeDirection.down: 0,
  };

  int _swiped = 0;

  static const List<double> _speeds = <double>[0.75, 1.0, 1.25];
  int _speedIndex = 1;

  bool get _isDone => _swiped >= _deck.length;

  void _onSwiped(int index, SwipeDirection direction) {
    setState(() {
      _swiped++;
      _counts[direction] = (_counts[direction] ?? 0) + 1;
    });
  }

  void _cycleSpeed() {
    setState(() {
      _speedIndex = (_speedIndex + 1) % _speeds.length;
      MotionTokens.speedScale = _speeds[_speedIndex];
    });
  }

  void _restart() {
    setState(() {
      _swiped = 0;
      for (final SwipeDirection d in _counts.keys) {
        _counts[d] = 0;
      }
    });
    _stack.reset();
  }

  Future<void> _stressTest() async {
    for (int i = 0; i < 10; i++) {
      if (!mounted) return;
      _stack.swipe(i.isEven ? SwipeDirection.right : SwipeDirection.left);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(
              speedLabel: '${_speeds[_speedIndex]}x',
              onSpeedTap: _cycleSpeed,
            ),
            _ProgressBar(value: _deck.isEmpty ? 0 : _swiped / _deck.length),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text(
                '$_swiped / ${_deck.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: _isDone
                    ? _DonePanel(counts: _counts, onRestart: _restart)
                    : CardStack(
                        controller: _stack,
                        itemCount: _deck.length,
                        onSwiped: _onSwiped,
                        itemBuilder: (BuildContext context, int index) =>
                            WordCard(word: _deck[index]),
                      ),
              ),
            ),
            if (!_isDone) _ActionBar(controller: _stack, onStress: _stressTest),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.speedLabel, required this.onSpeedTap});

  final String speedLabel;
  final VoidCallback onSpeedTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 8),
      child: Row(
        children: <Widget>[
          // Dar ekranda başlık ile hız düğmesi yan yana sığmıyordu.
          Expanded(
            child: Text(
              'Hareket prototipi',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onSpeedTap,
            icon: const Icon(Icons.speed_rounded, size: 18),
            label: Text(speedLabel),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: MotionTokens.progressFill,
        curve: MotionTokens.progress,
        builder: (BuildContext context, double v, Widget? _) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: v, minHeight: 6),
          );
        },
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller, required this.onStress});

  final CardStackController controller;
  final VoidCallback onStress;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _DirButton(
              direction: SwipeDirection.left,
              icon: Icons.close_rounded,
              controller: controller,
            ),
            _DirButton(
              direction: SwipeDirection.down,
              icon: Icons.keyboard_double_arrow_down_rounded,
              controller: controller,
            ),
            _DirButton(
              direction: SwipeDirection.up,
              icon: Icons.star_rounded,
              controller: controller,
            ),
            _DirButton(
              direction: SwipeDirection.right,
              icon: Icons.check_rounded,
              controller: controller,
            ),
          ],
        ),
        TextButton(
          onPressed: onStress,
          child: const Text('Stres testi: 10 kart, 120 ms arayla'),
        ),
      ],
    );
  }
}

class _DirButton extends StatelessWidget {
  const _DirButton({
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

class _DonePanel extends StatelessWidget {
  const _DonePanel({required this.counts, required this.onRestart});

  final Map<SwipeDirection, int> counts;
  final VoidCallback onRestart;

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
          const SizedBox(height: 24),
          Wrap(
            spacing: 20,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final SwipeDirection d in SwipeDirection.values)
                _CountTile(direction: d, value: counts[d] ?? 0),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(onPressed: onRestart, child: const Text('Baştan başla')),
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
          builder: (BuildContext context, double v, Widget? _) {
            return Text(
              '${v.round()}',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: direction.color,
              ),
            );
          },
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
