import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion_tokens.dart';

/// Perspektifli üç boyutlu kart çevirme.
///
/// Düz bir ölçek animasyonu değil, gerçek perspektif matrisi kullanır.
/// Dönme 90 dereceyi geçtiğinde içerik ön yüzden arka yüze değişir ve arka yüz
/// ters çevrilerek yazının aynalanması engellenir.
///
/// Animasyon yarıda kesilebilir: çevirme sürerken tekrar dokunmak mevcut
/// konumdan geri döndürür, baştan başlamaz.
class FlipCard extends StatefulWidget {
  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    this.onFlipped,
  });

  final Widget front;
  final Widget back;

  /// Arka yüz açıldığında true, ön yüze dönüldüğünde false ile çağrılır.
  final ValueChanged<bool>? onFlipped;

  @override
  State<FlipCard> createState() => FlipCardState();
}

class FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get isShowingBack => _controller.value > 0.5;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: MotionTokens.cardFlip,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void toggle() {
    final bool goingToBack = _controller.value <= 0.5;
    if (goingToBack) {
      _controller.animateTo(
        1.0,
        duration: MotionTokens.cardFlip,
        curve: MotionTokens.flip,
      );
    } else {
      _controller.animateBack(
        0.0,
        duration: MotionTokens.cardFlip,
        curve: MotionTokens.flip,
      );
    }
    widget.onFlipped?.call(goingToBack);
  }

  void reset() => _controller.value = 0.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: toggle,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) {
          final double t = _controller.value;
          final double angle = t * math.pi;

          // Ortada kart hafifçe büyür, öne gelip geri gidiyormuş hissi verir.
          final double scale =
              1.0 + math.sin(t * math.pi) * MotionTokens.flipScaleBoost;

          final bool showBack = t > 0.5;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, MotionTokens.perspective)
              ..rotateY(angle)
              ..scaleByDouble(scale, scale, scale, 1.0),
            child: showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: widget.back,
                  )
                : widget.front,
          );
        },
      ),
    );
  }
}
