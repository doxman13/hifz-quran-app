// lib/providers/hifz_session_provider.dart
//
// The single source of truth for all Hifz session logic.
// Supports both HifzSessionType.newVerses and HifzSessionType.review
// with all three ReviewGranularity options.
//
// ARCHITECTURE RULES (enforced here):
//  - Zero UI code in this file.
//  - All DB calls delegated to HifzRepository (injected dependency).
//  - Auto-save fires asynchronously on every incrementProgress() call.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/hifz_task.dart';
import '../models/hifz_session_config.dart';
import '../database/hifz_repository.dart';

class HifzSessionProvider extends ChangeNotifier {
  // ---------------------------------------------------------------------------
  // Dependencies
  // ---------------------------------------------------------------------------
  final HifzRepository _repo;

  // ---------------------------------------------------------------------------
  // Session type & mode
  // ---------------------------------------------------------------------------
  HifzSessionType _sessionType;
  HifzSessionType get sessionType => _sessionType;

  // ---------------------------------------------------------------------------
  // New Verses state (mirrors original provider exactly)
  // ---------------------------------------------------------------------------
  int _surahNumber;
  int _repeatStart;
  int _startVerse;
  int _endVerse;
  List<HifzTask> _tasks = [];
  int _currentTaskIndex = 0;
  bool _isPeekActive = false;
  final Map<int, int> _verseTallyMap = {};
  DateTime _startTime = DateTime.now();

  // ---------------------------------------------------------------------------
  // Review mode state
  // ---------------------------------------------------------------------------
  ReviewGranularity _reviewGranularity = ReviewGranularity.bySurah;
  ReviewTargetParams? _reviewTargetParams;
  List<ReviewStep> _reviewSteps = [];
  int _reviewStepIndex = 0;
  ReviewPhase _reviewPhase = ReviewPhase.visible;
  int _reviewTally = 0; // current recitation count in this phase (max 2)
  static const int _reviewTargetTally = 2;

  // ---------------------------------------------------------------------------
  // Shared
  // ---------------------------------------------------------------------------
  final String _sessionId;

  // ---------------------------------------------------------------------------
  // Constructor: New Verses mode (backward-compatible default)
  // ---------------------------------------------------------------------------
  HifzSessionProvider({
    HifzRepository? repository,
    int surahNumber = 1,
    int repeatStart = 1,
    int startVerse = 1,
    int endVerse = 3,
  })  : _repo = repository ?? HifzRepository(),
        _sessionType = HifzSessionType.newVerses,
        _surahNumber = surahNumber,
        _repeatStart = repeatStart,
        _startVerse = startVerse,
        _endVerse = endVerse,
        _sessionId = DateTime.now().millisecondsSinceEpoch.toString() {
    initRoutine(repeatStart, startVerse, endVerse);
  }

  // ---------------------------------------------------------------------------
  // Named constructor: Review mode
  // ---------------------------------------------------------------------------
  HifzSessionProvider.review({
    HifzRepository? repository,
    required ReviewGranularity granularity,
    required ReviewTargetParams targetParams,
  })  : _repo = repository ?? HifzRepository(),
        _sessionType = HifzSessionType.review,
        _surahNumber = 1,
        _repeatStart = 1,
        _startVerse = 1,
        _endVerse = 1,
        _sessionId = DateTime.now().millisecondsSinceEpoch.toString() {
    _reviewGranularity = granularity;
    _reviewTargetParams = targetParams;
    _initReviewRoutine(granularity, targetParams);
  }

  // ---------------------------------------------------------------------------
  // New Verses getters (preserved exactly)
  // ---------------------------------------------------------------------------
  int get surahNumber => _surahNumber;
  int get repeatStart => _repeatStart;
  int get startVerse => _startVerse;
  int get endVerse => _endVerse;
  List<HifzTask> get tasks => _tasks;
  int get currentTaskIndex => _currentTaskIndex;
  bool get isPeekActive => _isPeekActive;
  Map<int, int> get verseTallyMap => Map.unmodifiable(_verseTallyMap);
  DateTime get startTime => _startTime;

  HifzTask? get currentTask =>
      _tasks.isNotEmpty && _currentTaskIndex < _tasks.length
          ? _tasks[_currentTaskIndex]
          : null;

