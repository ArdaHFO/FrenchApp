import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../domain/companion.dart';
import '../../domain/game.dart';
import '../../domain/level.dart';
import '../../domain/srs/box_scheduler.dart';
import '../../domain/srs/srs_card.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/transitions.dart';
import '../../ui/game_companion.dart';
import '../../ui/preference_action.dart';
import '../game/companion_studio_screen.dart';
import '../onboarding/level_select_screen.dart';
import '../prototype/prototype_screen.dart';
import 'about_screen.dart';
import 'activity_heatmap.dart';
import 'backup_screen.dart';

/// İlerleme ve ayarlar. PLAN.md bölüm 4, beşinci sekme.
///
/// Seri sayacı ve günlük hedef çalışıyor; 30 günlük grafik henüz yok.
/// Burada sadece gerçekten ölçebildiklerimiz gösteriliyor.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    final Map<String, SrsCard> states = app.cards.snapshot();
    final int seen = states.length;
    final int known = states.values
        .where((SrsCard c) =>
            c.status == CardStatus.known || c.status == CardStatus.mastered)
        .length;
    final int mastered = states.values
        .where((SrsCard c) => c.status == CardStatus.mastered)
        .length;
    final Map<int, int> histogram = app.cards.boxHistogram();
    final int leeches = app.cards.leeches().length;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: <Widget>[
            Text(
              'İlerleme',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            _StreakCard(
              streak: app.streak,
              today: app.swipedToday,
              goal: app.dailyGoal,
            ),
            const SizedBox(height: 16),
            _GameProfileCard(profile: app.game.profile),
            const SizedBox(height: 22),
            Text('Günlük görevler', style: _sectionStyle(theme)),
            const SizedBox(height: 10),
            for (final DailyQuest quest in app.game.quests)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _QuestTile(quest: quest),
              ),
            const SizedBox(height: 16),
            Text('Başarımlar', style: _sectionStyle(theme)),
            const SizedBox(height: 10),
            _AchievementGrid(
              unlocked: app.game.unlockedAchievements,
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(child: _SummaryTile(value: seen, label: 'görülen')),
                const SizedBox(width: 10),
                Expanded(child: _SummaryTile(value: known, label: 'bilinen')),
                const SizedBox(width: 10),
                Expanded(
                    child: _SummaryTile(value: mastered, label: 'pekişmiş')),
              ],
            ),
            const SizedBox(height: 26),
            Text('Son 30 gün', style: _sectionStyle(theme)),
            Text(
              'Koyu kare çok kart demek. Çerçeveli olan bugün.',
              style: TextStyle(fontSize: 13, color: faint),
            ),
            const SizedBox(height: 12),
            ActivityHeatmap(stats: app.stats, goal: app.dailyGoal),

            const SizedBox(height: 26),
            Text(
              'Kutu dağılımı',
              style: _sectionStyle(theme),
            ),
            Text(
              'Kart yukarı çıktıkça tekrar aralığı uzar.',
              style: TextStyle(fontSize: 13, color: faint),
            ),
            const SizedBox(height: 12),
            for (int box = 0; box <= 5; box++)
              _BoxRow(
                box: box,
                count: histogram[box] ?? 0,
                maxCount: histogram.values.isEmpty
                    ? 1
                    : histogram.values.reduce((int a, int b) => a > b ? a : b),
              ),

            const SizedBox(height: 22),
            Text('Seviye ilerlemesi', style: _sectionStyle(theme)),
            const SizedBox(height: 10),
            for (final CefrLevel level in CefrLevel.values)
              _LevelBar(
                level: level,
                known: _knownInLevel(app, level),
                total:
                    app.words.candidateIds(levels: <CefrLevel>[level]).length,
                isCurrent: level == app.level,
              ),

            if (leeches > 0) ...<Widget>[
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFD9A21B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFD9A21B)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$leeches kelimede takıldın. Kelimeler sekmesindeki '
                        '"Zorlandıklarım" destesinden çalışabilirsin.',
                        style: TextStyle(fontSize: 13, color: faint),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 30),
            Text('Ayarlar', style: _sectionStyle(theme)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.school_rounded),
              title: const Text('Seviye ve günlük hedef'),
              subtitle: Text('${app.level.code} · ${app.dailyGoal} kart'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                fadeSlideRoute<void>(
                  const LevelSelectScreen(isSettingsMode: true),
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.face_rounded),
              title: const Text('Karakterim'),
              subtitle: Text(
                '${app.companion.label} · ${app.companionAccessory.label}',
              ),
              trailing: SizedBox.square(
                dimension: 48,
                child: GameCompanion(
                  kind: app.companion,
                  accessory: app.companionAccessory,
                  color: app.companionPalette.color,
                  evolutionStage: app.companionGrowth.stage,
                  growthTitle: app.companionGrowth.title,
                  animate: false,
                  showMessage: false,
                  size: 48,
                ),
              ),
              onTap: () => Navigator.of(context).push(
                fadeSlideRoute<void>(const CompanionStudioScreen()),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.speed_rounded),
              title: const Text('Animasyon hızı'),
              subtitle: Text(app.speedLabel),
              onTap: () => persistPreference(context, 'speed', app.cycleSpeed),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.motion_photos_off_rounded),
              title: const Text('Azaltılmış hareket'),
              subtitle: const Text(
                'Uzun yol ve parçacık efektlerini azaltır',
              ),
              value: app.reducedMotion,
              onChanged: (value) => persistPreference(context, 'motion', () => app.setReducedMotion(value)),
            ),
            // Hareket laboratuvarı ayarların yanında duruyor. Kelimeler
            // sekmesindeyken normal bir deste sanılıyordu; oysa işi
            // animasyonu ölçmek, kelime öğretmek değil.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.animation_rounded),
              title: const Text('Hareket laboratuvarı'),
              subtitle: const Text(
                'Kaydırma fiziğini ve stres testini denemek için',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                fadeSlideRoute<void>(const PrototypeScreen()),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.backup_rounded),
              title: const Text('Yedekleme'),
              subtitle: const Text(
                'İlerlemeni dışa aktar, yeni telefonda geri yükle',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                fadeSlideRoute<void>(const BackupScreen()),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Kaynaklar ve içerik künyesi'),
              subtitle: Text('${app.wordCount} kelime · lisans bilgisi'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                fadeSlideRoute<void>(const AboutScreen()),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.short_text_rounded),
              title: const Text('Kart ön yüzünde örnek cümle'),
              subtitle: const Text(
                'Kapalıyken anlamı tahmin etmek zorlaşır ama kendini daha iyi test edersin',
              ),
              value: app.showSentenceOnFront,
              onChanged: app.setShowSentenceOnFront,
            ),
            // Bildirilen hatalar bir sonraki içerik turunda elle düzeltilecek,
            // o yüzden sayının görünür olması gerekiyor.
            if (app.flags.count > 0)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.flag_rounded,
                  color: Color(0xFFD9A21B),
                ),
                title: const Text('Hatalı olarak işaretlediklerin'),
                subtitle: Text(
                  '${app.flags.count} kart · bir sonraki içerik turunda düzeltilecek',
                ),
              ),
          ],
        ),
      ),
    );
  }

  static TextStyle _sectionStyle(ThemeData theme) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      );

  static int _knownInLevel(AppState app, CefrLevel level) {
    final Set<String> ids =
        app.words.candidateIds(levels: <CefrLevel>[level]).toSet();
    return app.cards
        .snapshot()
        .values
        .where((SrsCard c) =>
            ids.contains(c.refId) &&
            (c.status == CardStatus.known || c.status == CardStatus.mastered))
        .length;
  }
}

