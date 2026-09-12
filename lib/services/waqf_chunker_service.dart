import "../models/hifz_verse_chunk.dart";
import "offline_quran_database_service.dart";

class WaqfChunkerService {
  static const int defaultMinVerseWords = 14; // > 1.5 lines (average line in Mushaf is ~9.5 words)
  static const int defaultMinChunkWords = 5; // avoid micro-fragments
  static const int defaultMaxChunkWords = 16; // limit chunk size before sub-splitting

  static const List<String> waqfSigns = [
    "\u06D6", // ۖ Sala
    "\u06D7", // ۗ Qala
    "\u06D8", // ۘ Meem
    "\u06D9", // ۙ Laa
    "\u06DA", // ۚ Jeem
    "\u06DB", // ۛ Three dots
    "\u06DC", // ۜ Saktah
  ];

  static bool hasWaqfSign(String word) {
    for (final sign in waqfSigns) {
      if (word.contains(sign)) return true;
    }
    return false;
  }

  static String? extractWaqfSign(String word) {
    for (final sign in waqfSigns) {
      if (word.contains(sign)) return sign;
    }
    return null;
  }

  /// Splits a single verse text into HifzVerseChunk segments.
  /// If verse length is < minVerseWords, returns a single chunk for the entire verse.
  static List<HifzVerseChunk> chunkVerse({
    required int surah,
    required int verse,
    required String verseText,
    int minVerseWords = defaultMinVerseWords,
    int minChunkWords = defaultMinChunkWords,
    int maxChunkWords = defaultMaxChunkWords,
  }) {
    final allTokens = verseText.trim().split(RegExp(r"\s+"));
    final words = <String>[];
    for (final token in allTokens) {
      if (_isVerseEndMarker(token)) continue;
      if (_isWaqfSignOnly(token)) {
        if (words.isNotEmpty) {
          words[words.length - 1] = "${words.last} $token";
        }
        continue;
      }
      words.add(token);
    }

    final totalWords = words.length;

    // Gate 1: If verse is <= 1.5 lines (< 14 words), keep as 1 whole verse!
    if (totalWords < minVerseWords || totalWords == 0) {
      return [
        HifzVerseChunk(
          surah: surah,
          verse: verse,
          chunkIndex: 1,
          totalChunks: 1,
          startWordPos: 1,
          endWordPos: totalWords > 0 ? totalWords : 1,
          text: words.join(" "),
          wordCount: totalWords,
        ),
      ];
    }

    // Gate 2: Split by Waqf signs
    final rawChunks = <List<({String word, int pos})>>[];
    var currentChunk = <({String word, int pos})>[];

    for (int i = 0; i < totalWords; i++) {
      final w = words[i];
      final pos = i + 1;
      currentChunk.add((word: w, pos: pos));
      if (hasWaqfSign(w)) {
        rawChunks.add(currentChunk);
        currentChunk = [];
      }
    }
    if (currentChunk.isNotEmpty) {
      rawChunks.add(currentChunk);
    }

    // Gate 3: If no waqf found or any chunk > maxChunkWords, sub-divide at clause conjunctions
    final splitChunks = <List<({String word, int pos})>>[];
    for (final ch in rawChunks) {
      if (ch.length <= maxChunkWords) {
        splitChunks.add(ch);
      } else {
        var sub = <({String word, int pos})>[];
        for (int i = 0; i < ch.length; i++) {
          final item = ch[i];
          final w = item.word;
          final isConj = _isClauseConjunction(w);
          final remaining = ch.length - i;
          if (sub.length >= 6 && isConj && remaining >= minChunkWords) {
            splitChunks.add(sub);
            sub = [item];
          } else {
            sub.add(item);
          }
        }
        if (sub.isNotEmpty) {
          splitChunks.add(sub);
        }
      }
    }

    // Gate 4: Merge micro-chunks (< minChunkWords)
    final merged = <List<({String word, int pos})>>[];
    for (final ch in splitChunks) {
      if (merged.isEmpty) {
        merged.add(ch);
      } else {
        if (ch.length < minChunkWords) {
          merged.last.addAll(ch);
        } else if (merged.last.length < minChunkWords) {
          merged.last.addAll(ch);
        } else {
          merged.add(ch);
        }
      }
    }

    if (merged.length > 1 && merged.last.length < minChunkWords) {
      final last = merged.removeLast();
      merged.last.addAll(last);
    }

    // Build final HifzVerseChunk objects
    final totalResultChunks = merged.length;
    final result = <HifzVerseChunk>[];

    for (int cIdx = 0; cIdx < totalResultChunks; cIdx++) {
      final chunkWords = merged[cIdx];
      final startPos = chunkWords.first.pos;
      final endPos = chunkWords.last.pos;
      final text = chunkWords.map((e) => e.word).join(" ");
      final lastWord = chunkWords.last.word;
      final waqf = extractWaqfSign(lastWord);

      result.add(HifzVerseChunk(
        surah: surah,
        verse: verse,
        chunkIndex: cIdx + 1,
        totalChunks: totalResultChunks,
        startWordPos: startPos,
        endWordPos: endPos,
        text: text,
        waqfSign: waqf,
        wordCount: chunkWords.length,
      ));
    }

    return result;
  }