  bool get isNewVersesSessionCompleted => _currentTaskIndex >= _tasks.length;

  double get routineProgress {
    if (_sessionType == HifzSessionType.newVerses) {
      if (_tasks.isEmpty) return 0.0;
      int totalReq = 0;
      int currentReq = 0;
      for (final task in _tasks) {
        totalReq += task.targetRepetitions;
        currentReq += task.currentProgress;
      }
      return totalReq == 0 ? 0.0 : (currentReq / totalReq).clamp(0.0, 1.0);
    } else {
      if (_reviewSteps.isEmpty) return 0.0;
      // Each step has 2 phases × 2 tally = 4 increments total
      final totalIncrements = _reviewSteps.length * 4;
      final doneSteps = _reviewStepIndex * 4;
      final phaseOffset = (_reviewPhase == ReviewPhase.hidden ? 2 : 0) + _reviewTally;
      return ((doneSteps + phaseOffset) / totalIncrements).clamp(0.0, 1.0);
    }
  }

  int get totalRecitationsCount {
    if (_sessionType == HifzSessionType.newVerses) {
      int total = 0;
      _verseTallyMap.forEach((_, count) => total += count);
      return total;
    } else {
      // Each increment in review = 1 recitation of the whole block
      return (_reviewStepIndex * 4) +
          (_reviewPhase == ReviewPhase.hidden ? 2 : 0) +
          _reviewTally;
    }
  }

  // ---------------------------------------------------------------------------
  // Review mode getters
  // ---------------------------------------------------------------------------
  ReviewGranularity get reviewGranularity => _reviewGranularity;
  ReviewTargetParams? get reviewTargetParams => _reviewTargetParams;
  List<ReviewStep> get reviewSteps => _reviewSteps;
  int get reviewStepIndex => _reviewStepIndex;
  ReviewPhase get reviewPhase => _reviewPhase;
  int get reviewTally => _reviewTally;
  int get reviewTargetTally => _reviewTargetTally;

  ReviewStep? get currentReviewStep =>
      _reviewSteps.isNotEmpty && _reviewStepIndex < _reviewSteps.length
          ? _reviewSteps[_reviewStepIndex]
          : null;

  bool get isReviewSessionCompleted => _reviewStepIndex >= _reviewSteps.length;

  // Unified "is session done" property
  bool get isSessionCompleted => _sessionType == HifzSessionType.newVerses
      ? isNewVersesSessionCompleted
      : isReviewSessionCompleted;

