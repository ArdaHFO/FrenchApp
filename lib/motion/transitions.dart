import 'dart:async';

import 'package:flutter/material.dart';

import 'motion_tokens.dart';

/// Liste öğelerinin sırayla belirmesi.
///
/// Her öğe kendinden önceki kadar gecikmeyle girer. Alt ağaç `child`
/// parametresinden geçtiği için animasyon sırasında yeniden kurulmaz.
class StaggeredEntry extends StatefulWidget {
  const StaggeredEntry({
    super.key,
    required this.index,
    required this.child,
    this.perItemDelay = const Duration(milliseconds: 40),
    this.slideFrom = 16.0,
  });

  final int index;
  final Widget child;
  final Duration perItemDelay;
  final double slideFrom;

  @override
  State<StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<StaggeredEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionTokens.cardSettle,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final Duration delay = widget.perItemDelay * widget.index;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = MotionTokens.settle.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.slideFrom * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Sayfa geçişi: kayma + solma. PLAN.md bölüm 6.6'daki tabloya uyar.
Route<T> fadeSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: MotionTokens.pageTransition,
    reverseTransitionDuration: MotionTokens.pageTransition,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondary,
      Widget child,
    ) {
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
        reverseCurve: Curves.easeInOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
