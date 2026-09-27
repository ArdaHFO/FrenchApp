import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../domain/companion.dart';
import '../../motion/motion_tokens.dart';
import '../../ui/game_companion.dart';
import '../../ui/game_ui.dart';

/// Oyuncunun yol arkadaşını, rengini ve aksesuarını değiştirdiği alan.
class CompanionStudioScreen extends StatelessWidget {
  const CompanionStudioScreen({super.key});

  void _locked(BuildContext context, int level) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bu seçim oyuncu seviyesi $level’de açılır.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final ThemeData theme = Theme.of(context);
    final int playerLevel = app.game.profile.playerLevel;
    final int xp = app.game.profile.xp;
    final CompanionGrowth growth = app.companionGrowth;
    final Color accent = app.companionPalette.color;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Karakter Stüdyosu')),
      body: GameBackdrop(
        accent: accent,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
            children: <Widget>[
              GamePanel(
                color: accent.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.20 : 0.10,
                ),
                borderColor: accent.withValues(alpha: 0.28),
                child: Row(
                  children: <Widget>[
                    Hero(
                      tag: 'player_companion',
                      child: GameCompanion(
                        kind: app.companion,
                        accessory: app.companionAccessory,
                        color: accent,
                        evolutionStage: growth.stage,
                        growthTitle: growth.title,
                        message: app.companion.encouragement(
                          streak: app.streak,
                          goalReached: app.goalReachedToday,
                          completed: app.game.profile.stationsPassed,
                          total: 0,
                        ),
                        size: 138,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            app.companion.label,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${app.companion.species} · ${app.companion.motto}',
                            style: TextStyle(
                              height: 1.35,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            growth.title,
                            key: const ValueKey<String>(
                                'companion_growth_title'),
                            style: const TextStyle(
                              color: GameColors.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 11),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: GamePill(
                                icon: Icons.stars_rounded,
                                label: 'Oyuncu seviyesi $playerLevel',
                                color: GameColors.gold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _GrowthCard(
                name: app.companion.label,
                growth: growth,
                xp: xp,
                color: accent,
              ),
              const SizedBox(height: 24),
              const _SectionTitle(
                title: 'Yol arkadaşını seç',
                subtitle: 'Seviye atladıkça yeni arkadaşlar ekibe katılır.',
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 11,
                crossAxisSpacing: 11,
                childAspectRatio: 1.08,
                children: <Widget>[
                  for (final CompanionKind kind in CompanionKind.values)
                    _CharacterCard(
                      key: ValueKey<String>('character_${kind.name}'),
                      kind: kind,
                      color: accent,
                      selected: kind == app.companion,
                      unlocked: playerLevel >= kind.unlockLevel,
                      onTap: () => playerLevel >= kind.unlockLevel
                          ? app.setCompanion(kind)
                          : _locked(context, kind.unlockLevel),
                    ),
                ],
              ),
              const SizedBox(height: 25),
              const _SectionTitle(
                title: 'Renk enerjisi',
                subtitle: 'Karakterin oyun dünyasında bu renkle parlar.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  for (final CompanionPalette palette
                      in CompanionPalette.values)
                    Semantics(
                      label: palette.label,
                      button: true,
                      selected: palette == app.companionPalette,
                      child: InkWell(
                        key: ValueKey<String>('palette_${palette.name}'),
                        onTap: () => app.setCompanionPalette(palette),
                        borderRadius: BorderRadius.circular(99),
                        child: AnimatedContainer(
                          duration: MotionTokens.selection,
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: palette.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: palette == app.companionPalette ? 4 : 1,
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: palette.color.withValues(alpha: 0.35),
                                blurRadius:
                                    palette == app.companionPalette ? 16 : 6,
                              ),
                            ],
                          ),
                          child: palette == app.companionPalette
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 25),
              const _SectionTitle(
                title: 'Aksesuar dolabı',
                subtitle: 'Görevlerle seviye kazan, yeni parçaları aç.',
              ),
              const SizedBox(height: 12),
              for (final CompanionAccessory accessory
                  in CompanionAccessory.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _AccessoryTile(
                    key: ValueKey<String>('accessory_${accessory.name}'),
                    accessory: accessory,
                    selected: accessory == app.companionAccessory,
                    unlocked: playerLevel >= accessory.unlockLevel,
                    color: accent,
                    onTap: () => playerLevel >= accessory.unlockLevel
                        ? app.setCompanionAccessory(accessory)
                        : _locked(context, accessory.unlockLevel),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrowthCard extends StatelessWidget {
  const _GrowthCard({
    required this.name,
    required this.growth,
    required this.xp,
    required this.color,
  });

  final String name;
  final CompanionGrowth growth;
  final int xp;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final int? remaining = growth.remainingXpFor(xp);
    return GamePanel(
      padding: const EdgeInsets.all(15),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.auto_awesome_rounded, color: GameColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$name ile bağın',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${growth.stage + 1}/4',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 11),
          JuicyProgressBar(
            value: growth.progressFor(xp),
            color: color,
            height: 9,
          ),
          const SizedBox(height: 7),
          Text(
            remaining == null
                ? 'En güçlü bağa ulaştınız. Birlikte efsanesiniz.'
                : 'Bir sonraki forma $remaining XP kaldı.',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.62),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.60),
            ),
          ),
        ],
      );
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    super.key,
    required this.kind,
    required this.color,
    required this.selected,
    required this.unlocked,
    required this.onTap,
  });

  final CompanionKind kind;
  final Color color;
  final bool selected;
  final bool unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return PressableScale(
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.16)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: MotionTokens.selection,
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? color
                    : theme.colorScheme.onSurface.withValues(alpha: 0.08),
                width: selected ? 2 : 1,
              ),
            ),
            child: Stack(
              children: <Widget>[
                Opacity(
                  opacity: unlocked ? 1 : 0.40,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: GameCompanion(
                          kind: kind,
                          accessory: CompanionAccessory.none,
                          color: color,
                          animate: false,
                          showMessage: false,
                          size: 103,
                        ),
                      ),
                      Text(kind.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                      Text(kind.species,
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.55))),
                    ],
                  ),
                ),
                if (!unlocked)
                  Positioned(
                    right: 3,
                    top: 3,
                    child: GamePill(
                      icon: Icons.lock_rounded,
                      label: 'SV ${kind.unlockLevel}',
                      color: GameColors.gold,
                    ),
                  ),
                if (selected)
                  Positioned(
                    right: 3,
                    top: 3,
                    child: Icon(Icons.check_circle_rounded, color: color),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessoryTile extends StatelessWidget {
  const _AccessoryTile({
    super.key,
    required this.accessory,
    required this.selected,
    required this.unlocked,
    required this.color,
    required this.onTap,
  });

  final CompanionAccessory accessory;
  final bool selected;
  final bool unlocked;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: selected
          ? color.withValues(alpha: 0.13)
          : theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(17),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(
            color: selected
                ? color
                : theme.colorScheme.onSurface.withValues(alpha: 0.07),
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: unlocked ? 0.16 : 0.06),
          child: Icon(
            unlocked ? accessory.icon : Icons.lock_rounded,
            color: unlocked
                ? color
                : theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
        title: Text(
          accessory.label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: unlocked
                ? null
                : theme.colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
        subtitle: unlocked
            ? Text(selected ? 'Şu an üzerinde' : 'Kullanıma hazır')
            : Text('Oyuncu seviyesi ${accessory.unlockLevel}’de açılır'),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: color)
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
