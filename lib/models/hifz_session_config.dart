// lib/models/hifz_session_config.dart
//
// Core configuration models for the dual-mode Hifz system.
// This file ONLY contains pure data models — zero UI, zero DB logic.

/// Top-level mode that determines which learning routine to run.
enum HifzSessionType {
  /// 10x visible / 5x hidden Takrar method, per verse/sub-chunk.
  newVerses,

  /// 2x visible / 2x hidden sequential review routine.
  review,
}

/// Granularity scope for Review mode. Only used when [HifzSessionType.review].
enum ReviewGranularity {
  /// Review full Surah by Surah (e.g. Surahs 100 to 114).
  bySurah,

  /// Review a specific verse range inside one Surah (e.g. Surah 2, Verses 255–260).
  byVerses,

  /// Review page by page (e.g. Pages 590 to 592).
  byPage,
}

/// Encapsulates the user-selected target for a review session.
class ReviewTargetParams {
  // --- bySurah fields ---
  final int? startSurah; // inclusive
  final int? endSurah; // inclusive

  // --- byVerses fields ---
  final int? surahNumber;
  final int? startVerse;
  final int? endVerse;

  // --- byPage fields ---
  final int? startPage; // inclusive
  final int? endPage; // inclusive

  const ReviewTargetParams({
    this.startSurah,
    this.endSurah,
    this.surahNumber,
    this.startVerse,
    this.endVerse,
    this.startPage,
    this.endPage,
  });

  /// Creates a params object for bySurah mode.
  factory ReviewTargetParams.bySurah({
    required int startSurah,
    required int endSurah,
  }) =>
      ReviewTargetParams(startSurah: startSurah, endSurah: endSurah);

  /// Creates a params object for byVerses mode.
  factory ReviewTargetParams.byVerses({
    required int surahNumber,
    required int startVerse,
    required int endVerse,
  }) =>
      ReviewTargetParams(
        surahNumber: surahNumber,
        startVerse: startVerse,
        endVerse: endVerse,
      );

  /// Creates a params object for byPage mode.
  factory ReviewTargetParams.byPage({
    required int startPage,
    required int endPage,
  }) =>
      ReviewTargetParams(startPage: startPage, endPage: endPage);

  /// Serialises to a JSON-compatible map for database storage.
  Map<String, dynamic> toJson() => {
        'startSurah': startSurah,
        'endSurah': endSurah,
        'surahNumber': surahNumber,
        'startVerse': startVerse,
        'endVerse': endVerse,
        'startPage': startPage,
        'endPage': endPage,
      };

  /// Deserialises from a JSON-compatible map.
  factory ReviewTargetParams.fromJson(Map<String, dynamic> json) =>
      ReviewTargetParams(
        startSurah: json['startSurah'] as int?,
        endSurah: json['endSurah'] as int?,
        surahNumber: json['surahNumber'] as int?,
        startVerse: json['startVerse'] as int?,
        endVerse: json['endVerse'] as int?,
        startPage: json['startPage'] as int?,
        endPage: json['endPage'] as int?,
      );
}

/// Immutable snapshot of an active session. Used for saving/restoring state.
class ActiveSessionSnapshot {
  final String sessionId;
  final HifzSessionType sessionType;

  // --- New Verses fields ---
  final int? nvSurahNumber;
  final int? nvRepeatStart;
  final int? nvStartVerse;
  final int? nvEndVerse;

  // --- Review fields ---
  final ReviewGranularity? reviewGranularity;
  final ReviewTargetParams? reviewTargetParams;

  // --- Shared progress ---
  final int currentStepIndex; // task index for newVerses; surah/page offset for review
  final String currentMode; // 'visible' | 'hidden'
  final int currentTally;
  final int targetTally; // 10 or 5 for NV; 2 for Review
  final int lastUpdatedTimestamp;

  const ActiveSessionSnapshot({
    required this.sessionId,
    required this.sessionType,
    this.nvSurahNumber,
    this.nvRepeatStart,
    this.nvStartVerse,
    this.nvEndVerse,
    this.reviewGranularity,
    this.reviewTargetParams,
    required this.currentStepIndex,
    required this.currentMode,
    required this.currentTally,
    required this.targetTally,
    required this.lastUpdatedTimestamp,
  });
}

/// Persisted record for a single Surah's completion progress.
class SurahCompletionRecord {
  final int surahNumber;
  final bool newVersesCompleted;
  final int reviewCount;
  final String? lastCompletedAt;

  const SurahCompletionRecord({
    required this.surahNumber,
    required this.newVersesCompleted,
    required this.reviewCount,
    this.lastCompletedAt,
  });

  SurahCompletionRecord copyWith({
    bool? newVersesCompleted,
    int? reviewCount,
    String? lastCompletedAt,
  }) =>
      SurahCompletionRecord(
        surahNumber: surahNumber,
        newVersesCompleted: newVersesCompleted ?? this.newVersesCompleted,
        reviewCount: reviewCount ?? this.reviewCount,
        lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
      );
}

/// Describes the current visibility phase inside a review step.
enum ReviewPhase { visible, hidden }

/// A single step in a review session (one Surah / verse block / page pass).
class ReviewStep {
  /// Human-readable label (e.g. "Surah 112 Al-Ikhlas", "Verse 255–260", "Page 604").
  final String label;

  /// For bySurah: surah number; for byVerses: surah number; for byPage: page number.
  final int primaryIndex;

  /// For byVerses: verse range within the surah.
  final int? verseStart;
  final int? verseEnd;

  /// For bySurah / byVerses: which surah to resolve verses against (Mushaf display).
  final int? surahNumber;

  const ReviewStep({
    required this.label,
    required this.primaryIndex,
    this.verseStart,
    this.verseEnd,
    this.surahNumber,
  });
}

class HifzHistoryRecord {
  final String id;
  final HifzSessionType sessionType;
  final int? surahNumber;
  final String title;
  final DateTime completedAt;

  const HifzHistoryRecord({
    required this.id,
    required this.sessionType,
    this.surahNumber,
    required this.title,
    required this.completedAt,
  });
}
