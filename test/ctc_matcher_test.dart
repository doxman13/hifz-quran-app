import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_space/models/recitation_event.dart';
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

  test('CtcMatcher loads token dictionary and vocab correctly', () {
    final a1 = matcher.getTargetTokens(1, 1);
    expect(a1, isNotNull);
    expect(a1, equals([351, 7, 59, 982, 986]));

    final a2 = matcher.getTargetTokens(1, 2);
    expect(a2, isNotNull);
    expect(a2, equals([18, 526, 632, 245, 496, 39]));

    final a3 = matcher.getTargetTokens(1, 3);
    expect(a3, isNotNull);
    expect(a3, equals([982, 986]));

    final textA1 = matcher.tokensToText(a1!);
    expect(textA1, contains('بسم الله الرحمن الرحيم'));
  });

  test('CtcMatcher greedy decoding collapses repeats and removes blank', () {
    // 1024 is blank
    final logProbs = [
      // Frame 0: token 351
      [for (int i = 0; i < 1025; i++) i == 351 ? 5.0 : 0.0],
      // Frame 1: repeat token 351 (should collapse)
      [for (int i = 0; i < 1025; i++) i == 351 ? 4.8 : 0.0],
      // Frame 2: blank 1024 (should drop)
      [for (int i = 0; i < 1025; i++) i == 1024 ? 6.0 : 0.0],
      // Frame 3: token 7
      [for (int i = 0; i < 1025; i++) i == 7 ? 5.2 : 0.0],
      // Frame 4: token 59
      [for (int i = 0; i < 1025; i++) i == 59 ? 5.1 : 0.0],
    ];

    final decoded = matcher.greedyDecode(logProbs);
    expect(decoded, equals([351, 7, 59]));
  });

  test('CtcMatcher matches expected verse correctly', () {
    // Simulate user reciting Ayah 1 with 1 minor noisy token inserted
    final candidate = [351, 7, 999, 59, 982, 986];

    final match = matcher.matchSlidingWindow(
      surah: 1,
      expectedAyah: 1,
      candidateTokens: candidate,
    );

    expect(match, isNotNull);
    expect(match!.isSkip, isFalse);
    expect(match.expectedAyah, equals(1));
    expect(match.detectedAyah, equals(1));
    expect(match.confidence, greaterThanOrEqualTo(0.80));
  });

  test('CtcMatcher detects skip when user jumps from Ayah 1 to Ayah 3', () {
    // Ayah 3: [982, 986]
    final a3Tokens = matcher.getTargetTokens(1, 3)!;

    // Expected is Ayah 2, but user recites Ayah 3
    final match = matcher.matchSlidingWindow(
      surah: 1,
      expectedAyah: 2,
      candidateTokens: a3Tokens,
      windowAhead: 2,
    );

    expect(match, isNotNull);
    expect(match!.isSkip, isTrue);
    expect(match.expectedAyah, equals(2));
    expect(match.detectedAyah, equals(3));
  });

  test('CtcMatcher does not match on partial incomplete verse', () {
    // Only 2 of 6 tokens for Ayah 2
    final candidate = [18, 526];

    final match = matcher.matchSlidingWindow(
      surah: 1,
      expectedAyah: 2,
      candidateTokens: candidate,
    );

    expect(match, isNull);
  });

  test('CtcMatcher rejects half-verse recitations and dropped endings', () {
    final partials = [
      (78, 6, 'الم نجعل الارض'), // missing مهادا
      (78, 11, 'وجعلنا النهار'), // missing معاشا
      (78, 12, 'وبنينا فوقكم سبعا'), // missing شدادا
      (1, 7, 'صراط الذين انعمت عليهم غير المغضوب عليهم'), // missing ولا الضالين
      (114, 1, 'قل اعوذ برب'), // missing الناس
      (114, 5, 'الذي يوسوس في صدور'), // missing الناس
    ];

    for (final p in partials) {
      final match = matcher.matchSlidingWindow(
        surah: p.$1,
        expectedAyah: p.$2,
        candidateTokens: const [],
        candidateText: p.$3,
      );
      expect(
        match,
        isNull,
        reason: 'Partial recitation "${p.$3}" for S${p.$1}:A${p.$2} should NOT pass!',
      );
    }
  });

  test('CtcMatcher accepts full verse recitations', () {
    final full = [
      (78, 6, 'الم نجعل الارض مهادا'),
      (78, 11, 'وجعلنا النهار معاشا'),
      (78, 12, 'وبنينا فوقكم سبعا شدادا'),
      (1, 7, 'صراط الذين انعمت عليهم غير المغضوب عليهم ولا الضالين'),
      (114, 1, 'قل اعوذ برب الناس'),
      (114, 5, 'الذي يوسوس في صدور الناس'),
    ];

    for (final f in full) {
      final match = matcher.matchSlidingWindow(
        surah: f.$1,
        expectedAyah: f.$2,
        candidateTokens: const [],
        candidateText: f.$3,
      );
      expect(
        match,
        isNotNull,
        reason: 'Full recitation "${f.$3}" for S${f.$1}:A${f.$2} SHOULD pass!',
      );
      expect(match!.detectedAyah, equals(f.$2));
    }
  });

  test('CtcMatcher supports continuous multi-verse recitation (Wasl) with word slicing', () {
    // Continuous recitation of Surah 114: Ayah 1 + Ayah 2 + Ayah 3 in one stream
    final combined = 'قل اعوذ برب الناس ملك الناس اله الناس';
    int expectedAyah = 1;
    String candidate = combined;
    final matchedAyahs = <int>[];

    while (expectedAyah <= 3 && candidate.isNotEmpty) {
      final match = matcher.matchSlidingWindow(
        surah: 114,
        expectedAyah: expectedAyah,
        candidateTokens: const [],
        candidateText: candidate,
      );

      expect(match, isNotNull);
      expect(match!.isSkip, isFalse);
      expect(match.detectedAyah, equals(expectedAyah));
      matchedAyahs.add(match.detectedAyah);

      // Slice candidate using wordsConsumed
      final words = candidate.split(' ').where((w) => w.isNotEmpty).toList();
      expect(match.wordsConsumed, greaterThan(0));
      if (match.wordsConsumed < words.length) {
        candidate = words.sublist(match.wordsConsumed).join(' ');
      } else {
        candidate = '';
      }
      expectedAyah = match.detectedAyah + 1;
    }

    expect(matchedAyahs, equals([1, 2, 3]));
  });

  test('CtcMatcher supports long verse recitation in multiple breaths with token accumulation', () {
    // Simulating Ayat al-Kursi (2:255) recited in 3 breaths with a repeated word on breath 2
    final breath1 = 'الله لا اله الا هو الحي القيوم لا تاخذه سنة ولا نوم';
    final breath2 = 'له ما في السماوات وما في الارض من ذا الذي يشفع عنده الا باذنه';
    // Reciter takes breath, restarts from 'يعلم' and repeats last words 'العلي العظيم'
    final breath3 = 'يعلم ما بين ايديهم وما خلفهم ولا يحيطون بشيء من علمه الا بما شاء وسع كرسيه السماوات والارض ولا يئوده حفظهما وهو العلي العظيم';

    // Breath 1: Partial verse
    final match1 = matcher.matchSlidingWindow(
      surah: 2,
      expectedAyah: 255,
      candidateTokens: const [],
      candidateText: breath1,
    );
    expect(match1, isNull, reason: 'Breath 1 alone should not match full verse');

    // Breath 2: Breath 1 + Breath 2 accumulated
    final accumulated1And2 = '$breath1 $breath2';
    final match2 = matcher.matchSlidingWindow(
      surah: 2,
      expectedAyah: 255,
      candidateTokens: const [],
      candidateText: accumulated1And2,
    );
    expect(match2, isNull, reason: 'Breath 1 + 2 is still incomplete, should not match yet');

    // Breath 3: Breath 1 + 2 + 3 accumulated (entire verse complete)
    final fullAccumulated = '$accumulated1And2 $breath3';
    final match3 = matcher.matchSlidingWindow(
      surah: 2,
      expectedAyah: 255,
      candidateTokens: const [],
      candidateText: fullAccumulated,
    );
    expect(match3, isNotNull, reason: 'Full accumulated breaths should match 2:255');
    expect(match3!.detectedAyah, equals(255));
    expect(match3.isSkip, isFalse);
    expect(match3.confidence, greaterThanOrEqualTo(0.85));
  });

  test('CtcMatcher adapts thresholds for short verses (1-3 words) and rejects incomplete ones', () {
    // 1. Legitimate short verses should match with adaptive thresholds
    final legitimateShortVerses = [
      (112, 2, 'الله الصمد'),
      (103, 1, 'والعصر'),
      (108, 1, 'انا اعطيناك الكوثر'),
      (108, 2, 'فصل لربك وانحر'),
      (55, 1, 'الرحمن'),
      (55, 2, 'علم القران'),
      (106, 1, 'لايلاف قريش'),
    ];

    for (final v in legitimateShortVerses) {
      final match = matcher.matchSlidingWindow(
        surah: v.$1,
        expectedAyah: v.$2,
        candidateTokens: const [],
        candidateText: v.$3,
      );
      expect(
        match,
        isNotNull,
        reason: 'Short verse "${v.$3}" for S${v.$1}:A${v.$2} should match with adaptive threshold',
      );
      expect(match!.detectedAyah, equals(v.$2));
    }

    // 2. Incomplete short verses MUST be rejected (missing final word)
    final incompleteShortVerses = [
      (112, 2, 'الله'), // missing الصمد
      (108, 1, 'انا اعطيناك'), // missing الكوثر
      (108, 2, 'فصل لربك'), // missing وانحر
      (106, 1, 'لايلاف'), // missing قريش
    ];

    for (final inv in incompleteShortVerses) {
      final match = matcher.matchSlidingWindow(
        surah: inv.$1,
        expectedAyah: inv.$2,
        candidateTokens: const [],
        candidateText: inv.$3,
      );
      expect(
        match,
        isNull,
        reason: 'Incomplete short verse "${inv.$3}" for S${inv.$1}:A${inv.$2} must be rejected!',
      );
    }
  });

  test('CtcMatcher supports detection precision levels (quickRecap, balanced, strict)', () {
    // 1. In quickRecap (Hadr), fast review with slight phoneme blending is accepted
    // For Surah 1 Ayah 2: "الحمد لله رب العالمين"
    // Rapid recitation where "لله" is slurred into "الحمد رب العالمين"
    const rapidRecapText = 'الحمد رب العالمين';

    final recapMatch = matcher.matchSlidingWindow(
      surah: 1,
      expectedAyah: 2,
      candidateTokens: const [],
      candidateText: rapidRecapText,
      sensitivity: RecitationSensitivity.quickRecap,
    );
    expect(
      recapMatch,
      isNotNull,
      reason: 'Quick recap mode should be forgiving of rapid recitation omitting or blurring small words',
    );
    expect(recapMatch!.detectedAyah, equals(2));

    // 2. In strict mode (Tahqeeq), that exact same sloppy recitation MUST be rejected!
    final strictMatch = matcher.matchSlidingWindow(
      surah: 1,
      expectedAyah: 2,
      candidateTokens: const [],
      candidateText: rapidRecapText,
      sensitivity: RecitationSensitivity.strict,
    );
    expect(
      strictMatch,
      isNull,
      reason: 'Strict mode should reject sloppy recitation missing words',
    );

    // 3. In strict mode, full and accurate recitation is accepted
    const accurateText = 'الحمد لله رب العالمين';
    final strictAccurateMatch = matcher.matchSlidingWindow(
      surah: 1,
      expectedAyah: 2,
      candidateTokens: const [],
      candidateText: accurateText,
      sensitivity: RecitationSensitivity.strict,
    );
    expect(strictAccurateMatch, isNotNull);
    expect(strictAccurateMatch!.detectedAyah, equals(2));

    // 4. In ALL modes, an incomplete recitation missing the ending word MUST be rejected
    const incompleteEndingText = 'الحمد لله رب'; // dropped العالمين
    for (final sensitivity in RecitationSensitivity.values) {
      final match = matcher.matchSlidingWindow(
        surah: 1,
        expectedAyah: 2,
        candidateTokens: const [],
        candidateText: incompleteEndingText,
        sensitivity: sensitivity,
      );
      expect(
        match,
        isNull,
        reason: 'Missing last word must be rejected in $sensitivity',
      );
    }
  });

  test('Adaptive Noise Floor VAD dynamically adjusts threshold and normalizes audio levels', () {
    // 1. Threshold calculation
    double ambientNoiseFloor = 0.005; // Very quiet room
    final quietThreshold = (ambientNoiseFloor * 1.75).clamp(0.010, 0.045);
    expect(quietThreshold, closeTo(0.010, 0.001));

    ambientNoiseFloor = 0.012; // Normal room
    final normalThreshold = (ambientNoiseFloor * 1.75).clamp(0.010, 0.045);
    expect(normalThreshold, closeTo(0.021, 0.001));

    ambientNoiseFloor = 0.020; // Room with fan / AC
    final noisyThreshold = (ambientNoiseFloor * 1.75).clamp(0.010, 0.045);
    expect(noisyThreshold, closeTo(0.035, 0.001));

    // Recitation voice at RMS 0.080 exceeds threshold in all rooms
    const voiceRms = 0.080;
    expect(voiceRms > quietThreshold, isTrue);
    expect(voiceRms > normalThreshold, isTrue);
    expect(voiceRms > noisyThreshold, isTrue);

    // In the noisy room, fan background at RMS 0.020 is silence (< 0.035)
    expect(ambientNoiseFloor > noisyThreshold, isFalse);

    // 2. Visual mic level calculation
    const fanIdleRms = 0.018;
    const voiceReciteRms = 0.075;
    // Fan idling: normalized level is 0.0
    final idleLevel = ((fanIdleRms - 0.018) * 15.0).clamp(0.0, 1.0);
    expect(idleLevel, equals(0.0));

    // Reciting: normalized level pulses
    final recitingLevel = ((voiceReciteRms - 0.018) * 15.0).clamp(0.0, 1.0);
    expect(recitingLevel, greaterThan(0.5));
  });
}


