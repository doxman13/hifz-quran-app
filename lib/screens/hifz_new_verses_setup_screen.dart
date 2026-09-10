// lib/screens/hifz_new_verses_setup_screen.dart
//
// Full-screen setup screen for New Verses (Takrar) Mode.
// Two tabs: By Surah | By Page
// Returns (surah, repeatStart, startVerse, endVerse, page, isSurahMode) to caller.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_foundation_repository.dart';
import '../data/quran_repository.dart';
import '../providers/settings_provider.dart';
import '../database/hifz_repository.dart';
import '../models/hifz_session_config.dart';
import 'hifz_memorize_screen.dart';

/// Return type from the setup screen.
class NewVersesSetupResult {
  final int surah;
  final int repeatStart;
  final int startVerse;
  final int endVerse;
  final int page;
  final bool isSurahMode;
  final ActiveSessionSnapshot? resumeSnapshot;

  const NewVersesSetupResult({
    required this.surah,
    required this.repeatStart,
    required this.startVerse,
    required this.endVerse,
    required this.page,
    required this.isSurahMode,
    this.resumeSnapshot,
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

    // Init page tab values
    if (!widget.initialIsSurahMode) {
      _initFromPage(_page);
    } else {
      _initFromPage(1);
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkForResumableSession();
      }
    });
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
        ),
      );
    } else if (resume == false) {
      await repo.clearActiveSession(sessionId: snap.sessionId);
    }
  }

  void _initFromPage(int page) {
    final pageItems = qcf.getPageData(page);
    if (pageItems.isNotEmpty) {
      _pageSurah = pageItems.first['surah'];
      _pageStart = pageItems.first['start'];
      _pageEnd = pageItems.last['end'];
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
        ? qcf.getPageNumber(selectedSurah, selectedStartVerse)
        : _page;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hifz_nv_surah', selectedSurah);
    await prefs.setInt('hifz_nv_start_verse', selectedStartVerse);
    await prefs.setInt('hifz_nv_end_verse', selectedEndVerse);
    await prefs.setInt('hifz_nv_repeat_start', selectedRepeatStart);
    await prefs.setInt('hifz_nv_page', selectedPage);
    await prefs.setBool('hifz_nv_is_surah_mode', isSurah);

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
            quranRepository: widget.quranRepository,
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
  final QuranRepository quranRepository;
  final void Function(int surah, int start, int end, int repeat) onChanged;

  const _BySurahTab({
    required this.surah,
    required this.startVerse,
    required this.endVerse,
    required this.repeatStart,
    required this.quranRepository,
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

  int get _totalVerses => qcf.getVerseCount(_surah);

  void _notify() => widget.onChanged(_surah, _start, _end, _repeat);

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
        const SizedBox(height: 24),
        _LabeledDropdown<int>(
          label: isThai ? 'ซูเราะฮ์' : 'Surah',
          value: _surah,
          items: List.generate(114, (i) => i + 1),
          itemLabel: (v) => widget.quranRepository.getSurahName(v.toString()),
          onChanged: (v) {
            setState(() {
              _surah = v;
              final total = qcf.getVerseCount(v);
              _start = 1;
              _repeat = 1;
              _end = total > 3 ? 3 : total;
            });
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
        const SizedBox(height: 24),
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
  final void Function(int page, int surah, int start, int end, int repeat) onChanged;

  const _ByPageTab({
    required this.page,
    required this.pageSurah,
    required this.pageStart,
    required this.pageEnd,
    required this.pageRepeatStart,
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

  void _notify() => widget.onChanged(_page, _pageSurah, _start, _end, _repeat);

  void _loadPage(int page) {
    final items = qcf.getPageData(page);
    if (items.isNotEmpty) {
      _page = page;
      _pageSurah = items.first['surah'];
      _start = items.first['start'];
      _end = items.last['end'];
      _repeat = _start;
    }
  }

  int get _totalVerses => qcf.getVerseCount(_pageSurah);

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
        const SizedBox(height: 24),
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
        const SizedBox(height: 24),
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
