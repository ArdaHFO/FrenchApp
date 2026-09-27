import 'package:flutter/material.dart';

import '../../domain/level.dart';
import '../../domain/song.dart';
import '../../motion/motion_tokens.dart';
import '../../motion/transitions.dart';
import '../../ui/game_ui.dart';
import 'popular_song_screen.dart';
import 'song_player_screen.dart';

enum _SongFilter { all, modern, lyrics, a1, a2, b1 }

class SongLibraryScreen extends StatefulWidget {
  const SongLibraryScreen({super.key});

  @override
  State<SongLibraryScreen> createState() => _SongLibraryScreenState();
}

class _SongLibraryScreenState extends State<SongLibraryScreen> {
  _SongFilter _filter = _SongFilter.all;
  String _query = '';

  bool _matches(String title, String artist, Iterable<SongWord> words) {
    final String query = _query.toLowerCase().trim();
    return query.isEmpty ||
        title.toLowerCase().contains(query) ||
        artist.toLowerCase().contains(query) ||
        words.any((word) =>
            word.text.toLowerCase().contains(query) ||
            word.meaningTr.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    final List<PopularSong> modern = PopularSongCatalog.songs.where((song) {
      if (song.isTraditional) return false;
      final bool filter = switch (_filter) {
        _SongFilter.all || _SongFilter.modern => true,
        _SongFilter.a1 => song.level == CefrLevel.a1,
        _SongFilter.a2 => song.level == CefrLevel.a2,
        _SongFilter.b1 => song.level == CefrLevel.b1,
        _SongFilter.lyrics => false,
      };
      return filter && _matches(song.title, song.artist, song.focusWords);
    }).toList(growable: false);
    final List<PopularSong> traditional =
        PopularSongCatalog.songs.where((song) {
      if (!song.isTraditional) return false;
      final bool filter = switch (_filter) {
        _SongFilter.all || _SongFilter.lyrics => true,
        _SongFilter.a1 => song.level == CefrLevel.a1,
        _SongFilter.a2 => song.level == CefrLevel.a2,
        _SongFilter.b1 => song.level == CefrLevel.b1,
        _SongFilter.modern => false,
      };
      return filter && _matches(song.title, song.artist, song.focusWords);
    }).toList(growable: false);
    final List<LearningSong> learning = SongCatalog.songs.where((song) {
      final bool filter = switch (_filter) {
        _SongFilter.all || _SongFilter.lyrics => true,
        _SongFilter.a1 => song.level == CefrLevel.a1,
        _SongFilter.a2 => song.level == CefrLevel.a2,
        _SongFilter.b1 => song.level == CefrLevel.b1,
        _SongFilter.modern => false,
      };
      final List<SongWord> words =
          song.lyrics.expand((line) => line.words).toList(growable: false);
      return filter && _matches(song.title, song.artist, words);
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Şarkılarla Fransızca')),
      body: GameBackdrop(
        accent: GameColors.coral,
        animate: false,
        child: CustomScrollView(
          key: const ValueKey<String>('song_library_scroll'),
          slivers: <Widget>[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              sliver: SliverToBoxAdapter(child: _LibraryHero()),
            ),
            if (_query.isEmpty && _filter == _SongFilter.all) ...<Widget>[
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 22, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _SectionTitle(
                    title: 'Öne çıkanlar',
                    subtitle: 'Kaydır, seç ve dinlemeye başla',
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 190,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: 3,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, index) => _FeaturedCard(
                      song: PopularSongCatalog.songs[index],
                      index: index,
                    ),
                  ),
                ),
              ),
            ],
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  key: const ValueKey<String>('song_search'),
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Şarkı, sanatçı veya Türkçe kelime ara',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: <Widget>[
                  _chip(_SongFilter.all, 'Tümü', Icons.grid_view_rounded),
                  _chip(_SongFilter.modern, 'Modern', Icons.bolt_rounded),
                  _chip(_SongFilter.lyrics, 'Geleneksel',
                      Icons.translate_rounded),
                  _chip(_SongFilter.a1, 'A1', Icons.school_rounded),
                  _chip(_SongFilter.a2, 'A2', Icons.school_rounded),
                  _chip(_SongFilter.b1, 'B1', Icons.school_rounded),
                ]),
              ),
            ),
            if (modern.isNotEmpty) ...<Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _SectionTitle(
                    title: 'Modern Fransızca hitler',
                    subtitle: '${modern.length} resmî video · altyazı varsa CC',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: modern.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 11),
                  itemBuilder: (_, index) => _OnlineSongCard(
                    song: modern[index],
                    index: index,
                  ),
                ),
              ),
            ],
            if (traditional.isNotEmpty) ...<Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _SectionTitle(
                    title: 'Geleneksel karaoke koleksiyonu',
                    subtitle:
                        '${traditional.length} video · canlı kelime ve Türkçe anlam',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: traditional.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 11),
                  itemBuilder: (_, index) => _OnlineSongCard(
                    song: traditional[index],
                    index: modern.length + index,
                  ),
                ),
              ),
            ],
            if (learning.isNotEmpty) ...<Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _SectionTitle(
                    title: 'Kelime kelime öğren',
                    subtitle:
                        '${learning.length} tam söz · Türkçe anlam · mini oyun',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: learning.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 11),
                  itemBuilder: (_, index) => _LearningCard(
                    song: learning[index],
                    index: modern.length + traditional.length + index,
                  ),
                ),
              ),
            ],
            if (modern.isEmpty && traditional.isEmpty && learning.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.all(32),
                sliver: SliverToBoxAdapter(child: _EmptySongs()),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _chip(_SongFilter filter, String label, IconData icon) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: ValueKey<String>('song_filter_${filter.name}'),
          selected: _filter == filter,
          showCheckmark: false,
          avatar: Icon(icon, size: 18),
          label: Text(label),
          onSelected: (_) => setState(() => _filter = filter),
        ),
      );
}

