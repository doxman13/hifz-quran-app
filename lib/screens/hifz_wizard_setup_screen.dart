// lib/screens/hifz_wizard_setup_screen.dart
//
// Guided 3-Step Setup Wizard for Hifz (Memorization) Mode.
// Step 1: Goal Selection (New Verses vs Review Mode with clear explanations)
// Step 2: Portion & Range (Surah Card with QcfSurahName, RangeSlider, Quick Presets, Visual Mushaf)
// Step 3: Session Plan & Launch (Duration estimate, chunking options, start CTA)
//
// Strictly follows Antigravity UI Refactoring Rules:
// - Zero business logic alteration (launches HifzMemorizeScreen with exact standard config)
// - Theme tokens only (M3 colorScheme, surfaceContainer, primary, etc.)
// - Clean typography hierarchy & 8px grid layout.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;
import '../data/medina_mushaf_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/offline_surah_names.dart';
import '../data/quran_foundation_repository.dart';
import '../data/quran_repository.dart';
import '../database/hifz_repository.dart';
import '../models/hifz_session_config.dart';
import '../providers/settings_provider.dart';
import '../widgets/surah_picker_sheet.dart';
import 'hifz_memorize_screen.dart';
import 'hifz_mushaf_range_picker_screen.dart';

class HifzWizardSetupScreen extends StatefulWidget {
  final QuranRepository quranRepository;
  final QuranFoundationRepository foundationRepository;
  final HifzSessionType? initialMode;
  final int? initialSurah;
  final int? initialStartVerse;
  final int? initialEndVerse;
  final int? initialRepeatStart;
  final int? initialPage;
  final int? initialStartSurah;
  final int? initialEndSurah;
  final int? initialStartPage;
  final int? initialEndPage;
  final int initialStep;

  const HifzWizardSetupScreen({
    super.key,
    required this.quranRepository,
    required this.foundationRepository,
    this.initialMode,
    this.initialSurah,
    this.initialStartVerse,
    this.initialEndVerse,
    this.initialRepeatStart,
    this.initialPage,
    this.initialStartSurah,
    this.initialEndSurah,
    this.initialStartPage,
    this.initialEndPage,
    this.initialStep = 0,
  });

  @override
  State<HifzWizardSetupScreen> createState() => _HifzWizardSetupScreenState();
}

class _HifzWizardSetupScreenState extends State<HifzWizardSetupScreen> {
  late int _currentStep;
  late HifzSessionType _selectedMode;

  // By Surah state (New Verses & Review By Verses)
  late int _surah;
  late int _startVerse;
  late int _endVerse;
  int _repeatStart = 1;

  // By Page state (New Verses)
  bool _isSurahScope = true;
  late int _page;
  int _pageSurah = 1;
  int _pageStart = 1;
  int _pageEnd = 3;

  // Review Mode multi-surah & multi-page range state
  // 0 = By Surah Range (multi-surah), 1 = By Verses, 2 = By Page Range
  int _reviewScopeIndex = 0;
  late int _reviewStartSurah;
  late int _reviewEndSurah;
  late int _reviewStartPage;
  late int _reviewEndPage;

  // Session Preferences
  bool _chunkLongVerses = true;
  bool _reviewStartHidden = false;

  ActiveSessionSnapshot? _resumableSession;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.initialStep.clamp(0, 2);
    _selectedMode = widget.initialMode ?? HifzSessionType.newVerses;

    _surah = widget.initialSurah ?? 67; // Default Al-Mulk
    final total = qcf.getVerseCount(_surah);
    _startVerse = widget.initialStartVerse ?? 1;
    _endVerse = widget.initialEndVerse ?? (_startVerse + 4).clamp(1, total);
    _repeatStart = widget.initialRepeatStart ?? 1;
    if (_repeatStart > _startVerse) _repeatStart = _startVerse;

    _page = widget.initialPage ?? getMedinaMushafPageNumber(_surah, _startVerse);
    _initFromPage(_page);

    _reviewStartSurah = widget.initialStartSurah ?? widget.initialSurah ?? 67;
    _reviewEndSurah = widget.initialEndSurah ?? _reviewStartSurah;
    _reviewStartPage = widget.initialStartPage ?? _page;
    _reviewEndPage = widget.initialEndPage ?? _reviewStartPage;

    if (widget.initialMode == HifzSessionType.review) {
      if (widget.initialStartPage != null) {
        _reviewScopeIndex = 2;
      } else if (widget.initialStartVerse != null) {
        _reviewScopeIndex = 1;
      } else {
        _reviewScopeIndex = 0;
      }
    }

