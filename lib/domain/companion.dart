import 'package:flutter/material.dart';

/// Oyuncunun yanında gezen karakterler.
enum CompanionKind { lumi, moka, pipou, nox }

/// Yol arkadaşının oyuncuyla birlikte gelişen bağ aşaması.
///
/// Ayrı bir ilerleme kaydı tutulmaz. Aşama doğrudan kazanılmış XP'den
/// hesaplandığı için yedekleme, geri yükleme ve eski kayıtlarla uyumludur.
class CompanionGrowth {
  const CompanionGrowth._({
    required this.stage,
    required this.title,
    required this.startXp,
    required this.nextXp,
  });

  final int stage;
  final String title;
  final int startXp;
  final int? nextXp;

  static CompanionGrowth forXp(int xp) {
    if (xp >= 2500) {
      return const CompanionGrowth._(
        stage: 3,
        title: 'Efsane Yol Arkadaşı',
        startXp: 2500,
        nextXp: null,
      );
    }
    if (xp >= 900) {
      return const CompanionGrowth._(
        stage: 2,
        title: 'Cesur Rehber',
        startXp: 900,
        nextXp: 2500,
      );
    }
    if (xp >= 250) {
      return const CompanionGrowth._(
        stage: 1,
        title: 'Takım Arkadaşı',
        startXp: 250,
        nextXp: 900,
      );
    }
    return const CompanionGrowth._(
      stage: 0,
      title: 'Yeni Dost',
      startXp: 0,
      nextXp: 250,
    );
  }

  double progressFor(int xp) {
    final int? target = nextXp;
    if (target == null) return 1;
    return ((xp - startXp) / (target - startXp)).clamp(0, 1);
  }

  int? remainingXpFor(int xp) {
    final int? target = nextXp;
    return target == null ? null : (target - xp).clamp(0, target);
  }
}

extension CompanionKindX on CompanionKind {
  String get label => switch (this) {
        CompanionKind.lumi => 'Lumi',
        CompanionKind.moka => 'Moka',
        CompanionKind.pipou => 'Pipou',
        CompanionKind.nox => 'Nox',
      };

  String get species => switch (this) {
        CompanionKind.lumi => 'Tilki',
        CompanionKind.moka => 'Kedi',
        CompanionKind.pipou => 'Kurbağa',
        CompanionKind.nox => 'Baykuş',
      };

  String get motto => switch (this) {
        CompanionKind.lumi => 'Merakla keşfet',
        CompanionKind.moka => 'Sakin kal, devam et',
        CompanionKind.pipou => 'Hatalardan sıçra',
        CompanionKind.nox => 'Bilgiyi biriktir',
      };

  /// Her karakter aynı duruma kendi kişiliğiyle cevap verir.
  String encouragement({
    required int streak,
    required bool goalReached,
    required int completed,
    required int total,
  }) {
    if (goalReached) {
      return switch (this) {
        CompanionKind.lumi => 'Bugün ışıldadın!',
        CompanionKind.moka => 'Ritmini buldun.',
        CompanionKind.pipou => 'Zıpla, hedef tamam!',
        CompanionKind.nox => 'Plan kusursuzdu.',
      };
    }
    if (total > 0 && completed >= total) {
      return switch (this) {
        CompanionKind.lumi => 'Dünyayı keşfettik!',
        CompanionKind.moka => 'Sakin ve sağlam.',
        CompanionKind.pipou => 'Hepsini geçtik!',
        CompanionKind.nox => 'Arşiv tamamlandı.',
      };
    }
    if (streak >= 3) {
      return switch (this) {
        CompanionKind.lumi => '$streak günlük keşif!',
        CompanionKind.moka => '$streak gün, güzel ritim.',
        CompanionKind.pipou => '$streak günlük seri!',
        CompanionKind.nox => '$streak gün kayıtlarda.',
      };
    }
    if (completed == 0) {
      return switch (this) {
        CompanionKind.lumi => 'İlk izi bulalım!',
        CompanionKind.moka => 'Bir adım yeter.',
        CompanionKind.pipou => 'Hadi başlayalım!',
        CompanionKind.nox => 'İlk ders hazır.',
      };
    }
    return switch (this) {
      CompanionKind.lumi => 'Sıradaki ipucu hazır!',
      CompanionKind.moka => 'Aynı ritimde devam.',
      CompanionKind.pipou => 'Yeni görev, yeni sıçrayış!',
      CompanionKind.nox => 'Bilgiyi büyütelim.',
    };
  }

  int get unlockLevel => switch (this) {
        CompanionKind.lumi || CompanionKind.moka => 1,
        CompanionKind.pipou => 2,
        CompanionKind.nox => 3,
      };

  static CompanionKind fromKey(String? key) => CompanionKind.values.firstWhere(
        (CompanionKind value) => value.name == key,
        orElse: () => CompanionKind.lumi,
      );
}

enum CompanionAccessory { none, beret, headphones, crown }

extension CompanionAccessoryX on CompanionAccessory {
  String get label => switch (this) {
        CompanionAccessory.none => 'Sade',
        CompanionAccessory.beret => 'Fransız beresi',
        CompanionAccessory.headphones => 'Kulaklık',
        CompanionAccessory.crown => 'Taç',
      };

  IconData get icon => switch (this) {
        CompanionAccessory.none => Icons.face_rounded,
        CompanionAccessory.beret => Icons.palette_rounded,
        CompanionAccessory.headphones => Icons.headphones_rounded,
        CompanionAccessory.crown => Icons.workspace_premium_rounded,
      };

  int get unlockLevel => switch (this) {
        CompanionAccessory.none || CompanionAccessory.beret => 1,
        CompanionAccessory.headphones => 2,
        CompanionAccessory.crown => 4,
      };

  static CompanionAccessory fromKey(String? key) =>
      CompanionAccessory.values.firstWhere(
        (CompanionAccessory value) => value.name == key,
        orElse: () => CompanionAccessory.beret,
      );
}

enum CompanionPalette { indigo, coral, mint, sky, gold }

extension CompanionPaletteX on CompanionPalette {
  String get label => switch (this) {
        CompanionPalette.indigo => 'Gece mavisi',
        CompanionPalette.coral => 'Mercan',
        CompanionPalette.mint => 'Nane',
        CompanionPalette.sky => 'Gökyüzü',
        CompanionPalette.gold => 'Bal',
      };

  Color get color => switch (this) {
        CompanionPalette.indigo => const Color(0xFF2477E8),
        CompanionPalette.coral => const Color(0xFFFF6B6B),
        CompanionPalette.mint => const Color(0xFF35C98A),
        CompanionPalette.sky => const Color(0xFF3097E8),
        CompanionPalette.gold => const Color(0xFFE5A92F),
      };

  static CompanionPalette fromKey(String? key) =>
      CompanionPalette.values.firstWhere(
        (CompanionPalette value) => value.name == key,
        orElse: () => CompanionPalette.indigo,
      );
}
