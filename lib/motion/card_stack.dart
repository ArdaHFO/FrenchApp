import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'motion_tokens.dart';
import 'swipe_badge.dart';
import 'swipe_direction.dart';

typedef CardStackItemBuilder = Widget Function(BuildContext context, int index);
typedef CardStackSwipeCallback = void Function(
    int index, SwipeDirection direction);

/// Kart destesini dışarıdan sürmek için. Düğmelerle kaydırma ve sıfırlama.
class CardStackController {
  _CardStackState? _state;

  bool get isAttached => _state != null;

  void swipe(SwipeDirection direction) => _state?._programmaticSwipe(direction);

  void reset() => _state?._reset();

  void _attach(_CardStackState state) => _state = state;

  void _detach(_CardStackState state) {
    if (identical(_state, state)) _state = null;
  }
}

/// Elle yazılan kart destesi.
///
/// Neden hazır paket değil: arkadaki kartların sürükleme sırasındaki davranışı,
/// dört yönlü eşikler, eşikte titreşim ve yarıda kesilebilen animasyonlar
/// hazır paketlerin dışarı açmadığı ayrıntılar. Bakınız PLAN.md bölüm 6.
///
/// Performans kuralı: sürükleme sırasında `setState` çağrılmaz. Kart widget'ları
/// [LayoutBuilder] içinde bir kez kurulur, [AnimatedBuilder] sadece dönüşümleri
/// günceller. Kart alt ağaçları aynı örnek kaldığı için yeniden kurulmaz.
class CardStack extends StatefulWidget {
  const CardStack({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.onSwiped,
    this.onSwipeAccepted,
    this.controller,
    this.allowedDirections = const <SwipeDirection>{
      SwipeDirection.right,
      SwipeDirection.left,
      SwipeDirection.up,
      SwipeDirection.down,
    },
  });

  final int itemCount;
  final CardStackItemBuilder itemBuilder;
  final CardStackSwipeCallback? onSwiped;

  /// Optional persistence boundary. False keeps the current card for retry.
  /// While pending, further gestures/buttons are ignored (not queued).
  final Future<bool> Function(int index, SwipeDirection direction)?
      onSwipeAccepted;
  final CardStackController? controller;

  /// Kapalı bir yöne kaydırma eşiği geçilse bile kart uçmaz, yerine döner.
  final Set<SwipeDirection> allowedDirections;

  @override
  State<CardStack> createState() => _CardStackState();
}

class _CardStackState extends State<CardStack> with TickerProviderStateMixin {
  /// Sürükleme ve uçma animasyonunu süren kontrolcü. Yay aşabildiği için
  /// sınırsız (0-1 aralığına kilitli değil).
  late final AnimationController _anim;

  /// Yeni açığa çıkan en arkadaki kartın belirmesi.
  late final AnimationController _settle;

  /// Kartın anlık kayması. Sürükleme sırasında sadece bu değişir.
  final ValueNotifier<Offset> _drag = ValueNotifier<Offset>(Offset.zero);

  late final Listenable _repaintTriggers;

  /// Kart boyutunu okumak için. Tutuş noktasının üst yarıda mı olduğunu bulur.
  final GlobalKey _cardKey = GlobalKey();

  Size _stackSize = Size.zero;
  Offset _releaseOffset = Offset.zero;
  Offset _flyTarget = Offset.zero;
  SwipeDirection? _flyDirection;
  bool _flying = false;
  bool _pending = false;
  bool _wasOverThreshold = false;
  final List<SwipeDirection> _programmaticQueue = <SwipeDirection>[];

  /// Kartın üstünden tutulursa alt taraf savrulur, altından tutulursa üst.
  double _grabSign = 1.0;

  int _topIndex = 0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController.unbounded(vsync: this)..addListener(_onTick);
    _settle = AnimationController(
      vsync: this,
      duration: MotionTokens.cardSettle,
      value: 1.0,
    );
    _repaintTriggers = Listenable.merge(<Listenable>[_drag, _settle]);
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant CardStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _anim.dispose();
    _settle.dispose();
    _drag.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- animasyon

  void _onTick() {
    if (_flying) {
      _drag.value = Offset.lerp(_releaseOffset, _flyTarget, _anim.value)!;
      if (_anim.value >= 1.0) _finishFlyOut();
    } else {
      // Yay 1.0'dan 0.0'a iner, kayma da onunla birlikte küçülür.
      _drag.value = _releaseOffset * _anim.value;
    }
  }

