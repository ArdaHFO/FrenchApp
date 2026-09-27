import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../domain/journey.dart';
import '../../domain/level.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/transitions.dart';
import '../quiz/quiz_screen.dart';
import '../vocab/swipe_session_screen.dart';
import 'station_builder.dart';
import 'station_quiz_screen.dart';

/// Yolculuk haritası.
///
/// Duraklar yukarıdan aşağı kıvrılan bir yol üzerinde dizilir. Bir durağı
/// açmak için bir öncekini geçmiş olmak gerekir; böylece quiz sonsuz bir
/// alıştırma değil, ilerlenen bir yol hâline geliyor.
class JourneyMapScreen extends StatefulWidget {
  const JourneyMapScreen({super.key});

  @override
  State<JourneyMapScreen> createState() => _JourneyMapScreenState();
}

// İki denetleyici var (_intro ve _travel), o yüzden Single değil çoklu
// ticker sağlayıcı gerekiyor.
class _JourneyMapScreenState extends State<JourneyMapScreen>
    with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();

  /// Harita açılırken yol çizilir, duraklar sırayla oturur.
  late final AnimationController _intro;

  /// Durak geçilince gezgini bir sonraki durağa yürüten animasyon.
  late final AnimationController _travel;

  /// Yürüyüşün başladığı ve bittiği durak sırası.
  int _travelFrom = 0;
  int _travelTo = 0;

  AppState? _app;
  List<JourneyStation> _stations = const <JourneyStation>[];
  bool _scrolledToCurrent = false;

  /// Duraklar arası dikey mesafe ve yolun yatay salınımı.
  static const double _step = 108;
  static const double _amplitude = 0.30;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: MotionTokens.mapIntro)
      ..forward();
    _travel = AnimationController(
      vsync: this,
      duration: MotionTokens.mapTravel,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppState app = AppScope.of(context);
    if (_app != app || _stations.isEmpty) {
      _app = app;
      _stations = StationBuilder.build(app);
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    _intro.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// İlk kilitli durağın sırası: haritadaki "buradasın" noktası.
  int get _currentIndex {
    final AppState app = _app!;
    final int start = _stations.indexWhere(
      (JourneyStation station) => station.level == app.level,
    );
    int lastInLevel = start < 0 ? 0 : start;
    for (int i = start < 0 ? 0 : start; i < _stations.length; i++) {
      if (_stations[i].level != app.level) break;
      lastInLevel = i;
      final StationResult? r = app.journey.resultFor(_stations[i].id);
      if (r == null || !r.passed) return i;
    }
    return lastInLevel;
  }

  bool _isUnlocked(int index) {
    if (index == 0) return true;
    final JourneyStation station = _stations[index];
    if (station.level == _app!.level && station.indexInLevel == 0) return true;
    final StationResult? prev =
        _app!.journey.resultFor(_stations[index - 1].id);
    return prev != null && prev.passed;
  }

  double _dx(int index) =>
      math.sin(index * 0.9) * _amplitude; // -amplitude .. +amplitude

  Future<void> _open(JourneyStation station, bool unlocked) async {
    if (!unlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce bir önceki durağı geç.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Doğrudan quize atlamak yerine kısa bir tanıtım: ne çıkacağını
    // bilmek, "başla"ya basmayı bir karar hâline getiriyor.
    final _StationAction? action = await showModalBottomSheet<_StationAction>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => _StationSheet(
        station: station,
        result: _app!.journey.resultFor(station.id),
      ),
    );
    if (action == null || !mounted) return;
    if (action == _StationAction.study) {
      await Navigator.of(context).push(
        fadeSlideRoute<void>(
          SwipeSessionScreen(
            title: '${station.title} çalışması',
            candidateIds: station.wordIds,
            includeNotDue: true,
          ),
        ),
      );
      return;
    }

    final int before = _currentIndex;
    await Navigator.of(context).push(
      fadeSlideRoute<void>(StationQuizScreen(station: station)),
    );
    if (!mounted) return;

    final int after = _currentIndex;
    setState(() {});
    if (after > before) {
      // Durak geçildi: gezgin yeni durağa yürüsün ve harita onu takip
      // etsin. Kullanıcı ilerlemeyi bir sayı olarak değil, hareket
      // olarak görüyor.
      _travelFrom = before;
      _travelTo = after;
      await HapticFeedback.mediumImpact();
      await _travel.forward(from: 0);
      if (!mounted) return;
      if (_scroll.hasClients) {
        await _scroll.animateTo(
          (after * _step - 220).clamp(0.0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final int current = _currentIndex;
    final List<JourneyStation> levelStations = _stations
        .where((JourneyStation station) => station.level == app.level)
        .toList();
    final int levelPassed = levelStations
        .where(
          (JourneyStation station) =>
              app.journey.resultFor(station.id)?.passed ?? false,
        )
        .length;

    if (_stations.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // İlk açılışta bulunduğun noktaya kaydır.
    if (!_scrolledToCurrent) {
      _scrolledToCurrent = true;
      _travelFrom = current;
      _travelTo = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final double target = (current * _step - 220)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
        );
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(
              level: app.level,
              passed: levelPassed,
              total: levelStations.length,
              stars: app.journey.totalStars,
              onFreeQuiz: () => Navigator.of(context).push(
                fadeSlideRoute<void>(const QuizScreen()),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  final double width = c.maxWidth;
                  final double height = _stations.length * _step + 160;
                  return SingleChildScrollView(
                    controller: _scroll,
                    child: SizedBox(
                      height: height,
                      width: width,
                      child: Stack(
                        children: <Widget>[
                          // Zemin dokusu: yol bir haritanın üstünde
                          // duruyor hissi versin diye seyrek noktalar.
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _DotGridPainter(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.05),
                              ),
                            ),
                          ),
                          // Yol açılışta yukarıdan aşağı çizilir.
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _intro,
                              builder: (BuildContext context, Widget? _) =>
                                  CustomPaint(
                                painter: _PathPainter(
                                  progress: Curves.easeOutCubic
                                      .transform(_intro.value),
                                  count: _stations.length,
                                  step: _step,
                                  dxFor: _dx,
                                  colors: <Color>[
                                    for (final JourneyStation s in _stations)
                                      AppTheme.levelColor(s.level.index),
                                  ],
                                  passed: <bool>[
                                    for (final JourneyStation s in _stations)
                                      app.journey.resultFor(s.id)?.passed ??
                                          false,
                                  ],
                                  dim: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.12),
                                ),
                              ),
                            ),
                          ),
                          // Gezgin: yol üzerinde duran, geçişte
                          // bir sonraki durağa yürüyen işaret.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedBuilder(
                                animation: Listenable.merge(
                                  <Listenable>[_travel, _intro],
                                ),
                                builder: (BuildContext context, Widget? _) =>
                                    CustomPaint(
                                  painter: _TravelerPainter(
                                    from: _travelFrom,
                                    to: _travelTo,
                                    t: Curves.easeInOutCubic
                                        .transform(_travel.value),
                                    fade: _intro.value,
                                    step: _step,
                                    dxFor: _dx,
                                    color: AppTheme.levelColor(
                                      _stations[_travelTo.clamp(
                                        0,
                                        _stations.length - 1,
                                      )]
                                          .level
                                          .index,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          for (int i = 0; i < _stations.length; i++)
                            _positioned(
                              context,
                              index: i,
                              width: width,
                              current: current,
                              app: app,
                            ),
                          // Seviye başlıkları yolun kenarında.
                          for (int i = 0; i < _stations.length; i++)
                            if (i == 0 ||
                                _stations[i].level != _stations[i - 1].level)
                              Positioned(
                                top: 80 + i * _step - 46,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: _LevelBanner(
                                    level: _stations[i].level,
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Her durak 8-12 soru. Geçmek için %70 yeter, '
                'üç yıldız için hatasız.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: faint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _positioned(
    BuildContext context, {
    required int index,
    required double width,
    required int current,
    required AppState app,
  }) {
    final JourneyStation s = _stations[index];
    final StationResult? result = app.journey.resultFor(s.id);
    final bool unlocked = _isUnlocked(index);
    const double size = 64;
    final double centerX = width / 2 + _dx(index) * width / 2;

    // Her durak, yolun oraya ulaşmasından hemen sonra oturur.
    final double appearAt = (index / _stations.length) * 0.85;

    return Positioned(
      top: 80 + index * _step - size / 2,
      left: centerX - size / 2,
      child: AnimatedBuilder(
        animation: _intro,
        builder: (BuildContext context, Widget? child) {
          final double t = ((_intro.value - appearAt) / 0.15).clamp(0.0, 1.0);
          return Opacity(
            opacity: t,
            child: Transform.scale(
              scale: 0.6 + 0.4 * Curves.easeOutBack.transform(t),
              child: child,
            ),
          );
        },
        child: _StationNode(
          station: s,
          result: result,
          unlocked: unlocked,
          isCurrent: index == current,
          onTap: () => _open(s, unlocked),
        ),
      ),
    );
  }
}

/// Yolu çizer. Duraklar arasını düz çizgi yerine yumuşak eğriyle bağlar;
/// geçilmiş bölüm seviye renginde, kalanı soluk.
/// Yol üzerinde duran gezgin.
///
/// Durak düğümlerinin arasındaki eğrinin üzerinde ilerler; iki durak
/// arasındaki kübik eğri doğrudan hesaplanır, böylece işaret yolun tam
/// üstünde kalır, düz bir çizgi boyunca kesmez.
class _TravelerPainter extends CustomPainter {
  _TravelerPainter({
    required this.from,
    required this.to,
    required this.t,
    required this.fade,
    required this.step,
    required this.dxFor,
    required this.color,
  });

  final int from;
  final int to;
  final double t;
  final double fade;
  final double step;
  final double Function(int) dxFor;
  final Color color;

  Offset _node(Size size, int i) => Offset(
        size.width / 2 + dxFor(i) * size.width / 2,
        80 + i * step,
      );

  /// İki durak arasındaki kübik eğri üzerinde `u` oranındaki nokta.
  Offset _onCurve(Size size, int i, double u) {
    final Offset a = _node(size, i);
    final Offset b = _node(size, i + 1);
    final Offset c1 = Offset(a.dx, a.dy + step * 0.5);
    final Offset c2 = Offset(b.dx, b.dy - step * 0.5);
    final double v = 1 - u;
    return Offset(
      v * v * v * a.dx +
          3 * v * v * u * c1.dx +
          3 * v * u * u * c2.dx +
          u * u * u * b.dx,
      v * v * v * a.dy +
          3 * v * v * u * c1.dy +
          3 * v * u * u * c2.dy +
          u * u * u * b.dy,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (fade < 0.35) return;

    final Offset pos;
    if (to <= from) {
      pos = _node(size, from);
    } else {
      // Birden fazla durak atlanmışsa parçalar sırayla yürünür.
      final int spans = to - from;
      final double scaled = (t * spans).clamp(0.0, spans.toDouble());
      final int segment = scaled.floor().clamp(0, spans - 1);
      pos = _onCurve(size, from + segment, scaled - segment);
    }

    final double opacity = ((fade - 0.35) / 0.3).clamp(0.0, 1.0);

    // Hafif bir hâle, sonra dolu daire, sonra beyaz ayak izi.
    canvas.drawCircle(
      pos,
      16,
      Paint()..color = color.withValues(alpha: 0.22 * opacity),
    );
    canvas.drawCircle(
      pos,
      10,
      Paint()..color = color.withValues(alpha: opacity),
    );
    canvas.drawCircle(
      pos.translate(0, -1),
      3.4,
      Paint()..color = Colors.white.withValues(alpha: 0.9 * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _TravelerPainter old) =>
      old.t != t || old.from != from || old.to != to || old.fade != fade;
}

/// Haritanın zemin dokusu. Sabit, animasyonsuz, ucuz.
class _DotGridPainter extends CustomPainter {
  _DotGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..color = color;
    const double gap = 26;
    for (double y = 0; y < size.height; y += gap) {
      for (double x = 0; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1.2, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter old) => old.color != color;
}

class _PathPainter extends CustomPainter {
  _PathPainter({
    required this.progress,
    required this.count,
    required this.step,
    required this.dxFor,
    required this.colors,
    required this.passed,
    required this.dim,
  });

  /// 0 → yol hiç çizilmemiş, 1 → tamamı. Açılışta 0'dan 1'e gider.
  final double progress;
  final int count;
  final double step;
  final double Function(int) dxFor;
  final List<Color> colors;
  final List<bool> passed;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    Offset pointAt(int i) => Offset(
          size.width / 2 + dxFor(i) * size.width / 2,
          80 + i * step,
        );

    // Yol yukarıdan aşağı doğru çizilir: kaç parça görünecek.
    final double drawn = progress * (count - 1);

    for (int i = 0; i < count - 1; i++) {
      if (i > drawn) break;
      final Offset a = pointAt(i);
      final Offset b = pointAt(i + 1);
      final Path path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(
          a.dx,
          a.dy + step * 0.5,
          b.dx,
          b.dy - step * 0.5,
          b.dx,
          b.dy,
        );
      final bool done = passed[i] && passed[i + 1];
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = done ? 6 : 5
          ..strokeCap = StrokeCap.round
          ..color = done ? colors[i].withValues(alpha: 0.55) : dim,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PathPainter old) =>
      old.progress != progress ||
      old.count != count ||
      !_sameFlags(old.passed, passed);

  static bool _sameFlags(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _StationNode extends StatelessWidget {
  const _StationNode({
    required this.station,
    required this.result,
    required this.unlocked,
    required this.isCurrent,
    required this.onTap,
  });

  final JourneyStation station;
  final StationResult? result;
  final bool unlocked;
  final bool isCurrent;
  final VoidCallback onTap;

  IconData get _icon => switch (station.kind) {
        StationKind.words => Icons.style_rounded,
        StationKind.idioms => Icons.format_quote_rounded,
        StationKind.verbs => Icons.change_circle_rounded,
        StationKind.boss => Icons.workspace_premium_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = AppTheme.levelColor(station.level.index);
    final bool passed = result?.passed ?? false;
    final Color bg = passed
        ? accent
        : unlocked
            ? accent.withValues(alpha: 0.22)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    return SizedBox(
      width: 64,
      height: 92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GestureDetector(
            onTap: onTap,
            child: _Pulse(
              active: isCurrent && !passed,
              color: accent,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: unlocked
                        ? accent
                        : theme.colorScheme.onSurface.withValues(alpha: 0.15),
                    width: isCurrent ? 3 : 2,
                  ),
                ),
                child: Icon(
                  unlocked ? _icon : Icons.lock_rounded,
                  size: station.isBoss ? 28 : 24,
                  color: passed
                      ? Colors.white
                      : unlocked
                          ? accent
                          : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (passed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < 3; i++)
                  Icon(
                    i < (result?.stars ?? 0)
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 13,
                    color: i < (result?.stars ?? 0)
                        ? const Color(0xFFD9A21B)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.25),
                  ),
              ],
            )
          else
            Text(
              station.kind.labelTr,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bulunduğun durağın etrafında yavaşça büyüyüp sönen halka.
///
/// Halka CustomPaint ile kutunun DIŞINA çiziliyor; büyürken düğümün
/// yerleşim boyutunu değiştirmiyor. Widget olarak eklenseydi Stack her
/// karede büyüyüp küçülür, kolon taşar ve düğüm zıplardı.
class _Pulse extends StatefulWidget {
  const _Pulse({
    required this.active,
    required this.color,
    required this.child,
  });

  final bool active;
  final Color color;
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  // Denetleyici initState'te KURULUR, alan başlatıcısında değil.
  //
  // `late final ... = AnimationController(...)` yazılırsa denetleyici ilk
  // kullanımda kurulur. Halka hiç dönmediyse (durak "buradasın" değilse)
  // build erken dönüyor ve denetleyiciye hiç dokunulmuyor; o zaman
  // dispose() içindeki `_c.dispose()` onu ilk kez ORADA kuruyor ve
  // "deactivated widget's ancestor" hatası atıyor.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _Pulse old) {
    super.didUpdateWidget(old);
    if (MotionTokens.reducedMotion) {
      _c.stop();
      _c.value = 0;
    } else if (widget.active && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || MotionTokens.reducedMotion) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (BuildContext context, Widget? child) => CustomPaint(
        foregroundPainter: _RingPainter(t: _c.value, color: widget.color),
        child: child,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2 + 13 * t;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: (1 - t) * 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.t != t || old.color != color;
}

/// Durağa girmeden önce açılan tanıtım.
class _StationSheet extends StatelessWidget {
  const _StationSheet({required this.station, required this.result});

  final JourneyStation station;
  final StationResult? result;

  String get _what => switch (station.kind) {
        StationKind.words => '${station.wordIds.length} kelime arasından',
        StationKind.idioms => '${station.wordIds.length} deyim arasından',
        StationKind.verbs => 'bu seviyenin fiil çekimlerinden',
        StationKind.boss =>
          'seviyenin her yerinden — geçmek için ${(station.passRatio * 100).round()}%',
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = AppTheme.levelColor(station.level.index);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  station.level.code,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                station.kind.labelTr,
                style: TextStyle(fontSize: 12, color: faint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            station.title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${station.questionCount} soru, $_what.',
            style: TextStyle(fontSize: 14, height: 1.4, color: faint),
          ),
          if (result != null && result!.passed) ...<Widget>[
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                for (int i = 0; i < 3; i++)
                  Icon(
                    i < result!.stars
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 20,
                    color: i < result!.stars
                        ? const Color(0xFFD9A21B)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.25),
                  ),
                const SizedBox(width: 10),
                Text(
                  'en iyi ${result!.bestCorrect}/${result!.bestTotal}',
                  style: TextStyle(fontSize: 12, color: faint),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          if (station.wordIds.isNotEmpty) ...<Widget>[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(_StationAction.study),
                icon: const Icon(Icons.style_rounded),
                label: const Text('Önce kartları çalış'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_StationAction.quiz),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                result?.passed ?? false ? 'Tekrar oyna' : 'Başla',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StationAction { study, quiz }

class _LevelBanner extends StatelessWidget {
  const _LevelBanner({required this.level});

  final CefrLevel level;

  @override
  Widget build(BuildContext context) {
    final Color accent = AppTheme.levelColor(level.index);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Text(
        level.code,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: accent,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.level,
    required this.passed,
    required this.total,
    required this.stars,
    required this.onFreeQuiz,
  });

  final CefrLevel level;
  final int passed;
  final int total;
  final int stars;

  /// Haritadan bağımsız, SRS havuzundan çalışan eski quiz. Yolculuk
  /// sırayla ilerler; bu ise "bugün ne öğrendiysem onu sor" der.
  final VoidCallback onFreeQuiz;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final double ratio = total == 0 ? 0 : passed / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (Navigator.of(context).canPop()) ...<Widget>[
                const BackButton(),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Yolculuk',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${level.code} · ${level.worldName}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.levelColor(level.index),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Serbest quiz',
                icon: const Icon(Icons.shuffle_rounded),
                onPressed: onFreeQuiz,
              ),
              const Icon(Icons.star_rounded,
                  size: 18, color: Color(0xFFD9A21B)),
              const SizedBox(width: 4),
              Text(
                '$stars',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD9A21B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: ratio),
              duration: MotionTokens.progressFill,
              curve: MotionTokens.progress,
              builder: (BuildContext context, double v, Widget? _) =>
                  LinearProgressIndicator(value: v, minHeight: 6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$passed / $total durak geçildi',
            style: TextStyle(fontSize: 12, color: faint),
          ),
        ],
      ),
    );
  }
}