class _LibraryHero extends StatelessWidget {
  const _LibraryHero();

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey<String>('song_library_hero'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF0B2940), Color(0xFFF06A5D)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: GameColors.violet.withValues(alpha: 0.26),
              blurRadius: 28,
              offset: const Offset(0, 13),
            ),
          ],
        ),
        child: Row(children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: <Widget>[
                  _EqualizerIcon(),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text('LE SON DU JOUR',
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w800)),
                  ),
                ]),
                SizedBox(height: 13),
                Text('Fransızcayı\nritimle yakala',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        height: 1.04,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 9),
                Text('16 şarkı · video · kelime kartları',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white24),
            ),
            child: const Row(children: <Widget>[
              Icon(Icons.circle, size: 8, color: Color(0xFF65F0AF)),
              SizedBox(width: 6),
              Text('ONLINE',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            ]),
          ),
        ]),
      );
}

class _EqualizerIcon extends StatefulWidget {
  const _EqualizerIcon();

  @override
  State<_EqualizerIcon> createState() => _EqualizerIconState();
}

class _EqualizerIconState extends State<_EqualizerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionTokens.rewardPop,
  );

  @override
  void initState() {
    super.initState();
    if (!MotionTokens.reducedMotion) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 24,
        height: 18,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List<Widget>.generate(4, (int index) {
                final double phase = (_controller.value + index * 0.23) % 1;
                final double scale =
                    0.35 + 0.65 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
                return Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Transform.scale(
                    alignment: Alignment.bottomCenter,
                    scaleY: scale,
                    child: Container(
                      width: 3,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55))),
        ],
      );
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.song, required this.index});
  final PopularSong song;
  final int index;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(song.colorValue);
    return StaggeredEntry(
      index: index,
      child: PressableScale(
        child: SizedBox(
          width: 260,
          child: Material(
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(24),
            color: color,
            child: InkWell(
              key: ValueKey<String>('featured_song_${song.id}'),
              onTap: () => _openPopular(context, song),
              child: Stack(fit: StackFit.expand, children: <Widget>[
                Image.network(song.thumbnailUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 520,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => ColoredBox(color: color)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Colors.transparent, Color(0xD9000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 14,
                  bottom: 14,
                  child: Row(children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900)),
                          Text(song.artist,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.play_circle_fill_rounded,
                        color: Colors.white, size: 40),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnlineSongCard extends StatelessWidget {
  const _OnlineSongCard({required this.song, required this.index});
  final PopularSong song;
  final int index;

  @override
  Widget build(BuildContext context) => _SongCardShell(
        key: ValueKey<String>('popular_song_${song.id}'),
        index: index,
        color: Color(song.colorValue),
        imageUrl: song.thumbnailUrl,
        title: song.title,
        subtitle: song.isTraditional
            ? '${song.artist} · Karaoke'
            : '${song.artist} · ${song.year}',
        badge: song.level.code,
        badgeIcon: Icons.school_rounded,
        onTap: () => _openPopular(context, song),
      );
}

class _LearningCard extends StatelessWidget {
  const _LearningCard({required this.song, required this.index});
  final LearningSong song;
  final int index;

  @override
  Widget build(BuildContext context) => _SongCardShell(
        key: ValueKey<String>('song_${song.id}'),
        index: index,
        color: Color(song.colorValue),
        title: song.title,
        subtitle: '${song.artist} · ${_format(song.duration)}',
        badge: 'Tam söz',
        badgeIcon: Icons.translate_rounded,
        onTap: () => Navigator.of(context).push(
          fadeSlideRoute<void>(SongPlayerScreen(song: song)),
        ),
      );
}

class _SongCardShell extends StatelessWidget {
  const _SongCardShell({
    super.key,
    required this.index,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeIcon,
    required this.onTap,
    this.imageUrl,
  });
  final int index;
  final Color color;
  final String title;
  final String subtitle;
  final String badge;
  final IconData badgeIcon;
  final VoidCallback onTap;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) => StaggeredEntry(
        index: index,
        child: PressableScale(
          child: GamePanel(
            padding: EdgeInsets.zero,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Row(children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: SizedBox(
                        width: 82,
                        height: 72,
                        child: imageUrl == null
                            ? ColoredBox(
                                color: color,
                                child: const Icon(Icons.graphic_eq_rounded,
                                    color: Colors.white, size: 32),
                              )
                            : Image.network(imageUrl!,
                                fit: BoxFit.cover,
                                cacheWidth: 200,
                                filterQuality: FilterQuality.low,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) => ColoredBox(
                                      color: color,
                                      child: const Icon(
                                          Icons.music_note_rounded,
                                          color: Colors.white),
                                    )),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w900)),
                          Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.58))),
                          const SizedBox(height: 7),
                          GamePill(icon: badgeIcon, label: badge, color: color),
                        ],
                      ),
                    ),
                    Icon(Icons.play_circle_fill_rounded,
                        color: color, size: 36),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

class _EmptySongs extends StatelessWidget {
  const _EmptySongs();
  @override
  Widget build(BuildContext context) => Column(children: <Widget>[
        const Icon(Icons.music_off_rounded, size: 54, color: GameColors.coral),
        const SizedBox(height: 12),
        Text('Bu aramaya uygun şarkı yok',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Başka bir kelime veya filtre dene.'),
      ]);
}

void _openPopular(BuildContext context, PopularSong song) {
  Navigator.of(context).push(
    fadeSlideRoute<void>(PopularSongScreen(song: song)),
  );
}

String _format(Duration value) {
  final int minutes = value.inMinutes;
  final int seconds = value.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
