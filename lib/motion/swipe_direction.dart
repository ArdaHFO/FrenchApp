import 'package:flutter/painting.dart';

/// Kartın kaydırılabileceği dört yön.
enum SwipeDirection { right, left, up, down }

extension SwipeDirectionX on SwipeDirection {
  /// Rozette görünen etiket.
  String get label => switch (this) {
        SwipeDirection.right => 'BİLİYORUM',
        SwipeDirection.left => 'BİLMİYORUM',
        SwipeDirection.up => 'ZOR',
        SwipeDirection.down => 'ATLA',
      };

  /// Yönün rengi. PLAN.md bölüm 2.2'deki tabloya karşılık gelir.
  Color get color => switch (this) {
        SwipeDirection.right => const Color(0xFF2E9E5B), // yeşil
        SwipeDirection.left => const Color(0xFFD9A21B), // sarı
        SwipeDirection.up => const Color(0xFF2F6FD0), // mavi
        SwipeDirection.down => const Color(0xFF6B7280), // gri
      };

  /// Birim vektör. Kartın hangi yöne uçacağını belirler.
  Offset get unit => switch (this) {
        SwipeDirection.right => const Offset(1, 0),
        SwipeDirection.left => const Offset(-1, 0),
        SwipeDirection.up => const Offset(0, -1),
        SwipeDirection.down => const Offset(0, 1),
      };

  bool get isHorizontal =>
      this == SwipeDirection.left || this == SwipeDirection.right;
}
