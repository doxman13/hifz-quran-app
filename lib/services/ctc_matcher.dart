import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/recitation_event.dart';

class AlignmentResult {
  final double score;
  final double recall;
  final double precision;
  final int endIndex;
  final int wordsConsumed;

  const AlignmentResult({
    required this.score,
    required this.recall,
    required this.precision,
    required this.endIndex,
    this.wordsConsumed = 0,
  });
}

class CtcMatcher {
  final Map<String, List<int>> ctcTokens;
  final Map<int, String> vocab;
  final Map<String, List<String>> _textVariantsCache = {};

  static const List<int> _basmalahTokens = [351, 7, 59, 982, 986];
  static final RegExp _diacriticsRegex = RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]');
  static final RegExp _alifRegex = RegExp(r'[إأآٱ]');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  CtcMatcher({
    required this.ctcTokens,
    required this.vocab,
  });

  /// Factory loader that works in Flutter apps (rootBundle) and host test environments (dart:io).
  static Future<CtcMatcher> load({
    String tokensPath = 'assets/models/quran_ctc_tokens.json',
    String vocabPath = 'assets/models/vocab.json',
  }) async {
    String tokensJsonStr;
    String vocabJsonStr;

    try {
      // Try rootBundle first (Flutter runtime)
      tokensJsonStr = await rootBundle.loadString(tokensPath);
      vocabJsonStr = await rootBundle.loadString(vocabPath);
    } catch (_) {
      // Fallback to File (host/unit tests)
      final tokensFile = File(tokensPath);
      final vocabFile = File(vocabPath);
      tokensJsonStr = await tokensFile.readAsString();
      vocabJsonStr = await vocabFile.readAsString();
    }

    return await compute(_parseMatcherData, (tokensJsonStr, vocabJsonStr));
  }

  static CtcMatcher _parseMatcherData((String, String) inputs) {
    final (tokensJsonStr, vocabJsonStr) = inputs;
    final rawTokens = jsonDecode(tokensJsonStr) as Map<String, dynamic>;
    final ctcTokens = <String, List<int>>{};
    rawTokens.forEach((key, val) {
      if (val is List) {
        ctcTokens[key] = val.map((e) => (e as num).toInt()).toList(growable: false);
      }
    });

    final rawVocab = jsonDecode(vocabJsonStr) as Map<String, dynamic>;
    final vocab = <int, String>{};
    rawVocab.forEach((key, val) {
      final idx = int.tryParse(key);
      if (idx != null) {
        vocab[idx] = val.toString();
      }
    });

    return CtcMatcher(ctcTokens: ctcTokens, vocab: vocab);
  }

  /// Greedy CTC decoding: argmax over vocab dimension, collapse repeats, drop blank.
  List<int> greedyDecode(
    List<List<double>> logProbs, {
    int blankIndex = 1024,
  }) {
    final tokens = <int>[];
    int prevToken = -1;

    for (final frame in logProbs) {
      int maxIdx = 0;
      double maxVal = frame.isNotEmpty ? frame[0] : -double.infinity;
      for (int i = 1; i < frame.length; i++) {
        if (frame[i] > maxVal) {
          maxVal = frame[i];
          maxIdx = i;
        }
      }

      if (maxIdx != blankIndex && maxIdx != prevToken) {
        tokens.add(maxIdx);
      }
      prevToken = maxIdx;
    }

    return tokens;
  }

  /// Converts CTC token IDs into human-readable Arabic text.
  String tokensToText(List<int> tokens) {
    final buffer = StringBuffer();
    for (final t in tokens) {
      final str = vocab[t];
      if (str != null && str != '<blank>' && str != '<unk>') {
        buffer.write(str);
      }
    }
    return buffer.toString().replaceAll('▁', ' ').trim();
  }

  /// Normalizes Arabic text by removing tashkeel/diacritics and normalizing alifs/ya/taa marbutah.
  static String normalizeArabic(String text) {
    return text
        .replaceAll(_diacriticsRegex, '')
        .replaceAll(_alifRegex, 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(_whitespaceRegex, ' ')
        .trim();
  }

  /// Retrieves base target CTC tokens for Surah [surah], Ayah [ayah].
  List<int>? getTargetTokens(int surah, int ayah) {
    return ctcTokens['$surah:$ayah:$ayah'];
  }

  /// Retrieves target CTC token variants (e.g. without Basmalah for Ayah 1 of Surahs 2-114).
  List<List<int>> getTargetVariants(int surah, int ayah) {
    final base = getTargetTokens(surah, ayah);
    if (base == null || base.isEmpty) return const [];

    if (ayah == 1 && surah != 1 && base.length >= 5) {
      bool startsWithBasmalah = true;
      for (int i = 0; i < 5; i++) {
        if (base[i] != _basmalahTokens[i]) {
          startsWithBasmalah = false;
          break;
        }
      }
      if (startsWithBasmalah) {
        return [
          base.sublist(5), // Without Basmalah first
          base,            // Full variant with Basmalah second
        ];
      }
    }

    return [base];
  }

  /// Retrieves normalized target Arabic text variants for Surah [surah], Ayah [ayah].
  List<String> getTargetTextVariants(int surah, int ayah) {
    final cacheKey = '$surah:$ayah';
    final cached = _textVariantsCache[cacheKey];
    if (cached != null) return cached;

    final tokenVariants = getTargetVariants(surah, ayah);
    final texts = <String>[];
    for (final variant in tokenVariants) {
      final rawText = tokensToText(variant);
      final norm = normalizeArabic(rawText);
      if (norm.isNotEmpty && !texts.contains(norm)) {
        texts.add(norm);
      }
    }
    _textVariantsCache[cacheKey] = texts;
    return texts;
  }

  /// Longest Common Subsequence on token lists using two-row dynamic programming ($O(N)$ space).
  static int longestCommonSubsequence(List<int> a, List<int> b) {
    final m = a.length;
    final n = b.length;
    if (m == 0 || n == 0) return 0;

    var prev = List<int>.filled(n + 1, 0);
    var curr = List<int>.filled(n + 1, 0);

    for (int i = 1; i <= m; i++) {
      final aVal = a[i - 1];
      for (int j = 1; j <= n; j++) {
        if (aVal == b[j - 1]) {
          curr[j] = prev[j - 1] + 1;
        } else {
          curr[j] = curr[j - 1] > prev[j] ? curr[j - 1] : prev[j];
        }
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }

    return prev[n];
  }

  /// Longest Common Subsequence on strings using two-row dynamic programming ($O(N)$ space).
  static int longestCommonSubsequenceString(String a, String b) {
    final m = a.length;
    final n = b.length;
    if (m == 0 || n == 0) return 0;

    var prev = List<int>.filled(n + 1, 0);
    var curr = List<int>.filled(n + 1, 0);

    for (int i = 1; i <= m; i++) {
      final aCode = a.codeUnitAt(i - 1);
      for (int j = 1; j <= n; j++) {
        if (aCode == b.codeUnitAt(j - 1)) {
          curr[j] = prev[j - 1] + 1;
        } else {
          curr[j] = curr[j - 1] > prev[j] ? curr[j - 1] : prev[j];
        }
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }

    return prev[n];
  }

  /// Sequentially checks if candidate words reach and match the end of target words.
  /// Returns a record of `(bool reachedEnd, int wordsConsumed)`.
  static (bool, int) checkReachesEndOfVerseWithEnd(
    List<String> candWords,
    List<String> targetWords, {
    RecitationSensitivity sensitivity = RecitationSensitivity.balanced,
  }) {
    if (targetWords.isEmpty) return (true, 0);
    if (candWords.isEmpty) return (false, 0);

    final matched = <int>[];
    int tIdx = 0;
    int lastCandIdx = 0;

    final double wordSimilarityCutoff;
    switch (sensitivity) {
      case RecitationSensitivity.quickRecap:
        wordSimilarityCutoff = 0.55;
        break;
      case RecitationSensitivity.strict:
        wordSimilarityCutoff = 0.72;
        break;
      case RecitationSensitivity.balanced:
        wordSimilarityCutoff = 0.65;
        break;
    }

    for (int cIdx = 0; cIdx < candWords.length && tIdx < targetWords.length; cIdx++) {
      final cw = candWords[cIdx];
      int bestMatchT = -1;
      for (int lookAhead = 0; lookAhead <= 2 && (tIdx + lookAhead) < targetWords.length; lookAhead++) {
        final tw = targetWords[tIdx + lookAhead];
        final l = longestCommonSubsequenceString(cw, tw);
        final maxLen = cw.length > tw.length ? cw.length : tw.length;
        if (maxLen > 0 && (l / maxLen) >= wordSimilarityCutoff) {
          bestMatchT = tIdx + lookAhead;
          break;
        }
      }

      if (bestMatchT != -1) {
        matched.add(bestMatchT);
        tIdx = bestMatchT + 1;
        lastCandIdx = cIdx;
      }
    }

    final bool lastWordMatched = matched.contains(targetWords.length - 1);
    final double wordRecall = matched.length / targetWords.length;

    final double requiredWordRecall;
    switch (sensitivity) {
      case RecitationSensitivity.quickRecap:
        requiredWordRecall = targetWords.length <= 2
            ? 0.40
            : (targetWords.length <= 4 ? 0.50 : 0.60);
        break;
      case RecitationSensitivity.strict:
        requiredWordRecall = targetWords.length <= 2
            ? 0.60
            : (targetWords.length <= 4 ? 0.75 : 0.85);
        break;
      case RecitationSensitivity.balanced:
        requiredWordRecall = targetWords.length <= 2
            ? 0.50
            : (targetWords.length <= 4 ? 0.65 : 0.75);
        break;
    }

    final bool reached = lastWordMatched && (wordRecall >= requiredWordRecall);

    return (reached, lastCandIdx + 1);
  }

  /// Sequentially checks if candidate words reach and match the end of target words.
  static bool checkReachesEndOfVerse(
    List<String> candWords,
    List<String> targetWords, {
    RecitationSensitivity sensitivity = RecitationSensitivity.balanced,
  }) {
    return checkReachesEndOfVerseWithEnd(
      candWords,
      targetWords,
      sensitivity: sensitivity,
    ).$1;
  }

  /// Finds the best matching prefix/subslice of [candidate] for [target].
  AlignmentResult findBestAlignment(
    List<int> candidate,
    List<int> target, {
    double recallThreshold = 0.82,
    double scoreThreshold = 0.70,
  }) {
    if (candidate.isEmpty || target.isEmpty) {
      return const AlignmentResult(
        score: 0.0,
        recall: 0.0,
        precision: 0.0,
        endIndex: 0,
      );
    }

    final tLen = target.length;
    double bestScore = 0.0;
    double bestRecall = 0.0;
    double bestPrecision = 0.0;
    int bestEnd = candidate.length;

    // 1. Scan prefix lengths from index 0
    for (int end = 1; end <= candidate.length; end++) {
      final sub = candidate.sublist(0, end);
      final l = longestCommonSubsequence(sub, target);
      final rec = l / tLen;
      final prec = l / end;
      final f1 = (rec + prec) > 0 ? (2 * rec * prec) / (rec + prec) : 0.0;

      final reachesEnd = target.isNotEmpty &&
          (sub.contains(target.last) ||
              (target.length >= 2 && sub.contains(target[target.length - 2])));

      if (rec >= recallThreshold && f1 > bestScore && f1 >= scoreThreshold && reachesEnd) {
        bestScore = f1;
        bestRecall = rec;
        bestPrecision = prec;
        bestEnd = end;
      }
    }

    // 2. If candidate has leading noise (longer than target), test sliding start offsets
    if (candidate.length > target.length) {
      final maxStart = candidate.length - math.max(1, target.length ~/ 2);
      for (int start = 1; start < maxStart; start++) {
        final sub = candidate.sublist(start);
        final l = longestCommonSubsequence(sub, target);
        final rec = l / tLen;
        final prec = l / sub.length;
        final f1 = (rec + prec) > 0 ? (2 * rec * prec) / (rec + prec) : 0.0;

        final reachesEnd = target.isNotEmpty &&
            (sub.contains(target.last) ||
                (target.length >= 2 && sub.contains(target[target.length - 2])));

        if (rec >= recallThreshold && f1 > bestScore && f1 >= scoreThreshold && reachesEnd) {
          bestScore = f1;
          bestRecall = rec;
          bestPrecision = prec;
          bestEnd = candidate.length;
        }
      }
    }

    // 3. Fallback to overall candidate check
    if (bestScore == 0.0) {
      final l = longestCommonSubsequence(candidate, target);
      final rec = l / tLen;
      final prec = l / candidate.length;
      final f1 = (rec + prec) > 0 ? (2 * rec * prec) / (rec + prec) : 0.0;
      final reachesEnd = target.isNotEmpty &&
          (candidate.contains(target.last) ||
              (target.length >= 2 && candidate.contains(target[target.length - 2])));
      return AlignmentResult(
        score: reachesEnd ? f1 : 0.0,
        recall: reachesEnd ? rec : 0.0,
        precision: reachesEnd ? prec : 0.0,
        endIndex: candidate.length,
      );
    }

    return AlignmentResult(
      score: bestScore,
      recall: bestRecall,
      precision: bestPrecision,
      endIndex: bestEnd,
    );
  }

  /// Finds the best matching text alignment between [candidateRaw] and [targetNormalized].
  AlignmentResult findBestTextAlignment(
    String candidateRaw,
    String targetNormalized, {
    double recallThreshold = 0.82,
    double scoreThreshold = 0.70,
    RecitationSensitivity sensitivity = RecitationSensitivity.balanced,
  }) {
    final candNorm = normalizeArabic(candidateRaw);
    if (candNorm.isEmpty || targetNormalized.isEmpty) {
      return const AlignmentResult(score: 0.0, recall: 0.0, precision: 0.0, endIndex: 0);
    }

    final candWords = candNorm.split(' ').where((w) => w.isNotEmpty).toList();
    final targetWords = targetNormalized.split(' ').where((w) => w.isNotEmpty).toList();
    if (candWords.isEmpty || targetWords.isEmpty) {
      return const AlignmentResult(score: 0.0, recall: 0.0, precision: 0.0, endIndex: 0);
    }

    final candClean = candWords.join();
    final targetClean = targetWords.join();
    final tLen = targetClean.length;

    // Full candidate comparison
    final lFull = longestCommonSubsequenceString(candClean, targetClean);
    final recFull = lFull / tLen;
    final precFull = candClean.isNotEmpty ? lFull / candClean.length : 0.0;
    final f1Full = (recFull + precFull) > 0 ? (2 * recFull * precFull) / (recFull + precFull) : 0.0;

    final (reachesEndFull, consumedWordsFull) = checkReachesEndOfVerseWithEnd(
      candWords,
      targetWords,
      sensitivity: sensitivity,
    );

    if (recFull >= recallThreshold && f1Full >= scoreThreshold && reachesEndFull) {
      return AlignmentResult(
        score: f1Full,
        recall: recFull,
        precision: precFull,
        endIndex: candidateRaw.length,
        wordsConsumed: consumedWordsFull > 0 ? consumedWordsFull : candWords.length,
      );
    }

    // If candidate has extra words / leading noise, scan word windows
    double bestScore = 0.0;
    double bestRecall = 0.0;
    double bestPrecision = 0.0;
    int bestEnd = candidateRaw.length;
    int bestWordsConsumed = candWords.length;

    if (candWords.length > targetWords.length) {
      final numWords = candWords.length;
      final tNum = targetWords.length;
      final minStart = math.max(0, numWords - (tNum + 5));

      for (int startW = minStart; startW < numWords; startW++) {
        for (int endW = startW + math.max(1, tNum - 2);
            endW <= math.min(numWords, startW + tNum + 4);
            endW++) {
          final subWords = candWords.sublist(startW, endW);
          final subClean = subWords.join();
          if (subClean.isEmpty) continue;

          final (reachesEndSub, consumedInSub) = checkReachesEndOfVerseWithEnd(
            subWords,
            targetWords,
            sensitivity: sensitivity,
          );
          if (!reachesEndSub) continue;

          final l = longestCommonSubsequenceString(subClean, targetClean);
          final rec = l / tLen;
          final prec = l / subClean.length;
          final f1 = (rec + prec) > 0 ? (2 * rec * prec) / (rec + prec) : 0.0;

          if (rec >= recallThreshold && f1 > bestScore && f1 >= scoreThreshold) {
            bestScore = f1;
            bestRecall = rec;
            bestPrecision = prec;
            bestEnd = candidateRaw.length;
            bestWordsConsumed = startW + (consumedInSub > 0 ? consumedInSub : subWords.length);
          }
        }
      }
    }

    return AlignmentResult(
      score: bestScore,
      recall: bestRecall,
      precision: bestPrecision,
      endIndex: bestEnd,
      wordsConsumed: bestWordsConsumed,
    );
  }

  /// Computes adaptive recall and F1 thresholds based on target word count, token count, and sensitivity.
  /// - [RecitationSensitivity.quickRecap] uses relaxed thresholds (0.62 / 0.58) for rapid review & whispered recitation.
  /// - [RecitationSensitivity.balanced] uses standard adaptive thresholds (0.70 / 0.65).
  /// - [RecitationSensitivity.strict] uses high precision thresholds (0.78 / 0.72) for strict exam testing.
  (double recallThreshold, double scoreThreshold) getAdaptiveThresholds(
    int surah,
    int ayah, {
    RecitationSensitivity sensitivity = RecitationSensitivity.balanced,
  }) {
    final texts = getTargetTextVariants(surah, ayah);
    final wordCount = texts.isNotEmpty
        ? texts.first.split(' ').where((w) => w.isNotEmpty).length
        : 10;
    final tokens = getTargetTokens(surah, ayah);
    final tokenCount = tokens?.length ?? 40;

    final bool isShort = texts.isNotEmpty ? wordCount <= 2 : tokenCount <= 8;
    final bool isMedium = texts.isNotEmpty ? wordCount <= 4 : tokenCount <= 22;

    switch (sensitivity) {
      case RecitationSensitivity.quickRecap:
        if (isShort) {
          return (0.62, 0.58);
        } else if (isMedium) {
          return (0.68, 0.62);
        } else {
          return (0.74, 0.64);
        }
      case RecitationSensitivity.strict:
        if (isShort) {
          return (0.78, 0.72);
        } else if (isMedium) {
          return (0.84, 0.75);
        } else {
          return (0.88, 0.78);
        }
      case RecitationSensitivity.balanced:
        if (isShort) {
          return (0.70, 0.65);
        } else if (isMedium) {
          return (0.76, 0.68);
        } else {
          return (0.82, 0.70);
        }
    }
  }

  /// Evaluates alignment for Surah [surah], Ayah [ayah] using both token and text LCS across variants.
  AlignmentResult evaluateAyahMatch(
    int surah,
    int ayah,
    List<int> candidateTokens, {
    String? candidateText,
    double? recallThreshold,
    double? scoreThreshold,
    RecitationSensitivity sensitivity = RecitationSensitivity.balanced,
  }) {
    final (adaptiveRecall, adaptiveScore) = getAdaptiveThresholds(
      surah,
      ayah,
      sensitivity: sensitivity,
    );
    final effectiveRecall = recallThreshold ?? adaptiveRecall;
    final effectiveScore = scoreThreshold ?? adaptiveScore;

    double bestScore = 0.0;
    double bestRecall = 0.0;
    double bestPrecision = 0.0;
    int bestEnd = candidateTokens.length;
    int bestWordsConsumed = 0;

    // 1. Evaluate Token Variants
    final tokenVariants = getTargetVariants(surah, ayah);
    for (final variant in tokenVariants) {
      final align = findBestAlignment(
        candidateTokens,
        variant,
        recallThreshold: effectiveRecall,
        scoreThreshold: effectiveScore,
      );
      if (align.recall >= effectiveRecall && align.score > bestScore) {
        bestScore = align.score;
        bestRecall = align.recall;
        bestPrecision = align.precision;
        bestEnd = align.endIndex;
      }
    }

    // 2. Evaluate Text Variants
    final candText = candidateText ?? tokensToText(candidateTokens);
    if (candText.isNotEmpty) {
      final textVariants = getTargetTextVariants(surah, ayah);
      for (final textVariant in textVariants) {
        final align = findBestTextAlignment(
          candText,
          textVariant,
          recallThreshold: effectiveRecall,
          scoreThreshold: effectiveScore,
          sensitivity: sensitivity,
        );
        if (align.recall >= effectiveRecall && align.score > bestScore) {
          bestScore = align.score;
          bestRecall = align.recall;
          bestPrecision = align.precision;
          if (bestEnd == 0) bestEnd = candidateTokens.length;
          bestWordsConsumed = align.wordsConsumed;
        }
      }
    }

    return AlignmentResult(
      score: bestScore,
      recall: bestRecall,
      precision: bestPrecision,
      endIndex: bestEnd,
      wordsConsumed: bestWordsConsumed,
    );
  }

  /// Matches [candidateTokens] / [candidateText] against a sliding window [expectedAyah .. expectedAyah + windowAhead].
  ///
  /// Returns [RecitationMatchResult] if a verse is recognized (either expected or skipped ahead),
  /// or null if still waiting/partial.
  RecitationMatchResult? matchSlidingWindow({
    required int surah,
    required int expectedAyah,
    required List<int> candidateTokens,
    String? candidateText,
    int windowAhead = 2,
    int maxAyah = 286,
    double? recallThreshold,
    double? scoreThreshold,
    RecitationSensitivity sensitivity = RecitationSensitivity.balanced,
  }) {
    if (candidateTokens.isEmpty && (candidateText == null || candidateText.isEmpty)) {
      return null;
    }

    final text = candidateText ?? tokensToText(candidateTokens);

    // 1. First priority: Check expectedAyah
    final (expRecall, expScore) = getAdaptiveThresholds(
      surah,
      expectedAyah,
      sensitivity: sensitivity,
    );
    final effectiveExpRecall = recallThreshold ?? expRecall;
    final effectiveExpScore = scoreThreshold ?? expScore;

    final expectedAlign = evaluateAyahMatch(
      surah,
      expectedAyah,
      candidateTokens,
      candidateText: text,
      recallThreshold: effectiveExpRecall,
      scoreThreshold: effectiveExpScore,
      sensitivity: sensitivity,
    );

    if (expectedAlign.recall >= effectiveExpRecall && expectedAlign.score >= effectiveExpScore) {
      return RecitationMatchResult(
        surah: surah,
        expectedAyah: expectedAyah,
        detectedAyah: expectedAyah,
        confidence: expectedAlign.score,
        isSkip: false,
        matchedTokens: candidateTokens.sublist(
          0,
          math.min(expectedAlign.endIndex, candidateTokens.length),
        ),
        tokensConsumed: expectedAlign.endIndex,
        wordsConsumed: expectedAlign.wordsConsumed,
        decodedText: text,
      );
    }

    // 2. Second priority: Check if user skipped ahead (e.g. expected + 1, expected + 2)
    final upperLimit = math.min(maxAyah, expectedAyah + windowAhead);
    for (int nextAyah = expectedAyah + 1; nextAyah <= upperLimit; nextAyah++) {
      final (skipRecall, skipScore) = getAdaptiveThresholds(
        surah,
        nextAyah,
        sensitivity: sensitivity,
      );
      final effectiveSkipRecall = recallThreshold ?? skipRecall;
      final effectiveSkipScore = scoreThreshold ?? skipScore;

      final skipAlign = evaluateAyahMatch(
        surah,
        nextAyah,
        candidateTokens,
        candidateText: text,
        recallThreshold: effectiveSkipRecall,
        scoreThreshold: effectiveSkipScore,
        sensitivity: sensitivity,
      );

      if (skipAlign.recall >= effectiveSkipRecall && skipAlign.score >= effectiveSkipScore) {
        return RecitationMatchResult(
          surah: surah,
          expectedAyah: expectedAyah,
          detectedAyah: nextAyah,
          confidence: skipAlign.score,
          isSkip: true,
          matchedTokens: candidateTokens.sublist(
            0,
            math.min(skipAlign.endIndex, candidateTokens.length),
          ),
          tokensConsumed: skipAlign.endIndex,
          wordsConsumed: skipAlign.wordsConsumed,
          decodedText: text,
        );
      }
    }

    return null;
  }
}