    _loadSavedPreferences();
    _checkForResumableSession();
  }

  void _initFromPage(int page) {
    final items = getMedinaMushafPageData(page);
    if (items.isNotEmpty) {
      _pageSurah = items.first['surah']!;
      _pageStart = items.first['start']!;
      _pageEnd = items.last['end']!;
      if (_repeatStart > _pageStart) _repeatStart = _pageStart;
    }
  }

  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _chunkLongVerses = prefs.getBool('hifz_chunk_long_verses') ?? true;
      if (widget.initialRepeatStart == null) {
        final savedRepeat = prefs.getInt('hifz_nv_repeat_start');
        final currentStart = _isSurahScope ? _startVerse : _pageStart;
        if (savedRepeat != null) {
          _repeatStart = savedRepeat.clamp(1, currentStart);
        }
      }
    });
  }

  Future<void> _checkForResumableSession() async {
    final repo = HifzRepository();
    final allSessions = await repo.getAllActiveSessions();
    for (final s in allSessions) {
      if (s.sessionType == _selectedMode) {
        if (mounted) {
          setState(() {
            _resumableSession = s;
          });
        }
        break;
      }
    }
  }

  int get _totalVersesInSurah => qcf.getVerseCount(_surah);

  int _getJuzForPage(int page) {
    try {
      final items = getMedinaMushafPageData(page);
      if (items.isNotEmpty) {
        final surah = items.first['surah'] ?? 1;
        final start = items.first['start'] ?? 1;
        return qcf.getJuzNumber(surah, start);
      }
    } catch (_) {}
    return 1;
  }

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _launchSession();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _openVisualPicker() async {
    final isReviewPageScope = _selectedMode == HifzSessionType.review && _reviewScopeIndex == 2;
    final curPage = isReviewPageScope
        ? _reviewStartPage
        : (_isSurahScope ? getMedinaMushafPageNumber(_surah, _startVerse) : _page);

    final result = await Navigator.push<HifzMushafRangePickerResult>(
      context,
      MaterialPageRoute(
        builder: (_) => HifzMushafRangePickerScreen(
          quranRepository: widget.quranRepository,
          foundationRepository: widget.foundationRepository,
          initialSurah: _surah,
          initialStartVerse: _startVerse,
          initialEndVerse: _endVerse,
          initialPage: curPage,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (isReviewPageScope) {
          _reviewStartPage = result.page;
          _reviewEndPage = result.page;
        } else {
          _surah = result.surah;
          _startVerse = result.startVerse;
          _endVerse = result.endVerse;
          _page = result.page;
          _initFromPage(_page);
        }
      });
    }
  }

  void _applyQuickPreset(int count) {
    setState(() {
      if (count == -1) {
        _startVerse = 1;
        _endVerse = _totalVersesInSurah;
      } else {
        _endVerse = (_startVerse + count - 1).clamp(1, _totalVersesInSurah);
      }
    });
  }

  Future<void> _launchSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hifz_chunk_long_verses', _chunkLongVerses);

    if (!mounted) return;

    if (_selectedMode == HifzSessionType.newVerses) {
      final finalSurah = _isSurahScope ? _surah : _pageSurah;
      final finalStart = _isSurahScope ? _startVerse : _pageStart;
      final finalEnd = _isSurahScope ? _endVerse : _pageEnd;
      final finalPage = _isSurahScope
          ? getMedinaMushafPageNumber(finalSurah, finalStart)
          : _page;

      final finalRepeat = _repeatStart.clamp(1, finalStart);
      await prefs.setInt('hifz_nv_surah', finalSurah);
      await prefs.setInt('hifz_nv_start_verse', finalStart);
      await prefs.setInt('hifz_nv_end_verse', finalEnd);
      await prefs.setInt('hifz_nv_repeat_start', finalRepeat);
      await prefs.setInt('hifz_nv_page', finalPage);
      await prefs.setBool('hifz_nv_is_surah_mode', _isSurahScope);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HifzMemorizeScreen(
            quranRepository: widget.quranRepository,
            foundationRepository: widget.foundationRepository,
            surahNumber: finalSurah,
            startVerse: finalStart,
            endVerse: finalEnd,
            initialSessionType: HifzSessionType.newVerses,
            repeatStart: finalRepeat,
            initialPage: finalPage,
            isSurahMode: _isSurahScope,
            chunkLongVerses: _chunkLongVerses,
          ),
        ),
      );
    } else {
      // Review Mode
      ReviewGranularity granularity;
      ReviewTargetParams params;

      if (_reviewScopeIndex == 0) {
        granularity = ReviewGranularity.bySurah;
        params = ReviewTargetParams.bySurah(
          startSurah: _reviewStartSurah,
          endSurah: _reviewEndSurah,
        );
      } else if (_reviewScopeIndex == 1) {
        granularity = ReviewGranularity.byVerses;
        params = ReviewTargetParams.byVerses(
          surahNumber: _surah,
          startVerse: _startVerse,
          endVerse: _endVerse,
        );
      } else {
        granularity = ReviewGranularity.byPage;
        params = ReviewTargetParams.byPage(
          startPage: _reviewStartPage,
          endPage: _reviewEndPage,
        );
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HifzMemorizeScreen(
            quranRepository: widget.quranRepository,
            foundationRepository: widget.foundationRepository,
            initialSessionType: HifzSessionType.review,
            reviewGranularity: granularity,
            reviewTargetParams: params,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        leading: IconButton(
          icon: Icon(
            _currentStep > 0 ? Icons.arrow_back_rounded : Icons.close_rounded,
            color: colorScheme.onSurface,
          ),
          onPressed: _prevStep,
        ),
        title: Text(
          isThai ? 'เตรียมการท่องจำ' : 'Hifz Setup Wizard',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Stepper Indicator ─────────────────────────────────────────────
            _buildStepIndicator(colorScheme, textTheme, isThai),
            const SizedBox(height: 8),

            // ── Step Content ──────────────────────────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.05, 0),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: _buildCurrentStepView(colorScheme, textTheme, isThai),
              ),
            ),

            // ── Sticky Bottom Bar ─────────────────────────────────────────────
            _buildBottomBar(colorScheme, textTheme, isThai),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Step Indicator Widget
  // ===========================================================================

  Widget _buildStepIndicator(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    final stepLabels = isThai
        ? ['1. เลือกโหมด', '2. กำหนดช่วง', '3. สรุป & เริ่ม']
        : ['1. Goal', '2. Portion', '3. Confirm'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          Row(
            children: List.generate(3, (index) {
              final isPassed = index < _currentStep;
              final isCurrent = index == _currentStep;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: isPassed || isCurrent
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (index) {
              final isCurrent = index == _currentStep;
              return Text(
                stepLabels[index],
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  color: isCurrent
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Step View Switcher
  // ===========================================================================

  Widget _buildCurrentStepView(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    switch (_currentStep) {
      case 0:
        return _buildStep1ModeSelection(colorScheme, textTheme, isThai);
      case 1:
        return _buildStep2RangeSelection(colorScheme, textTheme, isThai);
      case 2:
      default:
        return _buildStep3Summary(colorScheme, textTheme, isThai);
    }
  }

  // ===========================================================================
  // STEP 1: Mode Selection
  // ===========================================================================

  Widget _buildStep1ModeSelection(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    return ListView(
      key: const ValueKey(0),
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          isThai ? 'วันนี้คุณต้องการทำอะไร?' : 'What is your goal today?',
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isThai
              ? 'เลือกรูปแบบการท่องจำที่เหมาะกับความพร้อมและเป้าหมายของคุณ'
              : 'Choose the memorization style suited for your session.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Option 1: New Verses (Takrar)
        _ModeSelectionCard(
          isSelected: _selectedMode == HifzSessionType.newVerses,
          icon: Icons.menu_book_rounded,
          accentColor: colorScheme.primary,
          title: isThai ? 'ท่องจำอายะห์ใหม่ (Takrar)' : 'Memorize New Verses (Takrar)',
          subtitle: isThai
              ? 'เน้นเจาะลึกทีละอายะห์ ซ้ำ 15 รอบ (แสดง 10× + ซ่อน 5×) เพื่อปลูกฝังความจำลงสมอง แล้วเชื่อมโยงต่อเนื่อง'
              : 'Deep micro-learning: 15 repetitions per verse (10 visible + 5 hidden recall), followed by linked sequence.',
          badge: isThai ? '🌟 แนะนำ 3–5 อายะห์' : '🌟 3–5 Verses Recommended',
          features: isThai
              ? ['ฝึกทีละอายะห์อย่างประณีต', 'แบ่งย่อยอายะห์ยาวตามวักฟ์', 'เชื่อมต่ออายะห์เป็นชุด']
              : ['Precision verse drilling', 'Waqf chunking for long verses', 'Sequence linking drills'],
          colorScheme: colorScheme,
          textTheme: textTheme,
          onTap: () {
            setState(() => _selectedMode = HifzSessionType.newVerses);
          },
        ),

        const SizedBox(height: 16),

        // Option 2: Review (Muraja'ah)
        _ModeSelectionCard(
          isSelected: _selectedMode == HifzSessionType.review,
          icon: Icons.replay_circle_filled_rounded,
          accentColor: colorScheme.tertiary,
          title: isThai ? 'ทบทวนความจำ (Muraja\'ah)' : 'Review & Test (Muraja\'ah)',
          subtitle: isThai
              ? 'รักษาสิ่งที่เคยท่องได้แล้วไม่ให้เลือนหาย ท่องต่อเนื่องทั้งหน้าหรือทั้งซูเราะฮ์ พร้อมตรวจจับคำผิด'
              : 'Protect what you have memorized from fading. Recite full passages with real-time speech verification.',
          badge: isThai ? '🔄 หัวใจของการฮิฟซ์ 80%' : '🔄 80% of Memorization',
          features: isThai
              ? ['ท่องต่อเนื่องทั้งหน้า/ซูเราะฮ์', 'โหมดซ่อนตัวอักษรเพื่อทดสอบ', 'ประเมินความแม่นยำ']
              : ['Continuous passage recitation', 'Hidden text recall test', 'Real-time accuracy scoring'],
          colorScheme: colorScheme,
          textTheme: textTheme,
          onTap: () {
            setState(() => _selectedMode = HifzSessionType.review);
          },
        ),

        if (_resumableSession != null) ...[
          const SizedBox(height: 24),
          _ResumeBanner(
            snapshot: _resumableSession!,
            colorScheme: colorScheme,
            textTheme: textTheme,
            isThai: isThai,
            onResume: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => HifzMemorizeScreen(
                    quranRepository: widget.quranRepository,
                    foundationRepository: widget.foundationRepository,
                    resumeSessionSnapshot: _resumableSession!,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // ===========================================================================
  // STEP 2: Portion & Range Selection
  // ===========================================================================

  Widget _buildStep2RangeSelection(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    if (_selectedMode == HifzSessionType.review) {
      return _buildReviewStep2RangeSelection(colorScheme, textTheme, isThai);
    }
    return _buildNewVersesStep2RangeSelection(colorScheme, textTheme, isThai);
  }

  // ---------------------------------------------------------------------------
  // STEP 2A: Review Mode Range Selection (Multi-Surah, Verses, or Page Range)
  // ---------------------------------------------------------------------------

  Widget _buildReviewStep2RangeSelection(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    final surahTh = offlineSurahNamesTh[_surah.toString()] ?? '';
    final surahEn = offlineSurahNamesEn[_surah.toString()] ?? '';
    final verseCount = _endVerse - _startVerse + 1;

    return ListView(
      key: const ValueKey('review_step2'),
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          isThai ? 'เลือกขอบเขตการทบทวน' : 'Select Review Scope',
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isThai
              ? 'ทบทวนต่อเนื่องหลายซูเราะฮ์, เจาะจงอายะฮ์ หรือทบทวนตามช่วงหน้า'
              : 'Review across multiple full Surahs, specific verses, or a page range.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),

        // Scope Switch: By Surah Range (0) vs By Verses (1) vs By Page Range (2)
        SegmentedButton<int>(
          segments: [
            ButtonSegment<int>(
              value: 0,
              icon: const Icon(Icons.menu_book_rounded, size: 18),
              label: Text(isThai ? 'ช่วงซูเราะฮ์' : 'By Surah'),
            ),
            ButtonSegment<int>(
              value: 1,
              icon: const Icon(Icons.format_list_numbered_rounded, size: 18),
              label: Text(isThai ? 'ตามอายะห์' : 'By Verses'),
            ),
            ButtonSegment<int>(
              value: 2,
              icon: const Icon(Icons.auto_stories_rounded, size: 18),
              label: Text(isThai ? 'ช่วงหน้า' : 'By Page'),
            ),
          ],
          selected: {_reviewScopeIndex},
          onSelectionChanged: (set) {
            setState(() => _reviewScopeIndex = set.first);
          },
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 20),

        if (_reviewScopeIndex == 0) ...[
          // Multi-Surah Range Selector
          SurahSelectorTile(
            surahNumber: _reviewStartSurah,
            label: isThai ? 'ซูเราะฮ์เริ่มต้น' : 'Start Surah',
            onTap: () async {
              final picked = await SurahPickerSheet.show(
                context,
                selectedSurah: _reviewStartSurah,
                title: isThai ? 'เลือกซูเราะฮ์เริ่มต้น' : 'Select Start Surah',
              );
              if (picked != null && mounted) {
                setState(() {
                  _reviewStartSurah = picked;
                  if (_reviewEndSurah < _reviewStartSurah) _reviewEndSurah = _reviewStartSurah;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          SurahSelectorTile(
            surahNumber: _reviewEndSurah,
            label: isThai ? 'ซูเราะฮ์สิ้นสุด' : 'End Surah',
            onTap: () async {
              final picked = await SurahPickerSheet.show(
                context,
                selectedSurah: _reviewEndSurah,
                title: isThai ? 'เลือกซูเราะฮ์สิ้นสุด' : 'Select End Surah',
              );
              if (picked != null && mounted) {
                setState(() {
                  _reviewEndSurah = picked;
                  if (_reviewEndSurah < _reviewStartSurah) _reviewStartSurah = _reviewEndSurah;
                });
              }
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
                label: Text(isThai ? 'ซูเราะฮ์เดียว' : 'Single Surah'),
                onPressed: () {
                  setState(() => _reviewEndSurah = _reviewStartSurah);
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                backgroundColor: colorScheme.surfaceContainerLow,
              ),
              ActionChip(
                avatar: Icon(Icons.menu_book_rounded, size: 16, color: colorScheme.primary),
                label: Text(isThai ? 'ญุซอ์ 30 (78–114)' : 'Juz 30 (78–114)'),
                onPressed: () {
                  setState(() {
                    _reviewStartSurah = 78;
                    _reviewEndSurah = 114;
                  });
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                backgroundColor: colorScheme.surfaceContainerLow,
              ),
              ActionChip(
                avatar: Icon(Icons.auto_stories_rounded, size: 16, color: colorScheme.primary),
                label: Text(isThai ? 'อัลมุลก์–อันนาส (67–114)' : 'Al-Mulk–An-Nas (67–114)'),
                onPressed: () {
                  setState(() {
                    _reviewStartSurah = 67;
                    _reviewEndSurah = 114;
                  });
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                backgroundColor: colorScheme.surfaceContainerLow,
              ),
              ActionChip(
                avatar: Icon(Icons.stars_rounded, size: 16, color: colorScheme.primary),
                label: Text(isThai ? '10 ซูเราะฮ์สุดท้าย (105–114)' : 'Last 10 (105–114)'),
                onPressed: () {
                  setState(() {
                    _reviewStartSurah = 105;
                    _reviewEndSurah = 114;
                  });
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                backgroundColor: colorScheme.surfaceContainerLow,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isThai
                        ? 'ทบทวนทั้งหมด ${(_reviewEndSurah - _reviewStartSurah + 1).clamp(1, 114)} ซูเราะฮ์ (ท่องต่อเนื่องเรียงลำดับ)'
                        : 'Reviewing ${(_reviewEndSurah - _reviewStartSurah + 1).clamp(1, 114)} Surahs in sequence',
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (_reviewScopeIndex == 1) ...[
          // Surah Card with Calligraphy + Verse RangeSlider
          InkWell(
            onTap: () async {
              final picked = await SurahPickerSheet.show(
                context,
                selectedSurah: _surah,
                title: isThai ? 'เลือกซูเราะฮ์' : 'Select Surah',
              );
              if (picked != null && mounted) {
                setState(() {
                  _surah = picked;
                  final total = qcf.getVerseCount(picked);
                  _startVerse = 1;
                  _endVerse = total > 10 ? 10 : total;
                });
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$_surah',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          surahTh,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '$surahEn · $_totalVersesInSurah ${isThai ? 'อายะห์' : 'verses'}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    String.fromCharCode(0xe000 + _surah),
                    style: const TextStyle(
                      fontFamily: 'QcfSurahName',
                      fontSize: 34,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.unfold_more_rounded,
                      color: colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Interactive Verse Range Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isThai ? 'ช่วงอายะห์' : 'Verse Range',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isThai
                      ? 'อายะห์ $_startVerse – $_endVerse ($verseCount อายะห์)'
                      : 'Verse $_startVerse – $_endVerse ($verseCount Verses)',
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Range Slider
          if (_totalVersesInSurah > 1) ...[
            RangeSlider(
              values: RangeValues(_startVerse.toDouble(), _endVerse.toDouble()),
              min: 1,
              max: _totalVersesInSurah.toDouble(),
              divisions: _totalVersesInSurah > 1 ? _totalVersesInSurah - 1 : 1,
              labels: RangeLabels('$_startVerse', '$_endVerse'),
              onChanged: (vals) {
                setState(() {
                  _startVerse = vals.start.round();
                  _endVerse = vals.end.round();
                });
              },
            ),
          ],

          // Quick Range Presets
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
                label: Text(isThai ? '+5 อายะห์' : '+5 Verses'),
                onPressed: () => _applyQuickPreset(5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              ActionChip(
                avatar: Icon(Icons.add_rounded, size: 16, color: colorScheme.primary),
                label: Text(isThai ? '+10 อายะห์' : '+10 Verses'),
                onPressed: () => _applyQuickPreset(10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              ActionChip(
                avatar: Icon(Icons.menu_book_rounded, size: 16, color: colorScheme.primary),
                label: Text(isThai ? 'ทั้งซูเราะฮ์' : 'Full Surah'),
                onPressed: () => _applyQuickPreset(-1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ],
          ),
        ] else ...[
          // By Page Range Selector
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isThai
                          ? 'หน้า $_reviewStartPage ถึง $_reviewEndPage'
                          : 'Pages $_reviewStartPage to $_reviewEndPage',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isThai
                            ? '${_reviewEndPage - _reviewStartPage + 1} หน้า'
                            : '${_reviewEndPage - _reviewStartPage + 1} pages',
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  isThai ? 'หน้าเริ่มต้น: $_reviewStartPage' : 'Start Page: $_reviewStartPage',
                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Slider(
                  value: _reviewStartPage.toDouble(),
                  min: 1,
                  max: 604,
                  divisions: 603,
                  label: '$_reviewStartPage',
                  onChanged: (v) {
                    setState(() {
                      _reviewStartPage = v.round();
                      if (_reviewEndPage < _reviewStartPage) _reviewEndPage = _reviewStartPage;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  isThai ? 'หน้าสิ้นสุด: $_reviewEndPage' : 'End Page: $_reviewEndPage',
                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Slider(
                  value: _reviewEndPage.toDouble(),
                  min: 1,
                  max: 604,
                  divisions: 603,
                  label: '$_reviewEndPage',
                  onChanged: (v) {
                    setState(() {
                      _reviewEndPage = v.round();
                      if (_reviewEndPage < _reviewStartPage) _reviewStartPage = _reviewEndPage;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
                      label: Text(isThai ? 'หน้าเดียว' : 'Single Page'),
                      onPressed: () {
                        setState(() => _reviewEndPage = _reviewStartPage);
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      backgroundColor: colorScheme.surface,
                    ),
                    ActionChip(
                      avatar: Icon(Icons.add_rounded, size: 16, color: colorScheme.primary),
                      label: const Text('+2 หน้า'),
                      onPressed: () {
                        setState(() => _reviewEndPage = (_reviewStartPage + 1).clamp(1, 604));
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      backgroundColor: colorScheme.surface,
                    ),
                    ActionChip(
                      avatar: Icon(Icons.add_rounded, size: 16, color: colorScheme.primary),
                      label: const Text('+5 หน้า'),
                      onPressed: () {
                        setState(() => _reviewEndPage = (_reviewStartPage + 4).clamp(1, 604));
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      backgroundColor: colorScheme.surface,
                    ),
                    ActionChip(
                      avatar: Icon(Icons.menu_book_rounded, size: 16, color: colorScheme.primary),
                      label: Text(isThai ? 'ญุซอ์ 30 (582–604)' : 'Juz 30 (582–604)'),
                      onPressed: () {
                        setState(() {
                          _reviewStartPage = 582;
                          _reviewEndPage = 604;
                        });
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      backgroundColor: colorScheme.surface,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _openVisualPicker,
            icon: const Icon(Icons.auto_stories_outlined, size: 18),
            label: Text(
              isThai ? 'เปิดดูหน้ามุศฮัฟจริง' : 'Browse Visual Mushaf',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 2B: New Verses Range Selection
  // ---------------------------------------------------------------------------

  Widget _buildNewVersesStep2RangeSelection(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    final surahTh = offlineSurahNamesTh[_surah.toString()] ?? '';
    final surahEn = offlineSurahNamesEn[_surah.toString()] ?? '';
    final verseCount = _endVerse - _startVerse + 1;

    return ListView(
      key: const ValueKey(1),
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          isThai ? 'เลือกช่วงที่ต้องการท่อง' : 'Select Quran Portion',
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isThai
              ? 'แนะนำเลือก 3 ถึง 5 อายะห์ต่อวัน เพื่อผลลัพธ์ที่ดีที่สุด'
              : '3 to 5 verses per session are recommended for optimal retention.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),

        // Scope Switch: By Surah vs By Page
        SegmentedButton<bool>(
          segments: [
            ButtonSegment<bool>(
              value: true,
              icon: const Icon(Icons.menu_book_rounded, size: 18),
              label: Text(isThai ? 'ตามซูเราะฮ์' : 'By Surah'),
            ),
            ButtonSegment<bool>(
              value: false,
              icon: const Icon(Icons.auto_stories_rounded, size: 18),
              label: Text(isThai ? 'ตามหน้ามุศฮัฟ' : 'By Page'),
            ),
          ],
          selected: {_isSurahScope},
          onSelectionChanged: (set) {
            setState(() => _isSurahScope = set.first);
          },
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 20),

        if (_isSurahScope) ...[
          // Surah Card with Official QcfSurahName Calligraphy
          InkWell(
            onTap: () async {
              final picked = await SurahPickerSheet.show(
                context,
                selectedSurah: _surah,
                title: isThai ? 'เลือกซูเราะฮ์' : 'Select Surah',
              );
              if (picked != null && mounted) {
                setState(() {
                  _surah = picked;
                  final total = qcf.getVerseCount(picked);
                  _startVerse = 1;
                  _endVerse = total > 5 ? 5 : total;
                  _repeatStart = 1;
                });
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  // Surah Number
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$_surah',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Surah Names
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          surahTh,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '$surahEn · $_totalVersesInSurah ${isThai ? 'อายะห์' : 'verses'}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Official Calligraphy Badge
                  Text(
                    String.fromCharCode(0xe000 + _surah),
                    style: const TextStyle(
                      fontFamily: 'QcfSurahName',
                      fontSize: 34,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                  const SizedBox(width: 8),

                  Icon(Icons.unfold_more_rounded,
                      color: colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Interactive Verse Range Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isThai ? 'ช่วงอายะห์' : 'Verse Range',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isThai
                      ? 'อายะห์ $_startVerse – $_endVerse ($verseCount อายะห์)'
                      : 'Verse $_startVerse – $_endVerse ($verseCount Verses)',
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Range Slider (Smooth alternative to dropdown scrolling)
          if (_totalVersesInSurah > 1) ...[
            RangeSlider(
              values: RangeValues(_startVerse.toDouble(), _endVerse.toDouble()),
              min: 1,
              max: _totalVersesInSurah.toDouble(),
              divisions: _totalVersesInSurah > 1 ? _totalVersesInSurah - 1 : 1,
              labels: RangeLabels('$_startVerse', '$_endVerse'),
              onChanged: (vals) {
                setState(() {
                  _startVerse = vals.start.round();
                  _endVerse = vals.end.round();
                  if (_repeatStart > _startVerse) _repeatStart = _startVerse;
                });
              },
            ),
          ],

          // Quick Range Presets
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
                label: Text(isThai ? '+3 อายะห์' : '+3 Verses'),
                onPressed: () => _applyQuickPreset(3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              ActionChip(
                avatar: Icon(Icons.add_rounded, size: 16, color: colorScheme.primary),
                label: Text(isThai ? '+5 อายะห์' : '+5 Verses'),
                onPressed: () => _applyQuickPreset(5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              ActionChip(
                avatar: Icon(Icons.add_rounded, size: 16, color: colorScheme.primary),
                label: Text(isThai ? '+10 อายะห์' : '+10 Verses'),
                onPressed: () => _applyQuickPreset(10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              ActionChip(
                avatar: Icon(Icons.menu_book_rounded, size: 16, color: colorScheme.primary),
                label: Text(isThai ? 'ทั้งซูเราะฮ์' : 'Full Surah'),
                onPressed: () => _applyQuickPreset(-1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ],
          ),

          // Repeat / Linking start selector for By Surah mode
          _buildRepeatStartControl(colorScheme, textTheme, isThai),

          const SizedBox(height: 20),

          // Visual Mushaf Picker Link
          OutlinedButton.icon(
            onPressed: _openVisualPicker,
            icon: const Icon(Icons.auto_stories_outlined, size: 18),
            label: Text(
              isThai ? 'แตะเลือกบนหน้ามุศฮัฟจริง' : 'Select on Mushaf Page',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ] else ...[
          // Page Scope Selection
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isThai ? 'หน้ามุศฮัฟ: $_page' : 'Mushaf Page: $_page',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Juz ${_getJuzForPage(_page)}',
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Slider(
                  value: _page.toDouble(),
                  min: 1,
                  max: 604,
                  divisions: 603,
                  label: '$_page',
                  onChanged: (val) {
                    setState(() {
                      _page = val.round();
                      _initFromPage(_page);
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '${offlineSurahNamesTh[_pageSurah.toString()] ?? ''} (อายะห์ $_pageStart – $_pageEnd)',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Repeat / Linking start selector for By Page mode
          _buildRepeatStartControl(colorScheme, textTheme, isThai),

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _openVisualPicker,
            icon: const Icon(Icons.auto_stories_outlined, size: 18),
            label: Text(
              isThai ? 'เปิดดูหน้ามุศฮัฟจริง' : 'Browse Visual Mushaf',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ],
    );
  }

  // ===========================================================================
  // Repeat Start Control (Sequence Linking from)
  // ===========================================================================

  Widget _buildRepeatStartControl(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    if (_selectedMode != HifzSessionType.newVerses) return const SizedBox.shrink();

    final currentStart = _isSurahScope ? _startVerse : _pageStart;
    final currentEnd = _isSurahScope ? _endVerse : _pageEnd;

    if (currentStart <= 1) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.link_rounded, size: 20, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isThai
                    ? 'เริ่มจากต้นซูเราะฮ์ (เชื่อมโยงตั้งแต่ อายะห์ 1)'
                    : 'Starting from the beginning (Linked from Verse 1)',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final safeRepeat = _repeatStart.clamp(1, currentStart);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.link_rounded, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    isThai ? 'ลำดับเชื่อมโยงย้อนหลัง' : 'Sequence Linked From',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isThai
                      ? 'อายะห์ $safeRepeat → $currentEnd'
                      : 'V$safeRepeat → V$currentEnd',
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isThai
                ? '💡 เช่น ท่องอายะห์ $currentStart–$currentEnd ให้เลือกเริ่มจาก 1 เพื่อเชื่อมโยงเนื้อหาของวันก่อนหน้าเข้ากับรอบนี้'
                : '💡 e.g. Memorizing V$currentStart–V$currentEnd: start from 1 to bridge yesterday\'s session into today\'s drill.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          if (currentStart > 1) ...[
            Slider(
              value: safeRepeat.toDouble(),
              min: 1,
              max: currentStart.toDouble(),
              divisions: currentStart - 1 > 0 ? currentStart - 1 : 1,
              label: 'อายะห์ $safeRepeat',
              onChanged: (val) {
                setState(() {
                  _repeatStart = val.round();
                });
              },
            ),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _repeatStart = 1),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    backgroundColor: safeRepeat == 1 ? colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
                  ),
                  child: Text(
                    isThai ? 'จากต้น (อายะห์ 1)' : 'From Start (V1)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: safeRepeat == 1 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _repeatStart = currentStart),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    backgroundColor: safeRepeat == currentStart ? colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
                  ),
                  child: Text(
                    isThai ? 'เฉพาะวันนี้ (อายะห์ $currentStart)' : 'Today (V$currentStart)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: safeRepeat == currentStart ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // STEP 3: Confirm & Launch
  // ===========================================================================

  Widget _buildStep3Summary(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    final isNew = _selectedMode == HifzSessionType.newVerses;
    final finalSurah = _isSurahScope ? _surah : _pageSurah;
    final finalStart = _isSurahScope ? _startVerse : _pageStart;
    final finalEnd = _isSurahScope ? _endVerse : _pageEnd;
    final count = finalEnd - finalStart + 1;
    final surahName = offlineSurahNamesTh[finalSurah.toString()] ?? 'ซูเราะฮ์ $finalSurah';

    final String planTitle;
    final String planSubtitle;
    final int estMinutes;

    if (isNew) {
      planTitle = '$surahName ($finalSurah:$finalStart–$finalEnd)';
      planSubtitle = isThai
          ? 'จำนวน $count อายะห์ · ซ้ำ 15 รอบ/อายะห์ + เชื่อมโยง'
          : '$count Verses · 15x drills per verse + linking';
      estMinutes = (count * 2.5).ceil();
    } else {
      if (_reviewScopeIndex == 0) {
        final totalSurahs = (_reviewEndSurah - _reviewStartSurah + 1).clamp(1, 114);
        final sStartName = offlineSurahNamesTh[_reviewStartSurah.toString()] ?? 'ซูเราะฮ์ $_reviewStartSurah';
        final sEndName = offlineSurahNamesTh[_reviewEndSurah.toString()] ?? 'ซูเราะฮ์ $_reviewEndSurah';
        planTitle = _reviewStartSurah == _reviewEndSurah
            ? sStartName
            : '$sStartName – $sEndName';
        planSubtitle = isThai
            ? 'ทบทวนทั้งซูเราะฮ์ รวม $totalSurahs ซูเราะฮ์ (ท่องต่อเนื่องพร้อมตรวจคำผิด)'
            : 'Reviewing $totalSurahs Surahs in sequence';
        estMinutes = (totalSurahs * 4).clamp(5, 120);
      } else if (_reviewScopeIndex == 1) {
        planTitle = '$surahName ($finalSurah:$_startVerse–$_endVerse)';
        final verseCnt = _endVerse - _startVerse + 1;
        planSubtitle = isThai
            ? 'จำนวน $verseCnt อายะห์ (ท่องรวดเดียวพร้อมตรวจคำผิด)'
            : '$verseCnt Verses (Continuous recitation check)';
        estMinutes = (verseCnt * 0.8).ceil().clamp(3, 60);
      } else {
        final totalPages = (_reviewEndPage - _reviewStartPage + 1).clamp(1, 604);
        planTitle = isThai
            ? 'หน้า $_reviewStartPage ถึง $_reviewEndPage'
            : 'Pages $_reviewStartPage to $_reviewEndPage';
        planSubtitle = isThai
            ? 'ทบทวนตามหน้ามุศฮัฟ รวม $totalPages หน้า'
            : 'Reviewing $totalPages Mushaf pages';
        estMinutes = (totalPages * 3).clamp(5, 90);
      }
    }

    return ListView(
      key: const ValueKey(2),
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          isThai ? 'สรุปแผนการท่องจำ' : 'Session Plan Summary',
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isThai
              ? 'ตรวจสอบความพร้อมและปรับแต่งตัวเลือกก่อนเริ่ม'
              : 'Review your session parameters and start when ready.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Hero Summary Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                (isNew ? colorScheme.primaryContainer : colorScheme.tertiaryContainer)
                    .withValues(alpha: 0.7),
                colorScheme.surfaceContainerLow,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isNew ? colorScheme.primary : colorScheme.tertiary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isNew
                          ? (isThai ? '🌟 ท่องจำอายะห์ใหม่' : '🌟 New Verses')
                          : (isThai ? '🔄 ทบทวนความจำ' : '🔄 Review'),
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    isThai ? 'ประมาณ ~$estMinutes นาที' : 'Est. ~$estMinutes min',
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                planTitle,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                planSubtitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (isNew) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    isThai
                        ? '🔗 เชื่อมโยงลำดับ: อายะห์ ${_repeatStart.clamp(1, finalStart)} → $finalEnd'
                        : '🔗 Sequence link: Verse ${_repeatStart.clamp(1, finalStart)} → $finalEnd',
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Mode-specific Settings
        if (isNew) ...[
          // Chunk long verses toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.splitscreen_rounded,
                      color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isThai ? 'แบ่งท่อนอายะห์ยาว' : 'Chunk Long Verses',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        isThai
                            ? 'แบ่งตามเครื่องหมายวักฟ์เพื่อจำง่ายขึ้น'
                            : 'Splits by Waqf stops for easier memorization.',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _chunkLongVerses,
                  onChanged: (val) {
                    setState(() => _chunkLongVerses = val);
                  },
                ),
              ],
            ),
          ),
        ] else ...[
          // Review mode repetitions / text options
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isThai ? 'ตัวช่วยการทบทวน' : 'Review Assistance',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilterChip(
                        avatar: Icon(Icons.visibility_rounded,
                            size: 16,
                            color: !_reviewStartHidden ? colorScheme.primary : null),
                        label: Text(isThai ? 'แสดงตัวอักษร' : 'Visible Text'),
                        selected: !_reviewStartHidden,
                        onSelected: (val) =>
                            setState(() => _reviewStartHidden = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilterChip(
                        avatar: Icon(Icons.visibility_off_rounded,
                            size: 16,
                            color: _reviewStartHidden ? colorScheme.primary : null),
                        label: Text(isThai ? 'ซ่อนตัวอักษร' : 'Hidden Recall'),
                        selected: _reviewStartHidden,
                        onSelected: (val) =>
                            setState(() => _reviewStartHidden = true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ===========================================================================
  // Bottom Action Bar
  // ===========================================================================

  Widget _buildBottomBar(
      ColorScheme colorScheme, TextTheme textTheme, bool isThai) {
    final isLast = _currentStep == 2;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            OutlinedButton(
              onPressed: _prevStep,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(96, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(isThai ? 'ย้อนกลับ' : 'Back'),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: _nextStep,
              icon: Icon(
                isLast ? Icons.play_arrow_rounded : Icons.arrow_forward_rounded,
                size: 22,
              ),
              label: Text(
                isLast
                    ? (_selectedMode == HifzSessionType.newVerses
                        ? (isThai ? 'เริ่มท่องจำทันที' : 'Start Memorizing')
                        : (isThai ? 'เริ่มทบทวนทันที' : 'Start Review'))
                    : (isThai ? 'ถัดไป' : 'Next Step'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: isLast && _selectedMode == HifzSessionType.review
                    ? colorScheme.tertiary
                    : colorScheme.primary,
                foregroundColor: isLast && _selectedMode == HifzSessionType.review
                    ? colorScheme.onTertiary
                    : colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Helper Subcomponents
// =============================================================================

class _ModeSelectionCard extends StatelessWidget {
  final bool isSelected;
  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final String badge;
  final List<String> features;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final VoidCallback onTap;

  const _ModeSelectionCard({
    required this.isSelected,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.features,
    required this.colorScheme,
    required this.textTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.08)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? accentColor
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accentColor
                        : accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: isSelected ? Colors.white : accentColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? accentColor : colorScheme.outlineVariant,
                      width: 2,
                    ),
                    color: isSelected ? accentColor : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: features.map((f) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 14, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        f,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  final ActiveSessionSnapshot snapshot;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool isThai;
  final VoidCallback onResume;

  const _ResumeBanner({
    required this.snapshot,
    required this.colorScheme,
    required this.textTheme,
    required this.isThai,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final isNew = snapshot.sessionType == HifzSessionType.newVerses;
    final typeLabel = isNew
        ? (isThai ? 'ท่องจำอายะห์ใหม่' : 'New Verses')
        : (isThai ? 'ทบทวนความจำ' : 'Review');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, color: colorScheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isThai ? 'มีเซสชันค้างอยู่' : 'Active Session Found',
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                Text(
                  '$typeLabel · ${isThai ? 'งานที่' : 'Task'} ${snapshot.currentStepIndex + 1}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: onResume,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(isThai ? 'ท่องต่อ' : 'Resume'),
          ),
        ],
      ),
    );
  }
}
