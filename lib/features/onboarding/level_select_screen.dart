import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../domain/level.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/transitions.dart';
import '../../ui/game_companion.dart';
import '../../ui/game_ui.dart';
import 'placement_test_screen.dart';

/// İlk açılış: seviye ve günlük hedef seçimi.
/// PLAN.md bölüm 3.1'deki akışa karşılık gelir.
class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key, this.isSettingsMode = false});

  /// Ayarlardan açıldığında başlık ve düğme metni değişir.
  final bool isSettingsMode;

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  CefrLevel? _selected;
  int _goal = 20;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.isSettingsMode) {
      // Ayarlardan gelindiyse mevcut seçim önceden işaretli gelsin.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = AppScope.of(context);
        setState(() {
          _selected = state.level;
          _goal = state.dailyGoal;
        });
      });
    }
  }

  Future<void> _openPlacementTest() async {
    final CefrLevel? result = await Navigator.of(context).push<CefrLevel>(
      fadeSlideRoute<CefrLevel>(const PlacementTestScreen()),
    );
    if (result != null && mounted) {
      setState(() => _selected = result);
    }
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    final state = AppScope.of(context);
    try {
      await state.confirmLearningSettings(level: _selected ?? CefrLevel.a1,
          goal: _goal, finishOnboarding: !widget.isSettingsMode);
      if (widget.isSettingsMode) {
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sonuç kaydedilemedi. Tekrar deneyin.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      appBar: widget.isSettingsMode
          ? AppBar(title: const Text('Seviye ve hedef'))
          : null,
      body: GameBackdrop(
        accent: GameColors.frenchBlue,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  children: <Widget>[
                    if (!widget.isSettingsMode) ...<Widget>[
                      const _OnboardingHero(),
                      const SizedBox(height: 20),
                    ],
                    for (int i = 0; i < CefrLevel.values.length; i++)
                      StaggeredEntry(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _LevelCard(
                            level: CefrLevel.values[i],
                            selected: _selected == CefrLevel.values[i],
                            onTap: () =>
                                setState(() => _selected = CefrLevel.values[i]),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton.icon(
                        onPressed: _openPlacementTest,
                        icon: const Icon(Icons.help_outline_rounded, size: 18),
                        label: const Text('Seviyemi bilmiyorum'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Günlük hedef',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '20 kart yaklaşık üç dakika sürer.',
                      style: TextStyle(fontSize: 13, color: faint),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: <Widget>[
                        for (final int g in <int>[10, 20, 40])
                          ChoiceChip(
                            label: Text('$g kart'),
                            selected: _goal == g,
                            onSelected: (_) => setState(() => _goal = g),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selected == null || _saving ? null : _confirm,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.isSettingsMode ? 'Kaydet' : 'Başla'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final CefrLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Her seviye kendi rengiyle: A1 yeşilden C2 sıcak mercana doğru.
    final Color accent = AppTheme.levelColor(level.index);

    return AnimatedContainer(
      duration: MotionTokens.selection,
      curve: MotionTokens.settle,
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? accent
              : theme.colorScheme.onSurface.withValues(alpha: 0.10),
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? accent : accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    level.code,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : accent,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    level.descriptionTr,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: selected ? 0.95 : 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingHero extends StatelessWidget {
  const _OnboardingHero();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GamePanel(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      color: GameColors.frenchBlue.withValues(alpha: 0.12),
      borderColor: GameColors.frenchBlue.withValues(alpha: 0.28),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: GameColors.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'İLK GÖREV  •  ROTANI ÇİZ',
                    style: TextStyle(
                      color: GameColors.gold,
                      fontSize: 9,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Seviyeni seç',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Sana uygun Fransızca dünyasından başlayalım.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const GameCompanion(
            color: GameColors.frenchBlue,
            message: 'Salut!',
            size: 106,
          ),
        ],
      ),
    );
  }
}
