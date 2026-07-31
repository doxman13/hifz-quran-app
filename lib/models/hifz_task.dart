enum TextVisibilityMode { visible, hidden }
enum TaskType { singleVerse, cumulativeLink }

class HifzTask {
  final String id;
  final TaskType type;
  final List<int> verseNumbers; // e.g. [1] for single, [1, 2, 3] for cumulative link
  final TextVisibilityMode mode;
  final int targetRepetitions;
  int currentProgress;

  HifzTask({
    required this.id,
    required this.type,
    required this.verseNumbers,
    required this.mode,
    required this.targetRepetitions,
    this.currentProgress = 0,
  });

  bool get isCompleted => currentProgress >= targetRepetitions;
}

List<HifzTask> generateHifzRoutine(int repeatStart, int learnStart, int endVerse) {
  List<HifzTask> tasks = [];
  if (learnStart > endVerse) return tasks;
  if (repeatStart > learnStart) repeatStart = learnStart;

  for (int v = learnStart; v <= endVerse; v++) {
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

    // Cumulative Link
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
