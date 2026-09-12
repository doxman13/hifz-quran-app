class HifzVerseChunk {
  final int surah;
  final int verse;
  final int chunkIndex; // 1-based index (e.g. 1, 2, 3)
  final int totalChunks; // total chunks for this verse
  final int startWordPos; // 1-based word position in verse
  final int endWordPos; // 1-based word position in verse
  final String text; // Arabic text snippet
  final String? waqfSign; // e.g. "ۚ", "ۖ", "ۗ", etc., or null
  final int wordCount;

  const HifzVerseChunk({
    required this.surah,
    required this.verse,
    required this.chunkIndex,
    required this.totalChunks,
    required this.startWordPos,
    required this.endWordPos,
    required this.text,
    this.waqfSign,
    required this.wordCount,
  });

  bool get isWholeVerse => totalChunks <= 1;

  String get id => "s${surah}_v${verse}_c$chunkIndex";

  String get label => isWholeVerse ? "$verse" : "$verse ($chunkIndex/$totalChunks)";

  @override
  String toString() =>
      "HifzVerseChunk(surah: $surah, verse: $verse, chunk: $chunkIndex/$totalChunks, words: $startWordPos-$endWordPos, count: $wordCount)";
}