  /// Fetches verse texts and computes chunks for a given range of verses.
  static Future<Map<int, List<HifzVerseChunk>>> getChunksForVerseRange({
    required int surah,
    required int startVerse,
    required int endVerse,
    bool enabled = true,
  }) async {
    final Map<int, List<HifzVerseChunk>> map = {};
    for (int v = startVerse; v <= endVerse; v++) {
      final verseKey = "$surah:$v";
      final row = await OfflineQuranDatabaseService.getVerse(verseKey);
      final text = row?["text_uthmani"] as String? ?? "";

      if (!enabled) {
        final words = text.trim().split(RegExp(r"\s+")).where((t) => !_isVerseEndMarker(t)).toList();
        map[v] = [
          HifzVerseChunk(
            surah: surah,
            verse: v,
            chunkIndex: 1,
            totalChunks: 1,
            startWordPos: 1,
            endWordPos: words.isNotEmpty ? words.length : 1,
            text: words.join(" "),
            wordCount: words.length,
          ),
        ];
      } else {
        map[v] = chunkVerse(
          surah: surah,
          verse: v,
          verseText: text,
        );
      }
    }
    return map;
  }

  static bool _isClauseConjunction(String word) {
    if (word.startsWith("وَ") ||
        word.startsWith("فَ") ||
        word.startsWith("إِنَّ") ||
        word.startsWith("أَنَّ") ||
        word.startsWith("ثُمَّ")) {
      return true;
    }
    return false;
  }

  static bool _isVerseEndMarker(String token) {
    if (token.isEmpty) return true;
    if (token.length <= 4 && token.runes.every((r) => r >= 0x0660 && r <= 0x0669)) {
      return true;
    }
    if (token.contains("\u06DD")) return true;
    return false;
  }

  static bool _isWaqfSignOnly(String token) {
    if (token.isEmpty) return false;
    return token.runes.every((r) => waqfSigns.contains(String.fromCharCode(r)));
  }

  /// Tokenizes raw verse text using the same logic as [chunkVerse]:
  /// - filters out verse-end markers (standalone Arabic digits / ۝)
  /// - merges standalone waqf sign tokens into the preceding word
  ///
  /// Returns the canonical word list whose indices align with
  /// [HifzVerseChunk.startWordPos] / [HifzVerseChunk.endWordPos].
  static List<String> tokenizeVerseWords(String verseText) {
    final allTokens = verseText.trim().split(RegExp(r"\s+"));
    final words = <String>[];
    for (final token in allTokens) {
      if (_isVerseEndMarker(token)) continue;
      if (_isWaqfSignOnly(token)) {
        if (words.isNotEmpty) {
          words[words.length - 1] = "${words.last} $token";
        }
        continue;
      }
      words.add(token);
    }
    return words;
  }
}
