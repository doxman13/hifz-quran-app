import 'hifz_verse_chunk.dart';

enum TextVisibilityMode { visible, hidden }
enum TaskType { singleVerse, cumulativeLink }

class HifzTask {
  final String id;
  final TaskType type;
  final List<int> verseNumbers; // e.g. [1] for single, [1, 2, 3] for cumulative link
  final TextVisibilityMode mode;
  final int targetRepetitions;
  int currentProgress;

  // Sub-verse chunking support (for long verses > 1.5 lines)
  final int? chunkIndex; // 1-indexed (e.g. 1, 2, 3...)
  final int? totalChunks; // total chunks for this verse
  final int? startWordPosition; // 1-indexed word position
  final int? endWordPosition; // 1-indexed word position
  final String? chunkText; // Arabic snippet for this chunk
  final String? waqfSign; // e.g. 'ۚ', 'ۖ', etc.

  HifzTask({
    required this.id,
    required this.type,
    required this.verseNumbers,
    required this.mode,
    required this.targetRepetitions,
    this.currentProgress = 0,
    this.chunkIndex,
    this.totalChunks,
    this.startWordPosition,
    this.endWordPosition,
    this.chunkText,
    this.waqfSign,
  });

  bool get isCompleted => currentProgress >= targetRepetitions;
  bool get isChunk => chunkIndex != null && (totalChunks ?? 0) > 1;
}

List<HifzTask> generateHifzRoutine(
  int repeatStart,
  int learnStart,
  int endVerse, {
  Map<int, List<HifzVerseChunk>>? verseChunksMap,
}) {
  List<HifzTask> tasks = [];
  if (learnStart > endVerse) return tasks;
  if (repeatStart > learnStart) repeatStart = learnStart;

  for (int v = learnStart; v <= endVerse; v++) {
    final chunks = verseChunksMap?[v];

    if (chunks != null && chunks.length > 1) {
      // Chunked Routine for Long Verses
      for (final chunk in chunks) {
        final cIdx = chunk.chunkIndex;

        // 3 rounds per chunk (same as non-chunked verses)
        for (int round = 1; round <= 3; round++) {
          // Chunk: Visible x 10
          tasks.add(HifzTask(
            id: 'verse_${v}_chunk_${cIdx}_visible_r$round',
            type: TaskType.singleVerse,
            verseNumbers: [v],
            mode: TextVisibilityMode.visible,
            targetRepetitions: 10,
            chunkIndex: cIdx,
            totalChunks: chunk.totalChunks,
            startWordPosition: chunk.startWordPos,
            endWordPosition: chunk.endWordPos,
            chunkText: chunk.text,
            waqfSign: chunk.waqfSign,
          ));

          // Chunk: Hidden x 5
          tasks.add(HifzTask(
            id: 'verse_${v}_chunk_${cIdx}_hidden_r$round',
            type: TaskType.singleVerse,
            verseNumbers: [v],
            mode: TextVisibilityMode.hidden,
            targetRepetitions: 5,
            chunkIndex: cIdx,
            totalChunks: chunk.totalChunks,
            startWordPosition: chunk.startWordPos,
            endWordPosition: chunk.endWordPos,
            chunkText: chunk.text,
            waqfSign: chunk.waqfSign,
          ));
        }

        // Intra-verse cumulative link (chaining chunks 1..cIdx)
        if (cIdx > 1) {
          final chainedText = chunks.sublist(0, cIdx).map((c) => c.text).join(' ');
          // Chained Chunk: Visible x 2
          tasks.add(HifzTask(
            id: 'verse_${v}_link_chunk_1_to_${cIdx}_visible',
            type: TaskType.cumulativeLink,
            verseNumbers: [v],
            mode: TextVisibilityMode.visible,
            targetRepetitions: 2,
            chunkIndex: cIdx,
            totalChunks: chunk.totalChunks,
            startWordPosition: 1,
            endWordPosition: chunk.endWordPos,
            chunkText: chainedText,
          ));

          // Chained Chunk: Hidden x 2
          tasks.add(HifzTask(
            id: 'verse_${v}_link_chunk_1_to_${cIdx}_hidden',
            type: TaskType.cumulativeLink,
            verseNumbers: [v],
            mode: TextVisibilityMode.hidden,
            targetRepetitions: 2,
            chunkIndex: cIdx,
            totalChunks: chunk.totalChunks,
            startWordPosition: 1,
            endWordPosition: chunk.endWordPos,
            chunkText: chainedText,
          ));
        }
      }
    } else {
      // Standard Routine for verses <= 1.5 lines
      // 3 rounds of: 10x visible, 5x hidden
      for (int round = 1; round <= 3; round++) {
        // Single Verse: Visible x 10
        tasks.add(HifzTask(
          id: 'verse_${v}_visible_r$round',
          type: TaskType.singleVerse,
          verseNumbers: [v],
          mode: TextVisibilityMode.visible,
          targetRepetitions: 10,
        ));

        // Single Verse: Hidden x 5
        tasks.add(HifzTask(
          id: 'verse_${v}_hidden_r$round',
          type: TaskType.singleVerse,
          verseNumbers: [v],
          mode: TextVisibilityMode.hidden,
          targetRepetitions: 5,
        ));
      }
    }

    // Inter-verse Cumulative Link
    List<int> linkVerses = [];
    for (int i = repeatStart; i <= v; i++) {
      linkVerses.add(i);
    }

    if (linkVerses.length > 1) {
      // Cumulative Link: Visible x 2
      tasks.add(HifzTask(
        id: 'link_${repeatStart}_to_${v}_visible',
        type: TaskType.cumulativeLink,
        verseNumbers: linkVerses,
        mode: TextVisibilityMode.visible,
        targetRepetitions: 2,
      ));

      // Cumulative Link: Hidden x 2
      tasks.add(HifzTask(
        id: 'link_${repeatStart}_to_${v}_hidden',
        type: TaskType.cumulativeLink,
        verseNumbers: linkVerses,
        mode: TextVisibilityMode.hidden,
        targetRepetitions: 2,
      ));
    }
  }

  return tasks;
}
