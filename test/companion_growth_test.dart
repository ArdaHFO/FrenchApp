import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/domain/companion.dart';

void main() {
  test('karakter bağı XP eşiklerinde dört aşamada gelişir', () {
    expect(CompanionGrowth.forXp(0).title, 'Yeni Dost');
    expect(CompanionGrowth.forXp(249).stage, 0);
    expect(CompanionGrowth.forXp(250).title, 'Takım Arkadaşı');
    expect(CompanionGrowth.forXp(899).stage, 1);
    expect(CompanionGrowth.forXp(900).title, 'Cesur Rehber');
    expect(CompanionGrowth.forXp(2499).stage, 2);
    expect(CompanionGrowth.forXp(2500).title, 'Efsane Yol Arkadaşı');
    expect(CompanionGrowth.forXp(2500).progressFor(2500), 1);
    expect(CompanionGrowth.forXp(2500).remainingXpFor(2500), isNull);
  });

  test('her yol arkadaşı aynı durumda farklı kişilikle konuşur', () {
    final Set<String> lines = CompanionKind.values
        .map(
          (CompanionKind kind) => kind.encouragement(
            streak: 5,
            goalReached: false,
            completed: 1,
            total: 4,
          ),
        )
        .toSet();

    expect(lines, hasLength(CompanionKind.values.length));
    expect(lines.every((String line) => line.contains('5')), isTrue);
  });

  test('bağ ilerlemesi mevcut aşamanın XP aralığını kullanır', () {
    final CompanionGrowth growth = CompanionGrowth.forXp(575);
    expect(growth.progressFor(575), closeTo(0.5, 0.001));
    expect(growth.remainingXpFor(575), 325);
  });
}
