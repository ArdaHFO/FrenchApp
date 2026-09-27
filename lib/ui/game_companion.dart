import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/companion.dart';
import '../motion/motion_tokens.dart';
import 'game_ui.dart';

/// Macera ekranlarındaki kodla çizilen yol arkadaşı.
///
/// Bitmap kullanmaz; renkleri seçili dünyaya uyar. Nefes alma, göz kırpma,
/// el sallama ve parıltı tek bir düşük maliyetli CustomPainter içindedir.
class GameCompanion extends StatefulWidget {
  const GameCompanion({
    super.key,
    required this.color,
    this.message = 'Salut!',
    this.size = 142,
    this.kind = CompanionKind.lumi,
    this.accessory = CompanionAccessory.beret,
    this.animate = true,
    this.showMessage = true,
    this.evolutionStage = 0,
    this.growthTitle,
  });

  final Color color;
  final String message;
  final double size;
  final CompanionKind kind;
  final CompanionAccessory accessory;
  final bool animate;
  final bool showMessage;
  final int evolutionStage;
  final String? growthTitle;

  @override
  State<GameCompanion> createState() => _GameCompanionState();
}

class _GameCompanionState extends State<GameCompanion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionTokens.ambientLoop,
  );

  @override
  void initState() {
    super.initState();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant GameCompanion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (MotionTokens.reducedMotion || !widget.animate) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.kind.label}, '
          '${widget.growthTitle ?? "Fransızca yol arkadaşın"}. '
          '${widget.message}',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final double t = MotionTokens.reducedMotion ? 0 : _controller.value;
            final double bob = math.sin(t * math.pi * 2) * 3;
            return Transform.translate(
              offset: Offset(0, bob),
              child: Transform.rotate(
                angle: math.sin(t * math.pi * 2) * 0.018,
                child: child,
              ),
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (BuildContext context, Widget? child) =>
                        CustomPaint(
                      painter: _CompanionPainter(
                        color: widget.color,
                        t: MotionTokens.reducedMotion ? 0 : _controller.value,
                        kind: widget.kind,
                        accessory: widget.accessory,
                        evolutionStage: widget.evolutionStage,
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.showMessage)
                Positioned(
                  right: -2,
                  top: 2,
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey<String>(widget.message),
                    tween: Tween<double>(begin: 0.72, end: 1),
                    duration: MotionTokens.rewardPop,
                    curve: MotionTokens.badge,
                    builder:
                        (BuildContext context, double scale, Widget? child) =>
                            Transform.scale(scale: scale, child: child),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 78),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: widget.color.withValues(alpha: 0.22),
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color:
                                const Color(0xFF17224B).withValues(alpha: 0.16),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.message,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color.lerp(widget.color, Colors.black, 0.28),
                          fontSize: 10,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
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

class _CompanionPainter extends CustomPainter {
  const _CompanionPainter({
    required this.color,
    required this.t,
    required this.kind,
    required this.accessory,
    required this.evolutionStage,
  });

  final Color color;
  final double t;
  final CompanionKind kind;
  final CompanionAccessory accessory;
  final int evolutionStage;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 142;
    canvas.save();
    canvas.scale(scale, scale);

    final double phase = t * math.pi * 2;
    final Paint paint = Paint()..isAntiAlias = true;

    _drawGrowthAura(canvas, paint, phase);

    // Yumuşak zemin gölgesi.
    paint.color = const Color(0xFF111936).withValues(alpha: 0.18);
    canvas.drawOval(const Rect.fromLTWH(29, 126, 80, 12), paint);

    _drawTail(canvas, paint, phase);

    // Ayaklar.
    paint.color = kind == CompanionKind.pipou
        ? Color.lerp(color, Colors.black, 0.18)!
        : const Color(0xFF293255);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(49, 116, 19, 15),
        const Radius.circular(8),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(72, 116, 19, 15),
        const Radius.circular(8),
      ),
      paint,
    );

    // Gövde ve karın.
    paint.color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(43, 72, 54, 52),
        const Radius.circular(23),
      ),
      paint,
    );
    paint.color = Colors.white.withValues(alpha: 0.82);
    canvas.drawOval(const Rect.fromLTWH(57, 87, 27, 29), paint);

    _drawArms(canvas, paint, phase);
    _drawHead(canvas, paint, phase);

    // Altın atkı karakterlerin ortak takım işareti.
    paint.color = GameColors.gold;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(43, 75, 57, 9),
        const Radius.circular(5),
      ),
      paint,
    );
    final Path scarf = Path()
      ..moveTo(83, 81)
      ..lineTo(100, 103)
      ..lineTo(87, 106)
      ..lineTo(75, 82)
      ..close();
    canvas.drawPath(scarf, paint);
    _drawAccessory(canvas, paint);

    if (evolutionStage >= 2) {
      paint.color = Colors.white.withValues(alpha: 0.92);
      canvas.drawCircle(const Offset(70, 79), 4.2, paint);
      paint.color = GameColors.gold;
      _star(canvas, const Offset(70, 79), 2.6, paint);
    }

    // Döngü boyunca yer değiştiren iki küçük parıltı.
    paint.color = Colors.white.withValues(alpha: 0.72);
    final double sparkle = math.sin(phase) * 2;
    _star(canvas, Offset(29, 55 + sparkle), 4, paint);
    paint.color = GameColors.gold.withValues(alpha: 0.90);
    _star(canvas, Offset(113, 70 - sparkle), 3.5, paint);
    if (evolutionStage >= 3) {
      paint.color = GameColors.sky.withValues(alpha: 0.88);
      _star(canvas, Offset(22, 92 - sparkle), 3.2, paint);
      paint.color = GameColors.gold.withValues(alpha: 0.92);
      _star(canvas, Offset(119, 39 + sparkle), 4.2, paint);
    }

    canvas.restore();
  }

  void _drawGrowthAura(Canvas canvas, Paint paint, double phase) {
    if (evolutionStage <= 0) return;
    final double pulse = 1 + math.sin(phase) * 0.035;
    canvas.save();
    canvas.translate(71, 72);
    canvas.scale(pulse, pulse);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = evolutionStage >= 3 ? 3 : 2
      ..color = (evolutionStage >= 2 ? GameColors.gold : color).withValues(
        alpha: evolutionStage >= 3 ? 0.42 : 0.26,
      );
    canvas.drawOval(const Rect.fromLTWH(-48, -55, 96, 116), paint);
    if (evolutionStage >= 3) {
      paint
        ..strokeWidth = 1.4
        ..color = GameColors.sky.withValues(alpha: 0.30);
      canvas.drawOval(const Rect.fromLTWH(-55, -61, 110, 128), paint);
    }
    paint.style = PaintingStyle.fill;
    canvas.restore();
  }

  void _drawTail(Canvas canvas, Paint paint, double phase) {
    if (kind == CompanionKind.lumi) {
      canvas.save();
      canvas.translate(96, 102);
      canvas.rotate(0.22 + math.sin(phase) * 0.06);
      paint.color = Color.lerp(color, GameColors.coral, 0.38)!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-2, -12, 35, 21),
          const Radius.circular(14),
        ),
        paint,
      );
      paint.color = Colors.white.withValues(alpha: 0.82);
      canvas.drawCircle(const Offset(29, -2), 7, paint);
      canvas.restore();
    } else if (kind == CompanionKind.moka) {
      paint
        ..color = Color.lerp(color, Colors.black, 0.16)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round;
      final Path tail = Path()
        ..moveTo(94, 110)
        ..cubicTo(
          125,
          117,
          124 + math.sin(phase) * 3,
          82,
          108,
          81,
        );
      canvas.drawPath(tail, paint);
      paint.style = PaintingStyle.fill;
    }
  }

  void _drawArms(Canvas canvas, Paint paint, double phase) {
    if (kind == CompanionKind.nox) {
      paint.color = Color.lerp(color, Colors.black, 0.12)!;
      canvas.drawOval(const Rect.fromLTWH(32, 78, 25, 37), paint);
      canvas.save();
      canvas.translate(95, 84);
      canvas.rotate(-0.25 + math.sin(phase * 2) * 0.09);
      canvas.drawOval(const Rect.fromLTWH(0, -7, 24, 36), paint);
      canvas.restore();
      return;
    }

    paint
      ..color = color
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(48, 84), const Offset(33, 105), paint);
    canvas.save();
    canvas.translate(93, 85);
    canvas.rotate(-0.58 + math.sin(phase * 2) * 0.13);
    canvas.drawLine(Offset.zero, const Offset(18, -19), paint);
    paint
      ..style = PaintingStyle.fill
      ..color = kind == CompanionKind.pipou
          ? Color.lerp(color, Colors.white, 0.18)!
          : const Color(0xFFFFD4B5);
    canvas.drawCircle(const Offset(20, -22), 7, paint);
    canvas.restore();
  }

  void _drawHead(Canvas canvas, Paint paint, double phase) {
    final Color fur = Color.lerp(
      color,
      kind == CompanionKind.pipou ? Colors.white : GameColors.coral,
      kind == CompanionKind.pipou ? 0.08 : 0.30,
    )!;

    if (kind == CompanionKind.lumi || kind == CompanionKind.moka) {
      final double top = kind == CompanionKind.lumi ? 16 : 21;
      paint.color = fur;
      canvas.drawPath(
        Path()
          ..moveTo(43, 46)
          ..lineTo(43, top)
          ..lineTo(60, 32)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(82, 32)
          ..lineTo(100, top + 1)
          ..lineTo(97, 48)
          ..close(),
        paint,
      );
      paint.color = const Color(0xFFFFB49B).withValues(alpha: 0.80);
      canvas.drawPath(
        Path()
          ..moveTo(48, 38)
          ..lineTo(48, top + 9)
          ..lineTo(56, 34)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(87, 34)
          ..lineTo(95, top + 9)
          ..lineTo(93, 39)
          ..close(),
        paint,
      );
    } else if (kind == CompanionKind.pipou) {
      paint.color = fur;
      canvas.drawCircle(const Offset(52, 31), 13, paint);
      canvas.drawCircle(const Offset(91, 31), 13, paint);
    } else {
      paint.color = fur;
      canvas.drawPath(
        Path()
          ..moveTo(42, 43)
          ..lineTo(44, 18)
          ..lineTo(60, 32)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(82, 32)
          ..lineTo(99, 18)
          ..lineTo(98, 44)
          ..close(),
        paint,
      );
    }

    paint.color = fur;
    if (kind == CompanionKind.pipou) {
      canvas.drawOval(const Rect.fromLTWH(39, 30, 65, 52), paint);
    } else {
      canvas.drawCircle(const Offset(71, 54), 32, paint);
    }

    if (kind == CompanionKind.nox) {
      paint.color = Colors.white.withValues(alpha: 0.86);
      canvas.drawCircle(const Offset(59, 53), 13, paint);
      canvas.drawCircle(const Offset(83, 53), 13, paint);
    } else if (kind != CompanionKind.pipou) {
      paint.color = kind == CompanionKind.moka
          ? const Color(0xFFFFD7C2)
          : const Color(0xFFFFE1C8);
      canvas.drawOval(const Rect.fromLTWH(51, 51, 40, 29), paint);
    }

    final bool blink = math.sin(phase * 2.5) > 0.965;
    final double leftX = kind == CompanionKind.nox ? 59 : 63;
    final double rightX = kind == CompanionKind.nox ? 83 : 81;
    paint
      ..color = const Color(0xFF202744)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (blink) {
      canvas.drawLine(Offset(leftX - 4, 53), Offset(leftX + 4, 53), paint);
      canvas.drawLine(Offset(rightX - 4, 53), Offset(rightX + 4, 53), paint);
    } else {
      canvas.drawCircle(
          Offset(leftX, 53), kind == CompanionKind.nox ? 4 : 3, paint);
      canvas.drawCircle(
          Offset(rightX, 53), kind == CompanionKind.nox ? 4 : 3, paint);
      paint.color = Colors.white;
      canvas.drawCircle(Offset(leftX - 1, 52), 0.9, paint);
      canvas.drawCircle(Offset(rightX - 1, 52), 0.9, paint);
    }

    paint.color = const Color(0xFF2A2842);
    if (kind == CompanionKind.nox) {
      paint.color = GameColors.gold;
      canvas.drawPath(
        Path()
          ..moveTo(67, 61)
          ..lineTo(76, 61)
          ..lineTo(71.5, 69)
          ..close(),
        paint,
      );
    } else {
      canvas.drawCircle(const Offset(72, 63), 3, paint);
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawArc(
        const Rect.fromLTWH(65, 62, 14, 10),
        0.18,
        math.pi - 0.36,
        false,
        paint,
      );
      paint.style = PaintingStyle.fill;
    }
  }

  void _drawAccessory(Canvas canvas, Paint paint) {
    switch (accessory) {
      case CompanionAccessory.none:
        return;
      case CompanionAccessory.beret:
        paint.color = const Color(0xFFE35D52);
        canvas.drawOval(const Rect.fromLTWH(45, 20, 53, 15), paint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(52, 27, 45, 9),
            const Radius.circular(5),
          ),
          paint,
        );
        canvas.drawCircle(const Offset(73, 20), 3, paint);
      case CompanionAccessory.headphones:
        paint
          ..color = const Color(0xFF123D5A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7;
        canvas.drawArc(
          const Rect.fromLTWH(44, 25, 55, 54),
          math.pi,
          math.pi,
          false,
          paint,
        );
        paint.style = PaintingStyle.fill;
        paint.color = GameColors.coral;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(39, 48, 11, 22),
            const Radius.circular(6),
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(94, 48, 11, 22),
            const Radius.circular(6),
          ),
          paint,
        );
      case CompanionAccessory.crown:
        paint.color = GameColors.gold;
        canvas.drawPath(
          Path()
            ..moveTo(48, 34)
            ..lineTo(47, 15)
            ..lineTo(59, 25)
            ..lineTo(71, 10)
            ..lineTo(83, 25)
            ..lineTo(96, 15)
            ..lineTo(94, 35)
            ..close(),
          paint,
        );
        paint.color = Colors.white.withValues(alpha: 0.85);
        canvas.drawCircle(const Offset(71, 20), 3, paint);
    }
  }

  void _star(Canvas canvas, Offset center, double radius, Paint paint) {
    final Path path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * 0.32, center.dy - radius * 0.32)
      ..lineTo(center.dx + radius, center.dy)
      ..lineTo(center.dx + radius * 0.32, center.dy + radius * 0.32)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius * 0.32, center.dy + radius * 0.32)
      ..lineTo(center.dx - radius, center.dy)
      ..lineTo(center.dx - radius * 0.32, center.dy - radius * 0.32)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CompanionPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.t != t ||
      oldDelegate.kind != kind ||
      oldDelegate.accessory != accessory ||
      oldDelegate.evolutionStage != evolutionStage;
}
