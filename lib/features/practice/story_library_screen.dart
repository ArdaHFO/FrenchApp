import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../domain/adventure.dart';
import '../../domain/adventure_expansion.dart';
import '../../domain/level.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/transitions.dart';
import '../../ui/game_ui.dart';
import 'story_adventure_screen.dart';

class StoryLibraryScreen extends StatefulWidget {
  const StoryLibraryScreen({super.key, required this.level});

  final CefrLevel level;

  @override
  State<StoryLibraryScreen> createState() => _StoryLibraryScreenState();
}

class _StoryLibraryScreenState extends State<StoryLibraryScreen> {
  Future<void> _open(StoryAdventure story, bool unlocked) async {
    if (!unlocked) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce bir önceki bölümü tamamla.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      fadeSlideRoute<void>(StoryAdventureScreen(story: story)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final ThemeData theme = Theme.of(context);
    final Color color = AppTheme.levelColor(widget.level.index);
    final List<StoryAdventure> stories = storiesForLevel(widget.level);
    final int completed = stories
        .where((StoryAdventure s) => app.practice.story(s.id)?.completed ?? false)
        .length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Hikâye Dünyası')),
      body: GameBackdrop(
        accent: color,
        child: SafeArea(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          color,
                          Color.lerp(color, GameColors.violet, 0.55)!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: color.withValues(alpha: 0.28),
                          blurRadius: 24,
                          offset: const Offset(0, 11),
                        ),
                      ],
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(
                            Icons.auto_stories_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '${widget.level.code} · ${widget.level.worldName}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$completed/${stories.length} bölüm tamamlandı',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 9),
                              JuicyProgressBar(
                                value: stories.isEmpty
                                    ? 0
                                    : completed / stories.length,
                                color: GameColors.gold,
                                height: 8,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                sliver: SliverList.builder(
                  itemCount: stories.length,
                  itemBuilder: (BuildContext context, int index) {
                    final StoryAdventure story = stories[index];
                    final StoryProgress? progress = app.practice.story(story.id);
                    final bool completed = progress?.completed ?? false;
                    final bool unlocked = index == 0 ||
                        (app.practice.story(stories[index - 1].id)?.completed ??
                            false);
                    return StaggeredEntry(
                      index: index,
                      perItemDelay: const Duration(milliseconds: 90),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 15),
                        child: _ChapterCard(
                          story: story,
                          progress: progress,
                          color: color,
                          unlocked: unlocked,
                          completed: completed,
                          last: index == stories.length - 1,
                          onTap: () => _open(story, unlocked),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.story,
    required this.progress,
    required this.color,
    required this.unlocked,
    required this.completed,
    required this.last,
    required this.onTap,
  });

  final StoryAdventure story;
  final StoryProgress? progress;
  final Color color;
  final bool unlocked;
  final bool completed;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color stateColor = completed
        ? GameColors.mint
        : unlocked
            ? color
            : theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 48,
          child: Column(
            children: <Widget>[
              AnimatedContainer(
                duration: MotionTokens.rewardPop,
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: unlocked
                      ? LinearGradient(colors: <Color>[stateColor, color])
                      : null,
                  color: unlocked ? null : stateColor.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: stateColor.withValues(alpha: unlocked ? 0.55 : 0.18),
                    width: 2,
                  ),
                  boxShadow: unlocked
                      ? <BoxShadow>[
                          BoxShadow(
                            color: stateColor.withValues(alpha: 0.25),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  completed
                      ? Icons.check_rounded
                      : unlocked
                          ? Icons.play_arrow_rounded
                          : Icons.lock_rounded,
                  color: unlocked ? Colors.white : stateColor,
                ),
              ),
              if (!last)
                Container(
                  width: 3,
                  height: 178,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        stateColor.withValues(alpha: 0.45),
                        stateColor.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: PressableScale(
            child: Opacity(
              opacity: unlocked ? 1 : 0.62,
              child: GamePanel(
                padding: EdgeInsets.zero,
                borderColor: stateColor.withValues(alpha: 0.18),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: stateColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  'BÖLÜM ${story.chapter}',
                                  style: TextStyle(
                                    color: stateColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              const GamePill(
                                icon: Icons.bolt_rounded,
                                label: '+40 XP',
                                color: GameColors.gold,
                              ),
                            ],
                          ),
                          const SizedBox(height: 13),
                          Text(story.title, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 5),
                          Text(
                            story.subtitle,
                            style: TextStyle(
                              height: 1.3,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.68),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: <Widget>[
                              Icon(Icons.alt_route_rounded,
                                  size: 17, color: stateColor),
                              const SizedBox(width: 5),
                              const Expanded(
                                child: Text(
                                  'Dallanan seçimler',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    completed
                                        ? '${progress!.bestCorrect}/${progress!.bestTotal} doğru'
                                        : unlocked
                                            ? 'Oyna'
                                            : 'Kilitli',
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: stateColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
