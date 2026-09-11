import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mushaf_models.dart';
import '../theme/app_theme.dart';
import '../shared/localization.dart';
import 'mushaf_reader_screen.dart';
import '../data/quran_foundation_repository.dart';
import '../data/quran_repository.dart';
import '../models/hifz_task.dart';
import '../providers/hifz_session_provider.dart';
import '../providers/mushaf_audio_provider.dart';
import '../providers/mushaf_reading_provider.dart';
import '../providers/notes_provider.dart';

import '../models/hifz_session_config.dart';
import '../database/hifz_repository.dart';
import '../providers/settings_provider.dart';
import 'hifz_new_verses_setup_screen.dart';
import 'hifz_review_setup_screen.dart';
import '../providers/ble_remote_provider.dart';
import 'hifz_mastery_list_screen.dart';
import 'hifz_settings_screen.dart';

import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/translation_manager_provider.dart';
import '../services/tajweed_service.dart';
import '../widgets/mutashabihat_sheet.dart';
import '../widgets/word_by_word_strip.dart';
import '../services/offline_quran_database_service.dart';
import '../shared/quran_translation_helper.dart';
import '../utils/html_parser.dart';
import '../providers/recitation_tracker_provider.dart';
import '../widgets/voice_recitation_banner.dart';

class HifzMemorizeScreen extends StatefulWidget {
  final QuranRepository quranRepository;
  final QuranFoundationRepository foundationRepository;
  final int initialPage;
  final int surahNumber;
  final int startVerse;
  final int endVerse;
  final HifzSessionType? initialSessionType;
  final int? repeatStart;
  final bool? isSurahMode;
  final ReviewGranularity? reviewGranularity;
  final ReviewTargetParams? reviewTargetParams;
  final ActiveSessionSnapshot? resumeSessionSnapshot;

  const HifzMemorizeScreen({
    super.key,
    required this.quranRepository,
    required this.foundationRepository,
    this.initialPage = 1,
    this.surahNumber = 1,
    this.startVerse = 1,
    this.endVerse = 3,
    this.initialSessionType,
    this.repeatStart,
    this.isSurahMode,
    this.reviewGranularity,
    this.reviewTargetParams,
    this.resumeSessionSnapshot,
  });

  @override
  State<HifzMemorizeScreen> createState() => _HifzMemorizeScreenState();
}

