import '../../app/progress_session.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../domain/level.dart';
import '../../domain/song.dart';
import '../../domain/srs/srs_card.dart';
import '../../domain/word.dart';
import '../../domain/word_search.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/transitions.dart';
import '../../services/tts_service.dart';
import '../../ui/game_ui.dart';
import 'song_quiz_screen.dart';

class SongPlayerScreen extends StatefulWidget {
  const SongPlayerScreen({super.key, required this.song});

  final LearningSong song;

  @override
  State<SongPlayerScreen> createState() => _SongPlayerScreenState();
}

class _SongPlayerScreenState extends State<SongPlayerScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  late final AnimationController _coverController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  final ValueNotifier<Duration> _position =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<int> _activeLyric = ValueNotifier<int>(0);
  bool _loaded = false;
  bool _loading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _positionSubscription = _player
        .createPositionStream(
      minPeriod: MotionTokens.mediaPositionUpdate,
      maxPeriod: MotionTokens.mediaPositionUpdate,
    )
        .listen((Duration position) {
      _position.value = position;
      final int active = _activeLine(position);
      if (_activeLyric.value != active) _activeLyric.value = active;
    });
    _stateSubscription = _player.playerStateStream.listen((PlayerState state) {
      if (!mounted) return;
      if (state.playing && !MotionTokens.reducedMotion) {
        if (!_coverController.isAnimating) _coverController.repeat();
      } else if (_coverController.isAnimating) {
        _coverController.stop();
      }
    });
    _errorSubscription = _player.errorStream.listen((PlayerException error) {
      if (!mounted) return;
      setState(
          () => _loadError = 'Ses bağlantısı kesildi. Tekrar deneyebilirsin.');
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _errorSubscription?.cancel();
    _positionSubscription?.cancel();
    _position.dispose();
    _activeLyric.dispose();
    _coverController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<bool> _ensureLoaded() async {
    if (_loaded) return true;
    if (_loading) return false;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _player.setUrl(widget.song.audioUrl);
      if (!mounted) return false;
      setState(() {
        _loaded = true;
        _loading = false;
      });
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _loading = false;
        _loadError = 'Şarkı yüklenemedi. İnternet bağlantını kontrol et.';
      });
      return false;
    }
  }

  Future<void> _togglePlayback(PlayerState state) async {
    if (state.playing) {
      await _player.pause();
      return;
    }
    if (!await _ensureLoaded()) return;
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    unawaited(_player.play());
  }

  Future<void> _jumpTo(Duration position) async {
    if (!await _ensureLoaded()) return;
    await _player.seek(position);
    if (!_player.playing) unawaited(_player.play());
  }

  int _activeLine(Duration position) {
    int active = 0;
    for (int i = 0; i < widget.song.lyrics.length; i++) {
      if (position >= widget.song.lyrics[i].start) active = i;
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    final LearningSong song = widget.song;
    final Color color = Color(song.colorValue);
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(song.title)),
      body: GameBackdrop(
        accent: color,
        animate: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 34),
          children: <Widget>[
            _PlayerHero(
              song: song,
              color: color,
              coverController: _coverController,
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<Duration>(
              valueListenable: _position,
              builder:
                  (BuildContext context, Duration position, Widget? child) =>
                      GamePanel(
                child: Column(
                  children: <Widget>[
                    StreamBuilder<Duration?>(
                      stream: _player.durationStream,
                      initialData: song.duration,
                      builder: (BuildContext context,
                          AsyncSnapshot<Duration?> durationSnapshot) {
                        final Duration duration =
                            durationSnapshot.data ?? song.duration;
                        final double max = duration.inMilliseconds
                            .toDouble()
                            .clamp(1, double.infinity);
                        return Column(
                          children: <Widget>[
                            Slider(
                              key: const ValueKey<String>('song_progress'),
                              value: position.inMilliseconds
                                  .toDouble()
                                  .clamp(0, max),
                              max: max,
                              activeColor: color,
                              onChanged: _loaded
                                  ? (double value) => _player.seek(
                                        Duration(milliseconds: value.round()),
                                      )
                                  : null,
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Text(_format(position)),
                                  Text(_format(duration)),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (BuildContext context,
                          AsyncSnapshot<PlayerState> snapshot) {
                        final PlayerState state = snapshot.data ??
                            PlayerState(false, ProcessingState.idle);
                        final bool busy = _loading ||
                            state.processingState == ProcessingState.loading ||
                            state.processingState == ProcessingState.buffering;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            IconButton.filledTonal(
                              tooltip: '10 saniye geri',
                              onPressed: _loaded
                                  ? () => _player.seek(
                                        Duration(
                                          milliseconds:
                                              (position.inMilliseconds - 10000)
                                                  .clamp(0, 1 << 31)
                                                  .toInt(),
                                        ),
                                      )
                                  : null,
                              icon: const Icon(Icons.replay_10_rounded),
                            ),
                            const SizedBox(width: 18),
                            SizedBox.square(
                              dimension: 66,
                              child: FilledButton(
                                key: const ValueKey<String>('song_play'),
                                style: FilledButton.styleFrom(
                                  shape: const CircleBorder(),
                                  padding: EdgeInsets.zero,
                                  backgroundColor: color,
                                ),
                                onPressed:
                                    busy ? null : () => _togglePlayback(state),
                                child: busy
                                    ? const SizedBox.square(
                                        dimension: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        state.playing
                                            ? Icons.pause_rounded
                                            : state.processingState ==
                                                    ProcessingState.completed
                                                ? Icons.replay_rounded
                                                : Icons.play_arrow_rounded,
                                        size: 38,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 18),
                            IconButton.filledTonal(
                              tooltip: '10 saniye ileri',
                              onPressed: _loaded
                                  ? () => _player.seek(
                                        Duration(
                                          milliseconds:
                                              (position.inMilliseconds + 10000)
                                                  .clamp(0, 1 << 31)
                                                  .toInt(),
                                        ),
                                      )
                                  : null,
                              icon: const Icon(Icons.forward_10_rounded),
                            ),
                          ],
                        );
                      },
                    ),
                    if (_loadError != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: GameColors.coral,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Canlı sözler', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        'Kelimeye dokun · satıra dokunup oradan dinle',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                GamePill(
                  icon: Icons.translate_rounded,
                  label: '${song.quizWords.length} kelime',
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<int>(
              valueListenable: _activeLyric,
              builder: (BuildContext context, int activeLine, Widget? child) =>
                  Column(
                children: <Widget>[
                  for (int index = 0; index < song.lyrics.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _LyricLineCard(
                        line: song.lyrics[index],
                        active: index == activeLine,
                        color: color,
                        onJump: () => _jumpTo(song.lyrics[index].start),
                        onWord: (SongWord word) =>
                            _showWordSheet(context, word, color),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey<String>('song_quiz'),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: () async {
                await _player.pause();
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  fadeSlideRoute<void>(SongQuizScreen(song: song)),
                );
              },
              icon: const Icon(Icons.sports_esports_rounded),
              label: const Text('Şarkı oyununu başlat'),
            ),
            const SizedBox(height: 14),
            GamePanel(
              shadow: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Kayıt ve lisans', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 5),
                  Text(
                    '${song.attribution}\n${song.licenseLabel}\n${song.sourcePageUrl}',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.58),
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

class _PlayerHero extends StatelessWidget {
  const _PlayerHero({
    required this.song,
    required this.color,
    required this.coverController,
  });

  final LearningSong song;
  final Color color;
  final AnimationController coverController;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Hero(
            tag: 'song_cover_${song.id}',
            child: RotationTransition(
              turns: coverController,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      Colors.white,
                      color,
                      GameColors.violet,
                      const Color(0xFF0A2031),
                    ],
                    stops: const <double>[0, 0.12, 0.58, 1],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: const Icon(Icons.music_note_rounded,
                    color: Colors.white, size: 44),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            song.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(song.artist, textAlign: TextAlign.center),
        ],
      );
}

class _LyricLineCard extends StatelessWidget {
  const _LyricLineCard({
    required this.line,
    required this.active,
    required this.color,
    required this.onJump,
    required this.onWord,
  });

  final SongLyricLine line;
  final bool active;
  final Color color;
  final VoidCallback onJump;
  final ValueChanged<SongWord> onWord;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AnimatedContainer(
      duration: MotionTokens.selection,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active
            ? color.withValues(alpha: 0.14)
            : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.55)
              : theme.colorScheme.onSurface.withValues(alpha: 0.06),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onJump,
            child: Row(
              children: <Widget>[
                Icon(
                  active ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                  size: 18,
                  color: active ? color : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  _format(line.start),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: active ? color : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 6,
            children: <Widget>[
              for (int wordIndex = 0;
                  wordIndex < line.words.length;
                  wordIndex++)
                InkWell(
                  key: ValueKey<String>(
                    'lyric_${line.start.inSeconds}_$wordIndex',
                  ),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onWord(line.words[wordIndex]),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                    child: Text(
                      line.words[wordIndex].text,
                      style: TextStyle(
                        fontSize: active ? 18 : 16,
                        fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                        color: active ? color : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            line.translationTr,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }
}

void _showWordSheet(BuildContext context, SongWord token, Color color) {
  final AppState app = AppScope.of(context);
  final int generation = app.progressGeneration;
  final String foldedLemma = WordSearchEngine.fold(token.lemma);
  final List<WordSearchResult> matches = app.words.search(
    token.lemma,
    language: WordSearchLanguage.french,
    limit: 12,
  );
  Word? dictionaryWord;
  for (final WordSearchResult result in matches) {
    if (WordSearchEngine.fold(result.word.lemma) == foldedLemma) {
      dictionaryWord = result.word;
      break;
    }
  }
  final Word? matchedWord = dictionaryWord;

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setSheetState) {
        final SrsCard? card =
            matchedWord == null ? null : app.cards.stateFor(matchedWord.id);
        final bool saved = card?.starred ?? false;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        token.text,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Telaffuzu dinle',
                      onPressed: () async {
                        final TtsService tts = await TtsService.instance();
                        await tts.speak(token.lemma);
                      },
                      icon: const Icon(Icons.volume_up_rounded),
                    ),
                  ],
                ),
                if (token.lemma.toLowerCase() !=
                    token.text.replaceAll(RegExp(r'[,!?]'), '').toLowerCase())
                  Text(
                    'Sözlük biçimi: ${token.lemma}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                const SizedBox(height: 12),
                Text(
                  token.meaningTr,
                  style: const TextStyle(fontSize: 19, height: 1.35),
                ),
                if (matchedWord != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '${matchedWord.level.code} · ${matchedWord.posTr}'
                    '${matchedWord.ipa == null ? '' : ' · ${matchedWord.ipa}'}',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey<String>('save_song_word'),
                      onPressed: saved
                          ? null
                          : () async {
                              if (!allowProgress(context, app, generation)) return;
                              await app.cards.star(matchedWord.id);
                              app.notifyProgressChanged();
                              if (context.mounted) setSheetState(() {});
                            },
                      icon: Icon(saved
                          ? Icons.check_circle_rounded
                          : Icons.bookmark_add_rounded),
                      label: Text(saved
                          ? 'Kelime destene eklendi'
                          : 'Kelime desteme ekle'),
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    'Bu ifade ana sözlükte bağımsız bir kart değil; anlamı '
                    'şarkı notunda korunuyor.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

String _format(Duration value) {
  final int safeSeconds = value.inSeconds < 0 ? 0 : value.inSeconds;
  final int minutes = safeSeconds ~/ 60;
  final int seconds = safeSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