  // ---------------------------------------------------------------------------
  // New Verses init (backward-compatible)
  // ---------------------------------------------------------------------------
  void initRoutine(int repeatStart, int startVerse, int endVerse, {int? surah}) {
    _sessionType = HifzSessionType.newVerses;
    if (surah != null) {
      _surahNumber = surah;
    }
    _repeatStart = repeatStart;
    _startVerse = startVerse;
    _endVerse = endVerse;
    _tasks = generateHifzRoutine(repeatStart, startVerse, endVerse);
    _currentTaskIndex = 0;
    _isPeekActive = false;
    _verseTallyMap.clear();
    _startTime = DateTime.now();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Review mode init
  // ---------------------------------------------------------------------------
  void initReviewRoutine(
      ReviewGranularity granularity, ReviewTargetParams params) {
    _sessionType = HifzSessionType.review;
    _reviewGranularity = granularity;
    _reviewTargetParams = params;
    _initReviewRoutine(granularity, params);
    _startTime = DateTime.now();
    notifyListeners();
  }

  void _initReviewRoutine(
      ReviewGranularity granularity, ReviewTargetParams params) {
    _reviewSteps = _buildReviewSteps(granularity, params);
    _reviewStepIndex = 0;
    _reviewPhase = ReviewPhase.visible;
    _reviewTally = 0;
    _isPeekActive = false;
  }

  List<ReviewStep> _buildReviewSteps(
      ReviewGranularity granularity, ReviewTargetParams params) {
    final steps = <ReviewStep>[];
    switch (granularity) {
      case ReviewGranularity.bySurah:
        final start = params.startSurah ?? 1;
        final end = params.endSurah ?? 114;
        for (int s = start; s <= end; s++) {
          steps.add(ReviewStep(
            label: 'Surah $s',
            primaryIndex: s,
            surahNumber: s,
          ));
        }
        break;

      case ReviewGranularity.byVerses:
        final surah = params.surahNumber ?? 1;
        final vStart = params.startVerse ?? 1;
        final vEnd = params.endVerse ?? 1;
        steps.add(ReviewStep(
          label: 'Surah $surah, Verses $vStart–$vEnd',
          primaryIndex: surah,
          surahNumber: surah,
          verseStart: vStart,
          verseEnd: vEnd,
        ));
        break;

      case ReviewGranularity.byPage:
        final pStart = params.startPage ?? 1;
        final pEnd = params.endPage ?? 1;
        for (int p = pStart; p <= pEnd; p++) {
          steps.add(ReviewStep(
            label: 'Page $p',
            primaryIndex: p,
          ));
        }
        break;
    }
    return steps;
  }

  // ---------------------------------------------------------------------------
  // Peek (hold-to-reveal)
  // ---------------------------------------------------------------------------
  void setPeekActive(bool active) {
    if (_isPeekActive != active) {
      _isPeekActive = active;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // incrementProgress — the single entry point for all tally actions
  // ---------------------------------------------------------------------------
  void incrementProgress() {
    if (_sessionType == HifzSessionType.newVerses) {
      _incrementNewVerses();
    } else {
      _incrementReview();
    }
    // Fire-and-forget auto-save
    unawaited(_autoSave());
  }

  void advanceStepOrPhase() {
    if (_sessionType == HifzSessionType.newVerses) {
      if (currentTask == null || isNewVersesSessionCompleted) return;
      _currentTaskIndex++;
      if (isNewVersesSessionCompleted) {
        unawaited(_repo.markNewVersesCompleted(_surahNumber));
        unawaited(_repo.recordHistory(HifzSessionType.newVerses, 'Surah $_surahNumber (New Verses)', surahNumber: _surahNumber));
        unawaited(_repo.clearActiveSession(sessionId: _sessionId));
      }
    } else {
      if (isReviewSessionCompleted) return;
      if (_reviewPhase == ReviewPhase.visible) {
        _reviewPhase = ReviewPhase.hidden;
        _reviewTally = 0;
      } else {
        final step = currentReviewStep;
        if (step != null) {
          if (_reviewGranularity == ReviewGranularity.bySurah) {
            unawaited(_repo.incrementReviewCount(step.primaryIndex));
            unawaited(_repo.recordHistory(HifzSessionType.review, 'Surah ${step.primaryIndex} (Review)', surahNumber: step.primaryIndex));
          } else {
            unawaited(_repo.recordHistory(HifzSessionType.review, '${step.label} (Review)', surahNumber: step.surahNumber));
          }
        }
        _reviewStepIndex++;
        _reviewPhase = ReviewPhase.visible;
        _reviewTally = 0;

        if (isReviewSessionCompleted) {
          unawaited(_repo.clearActiveSession(sessionId: _sessionId));
        }
      }
    }
    notifyListeners();
    if (!isSessionCompleted) {
      unawaited(_autoSave());
    }
  }

  void _incrementNewVerses() {
    if (currentTask == null || isNewVersesSessionCompleted) return;
    final task = currentTask!;
    if (task.currentProgress < task.targetRepetitions) {
      task.currentProgress++;
      for (int v in task.verseNumbers) {
        _verseTallyMap[v] = (_verseTallyMap[v] ?? 0) + 1;
      }
    }
    notifyListeners();
  }

  void _incrementReview() {
    if (isReviewSessionCompleted) return;
    if (_reviewTally < _reviewTargetTally) {
      _reviewTally++;
    }
    notifyListeners();
  }

  void undoLastIncrement() {
    if (_sessionType == HifzSessionType.newVerses) {
      _undoNewVerses();
    } else {
      _undoReview();
    }
    notifyListeners();
    unawaited(_autoSave());
  }

  void _undoNewVerses() {
    if (currentTask == null || isNewVersesSessionCompleted) return;
    final task = currentTask!;
    if (task.currentProgress > 0) {
      task.currentProgress--;
      for (int v in task.verseNumbers) {
        _verseTallyMap[v] = (_verseTallyMap[v] ?? 0) - 1;
      }
    }
  }

  void _undoReview() {
    if (isReviewSessionCompleted) return;
    if (_reviewTally > 0) {
      _reviewTally--;
    }
  }

  void resetCurrentTask() {
    if (_sessionType == HifzSessionType.newVerses) {
      if (currentTask == null || isNewVersesSessionCompleted) return;
      currentTask!.currentProgress = 0;
      for (int v in currentTask!.verseNumbers) {
        _verseTallyMap[v] = 0;
      }
    } else {
      _reviewTally = 0;
    }
    notifyListeners();
    unawaited(_autoSave());
  }

  void resetSession() {
    if (_sessionType == HifzSessionType.newVerses) {
      initRoutine(_repeatStart, _startVerse, _endVerse);
    } else if (_reviewTargetParams != null) {
      initReviewRoutine(_reviewGranularity, _reviewTargetParams!);
    }
    unawaited(_repo.clearActiveSession(sessionId: _sessionId));
  }

  // ---------------------------------------------------------------------------
  // Restore from snapshot (called by resume dialog)
  // ---------------------------------------------------------------------------
  void restoreFromSnapshot(ActiveSessionSnapshot snap) {
    _sessionType = snap.sessionType;
    _startTime = DateTime.fromMillisecondsSinceEpoch(snap.lastUpdatedTimestamp);

    if (snap.sessionType == HifzSessionType.newVerses) {
      _surahNumber = snap.nvSurahNumber ?? _surahNumber;
      _repeatStart = snap.nvRepeatStart ?? _repeatStart;
      _startVerse = snap.nvStartVerse ?? _startVerse;
      _endVerse = snap.nvEndVerse ?? _endVerse;
      _tasks = generateHifzRoutine(_repeatStart, _startVerse, _endVerse);
      _currentTaskIndex = snap.currentStepIndex.clamp(0, _tasks.length);
      // Restore partial tally on the active task
      if (_currentTaskIndex < _tasks.length) {
        _tasks[_currentTaskIndex].currentProgress = snap.currentTally;
      }
      _verseTallyMap.clear();
    } else {
      _reviewGranularity = snap.reviewGranularity ?? ReviewGranularity.bySurah;
      _reviewTargetParams = snap.reviewTargetParams;
      if (_reviewTargetParams != null) {
        _reviewSteps =
            _buildReviewSteps(_reviewGranularity, _reviewTargetParams!);
      }
      _reviewStepIndex =
          snap.currentStepIndex.clamp(0, _reviewSteps.length);
      _reviewPhase = snap.currentMode == 'hidden'
          ? ReviewPhase.hidden
          : ReviewPhase.visible;
      _reviewTally = snap.currentTally;
    }

    _isPeekActive = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Auto-save helper (private)
  // ---------------------------------------------------------------------------
  Future<void> _autoSave() async {
    try {
      late ActiveSessionSnapshot snap;
      if (_sessionType == HifzSessionType.newVerses) {
        snap = ActiveSessionSnapshot(
          sessionId: _sessionId,
          sessionType: _sessionType,
          nvSurahNumber: _surahNumber,
          nvRepeatStart: _repeatStart,
          nvStartVerse: _startVerse,
          nvEndVerse: _endVerse,
          currentStepIndex: _currentTaskIndex,
          currentMode: 'visible',
          currentTally: currentTask?.currentProgress ?? 0,
          targetTally:
              currentTask?.targetRepetitions ?? 10,
          lastUpdatedTimestamp: DateTime.now().millisecondsSinceEpoch,
        );
      } else {
        snap = ActiveSessionSnapshot(
          sessionId: _sessionId,
          sessionType: _sessionType,
          reviewGranularity: _reviewGranularity,
          reviewTargetParams: _reviewTargetParams,
          currentStepIndex: _reviewStepIndex,
          currentMode:
              _reviewPhase == ReviewPhase.hidden ? 'hidden' : 'visible',
          currentTally: _reviewTally,
          targetTally: _reviewTargetTally,
          lastUpdatedTimestamp: DateTime.now().millisecondsSinceEpoch,
        );
      }
      await _repo.saveActiveSession(snap);
    } catch (_) {
      // Never surface auto-save errors to the user.
    }
  }
}
