import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:french_app/domain/song.dart';
import 'package:french_app/features/songs/song_player_screen.dart';

class FailingPlayer extends AudioPlayer {
  bool fail = true;
  int pauses = 0;
  @override
  Stream<Duration> createPositionStream({int steps = 800,
      Duration minPeriod = const Duration(milliseconds: 16),
      Duration maxPeriod = const Duration(milliseconds: 200)}) => const Stream.empty();
  @override
  Stream<PlayerState> get playerStateStream => Stream.value(PlayerState(true, ProcessingState.ready));
  @override
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Future<void> pause() async {
    pauses++;
    if (fail) throw StateError('injected pause failure');
  }
}

void main() {
  testWidgets('BUG-008 media command failure is shown without detached exception', (tester) async {
    final player = FailingPlayer();
    await tester.pumpWidget(MaterialApp(home: SongPlayerScreen(
        song: SongCatalog.songs.first, player: player)));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('song_play')));
    await tester.tap(find.byKey(const ValueKey('song_play')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('song_media_error')), findsOneWidget);
    player.fail = false;
    await tester.tap(find.byKey(const ValueKey('song_play')));
    await tester.pump();
    expect(player.pauses, 2);
    expect(find.byKey(const ValueKey('song_media_error')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
