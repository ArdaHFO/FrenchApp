import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/domain/song.dart';
import 'package:french_app/features/songs/song_library_screen.dart';
import 'package:french_app/features/songs/song_player_screen.dart';

void main() {
  test('şarkı kataloğu güvenli bağlantılar ve sıralı sözler içerir', () {
    expect(SongCatalog.songs.length, greaterThanOrEqualTo(3));
    expect(
      SongCatalog.songs.map((LearningSong song) => song.id).toSet().length,
      SongCatalog.songs.length,
    );

    for (final LearningSong song in SongCatalog.songs) {
      expect(Uri.parse(song.audioUrl).scheme, 'https');
      expect(song.audioUrl, contains('upload.wikimedia.org'));
      expect(song.sourcePageUrl, contains('commons.wikimedia.org'));
      expect(song.licenseLabel, isNotEmpty);
      expect(song.lyrics, isNotEmpty);
      for (int index = 1; index < song.lyrics.length; index++) {
        expect(
          song.lyrics[index].start,
          greaterThan(song.lyrics[index - 1].start),
        );
      }

      final List<SongQuizQuestion> quiz = SongQuizEngine.build(song);
      expect(quiz, isNotEmpty);
      for (final SongQuizQuestion question in quiz) {
        expect(question.options.length, greaterThanOrEqualTo(2));
        expect(
          question.options[question.correctIndex],
          question.word.meaningTr,
        );
      }
    }
  });

  test('modern şarkı kataloğu geçerli video ve kelime notları içerir', () {
    expect(PopularSongCatalog.songs.length, greaterThanOrEqualTo(13));
    expect(
      PopularSongCatalog.songs.where((song) => song.isTraditional).length,
      7,
    );
    expect(
      PopularSongCatalog.songs.where((song) => !song.isTraditional).length,
      6,
    );
    expect(
      PopularSongCatalog.songs
          .map((PopularSong song) => song.id)
          .toSet()
          .length,
      PopularSongCatalog.songs.length,
    );
    for (final PopularSong song in PopularSongCatalog.songs) {
      expect(song.videoId, hasLength(11));
      expect(Uri.parse(song.thumbnailUrl).scheme, 'https');
      expect(song.focusWords.length, greaterThanOrEqualTo(4));
      expect(
          song.focusWords.every((SongWord word) => word.meaningTr.isNotEmpty),
          isTrue);
    }
  });

  testWidgets('şarkı sahnesi telefon ekranında açılır',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: SongLibraryScreen()),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Şarkılarla Fransızca'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('song_search')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('song_filter_modern')),
        findsOneWidget);

    final Size heroBefore = tester.getSize(
      find.byKey(const ValueKey<String>('song_library_hero')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('song_library_hero'))),
      heroBefore,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('song_filter_lyrics')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('song_filter_lyrics')));
    await tester.pump(const Duration(seconds: 1));
    await tester.dragUntilVisible(
      find.byKey(const ValueKey<String>('song_frere_jacques')),
      find.byType(CustomScrollView),
      const Offset(0, -240),
    );
    expect(find.byKey(const ValueKey<String>('song_frere_jacques')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Türkçe kelime modern şarkı kataloğunda aranabilir',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SongLibraryScreen()));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(
      find.byKey(const ValueKey<String>('song_search')),
      'umut',
    );
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.byKey(const ValueKey<String>('popular_song_indila_derniere_danse')),
      findsOneWidget,
    );
    expect(find.text('Papaoutai'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('song_search')),
      'lahanalar',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(const ValueKey<String>('popular_song_trad_plante_les_choux')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('şarkı oynatıcı sözleri telefon ekranında gösterir',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: SongPlayerScreen(song: SongCatalog.songs.first)),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const ValueKey<String>('song_play')), findsOneWidget);
    expect(find.text('Canlı sözler'), findsOneWidget);
    expect(find.text('Jacques kardeş, Jacques kardeş'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
