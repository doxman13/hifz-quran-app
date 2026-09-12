import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_space/data/medina_mushaf_pages.dart';
import 'package:hifz_space/services/ctc_matcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Authoritative Medina Mushaf Page Boundaries', () {
    test('Surah 80 (Abasa) end of surah boundary: verses 41 and 42 are on Page 585', () {
      // In flawed qcf_quran 0.0.5, verses 41-42 were mapped to Page 586,
      // which caused premature page turn when reciting verse 40!
      expect(getMedinaMushafPageNumber(80, 40), 585);
      expect(getMedinaMushafPageNumber(80, 41), 585);
      expect(getMedinaMushafPageNumber(80, 42), 585);
      expect(getMedinaMushafPageNumber(81, 1), 586);
    });

    test('Surah 86/87 and 87/88 page boundaries', () {
      expect(getMedinaMushafPageNumber(86, 17), 591);
      expect(getMedinaMushafPageNumber(87, 15), 591);
      expect(getMedinaMushafPageNumber(87, 16), 592);
      expect(getMedinaMushafPageNumber(88, 26), 592);
      expect(getMedinaMushafPageNumber(89, 1), 593);
    });

    test('Surah 82/83 and 83/84 page boundaries', () {
      expect(getMedinaMushafPageNumber(82, 19), 587);
      expect(getMedinaMushafPageNumber(83, 6), 587);
      expect(getMedinaMushafPageNumber(83, 7), 588);
      expect(getMedinaMushafPageNumber(83, 34), 588);
      expect(getMedinaMushafPageNumber(83, 35), 589);
      expect(getMedinaMushafPageNumber(84, 25), 589);
      expect(getMedinaMushafPageNumber(85, 1), 590);
    });
  });

  group('Mid-Session Resume & Isti\'naf (Previous Verse) Matching', () {
    late CtcMatcher matcher;

    setUpAll(() async {
      matcher = await CtcMatcher.load();
    });

    test('matchSlidingWindow matches previous verse (isti\'naf) with isSkip = false', () {
      // Surah Al-Fatihah (1):
      // Verse 1: "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ"
      // Verse 2: "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ"
      // Verse 3: "الرَّحْمَٰنِ الرَّحِيمِ"
      // Verse 4: "مَالِكِ يَوْمِ الدِّينِ"

      // Scenario: User had recited verses 1 and 2, and paused.
      // Now resuming: expectedAyah is 3.
      // User repeats verse 2 before continuing.
      const verse2Text = 'الحمد لله رب العالمين';
      final v2Tokens = matcher.getTargetTokens(1, 2) ?? [];

      final matchV2 = matcher.matchSlidingWindow(
        surah: 1,
        expectedAyah: 3,
        candidateTokens: v2Tokens,
        candidateText: verse2Text,
        windowAhead: 2,
        windowBehind: 1,
        minAyah: 1,
        maxAyah: 7,
      );

      expect(matchV2, isNotNull);
      expect(matchV2!.detectedAyah, 2, reason: 'Must recognize previous verse (2)');
      expect(matchV2.isSkip, false, reason: 'Isti\'naf (previous verse) is NOT a skip');
    });

    test('matchSlidingWindow matches current expected verse normally', () {
      const verse3Text = 'الرحمن الرحيم';
      final v3Tokens = matcher.getTargetTokens(1, 3) ?? [];

      final matchV3 = matcher.matchSlidingWindow(
        surah: 1,
        expectedAyah: 3,
        candidateTokens: v3Tokens,
        candidateText: verse3Text,
        windowAhead: 2,
        windowBehind: 1,
        minAyah: 1,
        maxAyah: 7,
      );

      expect(matchV3, isNotNull);
      expect(matchV3!.detectedAyah, 3);
      expect(matchV3.isSkip, false);
    });

    test('matchSlidingWindow detects skip ahead when jumping past expected verse', () {
      const verse4Text = 'مالك يوم الدين';
      final v4Tokens = matcher.getTargetTokens(1, 4) ?? [];

      final matchV4 = matcher.matchSlidingWindow(
        surah: 1,
        expectedAyah: 3,
        candidateTokens: v4Tokens,
        candidateText: verse4Text,
        windowAhead: 2,
        windowBehind: 1,
        minAyah: 1,
        maxAyah: 7,
      );

      expect(matchV4, isNotNull);
      expect(matchV4!.detectedAyah, 4);
      expect(matchV4.isSkip, true, reason: 'Jumping to verse 4 while expecting 3 is a skip');
    });
  });
}
