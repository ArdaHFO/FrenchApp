import 'package:flutter/material.dart';

import '../ui/game_ui.dart';

class AppTheme {
  AppTheme._();

  static const Color seed = GameColors.frenchBlue;

  static const Color darkSurface = Color(0xFF071A2B);
  static const Color darkCard = Color(0xFF10283A);
  static const Color lightSurface = Color(0xFFF7F3EA);
  static const Color lightCard = Color(0xFFFFFCF6);

  /// Seviye rengi. Kart ve rozetlerde tutarlı bir renk dili kurar:
  /// kolaydan zora doğru yeşilden sıcak mercana. Kullanıcı kartın seviyesini
  /// yazıyı okumadan, göz ucuyla anlar.
  static const List<Color> levelColors = <Color>[
    Color(0xFF35A66F), // A1
    Color(0xFF73A936), // A2
    Color(0xFF1594A8), // B1
    Color(0xFF2D70D6), // B2
    Color(0xFFD28B2D), // C1
    Color(0xFFE05D52), // C2
  ];

  static Color levelColor(int index) =>
      levelColors[index.clamp(0, levelColors.length - 1)];

  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    ).copyWith(
      primary: seed,
      secondary: GameColors.coral,
      tertiary: GameColors.gold,
      surface: isDark ? darkSurface : lightSurface,
      surfaceContainer: isDark ? const Color(0xFF0D2233) : lightCard,
      surfaceContainerHigh:
          isDark ? const Color(0xFF163247) : const Color(0xFFF0E9DD),
    );
    final TextTheme text = ThemeData(brightness: brightness).textTheme;
    final BorderRadius cardRadius = BorderRadius.circular(22);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? darkSurface : lightSurface,
      textTheme: text.copyWith(
        headlineLarge: text.headlineLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.7,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark ? darkCard : lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: cardRadius,
          side: BorderSide(
            color: scheme.onSurface.withValues(alpha: isDark ? 0.11 : 0.07),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.all(18),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: (isDark ? const Color(0xFF0C2233) : lightCard)
            .withValues(alpha: 0.98),
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w900
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.onSurface.withValues(alpha: 0.08),
      ),
    );
  }

  /// Kart yüzeyinin rengi. Tema koyu ya da açık olabilir.
  static Color cardColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkCard : lightCard;
}