class _HifzMemorizeScreenState extends State<HifzMemorizeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _channel = MethodChannel('com.abuzayd.iqra/key_events');
  int _lastBleClickCount = 0;
  bool _isBleListenerAttached = false;
  DateTime? _lastShutterClickTime;
  late HifzSessionProvider _hifzProvider;
  bool _isMushafView = true;
  bool _isTajweedMushaf = false;
  bool _showWbw = false;
  bool _isSurahMode = true;
  int _selectedPage = 1;
  late int _selectedRepeatStart;
  late int _selectedStartVerse;
  late int _selectedEndVerse;
  late int _currentPage;
  final FocusNode _focusNode = FocusNode();
  final FocusNode _hiddenInputFocusNode = FocusNode();
  late PageController _newVersesPageController;
  late PageController _reviewPageController;
  int _reviewPageOffset = 0;
  bool _isTransitioningStep = false;
  String _transitionBannerMessage = '';

  // Voice recitation tracking state
  final Set<int> _voiceRevealedVerses = {};
  final Set<int> _weakOrAssistedVerses = {};
  int? _lastSkippedVerse;
  int? _hintedVerse;

  // Controls whether the top/bottom UI chrome is visible
  bool _chromeVisible = true;
  late AnimationController _chromeAnimController;
  late Animation<double> _chromeAnim;

  // List view scrolling & item keys
  final ScrollController _listScrollController = ScrollController();
  final Map<String, GlobalKey> _verseItemKeys = {};

  // Audio recitation tracking for page/list synchronization
  MushafAudioProvider? _audioProvider;
  String? _lastObservedAudioVerseKey;

  GlobalKey _keyForVerse(int surah, int verse) {
    return _verseItemKeys.putIfAbsent('$surah:$verse', GlobalKey.new);
  }

  Future<void> _animateToMushafPage(int targetPage, {bool animate = true}) async {
    final clampedPage = targetPage.clamp(1, 604);
    if (_currentPage == clampedPage) return;

    _currentPage = clampedPage;
    _selectedPage = clampedPage;

    if (!mounted) return;

    try {
      final isNewVerses = _hifzProvider.sessionType == HifzSessionType.newVerses;
      if (isNewVerses) {
        if (_newVersesPageController.hasClients) {
          final pageIndex = (clampedPage - 1).clamp(0, 603);
          if (animate) {
            await _newVersesPageController.animateToPage(
              pageIndex,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
            );
          } else {
            _newVersesPageController.jumpToPage(pageIndex);
          }
        }
      } else {
        if (_reviewPageController.hasClients) {
          final step = _hifzProvider.currentReviewStep;
          if (step != null) {
            final int basePageForStep;
            if (_hifzProvider.reviewGranularity == ReviewGranularity.byPage) {
              basePageForStep = step.primaryIndex;
            } else {
              final surah = step.surahNumber ?? step.primaryIndex;
              final verse = step.verseStart ?? 1;
              basePageForStep = qcf.getPageNumber(surah, verse);
            }
            final offset = clampedPage - basePageForStep;
            _reviewPageOffset = offset;
            final targetIndex = 10000 + offset;
            if (animate) {
              await _reviewPageController.animateToPage(
                targetIndex,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
              );
            } else {
              _reviewPageController.jumpToPage(targetIndex);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error navigating to page $clampedPage: $e');
    }
  }

  void _scrollToVerse(int surah, int verse, {bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _verseItemKeys['$surah:$verse'];
      final targetContext = key?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
          curve: Curves.easeInOutCubic,
          alignment: 0.12,
        );
      } else if (_listScrollController.hasClients) {
        final isNewVerses = _hifzProvider.sessionType == HifzSessionType.newVerses;
        int index = 0;
        if (isNewVerses) {
          final startDisplayVerse = _selectedRepeatStart < _selectedStartVerse
              ? _selectedRepeatStart
              : _selectedStartVerse;
          index = (verse - startDisplayVerse).clamp(0, 999);
        } else {
          final step = _hifzProvider.currentReviewStep;
          if (step != null) {
            final verses = _getVersesForReviewStep(step, _hifzProvider.reviewGranularity);
            final idx = verses.indexWhere((v) => v.$1 == surah && v.$2 == verse);
            if (idx >= 0) index = idx;
          }
        }
        final estimatedOffset = (index * 140.0).clamp(0.0, _listScrollController.position.maxScrollExtent);
        if (animate) {
          _listScrollController.animateTo(
            estimatedOffset,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
          );
        } else {
          _listScrollController.jumpTo(estimatedOffset);
        }
      }
    });
  }

  (int surah, int verse) _getLatestReadingVerse() {
    final surahNumber = _hifzProvider.currentSurahNumber;

    final tracker = Provider.of<RecitationTrackerProvider>(context, listen: false);
    if (tracker.isListening) {
      return (surahNumber, tracker.currentExpectedAyah);
    }

    final audio = Provider.of<MushafAudioProvider>(context, listen: false);
    if (audio.currentVerseKey != null) {
      final parts = audio.currentVerseKey!.split(':');
      if (parts.length == 2) {
        final s = int.tryParse(parts[0]) ?? surahNumber;
        final v = int.tryParse(parts[1]);
        if (v != null) return (s, v);
      }
    }

    if (_voiceRevealedVerses.isNotEmpty) {
      return (surahNumber, _voiceRevealedVerses.last);
    }

    if (_hifzProvider.sessionType == HifzSessionType.newVerses) {
      final task = _hifzProvider.currentTask;
      if (task != null && task.verseNumbers.isNotEmpty) {
        return (surahNumber, task.verseNumbers.first);
      }
      return (surahNumber, _selectedRepeatStart);
    }

    final step = _hifzProvider.currentReviewStep;
    if (step != null) {
      if (step.verseStart != null) {
        return (step.surahNumber ?? surahNumber, step.verseStart!);
      }
      final pageData = qcf.getPageData(_currentPage);
      if (pageData.isNotEmpty) {
        final firstItem = pageData.first;
        return (firstItem['surah'] as int, firstItem['start'] as int);
      }
    }

    return (surahNumber, 1);
  }

  void _toggleMushafListView() {
    final switchingToListView = _isMushafView;
    setState(() {
      _isMushafView = !_isMushafView;
    });
    if (switchingToListView) {
      final (surah, verse) = _getLatestReadingVerse();
      _scrollToVerse(surah, verse, animate: true);
    } else {
      final (surah, verse) = _getLatestReadingVerse();
      final targetPage = qcf.getPageNumber(surah, verse);
      if (targetPage != _currentPage) {
        _animateToMushafPage(targetPage, animate: false);
      }
    }
  }

  void _handleRoundRestartOrStepChange(int surah, int startAyah) {
    final targetPage = qcf.getPageNumber(surah, startAyah);
    if (_isMushafView) {
      if (targetPage != _currentPage) {
        _animateToMushafPage(targetPage, animate: true);
      }
    } else {
      _scrollToVerse(surah, startAyah, animate: true);
    }
  }

  void _syncToCurrentTaskOrStepStart() {
    final surahNumber = _hifzProvider.currentSurahNumber;
    final int startAyah;
    if (_hifzProvider.sessionType == HifzSessionType.newVerses) {
      final task = _hifzProvider.currentTask;
      startAyah = task != null ? task.verseNumbers.first : _selectedRepeatStart;
    } else {
      final step = _hifzProvider.currentReviewStep;
      startAyah = step?.verseStart ?? 1;
    }
    _handleRoundRestartOrStepChange(surahNumber, startAyah);
  }

  void _onAudioStateChanged() {
    final audio = _audioProvider;
    if (audio == null || !audio.isPlaying) return;
    final key = audio.currentVerseKey;
    if (key == null || key == _lastObservedAudioVerseKey) return;
    _lastObservedAudioVerseKey = key;

    final parts = key.split(':');
    if (parts.length != 2) return;
    final surah = int.tryParse(parts[0]);
    final verse = int.tryParse(parts[1]);
    if (surah == null || verse == null) return;

    final targetPage = qcf.getPageNumber(surah, verse);
    if (_isMushafView) {
      if (targetPage != _currentPage) {
        _animateToMushafPage(targetPage, animate: true);
      }
    } else {
      _scrollToVerse(surah, verse, animate: true);
    }
  }

  bool _isVerseHidden(int verseNum, HifzTask? currentTask) {
    final isReview = _hifzProvider.sessionType == HifzSessionType.review;
    if (isReview) {
      // In review mode: only hidden when in hidden review phase
      if (!_hifzProvider.isTargetHidden) {
        return false;
      }
      return !_voiceRevealedVerses.contains(verseNum);
    }

    if (verseNum < _selectedRepeatStart || verseNum > _selectedEndVerse) {
      return false;
    }

    // In New Verses mode:
    if (currentTask == null) return false;
    final targetVerse = currentTask.verseNumbers.last;
    if (verseNum > targetVerse) {
      // Future verses in progressive memorization are hidden
      return true;
    }

    final bool isStageHidden;
    if (verseNum < targetVerse) {
      if (currentTask.type == TaskType.cumulativeLink) {
        isStageHidden = _hifzProvider.isTargetHidden;
      } else {
        isStageHidden = false;
      }
    } else {
      isStageHidden = _hifzProvider.isTargetHidden;
    }

    if (!isStageHidden) {
      return false;
    }

    return !_voiceRevealedVerses.contains(verseNum);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentPage = widget.initialPage;
    _selectedPage = widget.initialPage;

    _chromeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1.0, // start visible
    );
    _chromeAnim = CurvedAnimation(
      parent: _chromeAnimController,
      curve: Curves.easeInOut,
    );

    // Apply initial input mode (Bluetooth shutter / BLE ring / in-app tally)
    _applyInputModeSettings();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TajweedService.load();
        _applyInputModeSettings();
        if (widget.resumeSessionSnapshot == null) {
          _checkForResumableSession();
        }

        // Ensure recitation tracking is strictly stopped when entering a session
        final tracker = Provider.of<RecitationTrackerProvider>(context, listen: false);
        if (tracker.isListening) {
          tracker.stopTracking();
        }

        // Warm up recitation engine in the background
        final settings = Provider.of<SettingsProvider>(context, listen: false);
        if (settings.voiceRecitationEnabled && !tracker.isEngineReady) {
          tracker.initializeEngine();
        }
      }
    });

    if (widget.resumeSessionSnapshot != null) {
      final snap = widget.resumeSessionSnapshot!;
      final restored = snap.sessionType == HifzSessionType.newVerses
          ? HifzSessionProvider(
              surahNumber: snap.nvSurahNumber ?? widget.surahNumber,
              repeatStart: snap.nvRepeatStart ?? widget.startVerse,
              startVerse: snap.nvStartVerse ?? widget.startVerse,
              endVerse: snap.nvEndVerse ?? widget.endVerse,
              sessionId: snap.sessionId,
            )
          : HifzSessionProvider.review(
              granularity: snap.reviewGranularity ?? ReviewGranularity.bySurah,
              targetParams: snap.reviewTargetParams ??
                  ReviewTargetParams.bySurah(startSurah: 100, endSurah: 114),
              sessionId: snap.sessionId,
            );
      restored.restoreFromSnapshot(snap);
      _hifzProvider = restored;

      if (snap.sessionType == HifzSessionType.newVerses) {
        _isSurahMode = true;
        _selectedRepeatStart = snap.nvRepeatStart ?? widget.startVerse;
        _selectedStartVerse = snap.nvStartVerse ?? widget.startVerse;
        _selectedEndVerse = snap.nvEndVerse ?? widget.endVerse;
        final targetSurah = snap.nvSurahNumber ?? widget.surahNumber;
        _currentPage = qcf.getPageNumber(targetSurah, _selectedStartVerse);
        _selectedPage = _currentPage;
      } else {
        _isSurahMode = true;
        final step = restored.currentReviewStep;
        if (step != null) {
          if (snap.reviewGranularity == ReviewGranularity.byPage) {
            _currentPage = step.primaryIndex;
          } else {
            final surah = step.surahNumber ?? step.primaryIndex;
            final verse = step.verseStart ?? 1;
            _currentPage = qcf.getPageNumber(surah, verse);
          }
        } else {
          _currentPage = widget.initialPage;
        }
        _selectedPage = _currentPage;
        _selectedRepeatStart = 1;
        _selectedStartVerse = 1;
        _selectedEndVerse = 1;
      }
    } else if (widget.initialSessionType == HifzSessionType.newVerses) {
      _isSurahMode = widget.isSurahMode ?? true;
      _selectedRepeatStart = widget.repeatStart ?? widget.startVerse;
      _selectedStartVerse = widget.startVerse;
      _selectedEndVerse = widget.endVerse;
      _currentPage = _isSurahMode
          ? qcf.getPageNumber(widget.surahNumber, _selectedStartVerse)
          : widget.initialPage;
      _selectedPage = _currentPage;
      _hifzProvider = HifzSessionProvider(
        surahNumber: widget.surahNumber,
        repeatStart: _selectedRepeatStart,
        startVerse: _selectedStartVerse,
        endVerse: _selectedEndVerse,
      );
    } else if (widget.initialSessionType == HifzSessionType.review) {
      _selectedRepeatStart = 1;
      _selectedStartVerse = 1;
      _selectedEndVerse = 1;
      _hifzProvider = HifzSessionProvider.review(
        granularity: widget.reviewGranularity!,
        targetParams: widget.reviewTargetParams!,
      );
      final step = _hifzProvider.currentReviewStep;
      if (step != null) {
        if (widget.reviewGranularity == ReviewGranularity.byPage) {
          _currentPage = step.primaryIndex;
        } else {
          final surah = step.surahNumber ?? step.primaryIndex;
          final verse = step.verseStart ?? 1;
          _currentPage = qcf.getPageNumber(surah, verse);
        }
      } else {
        _currentPage = widget.initialPage;
      }
      _selectedPage = _currentPage;
    } else {
      _selectedRepeatStart = widget.repeatStart ?? widget.startVerse;
      _selectedStartVerse = widget.startVerse;
      _selectedEndVerse = widget.endVerse;
      _currentPage = widget.initialPage;
      _selectedPage = widget.initialPage;
      _hifzProvider = HifzSessionProvider(
        surahNumber: widget.surahNumber,
        repeatStart: _selectedRepeatStart,
        startVerse: _selectedStartVerse,
        endVerse: _selectedEndVerse,
      );
    }

    _newVersesPageController = PageController(initialPage: (_currentPage - 1).clamp(0, 603));
    _reviewPageController = PageController(initialPage: 10000 + _reviewPageOffset);

  }

  void _applyInputModeSettings() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final inputMode = settings.hifzInputMode;

    // 1. Sync input mode to native channel (hardware key interception)
    final isShutter = inputMode == HifzInputMode.bluetoothShutter;
    _channel.invokeMethod('setInputMode', {
      'mode': isShutter ? 'bluetoothShutter' : 'none',
    });

    // 2. Configure method call handler for hardware/volume keys
    if (isShutter) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == "keyClick") {
          final audio = Provider.of<MushafAudioProvider>(context, listen: false);
          if (audio.isPlaying) return;

          final now = DateTime.now();
          if (_lastShutterClickTime != null &&
              now.difference(_lastShutterClickTime!).inMilliseconds < 450) {
            return;
          }
          _lastShutterClickTime = now;
          if (mounted && !_hifzProvider.isSessionCompleted) {
            _handleIncrementOrAdvance();
            HapticFeedback.lightImpact();
          }
        }
      });
    } else {
      _channel.setMethodCallHandler(null);
    }

    // 3. Dynamically attach or detach BLE Smart Ring listener
    final bleProvider = Provider.of<BleRemoteProvider>(context, listen: false);
    if (inputMode == HifzInputMode.bleSmartRing) {
      _lastBleClickCount = bleProvider.clickCount;
      if (!_isBleListenerAttached) {
        bleProvider.addListener(_onBleClick);
        _isBleListenerAttached = true;
      }
    } else {
      if (_isBleListenerAttached) {
        bleProvider.removeListener(_onBleClick);
        _isBleListenerAttached = false;
      }
    }

    // 4. Update wakelock
    _updateWakelockState();

    // 5. Update word-by-word visibility
    _showWbw = settings.showWordByWord;
  }

  void _updateWakelockState() {
    if (!mounted) return;
    final tracker = Provider.of<RecitationTrackerProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (tracker.isListening || settings.keepAwake) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _toggleVoiceRecitationMic(RecitationTrackerProvider tracker) async {
    if (tracker.isListening) {
      await tracker.stopTracking();
      _updateWakelockState();
      if (mounted) setState(() {});
      return;
    }

    if (!_hifzProvider.isVoiceTrackingEligible) {
      return;
    }

    if (tracker.isInitializing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recitation engine is warming up, please wait a moment...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final isReview = _hifzProvider.sessionType == HifzSessionType.review;
    final int surahNumber;
    final int startAyah;
    final int endAyah;
    final int totalNeeded;

    if (isReview) {
      final step = _hifzProvider.currentReviewStep;
      surahNumber = _hifzProvider.currentSurahNumber;
      startAyah = step?.verseStart ?? 1;
      endAyah = step?.verseEnd ?? qcf.getVerseCount(surahNumber);
      totalNeeded = endAyah - startAyah + 1;
    } else if (_hifzProvider.currentTask != null) {
      final task = _hifzProvider.currentTask!;
      surahNumber = _hifzProvider.currentSurahNumber;
      startAyah = task.verseNumbers.first;
      endAyah = task.verseNumbers.last;
      totalNeeded = task.verseNumbers.length;
    } else {
      surahNumber = _hifzProvider.currentSurahNumber;
      startAyah = _selectedRepeatStart;
      endAyah = _selectedEndVerse;
      totalNeeded = _selectedEndVerse - _selectedRepeatStart + 1;
    }

    _voiceRevealedVerses.clear();
    _lastSkippedVerse = null;
    _hintedVerse = null;

    try {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      WakelockPlus.enable();
      await tracker.startTracking(
        surah: surahNumber,
        startAyah: startAyah,
        endAyah: endAyah,
        sensitivity: settings.voiceRecitationSensitivity,
        adaptiveNoise: settings.voiceRecitationAdaptiveNoise,
        onVerseMatched: (ayah) {
          if (!mounted) return;
          setState(() {
            _voiceRevealedVerses.add(ayah);
            _lastSkippedVerse = null;
            if (_hintedVerse == ayah) {
              _hintedVerse = null;
            }
          });
          HapticFeedback.lightImpact();

          if (_voiceRevealedVerses.length >= totalNeeded) {
            _handleIncrementOrAdvance(clearVoiceImmediately: false);
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (!mounted) return;
              if (!_isTransitioningStep) {
                setState(() {
                  _voiceRevealedVerses.clear();
                  _hintedVerse = null;
                });
                if (tracker.isListening) {
                  tracker.setExpectedAyah(startAyah);
                }
                _handleRoundRestartOrStepChange(surahNumber, startAyah);
              }
            });
          } else {
            final nextAyah = ayah + 1;
            if (nextAyah <= endAyah) {
              final targetPage = qcf.getPageNumber(surahNumber, nextAyah);
              if (_isMushafView) {
                if (targetPage != _currentPage) {
                  Future.delayed(const Duration(milliseconds: 350), () {
                    if (mounted && _isMushafView && targetPage != _currentPage) {
                      _animateToMushafPage(targetPage, animate: true);
                    }
                  });
                }
              } else {
                _scrollToVerse(surahNumber, nextAyah, animate: true);
              }
            }
          }
        },
        onVerseSkipped: (expectedAyah, jumpedToAyah) {
          if (!mounted) return;
          HapticFeedback.heavyImpact();
          setState(() {
            _lastSkippedVerse = expectedAyah;
          });
        },
      );
    } catch (e) {
      _updateWakelockState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start voice tracking: $e')),
        );
      }
    }
    _updateWakelockState();
    if (mounted) setState(() {});
  }

  void _handleSkipOrRevealCurrentVerse(RecitationTrackerProvider tracker) {
    if (!tracker.isListening) return;

    final stuckAyah = tracker.currentExpectedAyah;
    final isReview = _hifzProvider.sessionType == HifzSessionType.review;
    final int surahNumber = _hifzProvider.currentSurahNumber;

    final int startAyah;
    final int endAyah;
    final int totalNeeded;

    if (isReview) {
      final step = _hifzProvider.currentReviewStep;
      startAyah = step?.verseStart ?? 1;
      endAyah = step?.verseEnd ?? qcf.getVerseCount(surahNumber);
      totalNeeded = endAyah - startAyah + 1;
    } else if (_hifzProvider.currentTask != null) {
      final task = _hifzProvider.currentTask!;
      startAyah = task.verseNumbers.first;
      endAyah = task.verseNumbers.last;
      totalNeeded = task.verseNumbers.length;
    } else {
      startAyah = _selectedRepeatStart;
      endAyah = _selectedEndVerse;
      totalNeeded = _selectedEndVerse - _selectedRepeatStart + 1;
    }

    // Stage 1: If current stuck verse is not yet hinted, hint it (reveal 1st word, do NOT advance tracker)
    if (_hintedVerse != stuckAyah) {
      setState(() {
        _hintedVerse = stuckAyah;
      });
      HapticFeedback.lightImpact();
      return;
    }

    // Stage 2: Second tap -> Strikeout! Full reveal, mark as assisted/weakness, and advance tracker
    setState(() {
      _voiceRevealedVerses.add(stuckAyah);
      _weakOrAssistedVerses.add(stuckAyah);
      _hintedVerse = null;
      _lastSkippedVerse = null;
    });

    HapticFeedback.mediumImpact();

    // Advance expected verse target if within range
    if (stuckAyah < endAyah) {
      tracker.setExpectedAyah(stuckAyah + 1);
    }

    // If all verses in the set are revealed, advance repetition round
    if (_voiceRevealedVerses.length >= totalNeeded) {
      _handleIncrementOrAdvance(clearVoiceImmediately: false);
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (!mounted) return;
        if (!_isTransitioningStep) {
          setState(() {
            _voiceRevealedVerses.clear();
            _hintedVerse = null;
          });
          if (tracker.isListening) {
            tracker.setExpectedAyah(startAyah);
          }
          _handleRoundRestartOrStepChange(surahNumber, startAyah);
        }
      });
    } else {
      final nextAyah = stuckAyah + 1;
      if (nextAyah <= endAyah) {
        final targetPage = qcf.getPageNumber(surahNumber, nextAyah);
        if (_isMushafView) {
          if (targetPage != _currentPage) {
            Future.delayed(const Duration(milliseconds: 350), () {
              if (mounted && _isMushafView && targetPage != _currentPage) {
                _animateToMushafPage(targetPage, animate: true);
              }
            });
          }
        } else {
          _scrollToVerse(surahNumber, nextAyah, animate: true);
        }
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyInputModeSettings();

    final audio = Provider.of<MushafAudioProvider>(context);
    if (_audioProvider != audio) {
      _audioProvider?.removeListener(_onAudioStateChanged);
      _audioProvider = audio;
      _audioProvider?.addListener(_onAudioStateChanged);
    }
  }

  void _onBleClick() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (settings.hifzInputMode != HifzInputMode.bleSmartRing) return;

    final bleProvider = Provider.of<BleRemoteProvider>(context, listen: false);
    if (bleProvider.clickCount > _lastBleClickCount) {
      _lastBleClickCount = bleProvider.clickCount;
      _handleIncrementOrAdvance();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateWakelockState();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioProvider?.removeListener(_onAudioStateChanged);
    final tracker = Provider.of<RecitationTrackerProvider>(context, listen: false);
    if (tracker.isListening) {
      tracker.stopTracking();
    }

    if (_isBleListenerAttached) {
      Provider.of<BleRemoteProvider>(context, listen: false)
          .removeListener(_onBleClick);
      _isBleListenerAttached = false;
    }
    // Always disable volume/hardware key interception when leaving Hifz session
    _channel.invokeMethod('setInputMode', {'mode': 'none'});
    _channel.setMethodCallHandler(null);

    _listScrollController.dispose();
    _newVersesPageController.dispose();
    _reviewPageController.dispose();
    _hiddenInputFocusNode.dispose();
    _focusNode.dispose();

    _chromeAnimController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _toggleChrome() {
    setState(() {
      _chromeVisible = !_chromeVisible;
    });
    if (_chromeVisible) {
      _chromeAnimController.forward();
    } else {
      _chromeAnimController.reverse();
    }
  }

  // ---------------------------------------------------------------------------
  // Session Recovery & Mode Selection Dialogs
  // ---------------------------------------------------------------------------

  Future<void> _checkForResumableSession() async {
    if (widget.initialSessionType != null) {
      return;
    }

    final repo = HifzRepository();
    final snap = widget.initialSessionType != null
        ? await repo.loadActiveSessionByConfig(
            sessionType: widget.initialSessionType!,
            nvSurahNumber: widget.surahNumber,
            nvStartVerse: widget.startVerse,
            nvEndVerse: widget.endVerse,
            reviewGranularity: widget.reviewGranularity,
            reviewTargetParams: widget.reviewTargetParams,
          )
        : await repo.loadActiveSession();
    if (!mounted) return;

    if (snap == null) {
      if (widget.initialSessionType != null) {
        return;
      }
      Navigator.pop(context);
      return;
    }

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isThai = settings.languageCode == 'th';

    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;
        final typeLabel = snap.sessionType == HifzSessionType.newVerses
            ? (isThai ? 'ท่องจำอายะห์ใหม่ (Takrar)' : 'New Verses (Takrar)')
            : (isThai ? 'ทบทวนฮิฟซ์ (Review)' : 'Review Mode');
        final stepLabel = snap.sessionType == HifzSessionType.review
            ? (isThai
                ? 'ขั้นตอนที่ ${snap.currentStepIndex + 1} · ${snap.currentMode == 'hidden' ? 'ซ่อน' : 'แสดง'}'
                : 'Step ${snap.currentStepIndex + 1} · ${snap.currentMode == 'hidden' ? 'Hidden' : 'Visible'}')
            : (isThai
                ? 'งานที่ ${snap.currentStepIndex + 1} · จำนวนรอบ ${snap.currentTally}'
                : 'Task ${snap.currentStepIndex + 1} · tally ${snap.currentTally}');

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: colorScheme.surface,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.history_rounded, color: colorScheme.primary, size: 32),
              const SizedBox(height: 8),
              Text(
                isThai ? 'กู้คืนเซสชัน?' : 'Resume Session?',
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isThai
                    ? 'พบการเรียนที่ทำค้างไว้ของโหมดนี้:'
                    : 'A previous session of this type was found:',
                style: textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ResumeRow(isThai ? 'โหมด' : 'Mode', typeLabel, colorScheme),
                    const SizedBox(height: 4),
                    _ResumeRow(isThai ? 'ความคืบหน้า' : 'Progress', stepLabel, colorScheme),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
              },
              child: Text(isThai ? 'เริ่มใหม่' : 'Start New'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isThai ? 'ทำต่อ' : 'Resume'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (resume == true) {
      final restored = snap.sessionType == HifzSessionType.newVerses
          ? HifzSessionProvider(
              surahNumber: snap.nvSurahNumber ?? widget.surahNumber,
              repeatStart: snap.nvRepeatStart ?? widget.startVerse,
              startVerse: snap.nvStartVerse ?? widget.startVerse,
              endVerse: snap.nvEndVerse ?? widget.endVerse,
              sessionId: snap.sessionId,
            )
          : HifzSessionProvider.review(
              granularity: snap.reviewGranularity ?? ReviewGranularity.bySurah,
              targetParams: snap.reviewTargetParams ??
                  ReviewTargetParams.bySurah(startSurah: 100, endSurah: 114),
              sessionId: snap.sessionId,
            );
      restored.restoreFromSnapshot(snap);

      int targetPage = 1;
      if (snap.sessionType == HifzSessionType.newVerses) {
        _selectedRepeatStart = snap.nvRepeatStart ?? _selectedRepeatStart;
        _selectedStartVerse = snap.nvStartVerse ?? _selectedStartVerse;
        _selectedEndVerse = snap.nvEndVerse ?? _selectedEndVerse;
        targetPage =
            qcf.getPageNumber(restored.surahNumber, _selectedStartVerse);
      } else {
        final step = restored.currentReviewStep;
        if (step != null) {
          if (snap.reviewGranularity == ReviewGranularity.byPage) {
            targetPage = step.primaryIndex;
          } else {
            final surah = step.surahNumber ?? step.primaryIndex;
            final verse = step.verseStart ?? 1;
            targetPage = qcf.getPageNumber(surah, verse);
          }
        }
      }

      setState(() {
        _hifzProvider = restored;
        _currentPage = targetPage;
        _selectedPage = targetPage;
        _reviewPageOffset = 0;
      });

      if (_newVersesPageController.hasClients) {
        _newVersesPageController.jumpToPage((targetPage - 1).clamp(0, 603));
      }
      if (_reviewPageController.hasClients) {
        _reviewPageController.jumpToPage(10000);
      }
    } else {
      if (widget.initialSessionType != null) {
        return;
      }
      await repo.clearActiveSession(sessionId: snap.sessionId);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }


  Future<void> _openNewVersesSetup(BuildContext context) async {
    final result = await Navigator.push<NewVersesSetupResult>(
      context,
      MaterialPageRoute(
        builder: (_) => HifzNewVersesSetupScreen(
          quranRepository: widget.quranRepository,
          initialSurah: _hifzProvider.surahNumber,
          initialStartVerse: _selectedStartVerse,
          initialEndVerse: _selectedEndVerse,
          initialRepeatStart: _selectedRepeatStart,
          initialPage: _selectedPage,
          initialIsSurahMode: _isSurahMode,
        ),
      ),
    );
    if (result != null && mounted) {
      final page = result.isSurahMode
          ? qcf.getPageNumber(result.surah, result.startVerse)
          : result.page;
      setState(() {
        _selectedRepeatStart = result.repeatStart;
        _selectedStartVerse = result.startVerse;
        _selectedEndVerse = result.endVerse;
        _isSurahMode = result.isSurahMode;
        _selectedPage = result.page;
        _currentPage = page;
        _hifzProvider.initRoutine(
          result.repeatStart,
          result.startVerse,
          result.endVerse,
          surah: result.surah,
        );
      });
      if (_newVersesPageController.hasClients) {
        _newVersesPageController.jumpToPage((page - 1).clamp(0, 603));
      }
    }
  }

  Future<void> _openReviewSetup(BuildContext context) async {
    final result = await Navigator.push<
        (ReviewGranularity, ReviewTargetParams, ActiveSessionSnapshot?)>(
      context,
      MaterialPageRoute(
        builder: (_) => HifzReviewSetupScreen(
          quranRepository: widget.quranRepository,
        ),
      ),
    );
    if (result != null && mounted) {
      final (granularity, params, _) = result;
      setState(() {
        _hifzProvider.initReviewRoutine(granularity, params);
        _reviewPageOffset = 0;
        final step = _hifzProvider.currentReviewStep;
        if (step != null) {
          if (granularity == ReviewGranularity.byPage) {
            _currentPage = step.primaryIndex;
          } else {
            final surah = step.surahNumber ?? step.primaryIndex;
            final verse = step.verseStart ?? 1;
            _currentPage = qcf.getPageNumber(surah, verse);
          }
          _selectedPage = _currentPage;
        }
      });
      if (_reviewPageController.hasClients) {
        _reviewPageController.jumpToPage(10000);
      }
    }
  }

  Widget _buildRepeatChipRow({
    required BuildContext context,
    required String title,
    required String subtitle,
    required int selectedValue,
    required ValueChanged<int> onSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final options = [1, 2, 5, 10];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              selectedValue == 1 ? '1× (Normal)' : '$selectedValue× Repeats',
              style: textTheme.labelSmall?.copyWith(
                color: selectedValue > 1
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight:
                    selectedValue > 1 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: options.map((opt) {
            final isSelected = selectedValue == opt;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  label: Text('$opt×'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) onSelected(opt);
                  },
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                  ),
                  selectedColor: colorScheme.primary,
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _showNewVersesAudioOptionsDialog(
      BuildContext context, HifzSessionProvider provider) async {
    final audio = Provider.of<MushafAudioProvider>(context, listen: false);

    if (audio.isPlaying) {
      audio.stop();
      return;
    }

    final currentTask = provider.currentTask;
    final currentTaskVerses = currentTask?.verseNumbers ?? [_selectedStartVerse];
    final surahStr = provider.surahNumber.toString();

    final fullRangeVerses = List.generate(
      _selectedEndVerse - _selectedRepeatStart + 1,
      (i) => _selectedRepeatStart + i,
    );

    final prefs = await SharedPreferences.getInstance();
    int verseRepeat = prefs.getInt('hifz_audio_verse_repeat') ?? 1;
    int rangeRepeat = prefs.getInt('hifz_audio_range_repeat') ?? 1;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;

        final taskLabel = currentTask == null
            ? 'Current Verse ($surahStr:${currentTaskVerses.first})'
            : currentTask.type == TaskType.singleVerse
                ? 'Current Verse ($surahStr:${currentTaskVerses.first})'
                : 'Current Sequence ($surahStr:${currentTaskVerses.first}–${currentTaskVerses.last})';

        final fullRangeLabel =
            'Full Selected Range ($surahStr:$_selectedRepeatStart–$_selectedEndVerse)';

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Audio Recitation',
                      style: textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Choose repetition options and playback range:',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 16),

                  // Repetition controls card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildRepeatChipRow(
                          context: context,
                          title: 'Repeat Each Verse',
                          subtitle:
                              'Recite each ayah N times before moving to next',
                          selectedValue: verseRepeat,
                          onSelected: (v) {
                            setModalState(() => verseRepeat = v);
                            prefs.setInt('hifz_audio_verse_repeat', v);
                          },
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        _buildRepeatChipRow(
                          context: context,
                          title: 'Repeat Entire Range',
                          subtitle: 'Loop the full selected sequence M times',
                          selectedValue: rangeRepeat,
                          onSelected: (v) {
                            setModalState(() => rangeRepeat = v);
                            prefs.setInt('hifz_audio_range_repeat', v);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Target Options
                  ListTile(
                    leading: Icon(Icons.play_circle_outline,
                        color: colorScheme.primary, size: 28),
                    title: Text('Play $taskLabel',
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      verseRepeat > 1 || rangeRepeat > 1
                          ? 'Repeat verse: ${verseRepeat}× · Range: ${rangeRepeat}×'
                          : 'Recite active verse or current sequence',
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    tileColor: colorScheme.surfaceContainerLow,
                    onTap: () {
                      Navigator.pop(ctx);
                      audio.playRange(
                        surahStr,
                        currentTaskVerses,
                        verseRepeat: verseRepeat,
                        rangeRepeat: rangeRepeat,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    leading: Icon(Icons.playlist_play_rounded,
                        color: colorScheme.primary, size: 28),
                    title: Text('Play $fullRangeLabel',
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      verseRepeat > 1 || rangeRepeat > 1
                          ? 'Repeat verse: ${verseRepeat}× · Range: ${rangeRepeat}×'
                          : 'Recite entire selected range including sequence start',
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    tileColor: colorScheme.surfaceContainerLow,
                    onTap: () {
                      Navigator.pop(ctx);
                      audio.playRange(
                        surahStr,
                        fullRangeVerses,
                        verseRepeat: verseRepeat,
                        rangeRepeat: rangeRepeat,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Volume slider
                  Row(
                    children: [
                      Icon(
                        audio.volume == 0.0
                            ? Icons.volume_off_rounded
                            : audio.volume < 0.5
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      Expanded(
                        child: Slider(
                          value: audio.volume,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (v) {
                            audio.setVolume(v);
                            setModalState(() {});
                          },
                          activeColor: colorScheme.primary,
                        ),
                      ),
                      Text(
                        '${(audio.volume * 100).round()}%',
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showReviewAudioOptionsDialog(
      BuildContext context, HifzSessionProvider provider) async {
    final audio = Provider.of<MushafAudioProvider>(context, listen: false);

    if (audio.isPlaying) {
      audio.stop();
      return;
    }

    final step = provider.currentReviewStep;
    if (step == null) return;

    final granularity = provider.reviewGranularity;
    final int basePageForStep;
    if (granularity == ReviewGranularity.byPage) {
      basePageForStep = step.primaryIndex;
    } else {
      final surah = step.surahNumber ?? step.primaryIndex;
      final verse = step.verseStart ?? 1;
      basePageForStep = qcf.getPageNumber(surah, verse);
    }
    final int currentReviewPage =
        (basePageForStep + _reviewPageOffset).clamp(1, 604);

    final prefs = await SharedPreferences.getInstance();
    int verseRepeat = prefs.getInt('hifz_audio_verse_repeat') ?? 1;
    int rangeRepeat = prefs.getInt('hifz_audio_range_repeat') ?? 1;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Review Audio Recitation',
                      style: textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Choose repetition options and playback range:',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 16),

                  // Repetition controls card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildRepeatChipRow(
                          context: context,
                          title: 'Repeat Each Verse',
                          subtitle:
                              'Recite each ayah N times before moving to next',
                          selectedValue: verseRepeat,
                          onSelected: (v) {
                            setModalState(() => verseRepeat = v);
                            prefs.setInt('hifz_audio_verse_repeat', v);
                          },
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        _buildRepeatChipRow(
                          context: context,
                          title: 'Repeat Entire Range',
                          subtitle: 'Loop the full selected sequence M times',
                          selectedValue: rangeRepeat,
                          onSelected: (v) {
                            setModalState(() => rangeRepeat = v);
                            prefs.setInt('hifz_audio_range_repeat', v);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  ListTile(
                    leading: Icon(Icons.play_circle_outline,
                        color: colorScheme.primary, size: 28),
                    title: Text('Play Current Step (${step.label})',
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      verseRepeat > 1 || rangeRepeat > 1
                          ? 'Repeat verse: ${verseRepeat}× · Range: ${rangeRepeat}×'
                          : 'Recite active review step',
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    tileColor: colorScheme.surfaceContainerLow,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (step.surahNumber != null ||
                          granularity != ReviewGranularity.byPage) {
                        final surahNum =
                            step.surahNumber ?? step.primaryIndex;
                        final vStart = step.verseStart ?? 1;
                        final vEnd =
                            step.verseEnd ?? qcf.getVerseCount(surahNum);
                        final verseList =
                            List.generate(vEnd - vStart + 1, (i) => vStart + i);
                        audio.playRange(
                          surahNum.toString(),
                          verseList,
                          verseRepeat: verseRepeat,
                          rangeRepeat: rangeRepeat,
                        );
                      } else {
                        _playPageAudio(
                          audio,
                          step.primaryIndex,
                          verseRepeat: verseRepeat,
                          rangeRepeat: rangeRepeat,
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    leading: Icon(Icons.menu_book_rounded,
                        color: colorScheme.primary, size: 28),
                    title: Text('Play Current Page (Page $currentReviewPage)',
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      verseRepeat > 1 || rangeRepeat > 1
                          ? 'Repeat verse: ${verseRepeat}× · Range: ${rangeRepeat}×'
                          : 'Recite page currently displayed on screen',
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    tileColor: colorScheme.surfaceContainerLow,
                    onTap: () {
                      Navigator.pop(ctx);
                      _playPageAudio(
                        audio,
                        currentReviewPage,
                        verseRepeat: verseRepeat,
                        rangeRepeat: rangeRepeat,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Volume slider
                  Row(
                    children: [
                      Icon(
                        audio.volume == 0.0
                            ? Icons.volume_off_rounded
                            : audio.volume < 0.5
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      Expanded(
                        child: Slider(
                          value: audio.volume,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (v) {
                            audio.setVolume(v);
                            setModalState(() {});
                          },
                          activeColor: colorScheme.primary,
                        ),
                      ),
                      Text(
                        '${(audio.volume * 100).round()}%',
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _playPageAudio(MushafAudioProvider audio, int pageNumber,
      {int verseRepeat = 1, int rangeRepeat = 1}) {
    final pageItems = qcf.getPageData(pageNumber);
    if (pageItems.isEmpty) return;
    final firstItem = pageItems.first;
    final int surah = firstItem['surah'];
    final int start = firstItem['start'];
    final int end = pageItems.last['end'];
    final verseList = List.generate(end - start + 1, (i) => start + i);
    audio.playRange(
      surah.toString(),
      verseList,
      verseRepeat: verseRepeat,
      rangeRepeat: rangeRepeat,
    );
  }


  Future<bool> _showExitConfirmationDialog(BuildContext context) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isThai = settings.languageCode == 'th';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.logout_rounded, color: colorScheme.error, size: 28),
          ),
          title: Text(
            isThai ? 'ออกจากโหมดท่องจำ?' : 'Exit Hifz Mode?',
            textAlign: TextAlign.center,
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          content: Text(
            isThai
                ? 'คุณแน่ใจหรือไม่ว่าต้องการออกจากโหมดท่องจำ? ระบบได้บันทึกความคืบหน้าของคุณโดยอัตโนมัติแล้ว'
                : 'Are you sure you want to exit Hifz mode? Your memorization progress has been saved automatically.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(isThai ? 'ออก' : 'Exit'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _confirmExit(BuildContext context) async {
    final shouldExit = await _showExitConfirmationDialog(context);
    if (shouldExit && context.mounted) {
      Navigator.pop(context);
    }
  }

  String _getVerseTranslationText(
      BuildContext context, int surahNumber, int verseNumber) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final transManager = Provider.of<TranslationManagerProvider>(context, listen: false);
    final verseKey = '$surahNumber:$verseNumber';
    final verse = widget.quranRepository.getVerse(
      surahNumber.toString(),
      verseNumber.toString(),
    );

    return resolveVerseTranslationText(
      context: context,
      verseKey: verseKey,
      verse: verse,
      settings: settings,
      transManager: transManager,
      repository: widget.quranRepository,
    );
  }


  void _showGundalReportModal(BuildContext context, HifzSessionProvider provider) {
    final isReview = provider.sessionType == HifzSessionType.review;
    final String col1Title;
    if (isReview) {
      switch (provider.reviewGranularity) {
        case ReviewGranularity.bySurah:
          col1Title = 'Surah';
          break;
        case ReviewGranularity.byVerses:
          col1Title = 'Verse Range';
          break;
        case ReviewGranularity.byPage:
          col1Title = 'Page';
          break;
      }
    } else {
      col1Title = 'Verse';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final elapsed = DateTime.now().difference(provider.startTime);
        final elapsedStr = '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s';

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Session Analytics',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(context, 'Recitations',
                        '${provider.totalRecitationsCount}', Icons.repeat),
                    _buildStatItem(
                        context, 'Time', elapsedStr, Icons.timer_outlined),
                    _buildStatItem(
                        context,
                        'Progress',
                        '${(provider.routineProgress * 100).round()}%',
                        Icons.check_circle_outline),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(isReview ? 'Review Summary' : 'Gundal Grid',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Table(
                    border: TableBorder.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    children: [
                      TableRow(
                        decoration:
                            BoxDecoration(color: colorScheme.surfaceContainerHigh),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Text(col1Title,
                                style: textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Text('Recitations',
                                style: textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center),
                          ),
                        ],
                      ),
                      if (isReview)
                        for (int i = 0; i < provider.reviewSteps.length; i++)
                          _buildReviewTableRow(context, provider, i, colorScheme, textTheme)
                      else
                        for (int v = provider.startVerse; v <= provider.endVerse; v++)
                          TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Text('Verse $v',
                                    style: textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                    textAlign: TextAlign.center),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Text(
                                  '${provider.verseTallyMap[v] ?? 0}x',
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Close'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  TableRow _buildReviewTableRow(
      BuildContext context,
      HifzSessionProvider provider,
      int index,
      ColorScheme colorScheme,
      TextTheme textTheme) {
    final step = provider.reviewSteps[index];
    final String countStr;
    final bool isDone;

    if (provider.isReviewSessionCompleted || index < provider.reviewStepIndex) {
      countStr = '2/2';
      isDone = true;
    } else if (index == provider.reviewStepIndex) {
      countStr = '${provider.reviewTally}/2';
      isDone = provider.reviewTally >= provider.reviewTargetTally;
    } else {
      countStr = '0/2';
      isDone = false;
    }

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            step.label,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDone ? colorScheme.primary : colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            countStr,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDone ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(
      BuildContext context, String label, String value, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Icon(icon, color: colorScheme.primary, size: 22),
        const SizedBox(height: 4),
        Text(value,
            style: textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
        const SizedBox(height: 2),
        Text(label,
            style:
                textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
      ],
    );
  }

  PopupMenuItem<String> _buildPopupItem(
      String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ChangeNotifierProvider<HifzSessionProvider>.value(
      value: _hifzProvider,
      child: Consumer<HifzSessionProvider>(
        builder: (context, provider, child) {
          final isReview = provider.sessionType == HifzSessionType.review;

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              await _confirmExit(context);
            },
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              canRequestFocus: true,
              child: Scaffold(
              body: Stack(
                children: [
                  // Hidden input for key events
                  Positioned(
                    left: -100,
                    top: -100,
                    child: SizedBox(
                      width: 1,
                      height: 1,
                      child: TextField(
                        focusNode: _hiddenInputFocusNode,
                        autofocus: true,
                        readOnly: true,
                        showCursor: false,
                        enableInteractiveSelection: false,
                        decoration:
                            const InputDecoration(border: InputBorder.none),
                      ),
                    ),
                  ),

                  // Main content
                  Positioned.fill(
                    child: Column(
                      children: [
                        // Collapsible top chrome
                        SizeTransition(
                          sizeFactor: _chromeAnim,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildCompactTopBar(
                                  context, provider, colorScheme, textTheme, isReview),
                              Consumer<RecitationTrackerProvider>(
                                builder: (context, tracker, _) {
                                  if (!provider.isVoiceTrackingEligible &&
                                      !tracker.isListening &&
                                      tracker.errorMessage == null) {
                                    return const SizedBox.shrink();
                                  }
                                  if (!tracker.isListening &&
                                      tracker.skippedFromAyah == null &&
                                      !tracker.isInitializing &&
                                      tracker.errorMessage == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return VoiceRecitationBanner(
                                    tracker: tracker,
                                    onToggleMic: () => _toggleVoiceRecitationMic(tracker),
                                    onDismissAlert: () {
                                      tracker.dismissSkipAlert();
                                      setState(() => _lastSkippedVerse = null);
                                    },
                                    onRetryVerse: (ayah) {
                                      tracker.retryVerse(ayah);
                                      setState(() => _lastSkippedVerse = null);
                                    },
                                    onAcceptSkip: (fromAyah, toAyah) {
                                      tracker.acceptSkip();
                                      setState(() => _lastSkippedVerse = null);
                                    },
                                    onSkipOrRevealNextVerse: () => _handleSkipOrRevealCurrentVerse(tracker),
                                    isCurrentVerseHinted: _hintedVerse == tracker.currentExpectedAyah,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // Reading area - takes all remaining space
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _chromeAnimController,
                            builder: (context, child) {
                              final topPadding = (MediaQuery.of(context).padding.top + 16.0) * (1.0 - _chromeAnim.value);
                              return Padding(
                                padding: EdgeInsets.only(top: topPadding),
                                child: child,
                              );
                            },
                            child: GestureDetector(
                              onTap: () {
                                // Single tap on reading area toggles top chrome
                                _toggleChrome();
                              },
                              behavior: HitTestBehavior.translucent,
                              child: isReview
                                  ? _buildReviewBody(
                                    context, provider, colorScheme, textTheme)
                                : _buildNewVersesBody(
                                    context, provider, colorScheme, textTheme),
                          ),
                        ),
                      ),

                        // Bottom chrome - stays visible so user can see count and tap tally
                        _buildBottomBar(
                            context, provider, colorScheme, textTheme, isReview),
                      ],
                    ),
                  ),

                  // Step completion banner (always on top)
                  if (_isTransitioningStep)
                    Positioned(
                      top: _chromeVisible ? kToolbarHeight + 16 : 16,
                      left: 20,
                      right: 20,
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        color: colorScheme.tertiaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: colorScheme.tertiary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.check_rounded,
                                    color: colorScheme.onTertiary, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  _transitionBannerMessage,
                                  style: textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onTertiaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: colorScheme.tertiary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Floating pull-down handle ("ติ่ง") when top chrome is collapsed
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: !_chromeVisible ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: IgnorePointer(
                            ignoring: _chromeVisible,
                            child: GestureDetector(
                              onTap: _toggleChrome,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.12),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 16,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      context.tr('menu'),
                                      style: GoogleFonts.notoSansThai(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

  // ---------------------------------------------------------------------------
  // Compact top bar (replaces AppBar)
  // ---------------------------------------------------------------------------
  Widget _buildCompactTopBar(BuildContext context, HifzSessionProvider provider,
      ColorScheme colorScheme, TextTheme textTheme, bool isReview) {
    final modeColor = isReview ? colorScheme.secondary : colorScheme.primary;
    final String modeLabel;
    if (isReview) {
      modeLabel = 'Review';
    } else {
      final startDisplayVerse = _selectedRepeatStart < _selectedStartVerse
          ? _selectedRepeatStart
          : _selectedStartVerse;
      modeLabel = 'S.${provider.surahNumber} : $startDisplayVerse-$_selectedEndVerse';
    }

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 4,
        left: 8,
        right: 8,
        bottom: 4,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => _confirmExit(context),
            tooltip: 'Back',
          ),

          // Mode pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: modeColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              modeLabel,
              style: textTheme.labelMedium?.copyWith(
                  color: modeColor, fontWeight: FontWeight.bold),
            ),
          ),

          const Spacer(),

          // Audio recitation options button (for both New Verses & Review mode)
          Consumer<MushafAudioProvider>(
            builder: (context, audio, _) {
              return IconButton(
                icon: audio.isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    : Icon(
                        audio.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.volume_up_rounded,
                        color: audio.isPlaying ? colorScheme.primary : null,
                        size: 22,
                      ),
                tooltip: audio.isLoading ? 'Loading audio...' : 'Audio Recitation',
                onPressed: () {
                  if (isReview) {
                    _showReviewAudioOptionsDialog(context, provider);
                  } else {
                    _showNewVersesAudioOptionsDialog(context, provider);
                  }
                },
              );
            },
          ),

          // View toggle for both new verses & review modes
          IconButton(
            icon: Icon(
              _isMushafView ? Icons.view_list_rounded : Icons.menu_book_rounded,
              size: 20,
            ),
            tooltip: _isMushafView ? 'List View' : 'Mushaf View',
            onPressed: _toggleMushafListView,
          ),

          // Visibility toggle (Show / Hide text override)
          IconButton(
            icon: Icon(
              provider.isTargetHidden
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: provider.isVisibilityOverridden
                  ? colorScheme.primary
                  : null,
              size: 20,
            ),
            tooltip: provider.isTargetHidden ? 'Show Text' : 'Hide Text',
            onPressed: () => provider.toggleVisibilityOverride(),
          ),

          // Voice Recitation toggle button (only in eligible hidden stages)
          if (provider.isVoiceTrackingEligible)
            Consumer<RecitationTrackerProvider>(
              builder: (context, tracker, _) {
              final isListening = tracker.isListening;
              final isInit = tracker.isInitializing;
              return IconButton(
                icon: isInit
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isListening
                              ? colorScheme.primaryContainer
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: isListening
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                tooltip: isListening
                    ? 'Voice Recitation Active (Tap to pause)'
                    : 'Start Voice Recitation',
                onPressed: () => _toggleVoiceRecitationMic(tracker),
              );
            },
          ),

          // Gear/more icon with popup menu (all settings consolidated)
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (val) async {
                  switch (val) {
                    case 'switch_mode':
                      Navigator.pop(context);
                      break;
                    case 'wbw':
                      setState(() {
                        _showWbw = !_showWbw;
                      });
                      break;
                    case 'dark_mode':
                      settings.toggleDarkMode(!settings.isDarkMode);
                      break;
                    case 'range':
                      _openNewVersesSetup(context);
                      break;
                    case 'report':
                      _showGundalReportModal(context, provider);
                      break;
                    case 'mastery':
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HifzMasteryListScreen(
                              quranRepository: widget.quranRepository),
                        ),
                      );
                      break;
                    case 'tajweed':
                      setState(() {
                        _isTajweedMushaf = !_isTajweedMushaf;
                      });
                      break;
                    case 'ble_settings':
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HifzSettingsScreen(),
                        ),
                      );
                      if (mounted) {
                        _applyInputModeSettings();
                        setState(() {});
                      }
                      break;
                  }
                },
                itemBuilder: (_) => [
                  _buildPopupItem('switch_mode', Icons.swap_horiz_rounded, 'Switch Mode'),
                  if (!_isMushafView)
                    _buildPopupItem(
                      'wbw',
                      _showWbw ? Icons.spellcheck_rounded : Icons.spellcheck_outlined,
                      _showWbw ? 'Hide Word by Word' : 'Word by Word (WBW)',
                    ),
                  _buildPopupItem(
                    'dark_mode',
                    settings.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    settings.isDarkMode ? 'Light Mode' : 'Dark Mode',
                  ),
                  _buildPopupItem('tajweed', Icons.font_download_outlined, _isTajweedMushaf ? 'Standard Mushaf' : 'Tajweed Mushaf'),
                  _buildPopupItem('ble_settings', Icons.settings_outlined, 'Hifz & Translation Settings'),
                  if (!isReview)
                    _buildPopupItem('range', Icons.tune_rounded, 'Select Range'),
                  _buildPopupItem('report', Icons.analytics_outlined, 'Report'),
                  _buildPopupItem('mastery', Icons.workspace_premium_outlined, 'Mastery'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Review body
  // ---------------------------------------------------------------------------
  Widget _buildReviewBody(BuildContext context, HifzSessionProvider provider,
      ColorScheme colorScheme, TextTheme textTheme) {
    final step = provider.currentReviewStep ??
        (provider.reviewSteps.isNotEmpty ? provider.reviewSteps.first : null);
    if (step == null) return const SizedBox();

    if (!_isMushafView) {
      return _buildReviewListView(context, provider, step, colorScheme, textTheme);
    }

    final isHiddenPhase = provider.isTargetHidden;
    final granularity = provider.reviewGranularity;

    final int basePageForStep;
    if (granularity == ReviewGranularity.byPage) {
      basePageForStep = step.primaryIndex;
    } else {
      final surah = step.surahNumber ?? step.primaryIndex;
      final verse = step.verseStart ?? 1;
      basePageForStep = qcf.getPageNumber(surah, verse);
    }

    final activeSurah = (granularity != ReviewGranularity.byPage)
        ? (step.surahNumber ?? step.primaryIndex)
        : null;
    Set<String> highlightedVerseKeys = const {};
    if (activeSurah != null) {
      final vStart = step.verseStart ?? 1;
      final vEnd = step.verseEnd ?? qcf.getVerseCount(activeSurah);
      highlightedVerseKeys = {
        for (int v = vStart; v <= vEnd; v++) '$activeSurah:$v'
      };
    }

    return PageView.builder(
      controller: _reviewPageController,
      reverse: true,
      onPageChanged: (index) {
        setState(() {
          _reviewPageOffset = index - 10000;
          _currentPage = (basePageForStep + _reviewPageOffset).clamp(1, 604);
        });
      },
      itemBuilder: (context, index) {
        final pageOffset = index - 10000;
        final pageToShow = (basePageForStep + pageOffset).clamp(1, 604);
        return _buildReviewMushafView(
          key: ValueKey('review_page_$pageToShow'),
          context: context,
          provider: provider,
          step: step,
          colorScheme: colorScheme,
          pageToShow: pageToShow,
          activeSurah: activeSurah,
          highlightedVerseKeys: highlightedVerseKeys,
          isHiddenPhase: isHiddenPhase,
        );
      },
    );
  }

  List<(int surah, int verseNum)> _getVersesForReviewStep(
    ReviewStep step,
    ReviewGranularity granularity,
  ) {
    final List<(int surah, int verseNum)> verses = [];
    if (granularity == ReviewGranularity.byPage) {
      final pageData = qcf.getPageData(step.primaryIndex);
      for (final item in pageData) {
        final int s = item['surah'];
        final int start = item['start'];
        final int end = item['end'];
        for (int v = start; v <= end; v++) {
          verses.add((s, v));
        }
      }
    } else {
      final int s = step.surahNumber ?? step.primaryIndex;
      final int start = step.verseStart ?? 1;
      final int end = step.verseEnd ?? qcf.getVerseCount(s);
      for (int v = start; v <= end; v++) {
        verses.add((s, v));
      }
    }
    return verses;
  }

  Widget _buildReviewListView(
    BuildContext context,
    HifzSessionProvider provider,
    ReviewStep step,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final granularity = provider.reviewGranularity;
    final isHidden = provider.isTargetHidden;
    final verses = _getVersesForReviewStep(step, granularity);

    if (verses.isEmpty) {
      return Center(
        child: Text(
          'No verses found for this step',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.separated(
      controller: _listScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: verses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final (surahNum, verseNum) = verses[index];
        final verseKey = '$surahNum:$verseNum';
        final translation = _getVerseTranslationText(context, surahNum, verseNum);
        final isVerseHidden = isHidden && !_voiceRevealedVerses.contains(verseNum);

        return KeyedSubtree(
          key: _keyForVerse(surahNum, verseNum),
          child: Consumer<MushafAudioProvider>(
          builder: (context, audio, _) {
            final isCurrentPlaying =
                audio.isPlaying && audio.currentVerseKey == verseKey;
            final isCurrentLoading =
                audio.isLoading && audio.currentVerseKey == verseKey;

            Widget playIcon;
            if (isCurrentLoading) {
              playIcon = SizedBox(
                width: 24,
                height: 24,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
              );
            } else if (isCurrentPlaying) {
              playIcon = Icon(
                Icons.stop_circle_rounded,
                color: colorScheme.primary,
                size: 24,
              );
            } else {
              playIcon = const Icon(
                Icons.volume_up_outlined,
                size: 24,
              );
            }

            final notesProvider = context.watch<NotesProvider>();
            final readingProvider = context.watch<MushafReadingProvider>();
            final settings = context.watch<SettingsProvider>();
            final favorited = notesProvider.getNoteObjectForVerse(
                  surahNum.toString(),
                  verseNum.toString(),
                ) !=
                null;
            final bookmarked = readingProvider.isVerseBookmarked(
              1,
              1,
              verseKey,
            );

            final showBismillah =
                (verseNum == 1) && surahNum != 1 && surahNum != 9;

            final isWeak = _weakOrAssistedVerses.contains(verseNum);
            final isHinted = isVerseHidden && _hintedVerse == verseNum;
            final card = AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isWeak
                    ? colorScheme.errorContainer.withValues(alpha: 0.20)
                    : (isHinted
                        ? colorScheme.primaryContainer.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerLow),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isCurrentPlaying
                      ? colorScheme.primary
                      : (isWeak
                          ? colorScheme.error.withValues(alpha: 0.55)
                          : (isHinted
                              ? colorScheme.primary.withValues(alpha: 0.5)
                              : colorScheme.outlineVariant.withValues(alpha: 0.3))),
                  width: (isCurrentPlaying || isWeak || isHinted) ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            verseKey,
                            style: GoogleFonts.notoSansThai(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isWeak
                                  ? colorScheme.error
                                  : colorScheme.primary.withValues(alpha: 0.8),
                            ),
                          ),
                          if (isWeak) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.flag_outlined, size: 12, color: colorScheme.error),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Assisted',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colorScheme.error,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (isHinted) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lightbulb_outline_rounded, size: 12, color: colorScheme.onPrimaryContainer),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Hint: 1st word',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (OfflineQuranDatabaseService.hasMutashabihatSync(
                              verseKey)) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () =>
                                  MutashabihatSheet.show(context, verseKey),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: colorScheme.primary
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.sync_alt_rounded,
                                      size: 13,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'โองการคล้ายกัน',
                                      style: GoogleFonts.notoSansThai(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        onSelected: (val) async {
                          if (val == 'play') {
                            if (isCurrentPlaying || isCurrentLoading) {
                              audio.stop();
                            } else {
                              audio.playRange(
                                surahNum.toString(),
                                [verseNum],
                              );
                            }
                          } else if (val == 'bookmark') {
                            await readingProvider.toggleVerseBookmark(
                              mushafId: 1,
                              pageNumber: 1,
                              verseKey: verseKey,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    bookmarked
                                        ? 'Bookmark removed'
                                        : 'Verse bookmarked',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          } else if (val == 'favorite') {
                            final surahStr = surahNum.toString();
                            final verseStr = verseNum.toString();
                            if (favorited) {
                              await notesProvider.deleteNote(
                                  surahStr, verseStr);
                            } else {
                              await notesProvider.saveNote(
                                surahId: surahStr,
                                verseId: verseStr,
                                noteText: '',
                              );
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    favorited
                                        ? 'Removed from favorites'
                                        : 'Saved to favorites',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          } else if (val == 'wbw') {
                            WordByWordSheet.show(context, verseKey: verseKey);
                          } else if (val == 'mutashabihat') {
                            MutashabihatSheet.show(context, verseKey);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'play',
                            child: Row(
                              children: [
                                Icon(
                                  isCurrentPlaying
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                  size: 20,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  isCurrentPlaying
                                      ? 'Pause verse'
                                      : 'Play verse',
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'wbw',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.spellcheck_rounded,
                                  size: 20,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                const Text('แปลคำต่อคำ (Word by Word)'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'bookmark',
                            child: Row(
                              children: [
                                Icon(
                                  bookmarked
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  size: 20,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  bookmarked
                                      ? 'Remove bookmark'
                                      : 'Bookmark',
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'favorite',
                            child: Row(
                              children: [
                                Icon(
                                  favorited
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 20,
                                  color: favorited
                                      ? Colors.red
                                      : colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  favorited
                                      ? 'Remove favorite'
                                      : 'Favorite',
                                ),
                              ],
                            ),
                          ),
                          if (OfflineQuranDatabaseService.hasMutashabihatSync(
                              verseKey))
                            PopupMenuItem(
                              value: 'mutashabihat',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.sync_alt_rounded,
                                    size: 20,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                      'โองการที่คล้ายคลึงกัน (Similar Ayat)'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (!isHidden)
                        IconButton(
                          icon: playIcon,
                          onPressed: () {
                            if (isCurrentPlaying || isCurrentLoading) {
                              audio.stop();
                            } else {
                              audio.playRange(
                                surahNum.toString(),
                                [verseNum],
                              );
                            }
                          },
                        ),
                      Expanded(
                        child: FutureBuilder<String>(
                          future: widget.quranRepository.fetchArabicVerse(
                              surahNum.toString(), verseNum.toString()),
                          builder: (context, snapshot) {
                            final arabicText = snapshot.data ?? '';
                            final cleanedText = formatArabicAyahText(
                              arabicText,
                              verseNumber: verseNum,
                            );
                            final isHintedVerse = isVerseHidden && _hintedVerse == verseNum;
                            final firstSpaceIndex = cleanedText.indexOf(' ');
                            final List<InlineSpan> spans;
                            if (isHintedVerse) {
                              if (firstSpaceIndex != -1) {
                                spans = [
                                  TextSpan(
                                    text: cleanedText.substring(0, firstSpaceIndex),
                                    style: TextStyle(
                                      color: textTheme.bodyLarge?.color,
                                      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  TextSpan(
                                    text: cleanedText.substring(firstSpaceIndex),
                                    style: const TextStyle(
                                      color: Colors.transparent,
                                    ),
                                  ),
                                ];
                              } else {
                                spans = [
                                  TextSpan(
                                    text: cleanedText,
                                    style: TextStyle(
                                      color: textTheme.bodyLarge?.color,
                                      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ];
                              }
                            } else {
                              spans = [
                                TextSpan(
                                  text: cleanedText,
                                  style: TextStyle(
                                    color: isVerseHidden
                                        ? Colors.transparent
                                        : textTheme.bodyLarge?.color,
                                  ),
                                ),
                              ];
                            }

                            return Directionality(
                              textDirection: TextDirection.rtl,
                              child: RichText(
                                textAlign: TextAlign.right,
                                softWrap: true,
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontFamily: 'UthmanicHafs',
                                    fontSize: 28,
                                    height: 2.0,
                                  ),
                                  children: spans,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_showWbw) ...[
                    const SizedBox(height: 12),
                    WordByWordView(
                      verseKey: verseKey,
                      isHidden: isVerseHidden,
                      isDarkMode:
                          Theme.of(context).brightness == Brightness.dark,
                    ),
                  ],
                  if (translation.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      thickness: 0.8,
                      color:
                          colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 10),
                    RichText(
                      softWrap: true,
                      text: TextSpan(
                        children: HtmlParser.parseTranslationText(
                          context,
                          translation,
                          getTranslationTextStyle(
                            context,
                            fontSize: settings.translationFontSize,
                            height: 1.5,
                            color: isVerseHidden
                                ? Colors.transparent
                                : colorScheme.onSurfaceVariant,
                            translationId: settings.primaryTranslationId,
                          ),
                          isVerseHidden ? Colors.transparent : colorScheme.primary,
                          verseKey: verseKey,
                          translationId: settings.primaryTranslationId,
                          isInteractive: !isVerseHidden,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );

            if (!showBismillah) return card;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: Center(
                    child: Text(
                      'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: 'UthmanicHafs',
                        fontSize: 22,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                card,
              ],
            );
          },
        ),
        );
      },
    );
  }


  Widget _buildReviewMushafView({
    Key? key,
    required BuildContext context,
    required HifzSessionProvider provider,
    required ReviewStep step,
    required ColorScheme colorScheme,
    required int pageToShow,
    required int? activeSurah,
    required Set<String> highlightedVerseKeys,
    required bool isHiddenPhase,
  }) {
    return Stack(
      key: key,
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: InteractiveViewer(
              minScale: 1.0,
            maxScale: 4.0,
            child: FutureBuilder<MushafPage>(
              future: widget.foundationRepository.fetchPage(
                  mushafId: _isTajweedMushaf ? 11 : 2, pageNumber: pageToShow),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final mushafPage = snapshot.data!;
                final actualMushafId = _isTajweedMushaf ? 11 : 2;
                final layout = MushafLayoutProfile.forMushaf(actualMushafId);
                final fontFamily = widget.foundationRepository.getFontFamily(actualMushafId, pageToShow);

                final surahStartsByLine = <int, List<String>>{};
                for (final v in mushafPage.verses) {
                  if (v.verseId != '1' || v.words.isEmpty) continue;
                  surahStartsByLine
                      .putIfAbsent(v.words.first.lineNumber, () => [])
                      .add(v.surahId);
                }
                final verseEndWords = <MushafWord>{};
                for (final v in mushafPage.verses) {
                  if (v.words.isNotEmpty) verseEndWords.add(v.words.last);
                }

                return LayoutBuilder(
                  builder: (ctx, constraints) {
                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: layout.horizontalPadding),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                        width: layout.pageWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final line in mushafPage.lines) ...[
                              for (final sid in surahStartsByLine[
                                          line.first.lineNumber] ??
                                      const <String>[])
                                QcfSurahHeader(
                                  surahNumber: int.tryParse(sid) ?? 0,
                                  colors: AppTheme.colors(
                                      isDark: Theme.of(ctx).brightness ==
                                          Brightness.dark),
                                  showSurahFrame: !surahsWithFrameOnPreviousPage.contains(sid),
                                  showBismillahText: true,
                                ),
                              MushafLine(
                                line: line,
                                fontFamily: fontFamily,
                                mushafId: actualMushafId,
                                pageNumber: mushafPage.pageNumber,
                                lineWidth: layout.lineWidth,
                                lineHeight: layout.lineHeight,
                                lineVerticalPadding: layout.lineVerticalPadding,
                                wordPadding: layout.wordPadding,
                                verseEndWords: verseEndWords,
                                surahStartsByLine: surahStartsByLine,
                                highlightedVerseKey: null,
                                highlightedVerseKeys: isHiddenPhase
                                    ? (activeSurah != null
                                        ? _voiceRevealedVerses
                                            .map((v) => '$activeSurah:$v')
                                            .toSet()
                                        : const <String>{})
                                    : highlightedVerseKeys,
                                weakVerseKeys: activeSurah != null
                                    ? _weakOrAssistedVerses
                                        .map((v) => '$activeSurah:$v')
                                        .toSet()
                                    : const <String>{},
                                hintedVerseKeys: (activeSurah != null && _hintedVerse != null)
                                    ? {'$activeSurah:$_hintedVerse'}
                                    : null,
                                onVerseTap: (_) => _toggleChrome(),
                                onVerseLongPressStart: (_) {},
                                onVerseLongPress: (_) {},
                                isVerseHidden: (verseKey) {
                                  if (!isHiddenPhase) return false;
                                  if (activeSurah == null) {
                                    return false;
                                  }
                                  if (!highlightedVerseKeys.contains(verseKey)) {
                                    return false;
                                  }
                                  final parts = verseKey.split(':');
                                  if (parts.length == 2 && parts[0] == activeSurah.toString()) {
                                    final vNum = int.tryParse(parts[1]);
                                    if (vNum != null) {
                                      return !_voiceRevealedVerses.contains(vNum);
                                    }
                                  }
                                  return false;
                                },
                                isWordHidden: (verseKey, wordPosition) {
                                  if (activeSurah != null &&
                                      _hintedVerse != null &&
                                      verseKey == '$activeSurah:$_hintedVerse') {
                                    return wordPosition != 1;
                                  }
                                  if (!isHiddenPhase) return false;
                                  if (activeSurah == null) return false;
                                  if (!highlightedVerseKeys.contains(verseKey)) return false;
                                  final parts = verseKey.split(':');
                                  if (parts.length == 2 && parts[0] == activeSurah.toString()) {
                                    final vNum = int.tryParse(parts[1]);
                                    if (vNum != null) {
                                      return !_voiceRevealedVerses.contains(vNum);
                                    }
                                  }
                                  return false;
                                },
                                isPeekActive: false,
                              ),
                            ],
                            if (surahFrameOnPageBottom[mushafPage.pageNumber] != null)
                              QcfSurahHeader(
                                surahNumber: int.tryParse(surahFrameOnPageBottom[mushafPage.pageNumber]!) ?? 0,
                                colors: AppTheme.colors(
                                    isDark: Theme.of(ctx).brightness ==
                                        Brightness.dark),
                                showSurahFrame: true,
                                showBismillahText: false,
                              ),
                          ],
                        ),
                      ),
                    ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),

        if (isHiddenPhase)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      colorScheme.errorContainer.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // New Verses body
  // ---------------------------------------------------------------------------
  Widget _buildNewVersesBody(BuildContext context, HifzSessionProvider provider,
      ColorScheme colorScheme, TextTheme textTheme) {
    final currentTask = provider.currentTask;

    return _isMushafView
        ? PageView.builder(
            controller: _newVersesPageController,
            reverse: true,
            itemCount: 604,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index + 1;
              });
            },
            itemBuilder: (context, index) {
              return _buildMushafView(
                  context, provider, currentTask, colorScheme, index + 1,
                  key: ValueKey('nv_mushaf_${index + 1}'));
            },
          )
        : _buildListView(context, provider, currentTask, colorScheme, textTheme);
  }

  // ---------------------------------------------------------------------------
  // Bottom bar
  // ---------------------------------------------------------------------------
  Widget _buildBottomBar(BuildContext context, HifzSessionProvider provider,
      ColorScheme colorScheme, TextTheme textTheme, bool isReview) {
    return Consumer<MushafAudioProvider>(
      builder: (context, audio, _) {
        final showAudioPlayer = audio.isPlaying || audio.isLoading || audio.currentVerseKey != null;
        final isCompleted = isReview
            ? provider.isReviewSessionCompleted
            : provider.isSessionCompleted;

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showAudioPlayer)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildLiveAudioPlayerBar(context, audio, colorScheme, textTheme),
                  )
                else if (isCompleted)
                  _buildCompletedBottomBar(context, provider, colorScheme, textTheme, isReview)
                else if (isReview)
                  _buildReviewBottomBar(context, provider, colorScheme, textTheme)
                else
                  _buildNewVersesBottomBar(context, provider, colorScheme, textTheme),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLiveAudioPlayerBar(BuildContext context, MushafAudioProvider audio,
      ColorScheme colorScheme, TextTheme textTheme) {
    final volume = audio.volume;
    final percentage = (volume * 100).round();
    final verseKey = audio.currentVerseKey ?? '';

    IconData volumeIcon;
    if (volume == 0.0) {
      volumeIcon = Icons.volume_off_rounded;
    } else if (volume < 0.5) {
      volumeIcon = Icons.volume_down_rounded;
    } else {
      volumeIcon = Icons.volume_up_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      verseKey.isNotEmpty
                          ? 'Reciting Verse $verseKey'
                          : 'Audio Recitation',
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (audio.playlist.length > 1)
                      Text(
                        'Track ${audio.playlistIndex + 1} of ${audio.playlist.length}',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: audio.isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    : Icon(
                        audio.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                onPressed: () => audio.togglePlayPause(),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.stop_rounded, color: colorScheme.error, size: 22),
                onPressed: () => audio.stop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(volumeIcon, size: 16, color: colorScheme.onSurfaceVariant),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  ),
                  child: Slider(
                    value: volume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => audio.setVolume(v),
                    activeColor: colorScheme.primary,
                  ),
                ),
              ),
              Text(
                '$percentage%',
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReviewBottomBar(BuildContext context, HifzSessionProvider provider,
      ColorScheme colorScheme, TextTheme textTheme) {
    if (provider.isReviewSessionCompleted) {
      return _buildCompletedBottomBar(
          context, provider, colorScheme, textTheme, true);
    }

    final phase = provider.reviewPhase;
    final tally = provider.reviewTally;
    final target = provider.reviewTargetTally;
    final phaseColor =
        phase == ReviewPhase.hidden ? colorScheme.error : colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Phase indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: phaseColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: phaseColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          phase == ReviewPhase.hidden
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 14,
                          color: phaseColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          phase == ReviewPhase.hidden ? 'Hidden' : 'Visible',
                          style: textTheme.labelMedium?.copyWith(
                              color: phaseColor, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${provider.reviewStepIndex + 1}/${provider.reviewSteps.length}',
                    style: textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    context: context,
                    icon: Icons.undo_rounded,
                    tooltip: 'Undo last tally',
                    accentColor: phaseColor,
                    onTap: () => _handleUndo(),
                  ),
                  const SizedBox(width: 6),
                  _buildActionButton(
                    context: context,
                    icon: Icons.refresh_rounded,
                    tooltip: 'Reset count',
                    accentColor: phaseColor,
                    onTap: () => _showResetDialog(context),
                  ),
                  if (provider.isVoiceTrackingEligible) ...[
                    const SizedBox(width: 6),
                    Consumer<RecitationTrackerProvider>(
                      builder: (context, tracker, _) {
                        final isListening = tracker.isListening;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildActionButton(
                              context: context,
                              icon: isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                              tooltip: isListening
                                  ? 'Voice Tracking Active (Tap to stop, hold for precision)'
                                  : 'Start Voice Tracking (Hold for precision)',
                              accentColor: isListening ? colorScheme.primary : phaseColor,
                              onTap: () => _toggleVoiceRecitationMic(tracker),
                              onLongPress: () => VoiceRecitationBanner.showSensitivitySheet(context, tracker),
                            ),
                            if (isListening) ...[
                              const SizedBox(width: 6),
                              _buildActionButton(
                                context: context,
                                icon: _hintedVerse == tracker.currentExpectedAyah
                                    ? Icons.arrow_forward_rounded
                                    : Icons.lightbulb_outline_rounded,
                                tooltip: _hintedVerse == tracker.currentExpectedAyah
                                    ? 'Skip Verse ${tracker.currentExpectedAyah} (Mark Assisted)'
                                    : 'Hint 1st Word of Verse ${tracker.currentExpectedAyah}',
                                accentColor: _hintedVerse == tracker.currentExpectedAyah
                                    ? colorScheme.error
                                    : colorScheme.primary,
                                onTap: () => _handleSkipOrRevealCurrentVerse(tracker),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Consumer<MushafAudioProvider>(
            builder: (context, audio, _) {
              return SizedBox(
                width: MediaQuery.of(context).size.width / 3,
                child: FilledButton(
                  onPressed: (audio.isPlaying || _isTransitioningStep)
                      ? null
                      : () => _handleIncrementOrAdvance(),
                  style: FilledButton.styleFrom(
                    backgroundColor: phaseColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Tally  ·  $tally/$target'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required Color accentColor,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Icon(icon, size: 16, color: accentColor),
          ),
        ),
      ),
    );
  }

  Widget _buildNewVersesBottomBar(BuildContext context,
      HifzSessionProvider provider, ColorScheme colorScheme, TextTheme textTheme) {
    final currentTask = provider.currentTask;

    if (currentTask == null) {
      return _buildCompletedBottomBar(
          context, provider, colorScheme, textTheme, false);
    }

    final isHiddenTask = currentTask.mode == TextVisibilityMode.hidden;
    final taskColor = isHiddenTask ? colorScheme.error : colorScheme.primary;
    final progress = currentTask.currentProgress;
    final target = currentTask.targetRepetitions;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Task info
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: taskColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: taskColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isHiddenTask
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 14,
                          color: taskColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          currentTask.type == TaskType.singleVerse
                              ? 'V${currentTask.verseNumbers.join()}'
                              : 'V${currentTask.verseNumbers.first}–${currentTask.verseNumbers.last}',
                          style: textTheme.labelMedium?.copyWith(
                              color: taskColor, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    context: context,
                    icon: Icons.undo_rounded,
                    tooltip: 'Undo last tally',
                    accentColor: taskColor,
                    onTap: () => _handleUndo(),
                  ),
                  const SizedBox(width: 6),
                  _buildActionButton(
                    context: context,
                    icon: Icons.refresh_rounded,
                    tooltip: 'Reset count',
                    accentColor: taskColor,
                    onTap: () => _showResetDialog(context),
                  ),
                  if (provider.isVoiceTrackingEligible) ...[
                    const SizedBox(width: 6),
                    Consumer<RecitationTrackerProvider>(
                      builder: (context, tracker, _) {
                        final isListening = tracker.isListening;
                        final isInit = tracker.isInitializing;
                        if (isInit) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            ),
                          );
                        }
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildActionButton(
                              context: context,
                              icon: isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                              tooltip: isListening
                                  ? 'Voice Tracking Active (Tap to stop, hold for precision)'
                                  : 'Start Voice Tracking (Hold for precision)',
                              accentColor: isListening ? colorScheme.primary : taskColor,
                              onTap: () => _toggleVoiceRecitationMic(tracker),
                              onLongPress: () => VoiceRecitationBanner.showSensitivitySheet(context, tracker),
                            ),
                            if (isListening) ...[
                              const SizedBox(width: 6),
                              _buildActionButton(
                                context: context,
                                icon: _hintedVerse == tracker.currentExpectedAyah
                                    ? Icons.arrow_forward_rounded
                                    : Icons.lightbulb_outline_rounded,
                                tooltip: _hintedVerse == tracker.currentExpectedAyah
                                    ? 'Skip Verse ${tracker.currentExpectedAyah} (Mark Assisted)'
                                    : 'Hint 1st Word of Verse ${tracker.currentExpectedAyah}',
                                accentColor: _hintedVerse == tracker.currentExpectedAyah
                                    ? colorScheme.error
                                    : colorScheme.primary,
                                onTap: () => _handleSkipOrRevealCurrentVerse(tracker),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Consumer<MushafAudioProvider>(
            builder: (context, audio, _) {
              return SizedBox(
                width: MediaQuery.of(context).size.width / 3,
                child: FilledButton(
                  onPressed: (audio.isPlaying || _isTransitioningStep)
                      ? null
                      : () => _handleIncrementOrAdvance(),
                  style: FilledButton.styleFrom(
                    backgroundColor: taskColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Tally  ·  $progress/$target'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Increment / advance logic
  // ---------------------------------------------------------------------------
  void _handleIncrementOrAdvance({bool clearVoiceImmediately = true}) {
    if (_isTransitioningStep) return;

    final isNewVerses = _hifzProvider.sessionType == HifzSessionType.newVerses;
    final int currentCount = isNewVerses
        ? (_hifzProvider.currentTask?.currentProgress ?? 0)
        : _hifzProvider.reviewTally;
    final int targetCount = isNewVerses
        ? (_hifzProvider.currentTask?.targetRepetitions ?? 1)
        : _hifzProvider.reviewTargetTally;

    // Check if audio is playing, which should block tallying
    final audio = Provider.of<MushafAudioProvider>(context, listen: false);
    if (audio.isPlaying) return;

    // Already completed – advance to next step
    if (currentCount >= targetCount) {
      _triggerStepCompletionAndHold();
      return;
    }

    _hifzProvider.incrementProgress();
    HapticFeedback.lightImpact();

    // When advancing round via tally click, immediately clear revealed verses so the new round hides the range again
    if (clearVoiceImmediately) {
      final int startAyah;
      if (isNewVerses) {
        final task = _hifzProvider.currentTask;
        startAyah = task != null ? task.verseNumbers.first : _selectedRepeatStart;
      } else {
        final step = _hifzProvider.currentReviewStep;
        startAyah = step?.verseStart ?? 1;
      }
      setState(() {
        _voiceRevealedVerses.clear();
        _lastSkippedVerse = null;
        _hintedVerse = null;
      });
      final tracker = Provider.of<RecitationTrackerProvider>(context, listen: false);
      if (tracker.isListening) {
        tracker.setExpectedAyah(startAyah);
      }
      _handleRoundRestartOrStepChange(_hifzProvider.currentSurahNumber, startAyah);
    }

    final int newCount = isNewVerses
        ? (_hifzProvider.currentTask?.currentProgress ?? 0)
        : _hifzProvider.reviewTally;

    // When reaching the target, show banner then advance
    if (newCount >= targetCount) {
      _triggerStepCompletionAndHold();
    }
  }

  void _triggerStepCompletionAndHold() {
    setState(() {
      _isTransitioningStep = true;
      _transitionBannerMessage = 'Step Complete! ✓';
    });

    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      _hifzProvider.advanceStepOrPhase();
      _voiceRevealedVerses.clear();
      _weakOrAssistedVerses.clear();
      _lastSkippedVerse = null;
      _hintedVerse = null;
      final tracker = Provider.of<RecitationTrackerProvider>(context, listen: false);
      // Never auto-toggle mic for a new step or range: always stop tracking on step completion
      if (tracker.isListening) {
        tracker.stopTracking();
        _updateWakelockState();
      }
      setState(() {
        _isTransitioningStep = false;
        _transitionBannerMessage = '';
      });
      _syncToCurrentTaskOrStepStart();
    });
  }

  void _handleUndo() {
    if (_isTransitioningStep) return;
    final audio = Provider.of<MushafAudioProvider>(context, listen: false);
    if (audio.isPlaying) return;
    _hifzProvider.undoLastIncrement();
    _voiceRevealedVerses.clear();
    _weakOrAssistedVerses.clear();
    _lastSkippedVerse = null;
    _hintedVerse = null;
    final tracker = Provider.of<RecitationTrackerProvider>(context, listen: false);
    if (tracker.isListening) {
      tracker.stopTracking();
      _updateWakelockState();
    }
    _syncToCurrentTaskOrStepStart();
    setState(() {});
  }

  Future<void> _showResetDialog(BuildContext context) async {
    final tracker = Provider.of<RecitationTrackerProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isThai = settings.languageCode == 'th';
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: colorScheme.surface,
          title: Text(
            isThai ? 'รีเซ็ตการนับ?' : 'Reset count?',
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: Text(
            isThai
                ? 'คุณต้องการรีเซ็ตเฉพาะอายะห์ปัจจุบัน หรือรีเซ็ตทั้งลำดับ?'
                : 'Do you want to reset just the current verse, or the entire sequence?',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'current'),
              child: Text(isThai ? 'รีเซ็ตอายะห์นี้' : 'Reset current verse'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              child: Text(isThai ? 'รีเซ็ตทั้งลำดับ' : 'Reset whole sequence'),
            ),
          ],
        );
      },
    );

    if (choice == null || !mounted) return;
    _voiceRevealedVerses.clear();
    _weakOrAssistedVerses.clear();
    _lastSkippedVerse = null;
    _hintedVerse = null;
    if (choice == 'current') {
      _hifzProvider.resetCurrentTask();
      if (!_hifzProvider.isVoiceTrackingEligible) {
        if (tracker.isListening) {
          tracker.stopTracking();
          _updateWakelockState();
        }
      }
      _syncToCurrentTaskOrStepStart();
      setState(() {});
    } else if (choice == 'all') {
      _hifzProvider.resetSession();
      if (tracker.isListening) {
        tracker.stopTracking();
        _updateWakelockState();
      }
      _syncToCurrentTaskOrStepStart();
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Completed Bottom Bar
  // ---------------------------------------------------------------------------
  Widget _buildCompletedBottomBar(
    BuildContext context,
    HifzSessionProvider provider,
    ColorScheme colorScheme,
    TextTheme textTheme,
    bool isReview,
  ) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isThai = settings.languageCode == 'th';

    final title = isReview
        ? (isThai ? 'ทบทวนเสร็จสมบูรณ์! 🎉' : 'Review Complete! 🎉')
        : (isThai ? 'ท่องจำเสร็จสมบูรณ์! 🎉' : 'Memorization Complete! 🎉');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Completion status pill / badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.assessment_outlined, size: 20),
                  tooltip: isThai ? 'รายงานสถิติ' : 'View Report',
                  color: colorScheme.primary,
                  onPressed: () => _showGundalReportModal(context, provider),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Action Buttons: Exit | Repeat | New Range
          Row(
            children: [
              // Exit button
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(isThai ? 'ออก' : 'Exit'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Repeat button
              Expanded(
                flex: 3,
                child: FilledButton.tonalIcon(
                  onPressed: () => provider.resetSession(),
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: Text(isThai ? 'ทำซ้ำ' : 'Repeat'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // New Range button
              Expanded(
                flex: 4,
                child: FilledButton.icon(
                  onPressed: () {
                    if (isReview) {
                      _openReviewSetup(context);
                    } else {
                      _openNewVersesSetup(context);
                    }
                  },
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(isThai ? 'เลือกช่วงใหม่' : 'New Range'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mushaf view (new verses)
  // ---------------------------------------------------------------------------
  Widget _buildMushafView(BuildContext context, HifzSessionProvider provider,
      HifzTask? currentTask, ColorScheme colorScheme, int pageNumber, {Key? key}) {
    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Set<String> highlightedKeys = currentTask != null
              ? currentTask.verseNumbers
                  .map((v) => '${provider.surahNumber}:$v')
                  .toSet()
              : {};
          final availWidth = constraints.maxWidth;
          final isTablet = constraints.maxWidth > 600 || constraints.maxHeight > 900;
          final double paddedWidth =
              isTablet ? availWidth.clamp(300.0, 600.0) : availWidth;
          return Stack(
            children: [
              Center(
                child: SizedBox(
                  width: paddedWidth,
                  height: constraints.maxHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: InteractiveViewer(
                      minScale: 1.0,
                    maxScale: 3.5,
                    child: FutureBuilder<MushafPage>(
                      future: widget.foundationRepository.fetchPage(
                          mushafId: _isTajweedMushaf ? 11 : 2, pageNumber: pageNumber),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final mushafPage = snapshot.data!;
                        final actualMushafId = _isTajweedMushaf ? 11 : 2;
                        final layout = MushafLayoutProfile.forMushaf(actualMushafId);
                        final fontFamily = widget.foundationRepository.getFontFamily(actualMushafId, pageNumber);

                        final surahStartsByLine = <int, List<String>>{};
                        for (final v in mushafPage.verses) {
                          if (v.verseId != '1' || v.words.isEmpty) continue;
                          surahStartsByLine
                              .putIfAbsent(v.words.first.lineNumber, () => [])
                              .add(v.surahId);
                        }
                        final verseEndWords = <MushafWord>{};
                        for (final v in mushafPage.verses) {
                          if (v.words.isNotEmpty) verseEndWords.add(v.words.last);
                        }

                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: layout.horizontalPadding),
                          child: FittedBox(
                            fit: BoxFit.contain,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                            width: layout.pageWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final line in mushafPage.lines) ...[
                                  for (final sid in surahStartsByLine[
                                              line.first.lineNumber] ??
                                          const <String>[])
                                    QcfSurahHeader(
                                      surahNumber: int.tryParse(sid) ?? 0,
                                      colors: AppTheme.colors(
                                          isDark: Theme.of(context).brightness ==
                                              Brightness.dark),
                                      showSurahFrame: !surahsWithFrameOnPreviousPage.contains(sid),
                                      showBismillahText: true,
                                    ),
                                  MushafLine(
                                    line: line,
                                    fontFamily: fontFamily,
                                    mushafId: actualMushafId,
                                    pageNumber: mushafPage.pageNumber,
                                    lineWidth: layout.lineWidth,
                                    lineHeight: layout.lineHeight,
                                    lineVerticalPadding:
                                        layout.lineVerticalPadding,
                                    wordPadding: layout.wordPadding,
                                    verseEndWords: verseEndWords,
                                    surahStartsByLine: surahStartsByLine,
                                    highlightedVerseKey: null,
                                    highlightedVerseKeys: highlightedKeys,
                                    weakVerseKeys: _weakOrAssistedVerses
                                        .map((v) => '${provider.surahNumber}:$v')
                                        .toSet(),
                                    hintedVerseKeys: _hintedVerse != null
                                        ? {'${provider.surahNumber}:$_hintedVerse'}
                                        : null,
                                    onVerseTap: (_) => _toggleChrome(),
                                    onVerseLongPressStart: (_) {},
                                    onVerseLongPress: (_) {},
                                    isVerseHidden: (verseKey) {
                                      if (currentTask == null) return false;
                                      final parts = verseKey.split(':');
                                      if (parts.length == 2 &&
                                          parts[0] ==
                                              provider.surahNumber.toString()) {
                                        final vNum = int.tryParse(parts[1]);
                                        if (vNum != null) {
                                          return _isVerseHidden(vNum, currentTask);
                                        }
                                      }
                                      return false;
                                    },
                                    isWordHidden: (verseKey, wordPosition) {
                                      if (currentTask == null) return false;
                                      if (_hintedVerse != null &&
                                          verseKey == '${provider.surahNumber}:$_hintedVerse') {
                                        return wordPosition != 1;
                                      }
                                      final parts = verseKey.split(':');
                                      if (parts.length == 2 &&
                                          parts[0] ==
                                              provider.surahNumber.toString()) {
                                        final vNum = int.tryParse(parts[1]);
                                        if (vNum != null) {
                                          return _isVerseHidden(vNum, currentTask);
                                        }
                                      }
                                      return false;
                                    },
                                    isPeekActive: false,
                                  ),
                                ],
                                if (surahFrameOnPageBottom[mushafPage.pageNumber] != null)
                                  QcfSurahHeader(
                                    surahNumber: int.tryParse(surahFrameOnPageBottom[mushafPage.pageNumber]!) ?? 0,
                                    colors: AppTheme.colors(
                                        isDark: Theme.of(context).brightness ==
                                            Brightness.dark),
                                    showSurahFrame: true,
                                    showBismillahText: false,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            ],
          );
        },
      ),
    );
  }

  Widget _buildListView(BuildContext context, HifzSessionProvider provider,
      HifzTask? currentTask, ColorScheme colorScheme, TextTheme textTheme) {
    final startDisplayVerse = _selectedRepeatStart < _selectedStartVerse
        ? _selectedRepeatStart
        : _selectedStartVerse;

    return ListView.separated(
      controller: _listScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _selectedEndVerse - startDisplayVerse + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final verseNum = startDisplayVerse + index;
        final isTarget =
            currentTask != null && currentTask.verseNumbers.contains(verseNum);
        final isHidden = _isVerseHidden(verseNum, currentTask);
        final translation =
            _getVerseTranslationText(context, provider.surahNumber, verseNum);

        return KeyedSubtree(
          key: _keyForVerse(provider.surahNumber, verseNum),
          child: Consumer<MushafAudioProvider>(
          builder: (context, audio, _) {
            final isCurrentPlaying = audio.isPlaying &&
                audio.currentVerseKey == '${provider.surahNumber}:$verseNum';
            final isCurrentLoading = audio.isLoading &&
                audio.currentVerseKey == '${provider.surahNumber}:$verseNum';

            Widget playIcon;
            if (isCurrentLoading) {
              playIcon = SizedBox(
                width: 24,
                height: 24,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isTarget ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            } else if (isCurrentPlaying) {
              playIcon = Icon(
                Icons.stop_circle_rounded,
                color: isTarget ? colorScheme.primary : colorScheme.onSurfaceVariant,
                size: 24,
              );
            } else {
              playIcon = Icon(
                Icons.volume_up_outlined,
                color: isTarget ? colorScheme.primary : null,
                size: 24,
              );
            }

            final verseKey = '${provider.surahNumber}:$verseNum';
            final notesProvider = context.watch<NotesProvider>();
            final readingProvider = context.watch<MushafReadingProvider>();
            final settings = context.watch<SettingsProvider>();
            final favorited = notesProvider.getNoteObjectForVerse(
                  provider.surahNumber.toString(),
                  verseNum.toString(),
                ) !=
                null;
            final bookmarked = readingProvider.isVerseBookmarked(
              1,
              1,
              verseKey,
            );

            final showBismillah = (index == 0 || verseNum == 1) &&
                provider.surahNumber != 1 &&
                provider.surahNumber != 9;

            final isSkipped = _lastSkippedVerse == verseNum;
            final isWeak = _weakOrAssistedVerses.contains(verseNum);
            final isHinted = isHidden && _hintedVerse == verseNum;
            final card = AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isWeak
                    ? colorScheme.errorContainer.withValues(alpha: 0.20)
                    : (isSkipped
                        ? colorScheme.errorContainer.withValues(alpha: 0.15)
                        : (isHinted
                            ? colorScheme.primaryContainer.withValues(alpha: 0.15)
                            : (isTarget
                                ? (isHidden
                                    ? colorScheme.primaryContainer.withValues(alpha: 0.04)
                                    : colorScheme.primaryContainer.withValues(alpha: 0.08))
                                : colorScheme.surfaceContainerLow))),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isWeak
                      ? colorScheme.error.withValues(alpha: 0.55)
                      : (isSkipped
                          ? colorScheme.error
                          : (isHinted
                              ? colorScheme.primary.withValues(alpha: 0.5)
                              : (isTarget
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant.withValues(alpha: 0.3)))),
                  width: (isWeak || isSkipped || isHinted) ? 2.0 : (isTarget ? 1.5 : 1.0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            verseKey,
                            style: GoogleFonts.notoSansThai(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isWeak
                                  ? colorScheme.error
                                  : colorScheme.primary.withValues(alpha: 0.8),
                            ),
                          ),
                          if (isWeak) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.flag_outlined, size: 12, color: colorScheme.error),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Assisted',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colorScheme.error,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (isHinted) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lightbulb_outline_rounded, size: 12, color: colorScheme.onPrimaryContainer),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Hint: 1st word',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (OfflineQuranDatabaseService.hasMutashabihatSync(verseKey)) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => MutashabihatSheet.show(context, verseKey),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: colorScheme.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.sync_alt_rounded,
                                      size: 13,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'โองการคล้ายกัน',
                                      style: GoogleFonts.notoSansThai(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        onSelected: (val) async {
                          if (val == 'play') {
                            if (isCurrentPlaying || isCurrentLoading) {
                              audio.stop();
                            } else {
                              audio.playRange(
                                provider.surahNumber.toString(),
                                [verseNum],
                              );
                            }
                          } else if (val == 'bookmark') {
                            await readingProvider.toggleVerseBookmark(
                              mushafId: 1,
                              pageNumber: 1,
                              verseKey: verseKey,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    bookmarked
                                        ? 'Bookmark removed'
                                        : 'Verse bookmarked',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          } else if (val == 'favorite') {
                            final surahStr = provider.surahNumber.toString();
                            final verseStr = verseNum.toString();
                            if (favorited) {
                              await notesProvider.deleteNote(surahStr, verseStr);
                            } else {
                              await notesProvider.saveNote(
                                surahId: surahStr,
                                verseId: verseStr,
                                noteText: '',
                              );
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    favorited
                                        ? 'Removed from favorites'
                                        : 'Saved to favorites',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          } else if (val == 'wbw') {
                            WordByWordSheet.show(context, verseKey: verseKey);
                          } else if (val == 'mutashabihat') {
                            MutashabihatSheet.show(context, verseKey);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'play',
                            child: Row(
                              children: [
                                Icon(
                                  isCurrentPlaying
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                  size: 20,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  isCurrentPlaying ? 'Pause verse' : 'Play verse',
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'wbw',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.spellcheck_rounded,
                                  size: 20,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                const Text('แปลคำต่อคำ (Word by Word)'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'bookmark',
                            child: Row(
                              children: [
                                Icon(
                                  bookmarked
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  size: 20,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  bookmarked ? 'Remove bookmark' : 'Bookmark',
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'favorite',
                            child: Row(
                              children: [
                                Icon(
                                  favorited
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 20,
                                  color: favorited
                                      ? Colors.red
                                      : colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  favorited ? 'Remove favorite' : 'Favorite',
                                ),
                              ],
                            ),
                          ),
                          if (OfflineQuranDatabaseService.hasMutashabihatSync(verseKey))
                            PopupMenuItem(
                              value: 'mutashabihat',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.sync_alt_rounded,
                                    size: 20,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('โองการที่คล้ายคลึงกัน (Similar Ayat)'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (!isHidden)
                        IconButton(
                          icon: playIcon,
                          onPressed: () {
                            if (isCurrentPlaying || isCurrentLoading) {
                              audio.stop();
                            } else {
                              audio.playRange(
                                provider.surahNumber.toString(),
                                [verseNum],
                              );
                            }
                          },
                        ),
                      Expanded(
                        child: FutureBuilder<String>(
                          future: widget.quranRepository.fetchArabicVerse(
                              provider.surahNumber.toString(), verseNum.toString()),
                          builder: (context, snapshot) {
                            final arabicText = snapshot.data ?? '';
                            final cleanedText = formatArabicAyahText(
                              arabicText,
                              verseNumber: verseNum,
                            );
                            final isHintedVerse = isHidden && _hintedVerse == verseNum;
                            final firstSpaceIndex = cleanedText.indexOf(' ');
                            final List<InlineSpan> spans;
                            if (isHintedVerse) {
                              if (firstSpaceIndex != -1) {
                                spans = [
                                  TextSpan(
                                    text: cleanedText.substring(0, firstSpaceIndex),
                                    style: TextStyle(
                                      color: textTheme.bodyLarge?.color,
                                      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  TextSpan(
                                    text: cleanedText.substring(firstSpaceIndex),
                                    style: const TextStyle(
                                      color: Colors.transparent,
                                    ),
                                  ),
                                ];
                              } else {
                                spans = [
                                  TextSpan(
                                    text: cleanedText,
                                    style: TextStyle(
                                      color: textTheme.bodyLarge?.color,
                                      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ];
                              }
                            } else {
                              spans = [
                                TextSpan(
                                  text: cleanedText,
                                  style: TextStyle(
                                    color: isHidden
                                        ? Colors.transparent
                                        : (isTarget
                                            ? textTheme.bodyLarge?.color
                                            : textTheme.bodyLarge?.color
                                                ?.withValues(alpha: 0.6)),
                                  ),
                                ),
                              ];
                            }

                            return Directionality(
                              textDirection: TextDirection.rtl,
                              child: RichText(
                                textAlign: TextAlign.right,
                                softWrap: true,
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontFamily: 'UthmanicHafs',
                                    fontSize: 28,
                                    height: 2.0,
                                  ),
                                  children: spans,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_showWbw) ...[
                    const SizedBox(height: 12),
                    WordByWordView(
                      verseKey: verseKey,
                      isHidden: isHidden,
                      isDarkMode: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ],
                  if (translation.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      thickness: 0.8,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 10),
                    RichText(
                      softWrap: true,
                      text: TextSpan(
                        children: HtmlParser.parseTranslationText(
                          context,
                          translation,
                          getTranslationTextStyle(
                            context,
                            fontSize: settings.translationFontSize,
                            height: 1.5,
                            color: isHidden
                                ? Colors.transparent
                                : colorScheme.onSurfaceVariant,
                            translationId: settings.primaryTranslationId,
                          ),
                          isHidden ? Colors.transparent : colorScheme.primary,
                          verseKey: verseKey,
                          translationId: settings.primaryTranslationId,
                          isInteractive: !isHidden,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );

            if (!showBismillah) return card;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/Bismillah_Calligraphy6.svg',
                      height: 48,
                      colorFilter: ColorFilter.mode(
                        colorScheme.onSurface,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
                card,
              ],
            );
          },
        ),
        );
      },
    );
  }
}



// =============================================================================
// Helper Widgets
// =============================================================================



class _ResumeRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _ResumeRow(this.label, this.value, this.colorScheme);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(
          '$label: ',
          style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
        ),
        Text(
          value,
          style: textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}


