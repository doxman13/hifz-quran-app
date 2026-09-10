// lib/screens/hifz_mastery_list_screen.dart
//
// Surah Completion & Mastery overview screen.
// Reads from HifzRepository to display all 114 Surahs with status badges.
// Zero business logic — all reads go through HifzRepository.

import 'package:flutter/material.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;

import '../data/quran_repository.dart';
import '../database/hifz_repository.dart';
import '../models/hifz_session_config.dart';

// Juz-to-Surah ranges (standard 30 Juz divisions)
const _juzSurahStarts = <int>[
  1, 2, 2, 3, 4, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15,
  17, 18, 19, 21, 22, 23, 25, 27, 29, 37, 46, 51, 58, 67, 78,
];

int _juzOfSurah(int surah) {
  int juz = 1;
  for (int i = _juzSurahStarts.length - 1; i >= 0; i--) {
    if (surah >= _juzSurahStarts[i]) {
      juz = i + 1;
      break;
    }
  }
  return juz;
}

enum _FilterMode { all, mastered, inProgress, juz29And30 }

class HifzMasteryListScreen extends StatefulWidget {
  final QuranRepository quranRepository;

  const HifzMasteryListScreen({
    super.key,
    required this.quranRepository,
  });

  @override
  State<HifzMasteryListScreen> createState() => _HifzMasteryListScreenState();
}

class _HifzMasteryListScreenState extends State<HifzMasteryListScreen> {
  final HifzRepository _repo = HifzRepository();
  Map<int, SurahCompletionRecord> _completionMap = {};
  bool _loading = true;
  _FilterMode _filterMode = _FilterMode.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final records = await _repo.getAllCompletionRecords();
    final map = <int, SurahCompletionRecord>{};
    for (final r in records) {
      map[r.surahNumber] = r;
    }
    if (mounted) {
      setState(() {
        _completionMap = map;
        _loading = false;
      });
    }
  }

  List<int> get _filteredSurahs {
    final all = List.generate(114, (i) => i + 1);
    switch (_filterMode) {
      case _FilterMode.mastered:
        return all.where((s) {
          final r = _completionMap[s];
          return r != null && r.newVersesCompleted;
        }).toList();
      case _FilterMode.inProgress:
        return all.where((s) {
          final r = _completionMap[s];
          return r != null && !r.newVersesCompleted && r.reviewCount > 0;
        }).toList();
      case _FilterMode.juz29And30:
        return all.where((s) => _juzOfSurah(s) >= 29).toList();
      case _FilterMode.all:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Hifz Mastery',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Filter chips ---
          _buildFilterBar(colorScheme, textTheme),
          // --- Stats summary ---
          _buildStatsSummary(colorScheme, textTheme),
          // --- Surah list ---
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _buildSurahList(colorScheme, textTheme),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      color: colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: 8,
          children: _FilterMode.values.map((mode) {
            final label = switch (mode) {
              _FilterMode.all => 'All (114)',
              _FilterMode.mastered => 'Mastered',
              _FilterMode.inProgress => 'In Progress',
              _FilterMode.juz29And30 => "Juz' 29 & 30",
            };
            final selected = _filterMode == mode;
            return FilterChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => setState(() => _filterMode = mode),
              selectedColor: colorScheme.primaryContainer,
              labelStyle: textTheme.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              side: BorderSide(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStatsSummary(ColorScheme colorScheme, TextTheme textTheme) {
    final total = 114;
    final mastered = _completionMap.values.where((r) => r.newVersesCompleted).length;
    final reviewed = _completionMap.values.where((r) => r.reviewCount > 0).length;
    final totalReviews = _completionMap.values.fold(0, (sum, r) => sum + r.reviewCount);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatPill(
            label: 'Mastered',
            value: '$mastered / $total',
            icon: Icons.verified_rounded,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
          _StatPill(
            label: 'Reviewed',
            value: '$reviewed',
            icon: Icons.replay_rounded,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
          _StatPill(
            label: 'Total Reviews',
            value: '$totalReviews',
            icon: Icons.bar_chart_rounded,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
      ),
    );
  }

  Widget _buildSurahList(ColorScheme colorScheme, TextTheme textTheme) {
    final surahs = _filteredSurahs;
    if (surahs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 56, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'No surahs found for this filter.',
                style: textTheme.bodyLarge
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: surahs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final surahNum = surahs[index];
        final record = _completionMap[surahNum];
        final surahName = widget.quranRepository.getSurahName(surahNum.toString());
        final verseCount = qcf.getVerseCount(surahNum);
        final juz = _juzOfSurah(surahNum);

        return _SurahMasteryCard(
          surahNumber: surahNum,
          surahName: surahName,
          verseCount: verseCount,
          juz: juz,
          record: record,
          colorScheme: colorScheme,
          textTheme: textTheme,
        );
      },
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _StatPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: colorScheme.primary, size: 22),
        const SizedBox(height: 4),
        Text(value,
            style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
        Text(label,
            style:
                textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SurahMasteryCard extends StatelessWidget {
  final int surahNumber;
  final String surahName;
  final int verseCount;
  final int juz;
  final SurahCompletionRecord? record;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _SurahMasteryCard({
    required this.surahNumber,
    required this.surahName,
    required this.verseCount,
    required this.juz,
    required this.record,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = record?.newVersesCompleted == true;
    final reviewCount = record?.reviewCount ?? 0;
    final hasPartial = !isCompleted && (reviewCount > 0);

    Color borderColor = colorScheme.outlineVariant.withValues(alpha: 0.3);
    Color? tileColor;
    if (isCompleted) {
      borderColor = const Color(0xFF4CAF50).withValues(alpha: 0.6);
      tileColor = const Color(0xFF4CAF50).withValues(alpha: 0.05);
    } else if (hasPartial) {
      borderColor = const Color(0xFFFFA726).withValues(alpha: 0.6);
      tileColor = const Color(0xFFFFA726).withValues(alpha: 0.04);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: tileColor ?? colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Surah number medallion
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                '$surahNumber',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    surahName,
                    style: textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$verseCount verses · Juz $juz',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Badges
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isCompleted)
                  _Badge('COMPLETED', const Color(0xFF4CAF50))
                else if (hasPartial)
                  _Badge('IN PROGRESS', const Color(0xFFFFA726))
                else
                  _Badge('NOT STARTED', colorScheme.onSurfaceVariant),
                if (reviewCount > 0) ...[
                  const SizedBox(height: 4),
                  _Badge(
                    'REVIEWED ×$reviewCount',
                    const Color(0xFF2196F3),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
