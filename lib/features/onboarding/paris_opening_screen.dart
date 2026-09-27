import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';

import '../../ui/game_companion.dart';
import '../../ui/game_ui.dart';

/// Veritabanı hazırlanırken gösterilen, tamamen Flutter ile çizilmiş açılış.
/// Ağ veya bitmap beklemez; ilk kare anında görünür.
class ParisOpeningScreen extends StatefulWidget {
  const ParisOpeningScreen({super.key});

  @override
  State<ParisOpeningScreen> createState() => _ParisOpeningScreenState();
}

class _ParisOpeningScreenState extends State<ParisOpeningScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  );
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );
  bool? _motionDisabled;

  late final Animation<double> _fade = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, 0.72, curve: Curves.easeOutCubic),
  );
  late final Animation<Offset> _titleSlide = Tween<Offset>(
    begin: const Offset(0, 0.24),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.22, 1, curve: Curves.easeOutCubic),
    ),
  );
  late final Animation<double> _characterScale = Tween<double>(
    begin: 0.72,
    end: 1,
  ).animate(
    CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.08, 0.78, curve: Curves.easeOutBack),
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool disabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_motionDisabled == disabled) return;
    _motionDisabled = disabled;
    if (disabled) {
      _intro.value = 1;
      _ambient
        ..stop()
        ..value = 0.38;
    } else {
      _intro.forward(from: 0);
      _ambient.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameColors.navy,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxHeight < 680;
          final double characterSize = compact ? 132 : 172;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFF061725),
                      Color(0xFF0A2D43),
                      Color(0xFF123D4D),
                    ],
                    stops: <double>[0, 0.58, 1],
                  ),
                ),
              ),
              Positioned.fill(
                child: ExcludeSemantics(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _ambient,
                      builder: (BuildContext context, Widget? child) =>
                          CustomPaint(
                        painter: _ParisMorningPainter(t: _ambient.value),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    compact ? 14 : 24,
                    24,
                    compact ? 18 : 28,
                  ),
                  child: Column(
                    children: <Widget>[
                      FadeTransition(
                        opacity: _fade,
                        child: const _BrandTicket(),
                      ),
                      const Spacer(),
                      ScaleTransition(
                        scale: _characterScale,
                        child: GameCompanion(
                          color: GameColors.frenchBlue,
                          message: 'On y va ?',
                          size: characterSize,
                        ),
                      ),
                      SizedBox(height: compact ? 2 : 10),
                      SlideTransition(
                        position: _titleSlide,
                        child: FadeTransition(
                          opacity: _fade,
                          child: const _OpeningTitle(),
                        ),
                      ),
                      const Spacer(),
                      FadeTransition(
                        opacity: _fade,
                        child: _TravelLoader(animation: _ambient),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BrandTicket extends StatelessWidget {
  const _BrandTicket();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 7, 13, 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _TricolorMark(),
            SizedBox(width: 9),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'PARLONS!  •  FRANÇAIS',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    letterSpacing: 1.35,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TricolorMark extends StatelessWidget {
  const _TricolorMark();

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: const SizedBox(
          width: 29,
          height: 29,
          child: Row(
            children: <Widget>[
              Expanded(child: ColoredBox(color: GameColors.frenchBlue)),
              Expanded(child: ColoredBox(color: GameColors.cream)),
              Expanded(child: ColoredBox(color: GameColors.coral)),
            ],
          ),
        ),
      );
}

class _OpeningTitle extends StatelessWidget {
  const _OpeningTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        Text(
          'Bonjour, maceracı!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 34,
            height: 1.04,
            letterSpacing: -1.15,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 9),
        Text(
          'Fransızca rotan bugün de seni bekliyor.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFC7D9E2),
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TravelLoader extends StatelessWidget {
  const _TravelLoader({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sözlük hazırlanıyor',
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 174,
            height: 22,
            child: AnimatedBuilder(
              animation: animation,
              builder: (BuildContext context, Widget? child) => CustomPaint(
                painter: _RouteLoaderPainter(t: animation.value),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sözlük hazırlanıyor',
            style: TextStyle(
              color: Color(0xFFD5E3E9),
              fontSize: 12,
              letterSpacing: 0.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteLoaderPainter extends CustomPainter {
  const _RouteLoaderPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final Path route = Path()
      ..moveTo(9, size.height * 0.62)
      ..cubicTo(
        size.width * 0.30,
        -2,
        size.width * 0.67,
        size.height + 3,
        size.width - 9,
        size.height * 0.38,
      );
    canvas.drawPath(route, line);

    final PathMetric metric = route.computeMetrics().first;
    final Tangent point = metric.getTangentForOffset(metric.length * t)!;
    final Paint glow = Paint()
      ..color = GameColors.gold.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawCircle(point.position, 8, glow);
    canvas.drawCircle(
      point.position,
      4,
      Paint()..color = GameColors.gold,
    );
    for (final double x in <double>[9, size.width / 2, size.width - 9]) {
      canvas.drawCircle(
        Offset(x, size.height / 2),
        3,
        Paint()..color = Colors.white.withValues(alpha: 0.58),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RouteLoaderPainter oldDelegate) =>
      oldDelegate.t != t;
}

class _ParisMorningPainter extends CustomPainter {
  const _ParisMorningPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..isAntiAlias = true;
    final double phase = t * math.pi * 2;

    paint
      ..color = GameColors.gold.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34);
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.18),
      70 + math.sin(phase) * 3,
      paint,
    );
    paint
      ..maskFilter = null
      ..color = const Color(0xFFF8D47B).withValues(alpha: 0.82);
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.18),
      27,
      paint,
    );

    final List<Offset> stars = <Offset>[
      const Offset(0.10, 0.18),
      const Offset(0.22, 0.31),
      const Offset(0.42, 0.13),
      const Offset(0.62, 0.27),
      const Offset(0.90, 0.34),
      const Offset(0.15, 0.48),
    ];
    for (int i = 0; i < stars.length; i++) {
      final double pulse =
          0.35 + 0.45 * (0.5 + 0.5 * math.sin(phase + i * 1.17));
      paint.color = Colors.white.withValues(alpha: pulse);
      canvas.drawCircle(
        Offset(stars[i].dx * size.width, stars[i].dy * size.height),
        i.isEven ? 1.7 : 1.1,
        paint,
      );
    }

    final double ground = size.height * 0.83;
    paint.color = const Color(0xFF06131F).withValues(alpha: 0.72);
    canvas.drawRect(Rect.fromLTRB(0, ground, size.width, size.height), paint);
    _drawBuildings(canvas, size, ground, paint);
    _drawTower(canvas, size, ground, paint);

    paint
      ..color = GameColors.frenchBlue.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.48, ground + 12),
        width: size.width * 0.74,
        height: 46,
      ),
      paint,
    );
  }

  void _drawBuildings(Canvas canvas, Size size, double ground, Paint paint) {
    const List<double> widths = <double>[.12, .17, .10, .15, .13, .18, .15];
    const List<double> heights = <double>[.08, .13, .10, .16, .09, .12, .07];
    double x = -4;
    for (int i = 0; i < widths.length; i++) {
      final double width = widths[i] * size.width;
      final double height = heights[i] * size.height;
      paint.color = Color.lerp(
        const Color(0xFF071622),
        const Color(0xFF102D3D),
        i.isEven ? 0.15 : 0.55,
      )!;
      canvas.drawRect(Rect.fromLTWH(x, ground - height, width, height), paint);
      paint.color = GameColors.gold.withValues(alpha: 0.34);
      for (double wx = x + 10; wx < x + width - 5; wx += 16) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(wx, ground - height + 13, 3, 5),
            const Radius.circular(1),
          ),
          paint,
        );
      }
      x += width - 1;
    }
  }

  void _drawTower(Canvas canvas, Size size, double ground, Paint paint) {
    final double center = size.width * 0.70;
    final double top = ground - math.min(190, size.height * 0.26);
    paint
      ..color = const Color(0xFF07131D)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Path tower = Path()
      ..moveTo(center, top)
      ..quadraticBezierTo(center - 12, top + 82, center - 48, ground)
      ..moveTo(center, top)
      ..quadraticBezierTo(center + 12, top + 82, center + 48, ground)
      ..moveTo(center - 34, ground - 32)
      ..quadraticBezierTo(center, ground - 58, center + 34, ground - 32)
      ..moveTo(center - 24, ground - 73)
      ..lineTo(center + 24, ground - 73)
      ..moveTo(center - 11, ground - 118)
      ..lineTo(center + 11, ground - 118);
    canvas.drawPath(tower, paint);
    paint.strokeWidth = 2;
    for (int i = 1; i < 7; i++) {
      final double y = top + i * (ground - top) / 7;
      final double half = i * 5.7;
      canvas.drawLine(
          Offset(center - half, y), Offset(center + half, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParisMorningPainter oldDelegate) =>
      oldDelegate.t != t;
}
