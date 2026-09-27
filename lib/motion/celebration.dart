import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion_tokens.dart';

/// Bir noktadan dışarı saçılan parçacıklar.
///
/// Hazır bir konfeti paketi yerine tek bir `CustomPainter`: parçacıklar
/// widget değil, dolayısıyla yerleşim ağacına dokunmuyor ve her karede
/// yalnızca boyama yeniden çalışıyor. Kart destesindeki yaklaşımın aynısı.
class Celebration extends StatefulWidget {
  const Celebration({
    super.key,
    required this.play,
    required this.colors,
    this.particleCount = 26,
    this.duration = const Duration(milliseconds: 1100),
    required this.child,
  });

  /// false → hiç animasyon kurulmaz, çocuk olduğu gibi döner.
  final bool play;
  final List<Color> colors;
  final int particleCount;
  final Duration duration;
  final Widget child;

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration>
    with SingleTickerProviderStateMixin {
  // Denetleyici initState'te kurulur; alan başlatıcısında kurulursa
  // hiç oynatılmadığı durumda dispose() sırasında ilk kez yaratılıyor
  // ve "deactivated widget's ancestor" hatası atıyor.
  late final AnimationController _c;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    final math.Random rng = math.Random();
    _particles = List<_Particle>.generate(widget.particleCount, (int i) {
      final double angle =
          (i / widget.particleCount) * math.pi * 2 + rng.nextDouble() * 0.4;
      return _Particle(
        angle: angle,
        speed: 70 + rng.nextDouble() * 130,
        size: 4 + rng.nextDouble() * 5,
        spin: (rng.nextDouble() - 0.5) * 8,
        color: widget.colors[i % widget.colors.length],
        delay: rng.nextDouble() * 0.15,
      );
    });
    if (widget.play) _c.forward();
  }

  @override
  void didUpdateWidget(covariant Celebration old) {
    super.didUpdateWidget(old);
    if (widget.play && !old.play) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.play) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (BuildContext context, Widget? child) => CustomPaint(
        foregroundPainter: _BurstPainter(t: _c.value, particles: _particles),
        child: child,
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.color,
    required this.delay,
  });

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final Color color;
  final double delay;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t, required this.particles});

  final double t;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final Offset origin = Offset(size.width / 2, size.height / 2);

    for (final _Particle p in particles) {
      final double local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;

      // Dışa açılırken yavaşlar, sonra yerçekimiyle düşer.
      final double eased = Curves.easeOutCubic.transform(local);
      final double dx = math.cos(p.angle) * p.speed * eased;
      final double dy =
          math.sin(p.angle) * p.speed * eased + 90 * local * local;

      final double opacity = local < 0.7 ? 1.0 : (1 - local) / 0.3;
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(p.spin * local);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 1.6,
          ),
          const Radius.circular(1.5),
        ),
        Paint()..color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}

/// Yanlış cevapta yatay titreme.
///
/// Rengin yanına hareket eklemek, hatanın fark edilmesini hızlandırıyor;
/// renk körü biri için de tek ipucu renk olmaktan çıkıyor.
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});

  /// Her değiştiğinde bir titreme oynatılır.
  final Object? trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: MotionTokens.cardSettle,
    );
    if (widget.trigger != null && !MotionTokens.reducedMotion) {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(covariant Shake old) {
    super.didUpdateWidget(old);
    if (!MotionTokens.reducedMotion &&
        widget.trigger != null &&
        widget.trigger != old.trigger) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MotionTokens.reducedMotion) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        if (_c.value == 0) return child!;
        // Sönümlenen sinüs: üç gidiş geliş, gitgide küçülen genlik.
        final double damp = 1 - _c.value;
        final double dx = math.sin(_c.value * math.pi * 6) * 9 * damp * damp;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}
