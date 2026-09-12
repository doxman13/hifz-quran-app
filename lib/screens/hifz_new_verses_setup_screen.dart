// lib/screens/hifz_new_verses_setup_screen.dart
//
// Full-screen setup screen for New Verses (Takrar) Mode.
// Two tabs: By Surah | By Page
// Returns (surah, repeatStart, startVerse, endVerse, page, isSurahMode) to caller.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;
import '../data/medina_mushaf_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_foundation_repository.dart';
import '../data/quran_repository.dart';
import '../providers/settings_provider.dart';
import '../database/hifz_repository.dart';
import '../models/hifz_session_config.dart';
import 'hifz_memorize_screen.dart';
import 'hifz_mushaf_range_picker_screen.dart';
import '../widgets/surah_picker_sheet.dart';

/// Return type from the setup screen.
class NewVersesSetupResult {
  final int surah;
  final int repeatStart;
  final int startVerse;
  final int endVerse;
  final int page;
  final bool isSurahMode;
  final ActiveSessionSnapshot? resumeSnapshot;
  final bool chunkLongVerses;

  const NewVersesSetupResult({
    required this.surah,
    required this.repeatStart,
    required this.startVerse,
    required this.endVerse,
    required this.page,
    required this.isSurahMode,
    this.resumeSnapshot,
    this.chunkLongVerses = true,
  });
}

class HifzNewVersesSetupScreen extends StatefulWidget {
  final QuranRepository quranRepository;
  final QuranFoundationRepository? foundationRepository;
  final int initialSurah;
  final int initialStartVerse;
  final int initialEndVerse;
  final int initialRepeatStart;
  final int initialPage;
  final bool initialIsSurahMode;
  final bool initialChunkLongVerses;

  const HifzNewVersesSetupScreen({
    super.key,
    required this.quranRepository,
    this.foundationRepository,
    this.initialSurah = 1,
    this.initialStartVerse = 1,
    this.initialEndVerse = 3,
    this.initialRepeatStart = 1,
    this.initialPage = 1,
    this.initialIsSurahMode = true,
    this.initialChunkLongVerses = true,
  });

  @override
  State<HifzNewVersesSetupScreen> createState() =>
      _HifzNewVersesSetupScreenState();
}

