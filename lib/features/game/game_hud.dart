import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../domain/companion.dart';
import '../../domain/game.dart';
import '../../motion/celebration.dart';
import '../../motion/motion_tokens.dart';
import '../../ui/game_ui.dart';
import '../../ui/game_companion.dart';

/// Sekmeler arasında kalan oyun durumu: oyuncu seviyesi, XP, seri ve coin.
class GameHud extends StatelessWidget {
  const GameHud({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final GameProfile profile = app.game.profile;
    final GameReward reward = app.lastReward;
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: Celebration(
        key: ValueKey<int>(app.rewardSerial),
        play: app.rewardSerial > 0 && !app.reducedMotion,
        particleCount: 18,
        duration: MotionTokens.counterRise,
        colors: const <Color>[
          GameColors.indigo,
          GameColors.gold,
          GameColors.coral,
          Colors.white,
        ],
        child: Container(
          height: 66,
          margin: const EdgeInsets.fromLTRB(12, 7, 12, 3),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                (dark ? const Color(0xFF123047) : GameColors.cream)
                    .withValues(alpha: 0.98),
                theme.colorScheme.primaryContainer
                    .withValues(alpha: dark ? 0.42 : 0.34),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.16),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: GameColors.indigo.withValues(alpha: dark ? 0.22 : 0.13),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              _LevelBadge(
                level: profile.playerLevel,
                progress: profile.levelProgress,
                app: app,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          '${profile.xp} XP',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                        if (app.streak > 0) ...<Widget>[
                          const SizedBox(width: 7),
                          Text(
                            '🔥 ${app.streak}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        const SizedBox(width: 5),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: !reward.isEmpty
                                ? AnimatedSwitcher(
                                    duration: MotionTokens.rewardPop,
                                    transitionBuilder: (
                                      Widget child,
                                      Animation<double> animation,
                                    ) =>
                                        FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.7),
                                          end: Offset.zero,
                                        ).animate(CurvedAnimation(
                                          parent: animation,
                                          curve: MotionTokens.badge,
                                        )),
                                        child: child,
                                      ),
                                    ),
                                    child: FittedBox(
                                      key: ValueKey<int>(app.rewardSerial),
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        reward.levelUp
                                            ? 'SEVİYE ATLADIN!'
                                            : '+${reward.xp} XP',
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: reward.levelUp
                                              ? GameColors.coral
                                              : theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    JuicyProgressBar(
                      value: profile.levelProgress,
                      color: theme.colorScheme.primary,
                      height: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: MotionTokens.rewardPop,
                transitionBuilder:
                    (Widget child, Animation<double> animation) =>
                        ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: MotionTokens.badge,
                  ),
                  child: child,
                ),
                child: GamePill(
                  key: ValueKey<int>(profile.coins),
                  icon: Icons.monetization_on_rounded,
                  label: '${profile.coins}',
                  color: GameColors.gold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({
    required this.level,
    required this.progress,
    required this.app,
  });

  final int level;
  final double progress;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.primary;
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(level),
      tween: Tween<double>(begin: 0.65, end: 1),
      duration: MotionTokens.rewardPop,
      curve: MotionTokens.badge,
      builder: (BuildContext context, double scale, Widget? child) =>
          Transform.scale(scale: scale, child: child),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                color: GameColors.gold,
                backgroundColor: color.withValues(alpha: 0.13),
              ),
            ),
            ClipOval(
              child: ColoredBox(
                color: app.companionPalette.color.withValues(alpha: 0.15),
                child: GameCompanion(
                  kind: app.companion,
                  accessory: app.companionAccessory,
                  color: app.companionPalette.color,
                  evolutionStage: app.companionGrowth.stage,
                  growthTitle: app.companionGrowth.title,
                  animate: false,
                  showMessage: false,
                  size: 41,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  '$level',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
