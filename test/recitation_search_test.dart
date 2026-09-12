import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_space/services/ctc_matcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CtcMatcher matcher;

  setUpAll(() async {
    matcher = await CtcMatcher.load(
      tokensPath: 'assets/models/quran_ctc_tokens.json',
      vocabPath: 'assets/models/vocab.json',
    );
  });

  test('searchVerses finds Al-Fatihah 1:2 from exact tokens', () {
    // [18, 526, 632, 245, 496, 39] = Alhamdulillahi Rabbil Alameen
    final results = matcher.searchVerses([18, 526, 632, 245, 496, 39]);

    expect(results, isNotEmpty);
    final topMatch = results.first;
    expect(topMatch.surah, equals(1));
    expect(topMatch.ayah, equals(2));
    expect(topMatch.score, greaterThanOrEqualTo(0.95));
  });

  test('searchVerses finds Al-Ikhlas 112:1 without Basmalah', () {
    // [380, 114, 59, 49, 154] = Qul huwa Allahu Ahad
    final results = matcher.searchVerses([380, 114, 59, 49, 154]);

    expect(results, isNotEmpty);
    final topMatch = results.first;
    expect(topMatch.surah, equals(112));
    expect(topMatch.ayah, equals(1));
    expect(topMatch.score, greaterThanOrEqualTo(0.95));
  });

  test('searchVerses finds Ayat al-Kursi from partial opening phrase', () {
    // 2:255 opening phrase: Allahu la ilaha illa huwal hayyul qayyum
    final openingTokens = [59, 64, 18, 3, 170, 114, 105, 2, 126, 2, 165];
    final results = matcher.searchVerses(openingTokens, limit: 5);

    expect(results, isNotEmpty);
    // 3:2 is the exact short verse, 2:255 is Ayat al-Kursi
    final matches = results.map((r) => '${r.surah}:${r.ayah}').toList();
    expect(matches.contains('2:255') || matches.contains('3:2'), isTrue);
  });
}
