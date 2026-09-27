import 'level.dart';

/// Dilbilgisi dersi. Gövdesi Markdown olarak `content.db` içinde durur.
class GrammarLesson {
  const GrammarLesson({
    required this.id,
    required this.slug,
    required this.title,
    required this.level,
    required this.sortOrder,
    required this.bodyMd,
    this.tenseKey,
  });

  final String id;
  final String slug;
  final String title;
  final CefrLevel level;
  final String? tenseKey;
  final int sortOrder;
  final String bodyMd;

  /// Kaba okuma süresi tahmini (dakika).
  int get readingMinutes {
    final int words = bodyMd.split(RegExp(r'\s+')).length;
    return (words / 180).ceil().clamp(1, 30);
  }
}
