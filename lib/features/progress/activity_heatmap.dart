import 'package:flutter/material.dart';

import '../../data/repositories.dart';

/// Son 30 günün etkinlik ızgarası.
///
/// Seri sayacı "kaç gündür kesintisiz" der ama nerede boşluk verdiğini
/// söylemez. Izgara bunu tek bakışta gösteriyor: dolu kareler çalıştığın
/// günler, koyusu daha çok kart demek.
class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({
    super.key,
    required this.stats,
    required this.goal,
    this.days = 30,
  });

  final DailyStatsStore stats;

  /// Günlük hedef. En koyu tonu bu belirler.
  final int goal;
  final int days;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.colorScheme.primary;
    final Color empty = theme.colorScheme.onSurface.withValues(alpha: 0.07);
    final DateTime today = DateTime.now();

    // En eskiden bugüne. Satır başına yedi gün.
    final List<DateTime> dates = <DateTime>[
      for (int i = days - 1; i >= 0; i--)
        DateTime(today.year, today.month, today.day - i),
    ];

    int total = 0;
    int activeDays = 0;
    for (final DateTime d in dates) {
      final int n = stats.forDay(d)?['cards_swiped'] ?? 0;
      total += n;
      if (n > 0) activeDays++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            const int perRow = 10;
            const double gap = 6;
            final double cell = (c.maxWidth - gap * (perRow - 1)) / perRow;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (final DateTime d in dates)
                  _Cell(
                    size: cell,
                    date: d,
                    count: stats.forDay(d)?['cards_swiped'] ?? 0,
                    goal: goal,
                    accent: accent,
                    empty: empty,
                    isToday: d.day == today.day &&
                        d.month == today.month &&
                        d.year == today.year,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          '$days günde $activeDays gün çalıştın · toplam $total kart',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.size,
    required this.date,
    required this.count,
    required this.goal,
    required this.accent,
    required this.empty,
    required this.isToday,
  });

  final double size;
  final DateTime date;
  final int count;
  final int goal;
  final Color accent;
  final Color empty;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    // Dört kademe: hedefin dörtte biri, yarısı, tamamı, üstü.
    final double ratio = goal == 0 ? 0 : (count / goal).clamp(0.0, 1.0);
    final Color color =
        count == 0 ? empty : accent.withValues(alpha: 0.25 + 0.65 * ratio);

    return Tooltip(
      message: '${date.day}.${date.month} · $count kart',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Duration(milliseconds: 260 + date.day * 6),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double v, Widget? child) =>
            Opacity(opacity: v, child: child),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
            border: isToday ? Border.all(color: accent, width: 1.6) : null,
          ),
        ),
      ),
    );
  }
}
