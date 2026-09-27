import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../domain/lesson.dart';
import '../../domain/level.dart';
import '../../domain/verb.dart';
import '../../motion/transitions.dart';
import '../verbs/verb_screens.dart';

/// Dilbilgisi ders listesi. Seviyeye göre gruplu, kilit yok.
class GrammarListScreen extends StatefulWidget {
  const GrammarListScreen({super.key});

  @override
  State<GrammarListScreen> createState() => _GrammarListScreenState();
}

class _GrammarListScreenState extends State<GrammarListScreen> {
  late Future<List<GrammarLesson>> _lessons;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _lessons = AppScope.of(context).lessons.all();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<GrammarLesson>>(
          future: _lessons,
          builder:
              (BuildContext context, AsyncSnapshot<List<GrammarLesson>> snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<GrammarLesson> lessons = snap.data!;
            final Map<CefrLevel, List<GrammarLesson>> byLevel =
                <CefrLevel, List<GrammarLesson>>{};
            for (final GrammarLesson l in lessons) {
              byLevel.putIfAbsent(l.level, () => <GrammarLesson>[]).add(l);
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: <Widget>[
                Text(
                  'Dilbilgisi',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${lessons.length} ders. Zaman kullanımları ve kuruluşları.',
                  style: TextStyle(fontSize: 13, color: faint),
                ),
                const SizedBox(height: 20),
                for (final CefrLevel level in CefrLevel.values)
                  if (byLevel.containsKey(level)) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, top: 6),
                      child: Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              level.code,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${byLevel[level]!.length} ders',
                            style: TextStyle(fontSize: 12, color: faint),
                          ),
                        ],
                      ),
                    ),
                    for (int i = 0; i < byLevel[level]!.length; i++)
                      StaggeredEntry(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LessonTile(lesson: byLevel[level]![i]),
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                if (lessons.isEmpty)
                  Text(
                    'Henüz ders yok.',
                    style: TextStyle(fontSize: 13, color: faint),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.lesson});

  final GrammarLesson lesson;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          fadeSlideRoute<void>(LessonScreen(lesson: lesson)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      lesson.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${lesson.readingMinutes} dakika',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
    );
  }
}

/// Ders ekranı. Gövde Markdown olarak saklanır, tablolarla birlikte
/// olduğu gibi gösterilir.
class LessonScreen extends StatelessWidget {
  const LessonScreen({super.key, required this.lesson});

  final GrammarLesson lesson;

  VerbTense? get _tense =>
      lesson.tenseKey == null ? null : VerbTenseX.fromKey(lesson.tenseKey!);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppState app = AppScope.of(context);
    final VerbTense? tense = _tense;

    return Scaffold(
      appBar: AppBar(title: Text(lesson.title)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Markdown(
                data: lesson.bodyMd,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  h1: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                  h2: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                  h3: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                  p: const TextStyle(fontSize: 15, height: 1.45),
                  tableBorder: TableBorder.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
                    width: 1,
                  ),
                  tableCellsPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            if (tense != null && tense.level.index <= app.level.index)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      fadeSlideRoute<void>(VerbDeckScreen(initialTense: tense)),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text('${tense.label} ile pratik yap'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
