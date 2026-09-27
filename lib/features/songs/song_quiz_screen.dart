import '../../app/progress_session.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../domain/companion.dart';
import '../../domain/song.dart';
import '../../motion/celebration.dart';
import '../../ui/game_companion.dart';
import '../../ui/game_ui.dart';

class SongQuizScreen extends StatefulWidget {
  const SongQuizScreen({super.key, required this.song});

  final LearningSong song;

  @override
  State<SongQuizScreen> createState() => _SongQuizScreenState();
}

class _SongQuizScreenState extends State<SongQuizScreen> with ProgressSession<SongQuizScreen> {
  late final List<SongQuizQuestion> _questions =
      SongQuizEngine.build(widget.song);
  int _index = 0;
  int _correct = 0;
  int? _selected;
  bool _finished = false;
  bool _recording = false;
  bool _saveFailed = false;

  void _answer(int option) {
    if (_selected != null) return;
    setState(() {
      _selected = option;
      if (option == _questions[_index].correctIndex) _correct++;
    });
  }

  Future<void> _next() async {
    if (!progressReady) return;
    if (_selected == null || _recording) return;
    if (_index < _questions.length - 1) {
      setState(() {
        _index++;
        _selected = null;
      });
      return;
    }
    setState(() { _recording = true; _saveFailed = false; });
    try {
      await AppScope.of(context).recordActivity(
        quizTotal: _questions.length,
        quizCorrect: _correct,
        combo: _correct,
      );
    } catch (_) {
      if (mounted) setState(() { _recording = false; _saveFailed = true; });
      return;
    }
    if (!mounted) return;
    if (!progressReady) { setState(() => _recording = false); return; }
    setState(() {
      _recording = false;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final Color color = Color(widget.song.colorValue);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.song.title} · Oyun')),
      body: GameBackdrop(
        accent: color,
        child: _questions.isEmpty
            ? const Center(child: Text('Bu şarkı için soru bulunamadı.'))
            : _finished
            ? _Result(
                app: app,
                song: widget.song,
                correct: _correct,
                total: _questions.length,
                onClose: () => Navigator.of(context).pop(),
              )
            : _QuestionView(
                question: _questions[_index],
                index: _index,
                total: _questions.length,
                selected: _selected,
                color: color,
                recording: _recording,
                saveFailed: _saveFailed,
                onAnswer: _answer,
                onNext: _next,
              ),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.question,
    required this.index,
    required this.total,
    required this.selected,
    required this.color,
    required this.recording,
    required this.saveFailed,
    required this.onAnswer,
    required this.onNext,
  });

  final SongQuizQuestion question;
  final int index;
  final int total;
  final int? selected;
  final Color color;
  final bool recording;
  final bool saveFailed;
  final ValueChanged<int> onAnswer;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (index + 1) / total,
                  minHeight: 10,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.13),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${index + 1}/$total',
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 28),
        GamePanel(
          color: color.withValues(alpha: 0.11),
          borderColor: color.withValues(alpha: 0.26),
          child: Column(
            children: <Widget>[
              Icon(Icons.music_note_rounded, color: color, size: 38),
              const SizedBox(height: 12),
              Text(
                '“${question.word.text}”',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Şarkıda bu kelime ne anlama geliyor?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        for (int option = 0; option < question.options.length; option++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Option(
              index: option,
              label: question.options[option],
              selected: selected == option,
              correct: option == question.correctIndex,
              revealed: selected != null,
              color: color,
              onTap: () => onAnswer(option),
            ),
          ),
        if (selected != null) ...<Widget>[
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              selected == question.correctIndex
                  ? 'Harika! Ritmi yakaladın. ✨'
                  : 'Doğru cevap: ${question.options[question.correctIndex]}',
              key: ValueKey<int>(selected!),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected == question.correctIndex
                    ? GameColors.mint
                    : GameColors.coral,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (saveFailed) const Text('Sonuç kaydedilemedi. Tekrar deneyin.'),
          FilledButton.icon(
            key: ValueKey<String>(saveFailed ? 'song_quiz_save_retry' : 'song_quiz_next'),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            onPressed: recording ? null : onNext,
            icon: recording
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(index == total - 1
                    ? Icons.emoji_events_rounded
                    : Icons.arrow_forward_rounded),
            label: Text(saveFailed ? 'Kaydetmeyi tekrar dene' : index == total - 1 ? 'Sonucu gör' : 'Sıradaki'),
          ),
        ],
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.index,
    required this.label,
    required this.selected,
    required this.correct,
    required this.revealed,
    required this.color,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool selected;
  final bool correct;
  final bool revealed;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color border = Theme.of(context).colorScheme.outlineVariant;
    Color? fill;
    IconData? icon;
    if (revealed && correct) {
      border = GameColors.mint;
      fill = GameColors.mint.withValues(alpha: 0.12);
      icon = Icons.check_circle_rounded;
    } else if (revealed && selected) {
      border = GameColors.coral;
      fill = GameColors.coral.withValues(alpha: 0.12);
      icon = Icons.cancel_rounded;
    } else if (selected) {
      border = color;
      fill = color.withValues(alpha: 0.10);
    }
    return PressableScale(
      child: Material(
        color: fill ?? Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: border, width: selected || correct ? 2 : 1),
        ),
        child: InkWell(
          key: ValueKey<String>('song_quiz_option_$index'),
          borderRadius: BorderRadius.circular(17),
          onTap: revealed ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: border.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    String.fromCharCode(65 + index),
                    style:
                        TextStyle(color: border, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (icon != null) Icon(icon, color: border),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.app,
    required this.song,
    required this.correct,
    required this.total,
    required this.onClose,
  });

  final AppState app;
  final LearningSong song;
  final int correct;
  final int total;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(song.colorValue);
    final int percent = total == 0 ? 0 : (correct * 100 / total).round();
    return Celebration(
      play: correct >= (total * 0.6).ceil(),
      colors: <Color>[color, GameColors.gold, GameColors.mint],
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: GamePanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                GameCompanion(
                  kind: app.companion,
                  accessory: app.companionAccessory,
                  color: app.companionPalette.color,
                  evolutionStage: app.companionGrowth.stage,
                  growthTitle: app.companionGrowth.title,
                  message: percent >= 80 ? 'Magnifique!' : 'Encore une fois!',
                  size: 132,
                ),
                const SizedBox(height: 12),
                Text(
                  percent >= 80 ? 'Sahneyi salladın!' : 'Ritmi yakalıyorsun!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  '$correct/$total doğru · %$percent',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sonucun XP ve günlük ilerlemene işlendi.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onClose,
                    icon: const Icon(Icons.library_music_rounded),
                    label: const Text('Şarkıya dön'),
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