class _HifzNewVersesSetupScreenState extends State<HifzNewVersesSetupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // --- By Surah state ---
  late int _surah;
  late int _startVerse;
  late int _endVerse;
  late int _repeatStart;

  // --- By Page state ---
  late int _page;
  int _pageSurah = 1;
  int _pageStart = 1;
  int _pageEnd = 3;
  int _pageRepeatStart = 1;
  bool _chunkLongVerses = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIsSurahMode ? 0 : 1,
    );

    _surah = widget.initialSurah;
    _startVerse = widget.initialStartVerse;
    _endVerse = widget.initialEndVerse;
    _repeatStart = widget.initialRepeatStart;
    _page = widget.initialPage;
    _chunkLongVerses = widget.initialChunkLongVerses;

    _loadChunkPreference();

    // Init page tab values
    if (!widget.initialIsSurahMode) {
      _initFromPage(_page);
    } else {
      final pageForSurah = getMedinaMushafPageNumber(_surah, _startVerse);
      _initFromPage(pageForSurah);
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkForResumableSession();
      }
    });
  }

  Future<void> _loadChunkPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _chunkLongVerses = prefs.getBool('hifz_chunk_long_verses') ?? true;
      });
    }
  }

  Future<void> _checkForResumableSession() async {
    final repo = HifzRepository();
    final allSessions = await repo.getAllActiveSessions();
    
    ActiveSessionSnapshot? snap;
    for (var s in allSessions) {
      if (s.sessionType == HifzSessionType.newVerses) {
        snap = s;
        break;
      }
    }
    
    if (snap == null) return;
    if (!mounted) return;

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isThai = settings.languageCode == 'th';

    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;
        final typeLabel = isThai ? 'ท่องจำอายะห์ใหม่ (Takrar)' : 'New Verses (Takrar)';
        final stepLabel = isThai
                ? 'งานที่ ${snap!.currentStepIndex + 1} · จำนวนรอบ ${snap.currentTally}'
                : 'Task ${snap!.currentStepIndex + 1} · tally ${snap.currentTally}';

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
      if (widget.foundationRepository != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HifzMemorizeScreen(
              quranRepository: widget.quranRepository,
              foundationRepository: widget.foundationRepository!,
              resumeSessionSnapshot: snap,
            ),
          ),
        );
        return;
      }
      Navigator.pop(
        context,
        NewVersesSetupResult(
          surah: snap.nvSurahNumber ?? _surah,
          repeatStart: snap.nvRepeatStart ?? _repeatStart,
          startVerse: snap.nvStartVerse ?? _startVerse,
          endVerse: snap.nvEndVerse ?? _endVerse,
          page: _page,
          isSurahMode: _tabController.index == 0,
          resumeSnapshot: snap,
          chunkLongVerses: _chunkLongVerses,
        ),
      );
    } else if (resume == false) {
      await repo.clearActiveSession(sessionId: snap.sessionId);
    }
  }

  void _initFromPage(int page) {
    final pageItems = getMedinaMushafPageData(page);
    if (pageItems.isNotEmpty) {
      _pageSurah = pageItems.first['surah']!;
      _pageStart = pageItems.first['start']!;
      _pageEnd = pageItems.last['end']!;
      _pageRepeatStart = _pageStart;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndReturn() async {
    final isSurah = _tabController.index == 0;
    final selectedSurah = isSurah ? _surah : _pageSurah;
    final selectedRepeatStart = isSurah ? _repeatStart : _pageRepeatStart;
    final selectedStartVerse = isSurah ? _startVerse : _pageStart;
    final selectedEndVerse = isSurah ? _endVerse : _pageEnd;
    final selectedPage = isSurah
        ? getMedinaMushafPageNumber(selectedSurah, selectedStartVerse)
        : _page;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hifz_nv_surah', selectedSurah);
    await prefs.setInt('hifz_nv_start_verse', selectedStartVerse);
    await prefs.setInt('hifz_nv_end_verse', selectedEndVerse);
    await prefs.setInt('hifz_nv_repeat_start', selectedRepeatStart);
    await prefs.setInt('hifz_nv_page', selectedPage);
    await prefs.setBool('hifz_nv_is_surah_mode', isSurah);
    await prefs.setBool('hifz_chunk_long_verses', _chunkLongVerses);

    if (widget.foundationRepository != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HifzMemorizeScreen(
            quranRepository: widget.quranRepository,
            foundationRepository: widget.foundationRepository!,
            surahNumber: selectedSurah,
            startVerse: selectedStartVerse,
            endVerse: selectedEndVerse,
            initialSessionType: HifzSessionType.newVerses,
            repeatStart: selectedRepeatStart,
            initialPage: selectedPage,
            isSurahMode: isSurah,
            chunkLongVerses: _chunkLongVerses,
          ),
        ),
      );
      return;
    }

    if (mounted) {
      Navigator.pop(
        context,
        NewVersesSetupResult(
          surah: selectedSurah,
          repeatStart: selectedRepeatStart,
          startVerse: selectedStartVerse,
          endVerse: selectedEndVerse,
          page: selectedPage,
          isSurahMode: isSurah,
          chunkLongVerses: _chunkLongVerses,
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
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          isThai ? 'ตั้งค่าโหมดท่องจำคำใหม่' : 'New Verses Setup',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          indicatorColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          tabs: [
            Tab(
              icon: const Icon(Icons.menu_book_outlined),
              text: isThai ? 'ตามซูเราะฮ์' : 'By Surah',
            ),
            Tab(
              icon: const Icon(Icons.auto_stories_outlined),
              text: isThai ? 'ตามหน้า' : 'By Page',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _BySurahTab(
            surah: _surah,
            startVerse: _startVerse,
            endVerse: _endVerse,
            repeatStart: _repeatStart,
            chunkLongVerses: _chunkLongVerses,
            onChunkToggle: (val) => setState(() => _chunkLongVerses = val),
            quranRepository: widget.quranRepository,
            foundationRepository: widget.foundationRepository,
            onChanged: (surah, start, end, repeat) => setState(() {
              _surah = surah;
              _startVerse = start;
              _endVerse = end;
              _repeatStart = repeat;
            }),
          ),
          _ByPageTab(
            page: _page,
            pageSurah: _pageSurah,
            pageStart: _pageStart,
            pageEnd: _pageEnd,
            pageRepeatStart: _pageRepeatStart,
            chunkLongVerses: _chunkLongVerses,
            onChunkToggle: (val) => setState(() => _chunkLongVerses = val),
            quranRepository: widget.quranRepository,
            foundationRepository: widget.foundationRepository,
            onChanged: (page, surah, start, end, repeat) => setState(() {
              _page = page;
              _pageSurah = surah;
              _pageStart = start;
              _pageEnd = end;
              _pageRepeatStart = repeat;
            }),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: FilledButton.icon(
            onPressed: _confirmAndReturn,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(isThai ? 'เริ่มท่องจำ' : 'Start Memorization'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Tab 1: By Surah
// =============================================================================

class _BySurahTab extends StatefulWidget {
  final int surah;
  final int startVerse;
  final int endVerse;
  final int repeatStart;
  final bool chunkLongVerses;
  final ValueChanged<bool> onChunkToggle;
  final QuranRepository quranRepository;
  final QuranFoundationRepository? foundationRepository;
  final void Function(int surah, int start, int end, int repeat) onChanged;

  const _BySurahTab({
    required this.surah,
    required this.startVerse,
    required this.endVerse,
    required this.repeatStart,
    required this.chunkLongVerses,
    required this.onChunkToggle,
    required this.quranRepository,
    this.foundationRepository,
    required this.onChanged,
  });

  @override
  State<_BySurahTab> createState() => _BySurahTabState();
}

class _BySurahTabState extends State<_BySurahTab> {
  late int _surah;
  late int _start;
  late int _end;
  late int _repeat;

  @override
  void initState() {
    super.initState();
    _surah = widget.surah;
    _start = widget.startVerse;
    _end = widget.endVerse;
    _repeat = widget.repeatStart;
  }

  @override
  void didUpdateWidget(_BySurahTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.surah != widget.surah ||
        oldWidget.startVerse != widget.startVerse ||
        oldWidget.endVerse != widget.endVerse ||
        oldWidget.repeatStart != widget.repeatStart) {
      setState(() {
        _surah = widget.surah;
        _start = widget.startVerse;
        _end = widget.endVerse;
        _repeat = widget.repeatStart;
      });
    }
  }

  int get _totalVerses => qcf.getVerseCount(_surah);

  void _notify() => widget.onChanged(_surah, _start, _end, _repeat);

  Future<void> _openVisualPicker() async {
    final result = await Navigator.push<HifzMushafRangePickerResult>(
      context,
      MaterialPageRoute(
        builder: (_) => HifzMushafRangePickerScreen(
          quranRepository: widget.quranRepository,
          foundationRepository:
              widget.foundationRepository ?? QuranFoundationRepository(),
          initialSurah: _surah,
          initialStartVerse: _start,
          initialEndVerse: _end,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _surah = result.surah;
        _start = result.startVerse;
        _end = result.endVerse;
        if (_repeat > _start) _repeat = _start;
      });
      _notify();
    }
  }

  void _applyRangePreset(int count) {
    setState(() {
      if (count == -1) {
        _start = 1;
        _end = _totalVerses;
        _repeat = 1;
      } else {
        _end = (_start + count - 1).clamp(1, _totalVerses);
      }
    });
    _notify();
  }

  Widget _buildQuickRangePresets(bool isThai, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isThai ? 'ช่วงอายะห์แบบรวดเร็ว' : 'Quick Range Presets',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
              label: Text(isThai ? '+3 อายะห์' : '+3 Verses'),
              onPressed: () => _applyRangePreset(3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              backgroundColor: colorScheme.surfaceContainerLow,
            ),
            ActionChip(
              avatar: Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
              label: Text(isThai ? '+5 อายะห์' : '+5 Verses'),
              onPressed: () => _applyRangePreset(5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              backgroundColor: colorScheme.surfaceContainerLow,
            ),
            ActionChip(
              avatar: Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
              label: Text(isThai ? '+10 อายะห์' : '+10 Verses'),
              onPressed: () => _applyRangePreset(10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              backgroundColor: colorScheme.surfaceContainerLow,
            ),
            ActionChip(
              avatar: Icon(Icons.menu_book_rounded, size: 16, color: colorScheme.primary),
              label: Text(isThai ? 'ทั้งซูเราะฮ์' : 'Full Surah'),
              onPressed: () => _applyRangePreset(-1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              backgroundColor: colorScheme.surfaceContainerLow,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';
    final count = _end - _start + 1;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(
          isThai ? 'เลือกซูเราะฮ์ & ช่วงอายะห์' : 'Select Surah & Verse Range',
          isThai
              ? 'ท่องจำแต่ละอายะห์ 3 รอบ (เห็น 10× + ซ่อน 5×) แล้วต่อลำดับ'
              : 'Memorize each verse with 3 rounds of (10× visible + 5× hidden), followed by linked sequence.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _openVisualPicker,
          icon: const Icon(Icons.auto_stories_rounded, size: 20),
          label: Text(
            isThai
                ? 'เลือกช่วงจากหน้ามุศฮัฟ (Visual Picker)'
                : 'Select Range from Mushaf (Visual)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            side:
                BorderSide(color: colorScheme.primary.withValues(alpha: 0.6)),
          ),
        ),
        const SizedBox(height: 20),
        SurahSelectorTile(
          surahNumber: _surah,
          label: isThai ? 'ซูเราะฮ์' : 'Surah',
          onTap: () async {
            final picked = await SurahPickerSheet.show(
              context,
              selectedSurah: _surah,
              title: isThai ? 'เลือกซูเราะฮ์ที่ต้องการท่องจำ' : 'Select Surah to Memorize',
            );
            if (picked != null && mounted) {
              setState(() {
                _surah = picked;
                final total = qcf.getVerseCount(picked);
                _start = 1;
                _repeat = 1;
                _end = total > 3 ? 3 : total;
              });
              _notify();
            }
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _LabeledDropdown<int>(
                label: isThai ? 'อายะห์เริ่ม' : 'Start Verse',
                value: _start,
                items: List.generate(_totalVerses, (i) => i + 1),
                itemLabel: (v) => isThai ? 'อายะห์ $v' : 'Verse $v',
                onChanged: (v) {
                  setState(() {
                    _start = v;
                    if (_repeat > _start) _repeat = _start;
                    if (_end < _start) _end = _start;
                    if (_end > _totalVerses) _end = _totalVerses;
                  });
                  _notify();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LabeledDropdown<int>(
                label: isThai ? 'อายะห์สิ้นสุด' : 'End Verse',
                value: _end,
                items: List.generate(_totalVerses - _start + 1, (i) => _start + i),
                itemLabel: (v) => isThai ? 'อายะห์ $v' : 'Verse $v',
                onChanged: (v) {
                  setState(() => _end = v);
                  _notify();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildQuickRangePresets(isThai, colorScheme),
        const SizedBox(height: 16),
        _LabeledDropdown<int>(
          label: isThai ? 'ลำดับเริ่มต้น (ทบทวนจาก)' : 'Sequence Linked From (Repeat Start)',
          value: _repeat,
          items: List.generate(_start, (i) => i + 1),
          itemLabel: (v) => isThai ? 'อายะห์ $v' : 'Verse $v',
          onChanged: (v) {
            setState(() => _repeat = v);
            _notify();
          },
        ),
        const SizedBox(height: 6),
        Text(
          isThai
              ? '💡 เช่น หากท่องจำอายะห์ 11–20 ให้เลือกเริ่มจาก 1 เพื่อเชื่อมโยงเนื้อหาของเซสชันก่อนหน้า (1–10) เข้ากับรอบนี้'
              : '💡 e.g. If memorizing verses 11–20, keep this at 1 to bridge yesterday\'s session (1–10) into today\'s flow.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 20),
        _ChunkLongVersesCard(
          value: widget.chunkLongVerses,
          onChanged: widget.onChunkToggle,
          colorScheme: colorScheme,
          textTheme: textTheme,
          isThai: isThai,
        ),
        const SizedBox(height: 20),
        _SummaryCard(
          colorScheme: colorScheme,
          textTheme: textTheme,
          items: [
            (isThai ? 'อายะห์' : 'Verses', '$count'),
            (isThai ? 'ต่ออายะห์' : 'Per Verse', '3× (10V + 5H)'),
            (isThai ? 'ลำดับ' : 'Sequence', 'V$_repeat → V$_end'),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Tab 2: By Page
// =============================================================================

class _ByPageTab extends StatefulWidget {
  final int page;
  final int pageSurah;
  final int pageStart;
  final int pageEnd;
  final int pageRepeatStart;
  final bool chunkLongVerses;
  final ValueChanged<bool> onChunkToggle;
  final QuranRepository quranRepository;
  final QuranFoundationRepository? foundationRepository;
  final void Function(int page, int surah, int start, int end, int repeat)
      onChanged;

  const _ByPageTab({
    required this.page,
    required this.pageSurah,
    required this.pageStart,
    required this.pageEnd,
    required this.pageRepeatStart,
    required this.chunkLongVerses,
    required this.onChunkToggle,
    required this.quranRepository,
    this.foundationRepository,
    required this.onChanged,
  });

  @override
  State<_ByPageTab> createState() => _ByPageTabState();
}

class _ByPageTabState extends State<_ByPageTab> {
  late int _page;
  late int _pageSurah;
  late int _start;
  late int _end;
  late int _repeat;

  @override
  void initState() {
    super.initState();
    _page = widget.page;
    _pageSurah = widget.pageSurah;
    _start = widget.pageStart;
    _end = widget.pageEnd;
    _repeat = widget.pageRepeatStart;
  }

  @override
  void didUpdateWidget(_ByPageTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page ||
        oldWidget.pageSurah != widget.pageSurah ||
        oldWidget.pageStart != widget.pageStart ||
        oldWidget.pageEnd != widget.pageEnd ||
        oldWidget.pageRepeatStart != widget.pageRepeatStart) {
      setState(() {
        _page = widget.page;
        _pageSurah = widget.pageSurah;
        _start = widget.pageStart;
        _end = widget.pageEnd;
        _repeat = widget.pageRepeatStart;
      });
    }
  }

  void _notify() => widget.onChanged(_page, _pageSurah, _start, _end, _repeat);

  void _loadPage(int page) {
    final items = getMedinaMushafPageData(page);
    if (items.isNotEmpty) {
      _page = page;
      _pageSurah = items.first['surah']!;
      _start = items.first['start']!;
      _end = items.last['end']!;
      _repeat = _start;
    }
  }

  int get _totalVerses => qcf.getVerseCount(_pageSurah);

  Future<void> _openVisualPicker() async {
    final result = await Navigator.push<HifzMushafRangePickerResult>(
      context,
      MaterialPageRoute(
        builder: (_) => HifzMushafRangePickerScreen(
          quranRepository: widget.quranRepository,
          foundationRepository:
              widget.foundationRepository ?? QuranFoundationRepository(),
          initialSurah: _pageSurah,
          initialStartVerse: _start,
          initialEndVerse: _end,
          initialPage: _page,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _page = result.page;
        _pageSurah = result.surah;
        _start = result.startVerse;
        _end = result.endVerse;
        if (_repeat > _start) _repeat = _start;
      });
      _notify();
    }
  }

  void _applyRangePreset(int count) {
    setState(() {
      if (count == -1) {
        final items = getMedinaMushafPageData(_page);
        if (items.isNotEmpty) {
          _start = items.first['start']!;
          _end = items.last['end']!;
          _repeat = _start;
        }
      } else {
        _end = (_start + count - 1).clamp(1, _totalVerses);
      }
    });
    _notify();
  }

  Widget _buildQuickRangePresets(bool isThai, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isThai ? 'ช่วงอายะห์แบบรวดเร็ว' : 'Quick Range Presets',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
              label: Text(isThai ? '+3 อายะห์' : '+3 Verses'),
              onPressed: () => _applyRangePreset(3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              backgroundColor: colorScheme.surfaceContainerLow,
            ),
            ActionChip(
              avatar: Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
              label: Text(isThai ? '+5 อายะห์' : '+5 Verses'),
              onPressed: () => _applyRangePreset(5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              backgroundColor: colorScheme.surfaceContainerLow,
            ),
            ActionChip(
              avatar: Icon(Icons.auto_stories_rounded, size: 16, color: colorScheme.primary),
              label: Text(isThai ? 'ทั้งหน้า' : 'Entire Page'),
              onPressed: () => _applyRangePreset(-1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              backgroundColor: colorScheme.surfaceContainerLow,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';
    final count = _end - _start + 1;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(
          isThai ? 'เลือกหน้า & ช่วงอายะห์' : 'Select Page & Verse Range',
          isThai
              ? 'ท่องจำแต่ละอายะห์ 3 รอบ (เห็น 10× + ซ่อน 5×) แล้วต่อลำดับ'
              : 'Memorize each verse with 3 rounds of (10× visible + 5× hidden), followed by linked sequence.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _openVisualPicker,
          icon: const Icon(Icons.auto_stories_rounded, size: 20),
          label: Text(
            isThai
                ? 'เลือกช่วงจากหน้ามุศฮัฟ (Visual Picker)'
                : 'Select Range from Mushaf (Visual)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            side:
                BorderSide(color: colorScheme.primary.withValues(alpha: 0.6)),
          ),
        ),
        const SizedBox(height: 20),
        _LabeledDropdown<int>(
          label: isThai ? 'หน้า' : 'Page',
          value: _page,
          items: List.generate(604, (i) => i + 1),
          itemLabel: (v) => isThai ? 'หน้า $v' : 'Page $v',
          onChanged: (v) {
            setState(() => _loadPage(v));
            _notify();
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _LabeledDropdown<int>(
                label: isThai ? 'อายะห์เริ่ม' : 'Start Verse',
                value: _start,
                items: List.generate(_totalVerses, (i) => i + 1),
                itemLabel: (v) => isThai ? 'อายะห์ $v' : 'Verse $v',
                onChanged: (v) {
                  setState(() {
                    _start = v;
                    if (_repeat > _start) _repeat = _start;
                    if (_end < _start) _end = _start;
                    if (_end > _totalVerses) _end = _totalVerses;
                  });
                  _notify();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LabeledDropdown<int>(
                label: isThai ? 'อายะห์สิ้นสุด' : 'End Verse',
                value: _end,
                items: List.generate(_totalVerses - _start + 1, (i) => _start + i),
                itemLabel: (v) => isThai ? 'อายะห์ $v' : 'Verse $v',
                onChanged: (v) {
                  setState(() => _end = v);
                  _notify();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildQuickRangePresets(isThai, colorScheme),
        const SizedBox(height: 16),
        _LabeledDropdown<int>(
          label: isThai ? 'ลำดับเริ่มต้น (ทบทวนจาก)' : 'Sequence Linked From (Repeat Start)',
          value: _repeat,
          items: List.generate(_start, (i) => i + 1),
          itemLabel: (v) => isThai ? 'อายะห์ $v' : 'Verse $v',
          onChanged: (v) {
            setState(() => _repeat = v);
            _notify();
          },
        ),
        const SizedBox(height: 6),
        Text(
          isThai
              ? '💡 เช่น หากท่องจำช่วงถัดไป ให้เลือกเริ่มจากอายะห์แรกของหน้า เพื่อเชื่อมโยงทั้งหน้าเข้าด้วยกัน'
              : '💡 e.g. When moving to the next block, set this to the first verse of the page to connect the entire page.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 20),
        _ChunkLongVersesCard(
          value: widget.chunkLongVerses,
          onChanged: widget.onChunkToggle,
          colorScheme: colorScheme,
          textTheme: textTheme,
          isThai: isThai,
        ),
        const SizedBox(height: 20),
        _SummaryCard(
          colorScheme: colorScheme,
          textTheme: textTheme,
          items: [
            (isThai ? 'อายะห์' : 'Verses', '$count'),
            (isThai ? 'ต่ออายะห์' : 'Per Verse', '3× (10V + 5H)'),
            (isThai ? 'ลำดับ' : 'Sequence', 'V$_repeat → V$_end'),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Shared helper widgets
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold, color: colorScheme.primary)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final void Function(T) onChanged;

  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          // ignore: deprecated_member_use
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: items
              .map((v) => DropdownMenuItem<T>(
                    value: v,
                    child:
                        Text(itemLabel(v), overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final List<(String, String)> items;

  const _SummaryCard({
    required this.colorScheme,
    required this.textTheme,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items
            .map((item) => Column(
                  children: [
                    Text(item.$2,
                        style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary)),
                    const SizedBox(height: 4),
                    Text(item.$1,
                        style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant)),
                  ],
                ))
            .toList(),
      ),
    );
  }
}

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

class _ChunkLongVersesCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool isThai;

  const _ChunkLongVersesCard({
    required this.value,
    required this.onChanged,
    required this.colorScheme,
    required this.textTheme,
    required this.isThai,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.auto_stories_rounded,
              color: colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isThai
                      ? 'แบ่งย่อยอายะฮ์ยาว (> 1.5 บรรทัด)'
                      : 'Chunk Long Verses (> 1.5 lines)',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isThai
                      ? 'ตัดตามเครื่องหมายวักฟ์และประโยค ช่วยให้ท่องจำง่ายขึ้น'
                      : 'Split by Waqf signs for progressive memorization',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: colorScheme.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

