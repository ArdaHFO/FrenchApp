import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../data/repositories.dart';
import '../../domain/level.dart';
import '../../domain/srs/srs_card.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/transitions.dart';
import 'search_screen.dart';
import 'swipe_session_screen.dart';

/// Deste seçimi. PLAN.md bölüm 3.3 ve 4.
class DeckSelectScreen extends StatefulWidget {
  const DeckSelectScreen({super.key});

  @override
  State<DeckSelectScreen> createState() => _DeckSelectScreenState();
}

class _DeckSelectScreenState extends State<DeckSelectScreen> {
  WordTheme? _theme;
  bool _showOptions = false;

  List<String> _candidates(AppState app) => app.words.candidateIds(
        levels: app.activeLevels,
        theme: _theme,
      );

  ({int total, int due, int fresh}) _stats(
    AppState app,
    List<String> ids,
  ) {
    final DateTime now = DateTime.now();
    final Map<String, SrsCard> states = app.cards.snapshot();
    int due = 0;
    int fresh = 0;
    for (final String id in ids) {
      final SrsCard? s = states[id];
      if (s == null || s.timesSeen == 0) {
        fresh++;
      } else if (s.status != CardStatus.archived && s.isDue(now)) {
        due++;
      }
    }
    return (total: ids.length, due: due, fresh: fresh);
  }

  Future<void> _startSession(
    AppState app, {
    required String title,
    required List<String> ids,
    bool includeNotDue = false,
  }) async {
    if (ids.isEmpty) return;
    await Navigator.of(context).push(
      fadeSlideRoute<void>(
        SwipeSessionScreen(
          title: title,
          candidateIds: ids,
          includeNotDue: includeNotDue,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final List<String> candidates = _candidates(app);
    final stats = _stats(app, candidates);

    // Kayıtlar korunur; yalnız güncel içerikte öğrenilebilir olanlar çalışılır.
    final List<SrsCard> leeches = app.cards
        .leeches()
        .where((SrsCard card) => app.words.learningWordById(card.refId) != null)
        .toList();
    final List<SrsCard> starred = app.cards
        .starred()
        .where((SrsCard card) => app.words.learningWordById(card.refId) != null)
        .toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: <Widget>[
            Row(
              children: <Widget>[
                // Erişilebilirlik için yazı büyütüldüğünde başlık, arama
                // düğmesi ve seviye rozeti yan yana sığmıyordu.
                Expanded(
                  child: Text(
                    'Kelimeler',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Sözlükte ara',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => Navigator.of(context).push(
                    fadeSlideRoute<void>(const SearchScreen()),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.levelColor(app.level.index)
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.levelColor(app.level.index)
                          .withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    app.level.code,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.levelColor(app.level.index),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            StaggeredEntry(
              index: 0,
              child: _SessionCard(
                due: stats.due,
                fresh: stats.fresh,
                goal: app.dailyGoal,
                onStart: () => _startSession(
                  app,
                  title: _theme == null ? 'Karışık deste' : _theme!.labelTr,
                  ids: candidates,
                ),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const ValueKey<String>('deck_options_toggle'),
              onPressed: () => setState(() => _showOptions = !_showOptions),
              icon: AnimatedRotation(
                turns: _showOptions ? 0.5 : 0,
                duration: MotionTokens.selection,
                child: const Icon(Icons.expand_more_rounded),
              ),
              label: Text(
                _showOptions ? 'Seçenekleri gizle' : 'Deste seçenekleri',
              ),
            ),
            AnimatedSize(
              duration: MotionTokens.pageTransition,
              curve: MotionTokens.settle,
              alignment: Alignment.topCenter,
              child: !_showOptions
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(height: 22),
                        Text(
                          'Alt seviyeleri karıştır',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          app.mixLowerLevels
                              ? '${app.activeLevels.map((CefrLevel l) => l.code).join(", ")} birlikte geliyor'
                              : 'Sadece ${app.level.code}',
                          style: TextStyle(fontSize: 13, color: faint),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Switch(
                            value: app.mixLowerLevels,
                            onChanged: app.setMixLowerLevels,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tema',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            ChoiceChip(
                              label: const Text('Hepsi'),
                              selected: _theme == null,
                              onSelected: (_) => setState(() => _theme = null),
                            ),
                            for (final WordTheme t in WordTheme.values)
                              ChoiceChip(
                                label: Text(t.labelTr),
                                selected: _theme == t,
                                onSelected: (_) => setState(() => _theme = t),
                              ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        Text(
                          'Özel desteler',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _MiniDeckTile(
                          icon: Icons.error_outline_rounded,
                          title: 'Zorlandıklarım',
                          subtitle: leeches.isEmpty
                              ? 'Çalışılabilir zorlanılan kelime yok'
                              : '${leeches.length} çalışılabilir kelime',
                          enabled: leeches.isNotEmpty,
                          onTap: () => _startSession(
                            app,
                            title: 'Zorlandıklarım',
                            ids: leeches.map((SrsCard c) => c.refId).toList(),
                            includeNotDue: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _MiniDeckTile(
                          icon: Icons.star_rounded,
                          title: 'Yıldızlılar',
                          subtitle: starred.isEmpty
                              ? 'Çalışılabilir yıldızlı kelime yok'
                              : '${starred.length} çalışılabilir kelime',
                          enabled: starred.isNotEmpty,
                          onTap: () => _startSession(
                            app,
                            title: 'Yıldızlılar',
                            ids: starred.map((SrsCard c) => c.refId).toList(),
                            includeNotDue: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (BuildContext context) {
                            // Deyimler seviye filtresine takılmadan gelir.
                            final List<String> ids = app.words.candidateIds(
                              levels: CefrLevel.values,
                              idiomsOnly: true,
                            );
                            return _MiniDeckTile(
                              icon: Icons.format_quote_rounded,
                              title: 'Deyimler ve kalıplar',
                              subtitle: ids.isEmpty
                                  ? 'Henüz deyim yok'
                                  : '${ids.length} deyim · örnek ve kullanım notları',
                              enabled: ids.isNotEmpty,
                              onTap: () => _startSession(
                                app,
                                title: 'Deyimler',
                                ids: ids,
                                includeNotDue: true,
                              ),
                            );
                          },
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

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.due,
    required this.fresh,
    required this.goal,
    required this.onStart,
  });

  final int due;
  final int fresh;
  final int goal;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool empty = due + fresh == 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            theme.colorScheme.primary.withValues(alpha: 0.20),
            theme.colorScheme.primary.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Wrap kullanılıyor: büyük yazı ayarında üç sayaç bir satıra
          // sığmayınca alt satıra iniyor, taşma hatası vermiyor.
          Wrap(
            spacing: 24,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            children: <Widget>[
              _Stat(value: due, label: 'tekrar'),
              _Stat(value: fresh, label: 'yeni'),
              _Stat(value: goal, label: 'hedef'),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: empty ? null : onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(empty ? 'Bu destede kart yok' : 'Oturumu başlat'),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: value.toDouble()),
          duration: MotionTokens.counterRise,
          curve: MotionTokens.counter,
          builder: (BuildContext context, double v, Widget? _) => Text(
            '${v.round()}',
            style: TextStyle(
              fontSize: 26,
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
    );
  }
}

class _MiniDeckTile extends StatelessWidget {
  const _MiniDeckTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double opacity = enabled ? 1.0 : 0.45;
    return Opacity(
      opacity: opacity,
      child: Material(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