/// Yavaşça büyüyüp küçülen alev simgesi.
class _BreathingFlame extends StatefulWidget {
  const _BreathingFlame({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  State<_BreathingFlame> createState() => _BreathingFlameState();
}

class _BreathingFlameState extends State<_BreathingFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _BreathingFlame old) {
    super.didUpdateWidget(old);
    if (MotionTokens.reducedMotion) {
      _c.stop();
      _c.value = 0;
    } else if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Icon icon = Icon(
      widget.active
          ? Icons.local_fire_department_rounded
          : Icons.local_fire_department_outlined,
      size: 34,
      color: widget.color,
    );
    if (!widget.active || MotionTokens.reducedMotion) return icon;
    return AnimatedBuilder(
      animation: _c,
      child: icon,
      builder: (BuildContext context, Widget? child) => Transform.scale(
        scale: 1 + 0.08 * Curves.easeInOut.transform(_c.value),
        child: child,
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value.toDouble()),
            duration: MotionTokens.counterRise,
            curve: MotionTokens.counter,
            builder: (BuildContext context, double v, Widget? _) => Text(
              '${v.round()}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoxRow extends StatelessWidget {
  const _BoxRow({
    required this.box,
    required this.count,
    required this.maxCount,
  });

  final int box;
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Duration interval = BoxScheduler.intervals[box];
    final String label =
        interval == Duration.zero ? 'aynı oturum' : '${interval.inDays} gün';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 26,
            child: Text(
              '$box',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: maxCount == 0 ? 0 : count / maxCount,
              ),
              duration: MotionTokens.progressFill,
              curve: MotionTokens.progress,
              builder: (BuildContext context, double v, Widget? _) => ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                    value: v,
                    // Kutu yukseldikce renk degisir: ilerlemeyi bir
                    // bakista gosterir.
                    color: AppTheme.levelColor(box),
                    minHeight: 8),
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              '  $count · $label',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelBar extends StatelessWidget {
  const _LevelBar({
    required this.level,
    required this.known,
    required this.total,
    required this.isCurrent,
  });

  final CefrLevel level;
  final int known;
  final int total;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double ratio = total == 0 ? 0 : known / total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 34,
            child: Text(
              level.code,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                color: isCurrent
                    ? AppTheme.levelColor(level.index)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: ratio),
              duration: MotionTokens.progressFill,
              curve: MotionTokens.progress,
              builder: (BuildContext context, double v, Widget? _) => ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: v,
                  color: AppTheme.levelColor(level.index),
                  minHeight: 8,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '  $known / $total',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Günlük seri ve bugünkü hedef.
///
/// Seri, bugünden geriye doğru kesintisiz gün sayısıdır. Bugün henüz
/// çalışılmadıysa dünden başlar; gün ortasında seri sıfırlanmış gibi
/// görünmesin diye.
class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.streak,
    required this.today,
    required this.goal,
  });

