// lib/screens/hifz_review_setup_screen.dart
//
// Dedicated setup screen for Review Mode.
// Three tabs: By Surah | By Verses | By Page
// Strictly UI-only — no business logic, only builds a ReviewTargetParams
// and pops it back to the caller.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_repository.dart';
import '../models/hifz_session_config.dart';
import '../database/hifz_repository.dart';
import '../providers/settings_provider.dart';

class HifzReviewSetupScreen extends StatefulWidget {
  final QuranRepository quranRepository;

  const HifzReviewSetupScreen({
    super.key,
    required this.quranRepository,
  });

  @override
  State<HifzReviewSetupScreen> createState() => _HifzReviewSetupScreenState();
}

class _HifzReviewSetupScreenState extends State<HifzReviewSetupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // --- bySurah ---
  int _startSurah = 67;
  int _endSurah = 67;

  // --- byVerses ---
  int _versesSurah = 67;
  int _versesStart = 1;
  int _versesEnd = 10;

  // --- byPage ---
  int _startPage = qcf.getPageNumber(67, 1);
  int _endPage = qcf.getPageNumber(67, 1);

  static const _prefKey = 'hifz_review_last_setup';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLastSetup();
    
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
      if (s.sessionType == HifzSessionType.review) {
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
        final typeLabel = isThai ? 'ทบทวนฮิฟซ์ (Review)' : 'Review Mode';
        final stepLabel = isThai
                ? 'ขั้นตอนที่ ${snap!.currentStepIndex + 1} · ${snap.currentMode == 'hidden' ? 'ซ่อน' : 'แสดง'}'
                : 'Step ${snap!.currentStepIndex + 1} · ${snap.currentMode == 'hidden' ? 'Hidden' : 'Visible'}';

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
      Navigator.pop(
        context,
        (snap.reviewGranularity ?? ReviewGranularity.bySurah, snap.reviewTargetParams ?? ReviewTargetParams.bySurah(startSurah: 114, endSurah: 114), snap),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLastSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved == null || !mounted) return;

    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      final tabIndex = data['tabIndex'] as int? ?? 0;
      _tabController.index = tabIndex.clamp(0, 2);

      if (tabIndex == 0) {
        _startSurah = (data['startSurah'] as int?) ?? 67;
        _endSurah = (data['endSurah'] as int?) ?? 67;
      } else if (tabIndex == 1) {
        _versesSurah = (data['versesSurah'] as int?) ?? 67;
        _versesStart = (data['versesStart'] as int?) ?? 1;
        _versesEnd = (data['versesEnd'] as int?) ?? 10;
      } else {
        _startPage = (data['startPage'] as int?) ?? _startPage;
        _endPage = (data['endPage'] as int?) ?? _endPage;
      }

      setState(() {});
    } catch (_) {}
  }

  Future<void> _saveLastSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      'tabIndex': _tabController.index,
    };
    if (_tabController.index == 0) {
      data['startSurah'] = _startSurah;
      data['endSurah'] = _endSurah;
    } else if (_tabController.index == 1) {
      data['versesSurah'] = _versesSurah;
      data['versesStart'] = _versesStart;
      data['versesEnd'] = _versesEnd;
    } else {
      data['startPage'] = _startPage;
      data['endPage'] = _endPage;
    }
    await prefs.setString(_prefKey, jsonEncode(data));
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _confirmAndReturn() async {
    final idx = _tabController.index;
    ReviewGranularity granularity;
    ReviewTargetParams params;

    switch (idx) {
      case 0:
        granularity = ReviewGranularity.bySurah;
        params = ReviewTargetParams.bySurah(
          startSurah: _startSurah,
          endSurah: _endSurah,
        );
        break;
      case 1:
        granularity = ReviewGranularity.byVerses;
        params = ReviewTargetParams.byVerses(
          surahNumber: _versesSurah,
          startVerse: _versesStart,
          endVerse: _versesEnd,
        );
        break;
      case 2:
      default:
        granularity = ReviewGranularity.byPage;
        params = ReviewTargetParams.byPage(
          startPage: _startPage,
          endPage: _endPage,
        );
        break;
    }

    await _saveLastSetup();
    Navigator.pop(context, (granularity, params, null));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          isThai ? 'ตั้งค่าโหมดทบทวน' : 'Review Mode Setup',
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
              icon: const Icon(Icons.format_list_numbered),
              text: isThai ? 'ตามอายะห์' : 'By Verses',
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
            startSurah: _startSurah,
            endSurah: _endSurah,
            quranRepository: widget.quranRepository,
            onChanged: (s, e) => setState(() {
              _startSurah = s;
              _endSurah = e;
            }),
          ),
          _ByVersesTab(
            surah: _versesSurah,
            startVerse: _versesStart,
            endVerse: _versesEnd,
            quranRepository: widget.quranRepository,
            onChanged: (surah, vs, ve) => setState(() {
              _versesSurah = surah;
              _versesStart = vs;
              _versesEnd = ve;
            }),
          ),
          _ByPageTab(
            startPage: _startPage,
            endPage: _endPage,
            onChanged: (sp, ep) => setState(() {
              _startPage = sp;
              _endPage = ep;
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
            label: Text(isThai ? 'เริ่มทบทวน' : 'Start Review Session'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
  final int startSurah;
  final int endSurah;
  final QuranRepository quranRepository;
  final void Function(int start, int end) onChanged;

  const _BySurahTab({
    required this.startSurah,
    required this.endSurah,
    required this.quranRepository,
    required this.onChanged,
  });

  @override
  State<_BySurahTab> createState() => _BySurahTabState();
}

class _BySurahTabState extends State<_BySurahTab> {
  late int _start;
  late int _end;

  @override
  void initState() {
    super.initState();
    _start = widget.startSurah;
    _end = widget.endSurah;
  }

  @override
  void didUpdateWidget(covariant _BySurahTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startSurah != widget.startSurah || oldWidget.endSurah != widget.endSurah) {
      _start = widget.startSurah;
      _end = widget.endSurah;
    }
  }

  void _notify() => widget.onChanged(_start, _end);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';
    final count = (_end - _start + 1).clamp(0, 114);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(
          isThai ? 'เลือกช่วงซูเราะฮ์' : 'Select Surah Range',
          isThai
              ? 'ทบทวนทั้งซูเราะฮ์ — เห็น  2× แล้วซ่อน 2× เลื่อนอัตโนมัติ'
              : 'Review entire Surahs — 2× visible then 2× hidden, auto-advance.',
        ),
        const SizedBox(height: 24),
        _LabeledDropdown<int>(
          label: isThai ? 'ซูเราะฮ์เริ่ม' : 'Start Surah',
          value: _start,
          items: List.generate(114, (i) => i + 1),
          itemLabel: (v) => widget.quranRepository.getSurahName(v.toString()),
          onChanged: (v) {
            setState(() {
              _start = v;
              if (_end < _start) _end = _start;
            });
            _notify();
          },
        ),
        const SizedBox(height: 16),
        _LabeledDropdown<int>(
          label: isThai ? 'ซูเราะฮ์สิ้นสุด' : 'End Surah',
          value: _end,
          items: List.generate(114 - _start + 1, (i) => _start + i),
          itemLabel: (v) => widget.quranRepository.getSurahName(v.toString()),
          onChanged: (v) {
            setState(() => _end = v);
            _notify();
          },
        ),
        const SizedBox(height: 24),
        _SummaryCard(
          colorScheme: colorScheme,
          textTheme: textTheme,
          items: [
            (isThai ? 'ซูเราะฮ์' : 'Surahs', '$count'),
            (isThai ? 'เฟส/ซูเราะฮ์' : 'Phases/Surah', '2V + 2H'),
            (isThai ? 'ทั้งหมด' : 'Total Steps', '$count'),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Tab 2: By Verses
// =============================================================================

class _ByVersesTab extends StatefulWidget {
  final int surah;
  final int startVerse;
  final int endVerse;
  final QuranRepository quranRepository;
  final void Function(int surah, int start, int end) onChanged;

  const _ByVersesTab({
    required this.surah,
    required this.startVerse,
    required this.endVerse,
    required this.quranRepository,
    required this.onChanged,
  });

  @override
  State<_ByVersesTab> createState() => _ByVersesTabState();
}

class _ByVersesTabState extends State<_ByVersesTab> {
  late int _surah;
  late int _start;
  late int _end;

  @override
  void initState() {
    super.initState();
    _surah = widget.surah;
    _start = widget.startVerse;
    _end = widget.endVerse;
  }

  @override
  void didUpdateWidget(covariant _ByVersesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.surah != widget.surah ||
        oldWidget.startVerse != widget.startVerse ||
        oldWidget.endVerse != widget.endVerse) {
      _surah = widget.surah;
      _start = widget.startVerse;
      _end = widget.endVerse;
    }
  }

  void _notify() => widget.onChanged(_surah, _start, _end);

  int get _totalVerses => qcf.getVerseCount(_surah);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';
    final count = (_end - _start + 1).clamp(0, _totalVerses);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(
          isThai ? 'เลือกช่วงอายะห์' : 'Select Verse Range',
          isThai
              ? 'ทบทวนอายะห์ที่เป็นชุด — เห็น 2× แล้วซ่อน 2×'
              : 'Review a specific verse block — displayed as a single unit, 2× visible then 2× hidden.',
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
              _end = total > 6 ? 6 : total;
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
                    if (_end < _start) _end = _start;
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
        const SizedBox(height: 24),
        _SummaryCard(
          colorScheme: colorScheme,
          textTheme: textTheme,
          items: [
            (isThai ? 'อายะห์' : 'Verses', '$count'),
            (isThai ? 'ชุดเดียว' : 'Single Block', isThai ? 'ใช่' : 'Yes'),
            (isThai ? 'เฟส' : 'Phases', '2V + 2H'),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Tab 3: By Page
// =============================================================================

class _ByPageTab extends StatefulWidget {
  final int startPage;
  final int endPage;
  final void Function(int start, int end) onChanged;

  const _ByPageTab({
    required this.startPage,
    required this.endPage,
    required this.onChanged,
  });

  @override
  State<_ByPageTab> createState() => _ByPageTabState();
}

class _ByPageTabState extends State<_ByPageTab> {
  late int _start;
  late int _end;

  @override
  void initState() {
    super.initState();
    _start = widget.startPage;
    _end = widget.endPage;
  }

  @override
  void didUpdateWidget(covariant _ByPageTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startPage != widget.startPage || oldWidget.endPage != widget.endPage) {
      _start = widget.startPage;
      _end = widget.endPage;
    }
  }

  void _notify() => widget.onChanged(_start, _end);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';
    final count = (_end - _start + 1).clamp(0, 604);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(
          isThai ? 'เลือกช่วงหน้า' : 'Select Page Range',
          isThai
              ? 'ทบทวนทีละหน้า — เห็น 2× แล้วซ่อน 2× เลื่อนอัตโนมัติ'
              : 'Review page by page — 2× visible then 2× hidden, auto-advance to next page.',
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _LabeledDropdown<int>(
                label: isThai ? 'หน้าเริ่ม' : 'Start Page',
                value: _start,
                items: List.generate(604, (i) => i + 1),
                itemLabel: (v) => isThai ? 'หน้า $v' : 'Page $v',
                onChanged: (v) {
                  setState(() {
                    _start = v;
                    if (_end < _start) _end = _start;
                  });
                  _notify();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LabeledDropdown<int>(
                label: isThai ? 'หน้าสุดท้าย' : 'End Page',
                value: _end,
                items: List.generate(604 - _start + 1, (i) => _start + i),
                itemLabel: (v) => isThai ? 'หน้า $v' : 'Page $v',
                onChanged: (v) {
                  setState(() => _end = v);
                  _notify();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SummaryCard(
          colorScheme: colorScheme,
          textTheme: textTheme,
          items: [
            (isThai ? 'หน้า' : 'Pages', '$count'),
            (isThai ? 'เฟส/หน้า' : 'Phases/Page', '2V + 2H'),
            (isThai ? 'ทั้งหมด' : 'Total Steps', '$count'),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Shared helper widgets (private to this file)
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
            style: textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary)),
        const SizedBox(height: 6),
        Text(subtitle,
            style:
                textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
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
                    child: Text(itemLabel(v), overflow: TextOverflow.ellipsis),
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
                        style: textTheme.bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant)),
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
