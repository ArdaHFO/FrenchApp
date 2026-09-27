import 'package:flutter/material.dart';

import 'motion_tokens.dart';
import 'swipe_direction.dart';

/// Sürükleme sırasında kartın üzerine binen renk katmanı ve yön rozeti.
///
/// Opaklık sürükleme oranıyla artar. Eşik geçildiğinde rozet bir anlık büyür.
/// Bu bileşen kartın içeriğini bilmez, sadece yön ve oran alır.
class SwipeOverlay extends StatelessWidget {
  const SwipeOverlay({
    super.key,
    required this.direction,
    required this.progress,
    this.borderRadius = 24.0,
  });

  final SwipeDirection direction;

  /// 0.0 ile 1.0 arası. 1.0 eşiğin geçildiği andır.
  final double progress;

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final double t = progress.clamp(0.0, 1.0);
    if (t <= 0.0) return const SizedBox.shrink();

    final bool overThreshold = t >= 1.0;

    // easeOutBack bilerek 1.0'ı aşabilir, rozet hafif zıplayarak oturur.
    final double eased = MotionTokens.badge.transform(t);
    double scale =
        MotionTokens.badgeMinScale + (1.0 - MotionTokens.badgeMinScale) * eased;
    if (overThreshold) scale *= MotionTokens.badgeOverThresholdScale;

    final Color color = direction.color;

    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color:
                    color.withValues(alpha: MotionTokens.overlayMaxOpacity * t),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: color.withValues(alpha: t),
                  width: 3.0,
                ),
              ),
            ),
          ),
          Center(
            child: Opacity(
              opacity: t,
              child: Transform.scale(
                scale: scale,
                child: Transform.rotate(
                  angle: -0.12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color, width: 3),
                    ),
                    child: Text(
                      direction.label,
                      style: TextStyle(
                        color: color,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