  final int streak;
  final int today;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool reached = today >= goal;
    final double ratio = goal == 0 ? 0 : (today / goal).clamp(0.0, 1.0);
    final Color accent =
        reached ? const Color(0xFF2E9E5B) : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: <Widget>[
          // Seri canlıysa alev yavaşça nefes alır. Sabit bir simgeden
          // farkı küçük ama kart "yaşıyor" gibi duruyor.
          _BreathingFlame(active: streak > 0, color: accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  streak > 0 ? '$streak günlük seri' : 'Seri yok',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reached
                      ? 'Bugünkü hedefi tamamladın'
                      : 'Bugün $today / $goal kart',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: ratio),
                  duration: MotionTokens.progressFill,
                  curve: MotionTokens.progress,
                  builder: (BuildContext c, double v, Widget? _) => ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GameProfileCard extends StatelessWidget {
  const _GameProfileCard({required this.profile});

  final GameProfile profile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            accent.withValues(alpha: 0.18),
            const Color(0xFFFFC247).withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${profile.playerLevel}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Oyuncu seviyesi ${profile.playerLevel}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${profile.xp} XP · ${profile.coins} coin · '
                      'en iyi seri ${profile.bestCombo}',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: profile.levelProgress),
            duration: MotionTokens.progressFill,
            curve: MotionTokens.progress,
            builder: (BuildContext context, double value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: value, minHeight: 8),
            ),
          ),
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Sonraki seviye: ${profile.nextLevelXp} XP',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestTile extends StatelessWidget {
  const _QuestTile({required this.quest});

  final DailyQuest quest;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color =
        quest.complete ? const Color(0xFF2E9E5B) : theme.colorScheme.primary;
    return AnimatedContainer(
      duration: MotionTokens.selection,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: quest.complete ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: <Widget>[
          AnimatedScale(
            scale: quest.complete ? 1 : 0.9,
            duration: MotionTokens.selection,
            curve: MotionTokens.badge,
            child: Icon(
              quest.complete
                  ? Icons.check_circle_rounded
                  : switch (quest.kind) {
                      QuestKind.cards => Icons.style_rounded,
                      QuestKind.quiz => Icons.quiz_rounded,
                      QuestKind.verbs => Icons.change_circle_rounded,
                    },
              color: color,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  quest.kind.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: quest.ratio),
                    duration: MotionTokens.progressFill,
                    builder: (BuildContext context, double value, _) =>
                        LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${quest.progress.clamp(0, quest.target)} / ${quest.target} '
                  '${quest.kind.description}',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.52),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '+${quest.rewardXp} XP\n+${quest.rewardCoins} coin',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementGrid extends StatelessWidget {
  const _AchievementGrid({required this.unlocked});

  final Set<String> unlocked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final AchievementDefinition achievement in gameAchievements)
          Tooltip(
            message: achievement.description,
            child: AnimatedContainer(
              duration: MotionTokens.selection,
              width: 102,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              decoration: BoxDecoration(
                color: unlocked.contains(achievement.id)
                    ? const Color(0xFFFFC247).withValues(alpha: 0.16)
                    : theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: <Widget>[
                  Icon(
                    unlocked.contains(achievement.id)
                        ? Icons.workspace_premium_rounded
                        : Icons.lock_outline_rounded,
                    color: unlocked.contains(achievement.id)
                        ? const Color(0xFFFFC247)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    achievement.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
