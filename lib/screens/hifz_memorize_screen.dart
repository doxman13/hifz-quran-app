import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;

import '../models/mushaf_models.dart';
import '../theme/app_theme.dart';
import 'mushaf_reader_screen.dart';
import '../data/quran_foundation_repository.dart';
import '../data/quran_repository.dart';
import '../models/hifz_task.dart';
import '../providers/hifz_session_provider.dart';
import '../providers/mushaf_audio_provider.dart';

import '../models/hifz_session_config.dart';
import '../database/hifz_repository.dart';
import '../providers/settings_provider.dart';
import 'hifz_new_verses_setup_screen.dart';
import '../providers/ble_remote_provider.dart';
import 'hifz_mastery_list_screen.dart';

import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/translation_manager_provider.dart';
import '../services/tajweed_service.dart';
import '../widgets/tajweed_text.dart';

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
    with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel('com.abuzayd.iqra/key_events');
  int _lastBleClickCount = 0;
  late HifzSessionProvider _hifzProvider;
  bool _isMushafView = true;
  bool _isTajweedMushaf = false;
  bool _showMeaning = false;
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

  // Controls whether the top/bottom UI chrome is visible
  bool _chromeVisible = true;
  late AnimationController _chromeAnimController;
  late Animation<double> _chromeAnim;

  bool _isVerseHidden(int verseNum, HifzTask? currentTask) {
    if (currentTask == null) return false;
    if (verseNum < _selectedRepeatStart || verseNum > _selectedEndVerse) {
      return false;
    }
    final targetVerse = currentTask.verseNumbers.last;
    if (verseNum > targetVerse) {
      return true;
    }
    if (verseNum < targetVerse) {
      if (currentTask.type == TaskType.cumulativeLink) {
        return currentTask.mode == TextVisibilityMode.hidden;
      } else {
        return false;
      }
    }
    return currentTask.mode == TextVisibilityMode.hidden;
  }

  @override
  void initState() {
    super.initState();
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

    // Sync input mode to native so volume keys are handled correctly
    _syncInputModeToNative();

    // Listen for BLE smart ring clicks (only when BLE mode is active)
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (settings.hifzInputMode == HifzInputMode.bleSmartRing) {
      Provider.of<BleRemoteProvider>(context, listen: false)
          .addListener(_onBleClick);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TajweedService.load();
        final settings = Provider.of<SettingsProvider>(context, listen: false);
        if (settings.keepAwake) {
          WakelockPlus.enable();
        }
        if (widget.resumeSessionSnapshot == null) {
          _checkForResumableSession();
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
            )
          : HifzSessionProvider.review(
              granularity: snap.reviewGranularity ?? ReviewGranularity.bySurah,
              targetParams: snap.reviewTargetParams ??
                  ReviewTargetParams.bySurah(startSurah: 100, endSurah: 114),
            );
      restored.restoreFromSnapshot(snap);
      _hifzProvider = restored;
      _selectedRepeatStart = snap.nvRepeatStart ?? widget.startVerse;
      _selectedStartVerse = snap.nvStartVerse ?? widget.startVerse;
      _selectedEndVerse = snap.nvEndVerse ?? widget.endVerse;
      _currentPage = snap.sessionType == HifzSessionType.newVerses
          ? qcf.getPageNumber(snap.nvSurahNumber ?? widget.surahNumber, snap.nvStartVerse ?? widget.startVerse)
          : widget.initialPage;
    } else if (widget.initialSessionType == HifzSessionType.newVerses) {
      _isSurahMode = widget.isSurahMode ?? true;
      _selectedRepeatStart = widget.repeatStart ?? widget.startVerse;
      _selectedStartVerse = widget.startVerse;
      _selectedEndVerse = widget.endVerse;
      _currentPage = _isSurahMode
          ? qcf.getPageNumber(widget.surahNumber, _selectedStartVerse)
          : widget.initialPage;
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
    } else {
      _selectedRepeatStart = widget.startVerse;
      _selectedStartVerse = widget.startVerse;
      _selectedEndVerse = widget.endVerse;
      _hifzProvider = HifzSessionProvider(
        surahNumber: widget.surahNumber,
        repeatStart: _selectedRepeatStart,
        startVerse: _selectedStartVerse,
        endVerse: _selectedEndVerse,
      );
    }

    _newVersesPageController = PageController(initialPage: _currentPage - 1);
    _reviewPageController = PageController(initialPage: 10000 + _reviewPageOffset);

    // Listen for hardware key events (only when Bluetooth Shutter mode is active)
    if (settings.hifzInputMode == HifzInputMode.bluetoothShutter) {
      DateTime? lastClickTime;
      _channel.setMethodCallHandler((call) async {
        if (call.method == "keyClick") {
          final audio = Provider.of<MushafAudioProvider>(context, listen: false);
          if (audio.isPlaying) return;

          final now = DateTime.now();
          if (lastClickTime != null && now.difference(lastClickTime!).inMilliseconds < 450) {
            return;
          }
          lastClickTime = now;
          if (mounted && !_hifzProvider.isSessionCompleted) {
            _handleIncrementOrAdvance();
            HapticFeedback.lightImpact();
          }
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (settings.hifzInputMode == HifzInputMode.bleSmartRing) {
      _lastBleClickCount =
          Provider.of<BleRemoteProvider>(context, listen: false).clickCount;
    }
    _syncInputModeToNative();
  }

  void _syncInputModeToNative() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final modeName = settings.hifzInputMode.name;
    _channel.invokeMethod('setInputMode', {'mode': modeName});
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
  void dispose() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (settings.hifzInputMode == HifzInputMode.bleSmartRing) {
      Provider.of<BleRemoteProvider>(context, listen: false)
          .removeListener(_onBleClick);
    }
    if (settings.hifzInputMode == HifzInputMode.bluetoothShutter) {
      _channel.setMethodCallHandler(null);
    }
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
            )
          : HifzSessionProvider.review(
              granularity: snap.reviewGranularity ?? ReviewGranularity.bySurah,
              targetParams: snap.reviewTargetParams ??
                  ReviewTargetParams.bySurah(startSurah: 100, endSurah: 114),
            );
      restored.restoreFromSnapshot(snap);
      setState(() {
        _hifzProvider = restored;
        if (snap.sessionType == HifzSessionType.newVerses) {
          _selectedRepeatStart = snap.nvRepeatStart ?? _selectedRepeatStart;
          _selectedStartVerse = snap.nvStartVerse ?? _selectedStartVerse;
          _selectedEndVerse = snap.nvEndVerse ?? _selectedEndVerse;
          _currentPage =
              qcf.getPageNumber(_hifzProvider.surahNumber, _selectedStartVerse);
        }
      });
    } else {
      if (widget.initialSessionType != null) {
        return;
      }
      Navigator.pop(context);
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
      setState(() {
        _selectedRepeatStart = result.repeatStart;
        _selectedStartVerse = result.startVerse;
        _selectedEndVerse = result.endVerse;
        _isSurahMode = result.isSurahMode;
        _selectedPage = result.page;
        _currentPage = result.isSurahMode
            ? qcf.getPageNumber(result.surah, result.startVerse)
            : result.page;
        _hifzProvider.initRoutine(
          result.repeatStart,
          result.startVerse,
          result.endVerse,
          surah: result.surah,
        );
      });
    }
  }

  void _showNewVersesAudioOptionsDialog(
      BuildContext context, HifzSessionProvider provider) {
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

    showModalBottomSheet(
      context: context,
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 20),
              Text('Audio Recitation',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Choose audio playback range:',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(Icons.play_circle_outline, color: colorScheme.primary, size: 28),
                title: Text('Play $taskLabel',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                subtitle: const Text('Recite active verse or current sequence'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: colorScheme.surfaceContainerLow,
                onTap: () {
                  Navigator.pop(ctx);
                  audio.playRange(surahStr, currentTaskVerses);
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.playlist_play_rounded, color: colorScheme.primary, size: 28),
                title: Text('Play $fullRangeLabel',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                subtitle: const Text('Recite entire selected range including sequence start'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: colorScheme.surfaceContainerLow,
                onTap: () {
                  Navigator.pop(ctx);
                  audio.playRange(surahStr, fullRangeVerses);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReviewAudioOptionsDialog(
      BuildContext context, HifzSessionProvider provider) {
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

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 20),
              Text('Review Audio Recitation',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Choose audio playback range:',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(Icons.play_circle_outline, color: colorScheme.primary, size: 28),
                title: Text('Play Current Step (${step.label})',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                subtitle: const Text('Recite active review step'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: colorScheme.surfaceContainerLow,
                onTap: () {
                  Navigator.pop(ctx);
                  if (step.surahNumber != null || granularity != ReviewGranularity.byPage) {
                    final surahNum = step.surahNumber ?? step.primaryIndex;
                    final vStart = step.verseStart ?? 1;
                    final vEnd = step.verseEnd ?? qcf.getVerseCount(surahNum);
                    final verseList = List.generate(vEnd - vStart + 1, (i) => vStart + i);
                    audio.playRange(surahNum.toString(), verseList);
                  } else {
                    _playPageAudio(audio, step.primaryIndex);
                  }
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.menu_book_rounded, color: colorScheme.primary, size: 28),
                title: Text('Play Current Page (Page $currentReviewPage)',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                subtitle: const Text('Recite page currently displayed on screen'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: colorScheme.surfaceContainerLow,
                onTap: () {
                  Navigator.pop(ctx);
                  _playPageAudio(audio, currentReviewPage);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _playPageAudio(MushafAudioProvider audio, int pageNumber) {
    final pageItems = qcf.getPageData(pageNumber);
    if (pageItems.isEmpty) return;
    final firstItem = pageItems.first;
    final int surah = firstItem['surah'];
    final int start = firstItem['start'];
    final int end = pageItems.last['end'];
    final verseList = List.generate(end - start + 1, (i) => start + i);
    audio.playRange(surah.toString(), verseList);
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
    final verse = widget.quranRepository
        .getVerse(surahNumber.toString(), verseNumber.toString());
    if (verse == null) return '';

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final primaryId = settings.primaryTranslationId;

    if (primaryId == 'english') {
      return verse.english;
    } else if (primaryId == 'thai_v2') {
      return verse.thaiV2;
    } else if (primaryId == 'thai_v3') {
      return verse.thaiV3;
    } else {
      final idInt = int.tryParse(primaryId) ?? -1;
      try {
        final transManager =
            Provider.of<TranslationManagerProvider>(context, listen: false);
        final customTrans = transManager.getVerseTranslation(
            idInt, '$surahNumber:$verseNumber');
        if (customTrans != null && customTrans.isNotEmpty) {
          return customTrans;
        }
      } catch (_) {}
      return verse.thaiV3;
    }
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
                          child: _buildCompactTopBar(
                              context, provider, colorScheme, textTheme, isReview),
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
                icon: Icon(
                  audio.isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.volume_up_rounded,
                  color: audio.isPlaying ? colorScheme.primary : null,
                  size: 22,
                ),
                tooltip: 'Audio Recitation',
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

          // View toggle & Meaning toggle for new verses mode
          if (!isReview) ...[
            IconButton(
              icon: Icon(
                _isMushafView ? Icons.view_list_rounded : Icons.menu_book_rounded,
                size: 20,
              ),
              tooltip: _isMushafView ? 'List View' : 'Mushaf View',
              onPressed: () => setState(() => _isMushafView = !_isMushafView),
            ),
            if (!_isMushafView)
              IconButton(
                icon: Icon(
                  _showMeaning
                      ? Icons.translate_rounded
                      : Icons.translate_outlined,
                  color: _showMeaning ? colorScheme.primary : null,
                  size: 20,
                ),
                tooltip: _showMeaning ? 'Hide Meaning' : 'Show Meaning',
                onPressed: () => setState(() => _showMeaning = !_showMeaning),
              ),
          ],

          // Dark mode toggle (for both modes)
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              return IconButton(
                icon: Icon(
                  settings.isDarkMode
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  size: 20,
                ),
                tooltip: settings.isDarkMode ? 'Light Mode' : 'Dark Mode',
                onPressed: () => settings.toggleDarkMode(!settings.isDarkMode),
              );
            },
          ),

          // Peek toggle
          IconButton(
            icon: Icon(
              provider.isPeekActive
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              size: 20,
            ),
            tooltip: provider.isPeekActive ? 'Hide Text' : 'Reveal Text',
            onPressed: () => provider.setPeekActive(!provider.isPeekActive),
          ),

          // Gear icon with popup menu (all settings consolidated)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 22),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (val) async {
              switch (val) {
                case 'switch_mode':
                  Navigator.pop(context);
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
              }
            },
            itemBuilder: (_) => [
              _buildPopupItem('switch_mode', Icons.swap_horiz_rounded, 'Switch Mode'),
              _buildPopupItem('tajweed', Icons.font_download_outlined, _isTajweedMushaf ? 'Standard Mushaf' : 'Tajweed Mushaf'),
              if (!isReview)
                _buildPopupItem('range', Icons.tune_rounded, 'Select Range'),
              _buildPopupItem('report', Icons.analytics_outlined, 'Report'),
              _buildPopupItem('mastery', Icons.workspace_premium_outlined, 'Mastery'),
            ],
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
    if (provider.isReviewSessionCompleted) {
      return _buildCompletionView(context, provider, colorScheme, textTheme,
          'Review Complete!', 'All selected Surahs/pages reviewed successfully.');
    }

    final step = provider.currentReviewStep;
    if (step == null) return const SizedBox();

    final isHiddenPhase = provider.reviewPhase == ReviewPhase.hidden;
    final isPeeking = provider.isPeekActive;
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
          isPeeking: isPeeking,
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
    required bool isPeeking,
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
                                    ? const {}
                                    : highlightedVerseKeys,
                                onVerseTap: (_) => _toggleChrome(),
                                onVerseLongPressStart: (_) {},
                                onVerseLongPress: (_) {},
                                isVerseHidden: (verseKey) {
                                  if (!isHiddenPhase || isPeeking) return false;
                                  if (activeSurah == null) {
                                    return true;
                                  }
                                  return highlightedVerseKeys.contains(verseKey);
                                },
                                isPeekActive: isPeeking,
                              ),
                            ],
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

        if (isHiddenPhase && !isPeeking)
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
    final isCompleted = provider.isSessionCompleted;

    return isCompleted
        ? _buildCompletionView(context, provider, colorScheme, textTheme,
            'Routine Complete!', 'Great job memorizing these verses.')
        : _isMushafView
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
        child: isReview
            ? _buildReviewBottomBar(context, provider, colorScheme, textTheme)
            : _buildNewVersesBottomBar(context, provider, colorScheme, textTheme),
      ),
    );
  }

  Widget _buildReviewBottomBar(BuildContext context, HifzSessionProvider provider,
      ColorScheme colorScheme, TextTheme textTheme) {
    if (provider.isReviewSessionCompleted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Review Complete! 🎉',
                style:
                    textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _showGundalReportModal(context, provider),
                icon: const Icon(Icons.assessment_outlined),
                label: const Text('View Analytics'),
                style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ),
      );
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
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.undo_rounded, size: 18, color: phaseColor),
                    tooltip: 'Undo last tally',
                    onPressed: () => _handleUndo(),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, size: 18, color: phaseColor),
                    tooltip: 'Reset count',
                    onPressed: () => _showResetDialog(context),
                  ),
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

  Widget _buildNewVersesBottomBar(BuildContext context,
      HifzSessionProvider provider, ColorScheme colorScheme, TextTheme textTheme) {
    final currentTask = provider.currentTask;

    if (currentTask == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Session Complete! 🎉',
                style:
                    textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _showGundalReportModal(context, provider),
                icon: const Icon(Icons.assessment_outlined),
                label: const Text('View Analytics'),
                style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ),
      );
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
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.undo_rounded, size: 18, color: taskColor),
                    tooltip: 'Undo last tally',
                    onPressed: () => _handleUndo(),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, size: 18, color: taskColor),
                    tooltip: 'Reset count',
                    onPressed: () => _showResetDialog(context),
                  ),
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
  void _handleIncrementOrAdvance() {
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

    // Already completed – nothing to do
    if (currentCount >= targetCount) return;

    _hifzProvider.incrementProgress();
    HapticFeedback.lightImpact();

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
      setState(() {
        _isTransitioningStep = false;
        _transitionBannerMessage = '';
      });
    });
  }

  void _handleUndo() {
    if (_isTransitioningStep) return;
    final audio = Provider.of<MushafAudioProvider>(context, listen: false);
    if (audio.isPlaying) return;
    _hifzProvider.undoLastIncrement();
  }

  Future<void> _showResetDialog(BuildContext context) async {
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
    if (choice == 'current') {
      _hifzProvider.resetCurrentTask();
    } else if (choice == 'all') {
      _hifzProvider.resetSession();
    }
  }

  // ---------------------------------------------------------------------------
  // Completion view
  // ---------------------------------------------------------------------------
  Widget _buildCompletionView(BuildContext context, HifzSessionProvider provider,
      ColorScheme colorScheme, TextTheme textTheme, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stars_rounded, size: 64, color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(title,
              style: textTheme.headlineMedium?.copyWith(
                  color: colorScheme.primary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, style: textTheme.bodyMedium),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => provider.resetSession(),
            icon: const Icon(Icons.replay),
            label: const Text('Restart Session'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _viewCompletedVerses(context, provider),
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('View Verses'),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHighest,
              foregroundColor: colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _viewCompletedVerses(BuildContext context, HifzSessionProvider provider) {
    int page;
    late Set<String> highlightedKeys;

    if (provider.sessionType == HifzSessionType.newVerses) {
      final surah = provider.surahNumber;
      page = qcf.getPageNumber(surah, provider.startVerse);
      highlightedKeys = {
        for (int v = provider.repeatStart; v <= provider.endVerse; v++)
          '$surah:$v',
      };
    } else {
      final params = provider.reviewTargetParams!;
      switch (provider.reviewGranularity) {
        case ReviewGranularity.byVerses:
          final surah = params.surahNumber!;
          page = qcf.getPageNumber(surah, params.startVerse!);
          highlightedKeys = {
            for (int v = params.startVerse!; v <= params.endVerse!; v++)
              '$surah:$v',
          };
          break;
        case ReviewGranularity.bySurah:
          final startSurah = params.startSurah!;
          final endSurah = params.endSurah!;
          page = qcf.getPageNumber(startSurah, 1);
          highlightedKeys = {
            for (int s = startSurah; s <= endSurah; s++)
              for (int v = 1; v <= qcf.getVerseCount(s); v++)
                '$s:$v',
          };
          break;
        case ReviewGranularity.byPage:
          page = params.startPage!;
          final items = qcf.getPageData(page);
          highlightedKeys = {
            for (final item in items)
              for (int v = item['start']; v <= item['end']; v++)
                '${item['surah']}:$v',
          };
          break;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MushafReaderScreen(
          quranRepository: widget.quranRepository,
          foundationRepository: widget.foundationRepository,
          initialPage: page,
          initialHighlightVerseKeys: highlightedKeys,
        ),
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
                                    isPeekActive: provider.isPeekActive,
                                  ),
                                ],
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
      padding: const EdgeInsets.all(16),
      itemCount: _selectedEndVerse - startDisplayVerse + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final verseNum = startDisplayVerse + index;
        final isTarget =
            currentTask != null && currentTask.verseNumbers.contains(verseNum);
        final isHidden =
            _isVerseHidden(verseNum, currentTask) && !provider.isPeekActive;
        final translation = _showMeaning
            ? _getVerseTranslationText(context, provider.surahNumber, verseNum)
            : '';

        return Consumer<MushafAudioProvider>(
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

            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isTarget
                    ? (isHidden
                        ? colorScheme.primaryContainer.withValues(alpha: 0.04)
                        : colorScheme.primaryContainer.withValues(alpha: 0.08))
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isTarget
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: isTarget ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                            final cleanedText = arabicText.split(' | ').join(' ');
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
                                  children: [
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
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_showMeaning && translation.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      thickness: 0.8,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      translation,
                      style: textTheme.bodyMedium?.copyWith(
                        color: isHidden
                            ? Colors.transparent
                            : colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
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


