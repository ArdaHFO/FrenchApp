import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';

/// Oyun ekranlarında kullanılan ortak renkler.
abstract final class GameColors {
  /// Ana kimlik: Paris gecesi + Fransız mavisi + sıcak kafe tonları.
  static const Color frenchBlue = Color(0xFF2477E8);
  static const Color sky = Color(0xFF55B8E8);
  static const Color coral = Color(0xFFF06A5D);
  static const Color gold = Color(0xFFF2B84B);
  static const Color mint = Color(0xFF2EB889);
  static const Color ink = Color(0xFF10263A);
  static const Color navy = Color(0xFF071A2B);
  static const Color cream = Color(0xFFFFF8EC);

  // Eski bileşen adları API uyumluluğu için kalıyor; artık mor değiller.
  static const Color indigo = frenchBlue;
  static const Color violet = sky;
}

/// İçeriğin arkasında hafif hareket eden, gözü yormayan oyun dünyası zemini.
class GameBackdrop extends StatefulWidget {
  const GameBackdrop({
    super.key,
    required this.child,
    this.accent = GameColors.indigo,
    this.animate = true,
  });

  final Widget child;
  final Color accent;
  final bool animate;

  @override
  State<GameBackdrop> createState() => _GameBackdropState();
}

class _GameBackdropState extends State<GameBackdrop>
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
  void didUpdateWidget(covariant GameBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if ((!widget.animate || MotionTokens.reducedMotion) &&
        _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    } else if (widget.animate &&
        !MotionTokens.reducedMotion &&
        !_controller.isAnimating) {
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
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color base = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: base,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final double t = !widget.animate || MotionTokens.reducedMotion
              ? 0
              : _controller.value;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        widget.accent.withValues(alpha: dark ? 0.12 : 0.10),
                        base,
                        GameColors.gold.withValues(alpha: dark ? 0.05 : 0.04),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -70 + math.sin(t * math.pi * 2) * 12,
                top: 60 + math.cos(t * math.pi * 2) * 14,
                child: _GlowOrb(
                  size: 190,
                  color: widget.accent.withValues(alpha: dark ? 0.10 : 0.08),
                ),
              ),
              Positioned(
                left: -85 + math.cos(t * math.pi * 2) * 10,
                bottom: 90 + math.sin(t * math.pi * 2) * 16,
                child: _GlowOrb(
                  size: 220,
                  color: GameColors.sky.withValues(alpha: dark ? 0.08 : 0.06),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SparkleFieldPainter(
                      color:
                          widget.accent.withValues(alpha: dark ? 0.11 : 0.08),
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: child!),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      );
}

class _SparkleFieldPainter extends CustomPainter {
  const _SparkleFieldPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    const List<Offset> points = <Offset>[
      Offset(0.08, 0.12),
      Offset(0.88, 0.18),
      Offset(0.72, 0.38),
      Offset(0.14, 0.51),
      Offset(0.91, 0.66),
      Offset(0.30, 0.78),
      Offset(0.64, 0.91),
    ];
    for (int i = 0; i < points.length; i++) {
      final Offset point =
          Offset(points[i].dx * size.width, points[i].dy * size.height);
      canvas.drawCircle(point, i.isEven ? 2.2 : 1.4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkleFieldPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Cam hissi veren, temayla uyumlu ortak panel.
class GamePanel extends StatelessWidget {
  const GamePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.borderColor,
    this.radius = 24,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ??
            theme.colorScheme.surfaceContainerHigh
                .withValues(alpha: dark ? 0.90 : 0.94),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ??
              theme.colorScheme.onSurface.withValues(alpha: dark ? 0.10 : 0.07),
        ),
        boxShadow: shadow
            ? <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFF15234A)
                      .withValues(alpha: dark ? 0.24 : 0.09),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// Dokunulduğunda fiziksel olarak sıkışan, içeriğin kendi onTap'ine karışmayan sarmalayıcı.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.scale = 0.975,
  });

  final Widget child;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed == value || MotionTokens.reducedMotion) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _pressed ? widget.scale : 1,
          duration: MotionTokens.press,
          curve: MotionTokens.settle,
          child: widget.child,
        ),
      );
}

/// Gradyan, parlama ve yaylanmalı ilerleme çubuğu.
class JuicyProgressBar extends StatelessWidget {
  const JuicyProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 10,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final Color track =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.09);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.clamp(0, 1)),
      duration: MotionTokens.progressFill,
      curve: MotionTokens.badge,
      builder: (BuildContext context, double progress, Widget? child) =>
          LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth * progress;
          return Container(
            height: height,
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(99),
            ),
            alignment: Alignment.centerLeft,
            child: Container(
              width: width,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    color,
                    Color.lerp(color, Colors.white, 0.22)!
                  ],
                ),
                borderRadius: BorderRadius.circular(99),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: 0.34),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  height: math.max(2, height * 0.28),
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class GamePill extends StatelessWidget {
  const GamePill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      );
}
