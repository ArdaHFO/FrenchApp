import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../domain/companion.dart';
import '../../domain/adventure.dart';
import '../../domain/adventure_expansion.dart';
import '../../domain/level.dart';
import '../../domain/sentence_practice.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/transitions.dart';
import '../../ui/game_companion.dart';
import '../../ui/game_ui.dart';
import '../../ui/preference_action.dart';
import '../journey/journey_map_screen.dart';
import '../game/companion_studio_screen.dart';
import 'sentence_practice_screen.dart';
import 'story_library_screen.dart';
import '../songs/song_library_screen.dart';

class PracticeHubScreen extends StatefulWidget {
  const PracticeHubScreen({super.key});

  @override
  State<PracticeHubScreen> createState() => _PracticeHubScreenState();
}

class _PracticeHubScreenState extends State<PracticeHubScreen> {
  bool _showMoreModes = false;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final ThemeData theme = Theme.of(context);
    final List<StoryAdventure> stories = storiesForLevel(app.level);
    final int completedStories = stories
        .where(
            (StoryAdventure s) => app.practice.story(s.id)?.completed ?? false)
        .length;
    final StoryAdventure story = stories.firstWhere(
      (StoryAdventure s) => !(app.practice.story(s.id)?.completed ?? false),
      orElse: () => stories.last,
    );
    final List<SentencePrompt> prompts = promptsForLevel(app.level);
    final int solved = prompts
        .where(
            (SentencePrompt p) => app.practice.sentence(p.id)?.solved ?? false)
        .length;
    final Color levelColor = AppTheme.levelColor(app.level.index);
    final int completedUnits = completedStories + solved;
    final int totalUnits = prompts.length + stories.length;
    final bool firstVisit = app.game.profile.totalCards == 0 &&
        app.game.profile.totalVerbs == 0 &&
        app.game.profile.totalAnswers == 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GameBackdrop(
        accent: levelColor,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'BUGÜN NEREYE?',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Macera Merkezi',
                                style: theme.textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Bir oyun seç, görevi tamamla ve ödülünü topla.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.60),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GamePill(
                          icon: Icons.local_fire_department_rounded,
                          label: '${app.streak} gün',
                          color: GameColors.coral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _WorldHero(
                      level: app.level,
                      color: levelColor,
                      completed: completedUnits,
                      total: totalUnits,
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          for (final CefrLevel level in CefrLevel.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _LevelChip(
                                key: ValueKey<String>('practice_${level.code}'),
                                level: level,
                                selected: level == app.level,
                                onTap: () => persistPreference(context, 'level', () => app.setLevel(level)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 30),
              sliver: SliverList.list(
                children: <Widget>[
                  if (firstVisit) ...<Widget>[
                    const StaggeredEntry(
                      index: 0,
                      child: _HowToPlay(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _SectionEyebrow(
                    label: 'BUGÜNÜN ÖNERİLEN GÖREVİ',
                    color: levelColor,
                  ),
                  const SizedBox(height: 9),
                  StaggeredEntry(
                    index: 1,
                    child: _ModeCard(
                      key: const ValueKey<String>('story_mode_card'),
                      icon: Icons.auto_stories_rounded,
                      color: levelColor,
                      accent: GameColors.violet,
                      eyebrow: 'DALLANAN HİKÂYE',
                      title: story.title,
                      description:
                          '${story.subtitle} · Bu dünyada ${stories.length} bölüm var.',
                      progress: stories.isEmpty
                          ? 0
                          : completedStories / stories.length,
                      progressLabel:
                          '$completedStories/${stories.length} bölüm tamamlandı',
                      reward: '+40 XP',
                      buttonLabel: 'Bölümleri aç',
                      onTap: () => Navigator.of(context).push(
                        fadeSlideRoute<void>(
                          StoryLibraryScreen(level: app.level),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('more_modes_toggle'),
                    onPressed: () =>
                        setState(() => _showMoreModes = !_showMoreModes),
                    icon: AnimatedRotation(
                      turns: _showMoreModes ? 0.5 : 0,
                      duration: MotionTokens.selection,
                      child: const Icon(Icons.expand_more_rounded),
                    ),
                    label: Text(
                      _showMoreModes
                          ? 'Diğer modları gizle'
                          : 'Diğer oyun modları',
                    ),
                  ),
                  AnimatedSize(
                    duration: MotionTokens.pageTransition,
                    curve: MotionTokens.settle,
                    alignment: Alignment.topCenter,
                    child: !_showMoreModes
                        ? const SizedBox.shrink()
                        : Column(
                            children: <Widget>[
                              const SizedBox(height: 16),
                              StaggeredEntry(
                                index: 2,
                                child: _ModeCard(
                                  key: const ValueKey<String>(
                                      'sentence_mode_card'),
                                  icon: Icons.edit_note_rounded,
                                  color: GameColors.coral,
                                  accent: GameColors.gold,
                                  eyebrow: 'AKTİF ÜRETİM',
                                  title: 'Cümle Atölyesi',
                                  description:
                                      'Görevli cümle çöz veya kendi metnini yaz. Ayrıntılı gramer koçluğu al.',
                                  progress: prompts.isEmpty
                                      ? 0
                                      : solved / prompts.length,
                                  progressLabel:
                                      '$solved/${prompts.length} senaryo çözüldü',
                                  reward: '+15 XP',
                                  buttonLabel: 'Yazı koçunu aç',
                                  onTap: () => Navigator.of(context).push(
                                    fadeSlideRoute<void>(
                                      SentencePracticeScreen(level: app.level),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              StaggeredEntry(
                                index: 3,
                                child: _ModeCard(
                                  key: const ValueKey<String>('song_mode_card'),
                                  icon: Icons.headphones_rounded,
                                  color: GameColors.coral,
                                  accent: GameColors.violet,
                                  eyebrow: 'MÜZİKLE ÖĞREN',
                                  title: 'Şarkı Sahnesi',
                                  description:
                                      'Şarkıyı dinle, akan sözlere dokun ve kelimeleri ritimle öğren.',
                                  progress: 0,
                                  progressLabel:
                                      '16 parça · modern ve geleneksel',
                                  reward: '+XP',
                                  buttonLabel: 'Kulaklığı tak',
                                  onTap: () => Navigator.of(context).push(
                                    fadeSlideRoute<void>(
                                        const SongLibraryScreen()),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              StaggeredEntry(
                                index: 4,
                                child: PressableScale(
                                  child: GamePanel(
                                    padding: EdgeInsets.zero,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(24),
                                        onTap: () => Navigator.of(context).push(
                                          fadeSlideRoute<void>(
                                              const JourneyMapScreen()),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(18),
                                          child: Row(
                                            children: <Widget>[
                                              Container(
                                                width: 52,
                                                height: 52,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: <Color>[
                                                      theme.colorScheme.primary,
                                                      GameColors.violet,
                                                    ],
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(17),
                                                  boxShadow: <BoxShadow>[
                                                    BoxShadow(
                                                      color: theme
                                                          .colorScheme.primary
                                                          .withValues(
                                                              alpha: 0.26),
                                                      blurRadius: 14,
                                                      offset:
                                                          const Offset(0, 7),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.route_rounded,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              const Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: <Widget>[
                                                    Text(
                                                      'Ders Yolculuğu',
                                                      style: TextStyle(
                                                        fontSize: 17,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                    SizedBox(height: 3),
                                                    Text(
                                                        'Durakları geç · yıldızları topla'),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: theme
                                                      .colorScheme.primary
                                                      .withValues(alpha: 0.10),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.arrow_forward_rounded,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldHero extends StatelessWidget {
  const _WorldHero({
    required this.level,
    required this.color,
    required this.completed,
    required this.total,
  });

  final CefrLevel level;
  final Color color;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final CompanionGrowth growth = app.companionGrowth;
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 174,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            color,
            Color.lerp(color, GameColors.violet, 0.55)!,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: 0.30),
            blurRadius: 28,
            offset: const Offset(0, 13),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            right: -14,
            bottom: -7,
            child: Semantics(
              label: 'Karakterini değiştir',
              button: true,
              child: GestureDetector(
                key: const ValueKey<String>('open_companion_studio'),
                onTap: () => Navigator.of(context).push(
                  fadeSlideRoute<void>(const CompanionStudioScreen()),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Hero(
                      tag: 'player_companion',
                      child: GameCompanion(
                        key: const ValueKey<String>('game_companion'),
                        kind: app.companion,
                        accessory: app.companionAccessory,
                        color: app.companionPalette.color,
                        size: 136,
                        evolutionStage: growth.stage,
                        growthTitle: growth.title,
                        message: app.companion.encouragement(
                          streak: app.streak,
                          goalReached: app.goalReachedToday,
                          completed: completed,
                          total: total,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 4,
                      child: Container(
                        width: 31,
                        height: 31,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: app.companionPalette.color,
                            width: 2,
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(color: Colors.black26, blurRadius: 8),
                          ],
                        ),
                        child: Icon(
                          Icons.edit_rounded,
                          size: 17,
                          color: app.companionPalette.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 102),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    '${level.code} DÜNYASI',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  level.worldName,
                  maxLines: 2,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Dünya ilerlemesi',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: JuicyProgressBar(
                        value: total == 0 ? 0 : completed / total,
                        color: GameColors.gold,
                        height: 8,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      '$completed/$total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
        ],
      );
}

class _HowToPlay extends StatefulWidget {
  const _HowToPlay();

  @override
  State<_HowToPlay> createState() => _HowToPlayState();
}

class _HowToPlayState extends State<_HowToPlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GamePanel(
      padding: const EdgeInsets.fromLTRB(15, 8, 10, 8),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            key: const ValueKey<String>('how_to_play_toggle'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.lightbulb_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Nasıl oynanır?',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: MotionTokens.selection,
                    child: const Icon(Icons.expand_more_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: MotionTokens.pageTransition,
            curve: MotionTokens.settle,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox.shrink()
                : const Padding(
                    padding: EdgeInsets.only(top: 11, bottom: 6),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _HowStep(
                            icon: Icons.touch_app_rounded,
                            number: '1',
                            label: 'Modunu seç',
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                        Expanded(
                          child: _HowStep(
                            icon: Icons.sports_esports_rounded,
                            number: '2',
                            label: 'Görevi bitir',
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                        Expanded(
                          child: _HowStep(
                            icon: Icons.stars_rounded,
                            number: '3',
                            label: 'XP kazan',
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HowStep extends StatelessWidget {
  const _HowStep({
    required this.icon,
    required this.number,
    required this.label,
  });

  final IconData icon;
  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.primary;
    return Column(
      children: <Widget>[
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            Positioned(
              right: -3,
              top: -4,
              child: Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  number,
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
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            height: 1.05,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    super.key,
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final CefrLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = AppTheme.levelColor(level.index);
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: MotionTokens.selection,
            width: selected ? 60 : 50,
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? color : color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? color : color.withValues(alpha: 0.18),
              ),
              boxShadow: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: color.withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              level.code,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.color,
    required this.accent,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.progress,
    required this.progressLabel,
    required this.reward,
    required this.buttonLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color accent;
  final String eyebrow;
  final String title;
  final String description;
  final double progress;
  final String progressLabel;
  final String reward;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return PressableScale(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              color.withValues(alpha: dark ? 0.25 : 0.15),
              theme.colorScheme.surfaceContainerHigh,
              accent.withValues(alpha: dark ? 0.14 : 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: color.withValues(alpha: 0.20)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: dark ? 0.14 : 0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              children: <Widget>[
                Positioned(
                  right: -24,
                  top: -22,
                  child: Icon(
                    icon,
                    size: 145,
                    color: color.withValues(alpha: 0.075),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(21),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: <Color>[color, accent]),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: color.withValues(alpha: 0.28),
                                  blurRadius: 13,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(icon, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              eyebrow,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          GamePill(
                            icon: Icons.bolt_rounded,
                            label: reward,
                            color: GameColors.gold,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(title, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 7),
                      Text(
                        description,
                        style: TextStyle(
                          height: 1.35,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 17),
                      JuicyProgressBar(
                          value: progress, color: color, height: 9),
                      const SizedBox(height: 8),
                      Text(
                        progressLabel,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: onTap,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(buttonLabel),
                        style: FilledButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          shadowColor: color.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
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