  Future<void> _finishFlyOut() async {
    if (!mounted) return;
    final SwipeDirection? direction = _flyDirection;
    final int swipedIndex = _topIndex;

    _flying = false;
    _flyDirection = null;
    _wasOverThreshold = false;
    _grabSign = 1.0;
    _releaseOffset = Offset.zero;
    _drag.value = Offset.zero;
    _anim.value = 0.0;

    if (direction != null && widget.onSwipeAccepted != null) {
      setState(() => _pending = true);
      final bool accepted;
      try {
        accepted = await widget.onSwipeAccepted!(swipedIndex, direction);
      } finally {
        if (mounted) setState(() => _pending = false);
      }
      if (!mounted || !accepted) return;
    }
    setState(() => _topIndex = swipedIndex + 1);
    _settle.forward(from: 0.0);

    if (direction != null) widget.onSwiped?.call(swipedIndex, direction);
    if (_programmaticQueue.isNotEmpty && _topIndex < widget.itemCount) {
      final SwipeDirection next = _programmaticQueue.removeAt(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _programmaticSwipe(next);
      });
    }
  }

  void _flyOut(SwipeDirection direction) {
    _releaseOffset = _drag.value;
    final double distance = math.max(_stackSize.width, _stackSize.height) *
        MotionTokens.flyOutOvershoot;
    _flyTarget = _releaseOffset +
        Offset(direction.unit.dx * distance, direction.unit.dy * distance);
    _flyDirection = direction;
    _flying = true;
    _anim.value = 0.0;
    _anim.animateTo(
      1.0,
      duration: MotionTokens.cardFlyOut,
      curve: MotionTokens.flyOut,
    );
  }

  void _springBack(Offset velocity) {
    _flying = false;
    _releaseOffset = _drag.value;
    final double distance = _releaseOffset.distance;

    // Hızı 1.0 -> 0.0 ölçeğine çevir. Dışa doğru fırlatma pozitif olur ve
    // yayın hafifçe aşmasını sağlar.
    double normalized = 0.0;
    if (distance > 0.5) {
      final Offset unit = _releaseOffset / distance;
      normalized = (velocity.dx * unit.dx + velocity.dy * unit.dy) / distance;
    }

    _anim.animateWith(
      SpringSimulation(MotionTokens.returnSpring, 1.0, 0.0, normalized),
    );
  }

  // ----------------------------------------------------------------- girdi

  void _onPanDown(DragDownDetails details) {
    if (_pending) return;
    // Kesintiye uğratılabilirlik: süren animasyon durur, kart bulunduğu yerde
    // kalır ve parmağa devredilir. Kontrolcü sıfırlanmaz.
    _anim.stop();
    _programmaticQueue.clear();
    _flying = false;
    _flyDirection = null;

    final double cardHeight =
        _cardKey.currentContext?.size?.height ?? _stackSize.height;
    _grabSign = details.localPosition.dy < cardHeight / 2 ? 1.0 : -1.0;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_pending) return;
    _drag.value += details.delta;
    _updateThresholdHaptic();
  }

  void _onPanEnd(DragEndDetails details) {
    if (_pending) return;
    final Offset velocity = details.velocity.pixelsPerSecond;
    final SwipeDirection? direction = _resolveDirection(_drag.value, velocity);
    if (direction != null) {
      _flyOut(direction);
    } else {
      _springBack(velocity);
    }
  }

  void _onPanCancel() {
    if (!_pending) _springBack(Offset.zero);
  }

  void _updateThresholdHaptic() {
    final bool over = _resolveDirection(_drag.value, Offset.zero) != null;
    if (over == _wasOverThreshold) return;
    _wasOverThreshold = over;
    // Ekrana bakmadan da kartın gideceğini parmakla anlamayı sağlar.
    if (over) HapticFeedback.selectionClick();
  }

  void _programmaticSwipe(SwipeDirection direction) {
    if (_pending || (_flying && widget.onSwipeAccepted != null)) return;
    if (_topIndex >= widget.itemCount || _stackSize.isEmpty) return;
    if (!widget.allowedDirections.contains(direction)) return;
    if (_flying) {
      _programmaticQueue.add(direction);
      return;
    }
    _anim.stop();
    _grabSign = 1.0;
    _drag.value = Offset(
      direction.unit.dx * _stackSize.width * 0.30,
      direction.unit.dy * _stackSize.height * 0.20,
    );
    _flyOut(direction);
  }

  void _reset() {
    if (_pending) return;
    _anim.stop();
    _programmaticQueue.clear();
    _flying = false;
    _flyDirection = null;
    _wasOverThreshold = false;
    _grabSign = 1.0;
    _releaseOffset = Offset.zero;
    _drag.value = Offset.zero;
    _anim.value = 0.0;
    setState(() => _topIndex = 0);
    _settle.value = 1.0;
  }

  // ------------------------------------------------------------- hesaplar

  /// Sürükleme yönünden niyeti okur. Eşiği geçmiş olması gerekmez.
  SwipeDirection? _intentDirection(Offset offset) {
    if (offset.distance < 4.0) return null;
    final bool horizontal = offset.dx.abs() >= offset.dy.abs();
    final SwipeDirection candidate = horizontal
        ? (offset.dx > 0 ? SwipeDirection.right : SwipeDirection.left)
        : (offset.dy > 0 ? SwipeDirection.down : SwipeDirection.up);
    return widget.allowedDirections.contains(candidate) ? candidate : null;
  }

  /// 0.0 ile 1.0 arası. 1.0 eşiğin tam geçildiği andır.
  double _intentProgress(Offset offset, SwipeDirection direction) {
    final double travelled =
        direction.isHorizontal ? offset.dx.abs() : offset.dy.abs();
    final double limit = direction.isHorizontal
        ? _stackSize.width * MotionTokens.thresholdFraction
        : _stackSize.height * MotionTokens.thresholdFractionVertical;
    if (limit <= 0.0) return 0.0;
    return (travelled / limit).clamp(0.0, 1.0);
  }

  SwipeDirection? _resolveDirection(Offset offset, Offset velocity) {
    final SwipeDirection? direction = _intentDirection(offset);
    if (direction == null) return null;

    final bool passedDistance = _intentProgress(offset, direction) >= 1.0;

    final double speed =
        direction.isHorizontal ? velocity.dx.abs() : velocity.dy.abs();
    final bool passedVelocity = speed > MotionTokens.velocityThreshold &&
        offset.distance > MotionTokens.velocityMinTravel;

    return (passedDistance || passedVelocity) ? direction : null;
  }

  double _lerpDepth(List<double> values, double t) {
    final double clamped = t.clamp(0.0, (values.length - 1).toDouble());
    final int i = clamped.floor();
    final int j = math.min(i + 1, values.length - 1);
    return values[i] + (values[j] - values[i]) * (clamped - i);
  }

  // ---------------------------------------------------------------- çizim

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _stackSize = Size(constraints.maxWidth, constraints.maxHeight);

        final int remaining = widget.itemCount - _topIndex;
        if (remaining <= 0) return const SizedBox.expand();

        final int count = math.min(MotionTokens.visibleCards, remaining);

        // Kart widget'ları burada bir kez kurulur. Sürükleme sırasında bu
        // builder çalışmaz, dolayısıyla alt ağaçlar yeniden kurulmaz.
        final List<Widget> cards = <Widget>[
          for (int depth = 0; depth < count; depth++)
            RepaintBoundary(
              key: ValueKey<int>(_topIndex + depth),
              child: widget.itemBuilder(context, _topIndex + depth),
            ),
        ];

        return AnimatedBuilder(
          animation: _repaintTriggers,
          builder: (BuildContext context, Widget? _) {
            final Offset offset = _drag.value;
            final SwipeDirection? direction = _intentDirection(offset);
            final double progress =
                direction == null ? 0.0 : _intentProgress(offset, direction);

            final List<Widget> layers = <Widget>[];
            // Arkadan öne diz: son eklenen en üstte görünür.
            for (int depth = count - 1; depth >= 1; depth--) {
              layers.add(_buildBackCard(
                cards[depth],
                depth,
                progress,
                isDeepest:
                    depth == count - 1 && count == MotionTokens.visibleCards,
              ));
            }
            layers.add(_buildTopCard(cards[0], offset, direction, progress));

            // expand: kartlar deste alanının tamamını kaplar.
            return Stack(fit: StackFit.expand, children: <Widget>[
              ...layers,
              if (_pending)
                const Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(child: Text('Kaydediliyor…'))),
            ]);
          },
        );
      },
    );
  }

  Widget _buildTopCard(
    Widget card,
    Offset offset,
    SwipeDirection? direction,
    double progress,
  ) {
    final double rotation =
        (offset.dx / math.max(_stackSize.width / 2, 1.0)).clamp(-1.0, 1.0) *
            MotionTokens.maxRotationRadians *
            _grabSign;

    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: rotation,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: _onPanDown,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onPanCancel: _onPanCancel,
          child: Stack(
            key: _cardKey,
            fit: StackFit.passthrough,
            children: <Widget>[
              card,
              if (direction != null)
                Positioned.fill(
                  child: SwipeOverlay(direction: direction, progress: progress),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackCard(
    Widget card,
    int depth,
    double progress, {
    required bool isDeepest,
  }) {
    // Üstteki kart sürüklendikçe arkadakiler eş zamanlı olarak öne ilerler.
    // Ayrı bir animasyon değil, sürükleme oranının türevi.
    final double effective = depth - progress;

    double scale = _lerpDepth(MotionTokens.depthScale, effective);
    final double dy = _lerpDepth(MotionTokens.depthOffsetY, effective);
    double opacity = _lerpDepth(MotionTokens.depthOpacity, effective);

    if (isDeepest) {
      final double entry =
          MotionTokens.settle.transform(_settle.value.clamp(0.0, 1.0));
      opacity *= entry;
      scale *= 0.96 + 0.04 * entry;
    }

    return Transform.translate(
      offset: Offset(0, dy),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: IgnorePointer(child: card),
        ),
      ),
    );
  }
}
