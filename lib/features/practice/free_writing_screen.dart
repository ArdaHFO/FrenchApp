import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/free_writing.dart';
import '../../motion/motion_tokens.dart';
import '../../ui/game_ui.dart';

class FreeWritingScreen extends StatefulWidget {
  const FreeWritingScreen({super.key});

  @override
  State<FreeWritingScreen> createState() => _FreeWritingScreenState();
}

class _FreeWritingScreenState extends State<FreeWritingScreen> {
  final TextEditingController _controller = TextEditingController();
  WritingEvaluation? _evaluation;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _analyze() {
    FocusScope.of(context).unfocus();
    setState(() {
      _evaluation = FreeWritingAnalyzer.analyze(_controller.text);
    });
    if (_evaluation!.hasErrors) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  void _applyCorrection() {
    final WritingEvaluation? evaluation = _evaluation;
    if (evaluation == null) return;
    _controller
      ..text = evaluation.correctedText
      ..selection = TextSelection.collapsed(
        offset: evaluation.correctedText.length,
      );
    setState(() => _evaluation = null);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Serbest Yazı Koçu')),
      body: GameBackdrop(
        accent: GameColors.coral,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
            children: <Widget>[
              GamePanel(
                color: GameColors.frenchBlue.withValues(alpha: 0.10),
                borderColor: GameColors.frenchBlue.withValues(alpha: 0.22),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[
                            GameColors.frenchBlue,
                            GameColors.sky,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.rate_review_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'İstediğini Fransızca yaz',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Artikel, çekim, edat, olumsuzluk, daralma, '
                            'aksan, noktalama ve doğallık ayrı ayrı incelenir.',
                            style: TextStyle(
                              height: 1.35,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey<String>('free_writing_input'),
                controller: _controller,
                minLines: 7,
                maxLines: 12,
                maxLength: 1200,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(1200),
                ],
                decoration: InputDecoration(
                  labelText: 'Fransızca metnin',
                  hintText: 'Aujourd’hui, je voudrais raconter ma journée…',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Temizle',
                    onPressed: () {
                      _controller.clear();
                      setState(() => _evaluation = null);
                    },
                    icon: const Icon(Icons.clear_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey<String>('analyze_free_writing'),
                onPressed: _analyze,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Metnimi ayrıntılı incele'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: GameColors.coral,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.phonelink_lock_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.48),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Metin cihazında incelenir ve dışarı gönderilmez.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.48),
                      ),
                    ),
                  ),
                ],
              ),
              if (_evaluation != null) ...<Widget>[
                const SizedBox(height: 20),
                _WritingReport(
                  evaluation: _evaluation!,
                  onApply: _applyCorrection,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WritingReport extends StatelessWidget {
  const _WritingReport({required this.evaluation, required this.onApply});

  final WritingEvaluation evaluation;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color status = evaluation.score >= 85
        ? GameColors.mint
        : evaluation.score >= 60
            ? GameColors.gold
            : GameColors.coral;
    return AnimatedSize(
      duration: MotionTokens.pageTransition,
      curve: MotionTokens.settle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GamePanel(
            color: status.withValues(alpha: 0.10),
            borderColor: status.withValues(alpha: 0.25),
            child: Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: 58,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      CircularProgressIndicator(
                        value: evaluation.score / 100,
                        strokeWidth: 6,
                        color: status,
                        backgroundColor: status.withValues(alpha: 0.16),
                      ),
                      Text(
                        '${evaluation.score}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        evaluation.issues.isEmpty
                            ? 'Temiz ve doğal görünüyor'
                            : '${evaluation.issues.length} geliştirme noktası',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${evaluation.wordCount} kelime · '
                        '${evaluation.sentenceCount} cümle',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.58),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (evaluation.strengths.isNotEmpty) ...<Widget>[
            const SizedBox(height: 13),
            GamePanel(
              shadow: false,
              color: GameColors.mint.withValues(alpha: 0.08),
              borderColor: GameColors.mint.withValues(alpha: 0.18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _ReportTitle(
                    icon: Icons.thumb_up_alt_rounded,
                    label: 'İyi yaptıkların',
                    color: GameColors.mint,
                  ),
                  const SizedBox(height: 9),
                  for (final String strength in evaluation.strengths)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text('• $strength'),
                    ),
                ],
              ),
            ),
          ],
          if (evaluation.issues.isNotEmpty) ...<Widget>[
            const SizedBox(height: 13),
            Text(
              'Neyi, neden düzeltmelisin?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            for (int i = 0; i < evaluation.issues.length; i++) ...<Widget>[
              _IssueCard(issue: evaluation.issues[i]),
              if (i + 1 < evaluation.issues.length) const SizedBox(height: 9),
            ],
          ],
          const SizedBox(height: 13),
          GamePanel(
            shadow: false,
            color: GameColors.frenchBlue.withValues(alpha: 0.08),
            borderColor: GameColors.frenchBlue.withValues(alpha: 0.18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _ReportTitle(
                  icon: Icons.edit_note_rounded,
                  label: 'Düzeltilmiş öneri',
                  color: GameColors.frenchBlue,
                ),
                const SizedBox(height: 9),
                SelectableText(
                  evaluation.correctedText,
                  key: const ValueKey<String>('corrected_free_writing'),
                  style: const TextStyle(fontSize: 16, height: 1.45),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Öneriyi düzenlemeye devam et'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Koç yalnızca güvenle açıklayabildiği yaygın kuralları işaretler. '
            'Karmaşık edebî veya akademik metinlerde insan incelemesi de gerekir.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.48),
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.issue});

  final WritingIssue issue;

  @override
  Widget build(BuildContext context) {
    final bool error = issue.severity == WritingIssueSeverity.error;
    final Color color = error ? GameColors.coral : GameColors.gold;
    return GamePanel(
      shadow: false,
      padding: const EdgeInsets.all(14),
      color: color.withValues(alpha: 0.07),
      borderColor: color.withValues(alpha: 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  issue.type.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                error ? Icons.error_rounded : Icons.tips_and_updates_rounded,
                size: 18,
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            issue.message,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (issue.original != null && issue.suggestion != null) ...<Widget>[
            const SizedBox(height: 7),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 7,
              runSpacing: 5,
              children: <Widget>[
                Text(
                  issue.original!,
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: GameColors.coral,
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 15),
                Text(
                  issue.suggestion!,
                  style: const TextStyle(
                    color: GameColors.mint,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Kural: ${issue.rule}',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportTitle extends StatelessWidget {
  const _ReportTitle({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      );
}
