import '../../app/progress_session.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../domain/level.dart';
import '../../domain/song.dart';
import '../../domain/srs/srs_card.dart';
import '../../domain/word.dart';
import '../../domain/word_search.dart';
import '../../motion/motion_tokens.dart';
import '../../services/tts_service.dart';
import '../../ui/game_ui.dart';

class PopularSongScreen extends StatefulWidget {
  const PopularSongScreen({super.key, required this.song});

  final PopularSong song;

  @override
  State<PopularSongScreen> createState() => _PopularSongScreenState();
}

class _PopularSongScreenState extends State<PopularSongScreen> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.song.videoId,
      params: YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        enableCaption: true,
        captionLanguage: 'fr',
        interfaceLanguage: 'fr',
        strictRelatedVideos: true,
        privacyEnhancedMode: true,
        videoStateUpdateInterval:
            MotionTokens.mediaPositionUpdate.inMilliseconds,
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PopularSong song = widget.song;
    final Color color = Color(song.colorValue);
    final ThemeData theme = Theme.of(context);
    return YoutubePlayerControllerProvider(
      controller: _controller,
      child: Scaffold(
        appBar: AppBar(title: Text(song.title)),
        body: GameBackdrop(
          accent: color,
          animate: false,
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              // 360 px genişlikte 16:9 oynatıcı 202.5 px olur ve YouTube'un
              // gömülü oynatıcı için istediği 200 px alt sınırını korur.
              ColoredBox(
                color: Colors.black,
                child: YoutubePlayer(
                  key: const ValueKey<String>('youtube_song_player'),
                  controller: _controller,
                  aspectRatio: 16 / 9,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(song.title,
                                  style: theme.textTheme.headlineSmall),
                              const SizedBox(height: 3),
                              Text(
                                song.artist,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GamePill(
                          icon: Icons.school_rounded,
                          label: song.level.code,
                          color: color,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      song.isTraditional
                          ? 'Geleneksel · ${song.mood}'
                          : '${song.year} · ${song.mood}',
                      style: TextStyle(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _LiveMeaningFlow(
                      controller: _controller,
                      song: song,
                      color: color,
                    ),
                    const SizedBox(height: 14),
                    GamePanel(
                      color: color.withValues(alpha: 0.11),
                      borderColor: color.withValues(alpha: 0.24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(Icons.closed_caption_rounded, color: color),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Videodaki karaoke yazısını veya varsa CC altyazısını '
                              'takip et. Altındaki kart önemli kelimelerin Türkçe '
                              'anlamını müzikle birlikte akıtır.',
                              style: TextStyle(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Şarkıya giriş kelimeleri',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Dinlemeden önce kelimelere dokun; anlamını ve telaffuzunu öğren.',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (int index = 0; index < song.focusWords.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _FocusWordTile(
                          word: song.focusWords[index],
                          color: color,
                          index: index,
                        ),
                      ),
                    const SizedBox(height: 10),
                    GamePanel(
                      shadow: false,
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.verified_rounded,
                              color: GameColors.mint),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${song.isTraditional ? 'Geleneksel eser · kaynak kanal videosu' : 'Resmî sanatçı videosu'} · '
                              'YouTube IFrame · gizlilik geliştirilmiş mod',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.62),
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
      ),
    );
  }
}

class _LiveMeaningFlow extends StatelessWidget {
  const _LiveMeaningFlow({
    required this.controller,
    required this.song,
    required this.color,
  });

  final YoutubePlayerController controller;
  final PopularSong song;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GamePanel(
      key: const ValueKey<String>('popular_live_meaning'),
      padding: const EdgeInsets.all(16),
      color: color.withValues(alpha: 0.13),
      borderColor: color.withValues(alpha: 0.30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.graphic_eq_rounded,
                    size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Canlı söz + anlam',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    Text('CC sözleri · kart Türkçe anlamı gösterir',
                        style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 116,
            child: StreamBuilder<YoutubeVideoState>(
              stream: controller.videoStateStream,
              initialData: const YoutubeVideoState(),
              builder: (BuildContext context,
                  AsyncSnapshot<YoutubeVideoState> snapshot) {
                final Duration position =
                    snapshot.data?.position ?? Duration.zero;
                final int slot = position.inSeconds ~/ 8;
                final int index = slot % song.focusWords.length;
                final SongWord word = song.focusWords[index];
                final double progress = (position.inMilliseconds % 8000) / 8000;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: MotionTokens.selection,
                        switchInCurve: MotionTokens.settle,
                        child: InkWell(
                          key: ValueKey<String>('live_${word.lemma}_$slot'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showFocusWord(context, word, color),
                          child: SizedBox.expand(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(word.text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 25,
                                        fontWeight: FontWeight.w900)),
                                const SizedBox(height: 2),
                                Text(word.meaningTr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: color)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(99),
                            color: color,
                            backgroundColor: theme.colorScheme.onSurface
                                .withValues(alpha: 0.08),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(_formatPosition(position),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPosition(Duration value) {
  final int minutes = value.inMinutes;
  final int seconds = value.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _FocusWordTile extends StatelessWidget {
  const _FocusWordTile({
    required this.word,
    required this.color,
    required this.index,
  });

  final SongWord word;
  final Color color;
  final int index;

  @override
  Widget build(BuildContext context) => PressableScale(
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            key: ValueKey<String>('popular_focus_$index'),
            borderRadius: BorderRadius.circular(17),
            onTap: () => _showFocusWord(context, word, color),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.music_note_rounded, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(word.text,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w900)),
                        Text(word.meaningTr),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      );
}

void _showFocusWord(BuildContext context, SongWord token, Color color) {
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
    builder: (BuildContext context) => StatefulBuilder(
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
                      child: Text(token.text,
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w900)),
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
                Text(token.meaningTr,
                    style: const TextStyle(fontSize: 19, height: 1.35)),
                if (matchedWord != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '${matchedWord.level.code} · ${matchedWord.posTr}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
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
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}
