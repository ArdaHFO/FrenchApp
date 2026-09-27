import 'package:flutter/material.dart';

import '../features/grammar/grammar_screens.dart';
import '../features/game/game_hud.dart';
import '../features/progress/progress_screen.dart';
import '../features/practice/practice_hub_screen.dart';
import '../features/verbs/verb_screens.dart';
import '../features/vocab/deck_select_screen.dart';
import '../motion/motion_tokens.dart';

/// Beş sekmeli ana kabuk. PLAN.md bölüm 4.
///
/// [IndexedStack] kullanılıyor, böylece sekme değiştirince ekranların durumu
/// korunuyor (deste filtresi, kaydırma konumu gibi).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  final List<Widget?> _pages = List<Widget?>.filled(5, null);

  /// Sekme değişiminde çalışan kısa soldurma.
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _pages[0] = const DeckSelectScreen();
    _fade = AnimationController(
      vsync: this,
      duration: MotionTokens.pageTransition,
      value: 1,
    );
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _pages[i] ??= _buildPage(i);
    });
    _fade.forward(from: 0);
  }

  Widget _buildPage(int index) => switch (index) {
        0 => const DeckSelectScreen(),
        1 => const VerbDeckScreen(),
        2 => const GrammarListScreen(),
        3 => const PracticeHubScreen(),
        _ => const ProgressScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Sekme geçişi.
      //
      // AnimatedSwitcher kullanılamaz: anahtarı değişen bir alt ağaç
      // yeniden kurulur ve IndexedStack'in koruduğu sekme durumu
      // (deste filtresi, kaydırma konumu) uçar. Onun yerine yığının
      // KENDİSİ soldurulup hafifçe yükseltiliyor; ağaç aynı kalıyor.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const GameHud(),
            Expanded(
              child: AnimatedBuilder(
                animation: _fade,
                builder: (BuildContext context, Widget? child) {
                  final double t = MotionTokens.settle.transform(_fade.value);
                  return Opacity(
                    opacity: 0.3 + 0.7 * t,
                    child: Transform.translate(
                      offset: Offset(0, 8 * (1 - t)),
                      child: child,
                    ),
                  );
                },
                child: IndexedStack(
                  index: _index,
                  children: List<Widget>.generate(
                    _pages.length,
                    (int i) => TickerMode(
                      enabled: i == _index,
                      child: _pages[i] ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: <BoxShadow>[
            BoxShadow(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
              blurRadius: 22,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: <Widget>[
            _dest(0, Icons.style_outlined, Icons.style_rounded, 'Kelimeler'),
            _dest(1, Icons.change_circle_outlined, Icons.change_circle_rounded,
                'Fiiller'),
            _dest(2, Icons.menu_book_outlined, Icons.menu_book_rounded,
                'Dilbilgisi'),
            _dest(3, Icons.explore_outlined, Icons.explore_rounded, 'Macera'),
            _dest(
                4, Icons.insights_outlined, Icons.insights_rounded, 'İlerleme'),
          ],
        ),
      ),
    );
  }

  NavigationDestination _dest(
    int index,
    IconData icon,
    IconData selectedIcon,
    String label,
  ) {
    return NavigationDestination(
      icon: Icon(icon),
      selectedIcon: _BouncyIcon(icon: selectedIcon, trigger: _index == index),
      label: label,
    );
  }
}

/// Seçili sekme ikonu bir anlık büyüyüp normale döner.
/// PLAN.md bölüm 6.6: 200 ms, easeOutBack, ölçek 1.0 -> 1.15 -> 1.0.
class _BouncyIcon extends StatefulWidget {
  const _BouncyIcon({required this.icon, required this.trigger});

  final IconData icon;
  final bool trigger;

  @override
  State<_BouncyIcon> createState() => _BouncyIconState();
}

class _BouncyIconState extends State<_BouncyIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionTokens.selection,
  );

  @override
  void initState() {
    super.initState();
    if (widget.trigger) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _BouncyIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger && !oldWidget.trigger) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: Icon(widget.icon),
      builder: (BuildContext context, Widget? child) {
        // Gidip gelen tek darbe: ortada en büyük.
        final double t = _controller.value;
        final double pulse = t <= 0 || t >= 1 ? 0 : (1 - (2 * t - 1).abs());
        return Transform.scale(scale: 1 + 0.15 * pulse, child: child);
      },
    );
  }
}
