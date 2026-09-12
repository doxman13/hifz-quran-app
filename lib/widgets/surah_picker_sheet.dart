// lib/widgets/surah_picker_sheet.dart
//
// Modern Material 3 Searchable Surah Picker Bottom Sheet.
// Replaces cumbersome 114-item native dropdowns with instant search,
// quick category chips, Arabic typography, and clear selection feedback.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;

import '../data/offline_surah_names.dart';
import '../providers/settings_provider.dart';

class SurahPickerSheet extends StatefulWidget {
  final int selectedSurah;
  final String? title;

  const SurahPickerSheet({
    super.key,
    required this.selectedSurah,
    this.title,
  });

  static Future<int?> show(
    BuildContext context, {
    required int selectedSurah,
    String? title,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SurahPickerSheet(
        selectedSurah: selectedSurah,
        title: title,
      ),
    );
  }

  @override
  State<SurahPickerSheet> createState() => _SurahPickerSheetState();
}

class _SurahPickerSheetState extends State<SurahPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _activeFilterIndex = 0; // 0: All, 1: Juz 30, 2: Popular (67, 36, 18, 56)

  static const List<int> _popularSurahs = [1, 18, 36, 55, 56, 67, 78, 112, 113, 114];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<int> _filterSurahs() {
    List<int> baseList;
    if (_activeFilterIndex == 1) {
      // Juz 30: Surahs 78 to 114
      baseList = List.generate(37, (i) => 78 + i);
    } else if (_activeFilterIndex == 2) {
      baseList = _popularSurahs;
    } else {
      baseList = List.generate(114, (i) => i + 1);
    }

    if (_query.isEmpty) return baseList;

    final q = _query.toLowerCase().trim();
    return baseList.where((s) {
      final sStr = s.toString();
      final en = (offlineSurahNamesEn[sStr] ?? '').toLowerCase();
      final ar = offlineSurahNamesAr[sStr] ?? '';
      final th = (offlineSurahNamesTh[sStr] ?? '').toLowerCase();
      return sStr == q || en.contains(q) || ar.contains(q) || th.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';
    final filtered = _filterSurahs();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  widget.title ?? (isThai ? 'เลือกสูเราะฮ์' : 'Select Surah'),
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: isThai
                      ? 'ค้นหาชื่อหรือหมายเลขสูเราะฮ์...'
                      : 'Search Surah name or number...',
                  hintStyle: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: colorScheme.primary, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Quick Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _buildFilterChip(0, isThai ? 'ทั้งหมด (114)' : 'All (114)', colorScheme),
                const SizedBox(width: 8),
                _buildFilterChip(1, isThai ? 'ญุซอ์ 30 (78–114)' : 'Juz 30 (78–114)', colorScheme),
                const SizedBox(width: 8),
                _buildFilterChip(2, isThai ? 'สูเราะฮ์ยอดนิยม' : 'Popular Surahs', colorScheme),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),

          // Surah List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 44, color: colorScheme.outline),
                        const SizedBox(height: 8),
                        Text(
                          isThai ? 'ไม่พบสูเราะฮ์ที่ค้นหา' : 'No Surah found',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final surahNumber = filtered[index];
                      final sKey = surahNumber.toString();
                      final enName = offlineSurahNamesEn[sKey] ?? 'Surah $surahNumber';
                      final arName = offlineSurahNamesAr[sKey] ?? '';
                      final thName = offlineSurahNamesTh[sKey] ?? '';
                      final totalVerses = qcf.getVerseCount(surahNumber);
                      final isSelected = surahNumber == widget.selectedSurah;

                      return Material(
                        color: isSelected
                            ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                            : colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => Navigator.pop(context, surahNumber),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                // Number Badge
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.primaryContainer.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$surahNumber',
                                    style: textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? colorScheme.onPrimary
                                          : colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // English and Thai Name
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        enName,
                                        style: textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      Text(
                                        isThai && thName.isNotEmpty
                                            ? '$thName · $totalVerses อายะห์'
                                            : '$totalVerses verses',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Arabic Name
                                Text(
                                  arName,
                                  style: GoogleFonts.amiri(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.onSurface,
                                  ),
                                  textDirection: TextDirection.rtl,
                                ),
                                const SizedBox(width: 12),

                                // Selected indicator
                                if (isSelected)
                                  Icon(Icons.check_circle_rounded,
                                      color: colorScheme.primary, size: 22)
                                else
                                  Icon(Icons.chevron_right_rounded,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.4),
                                      size: 20),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(int index, String label, ColorScheme colorScheme) {
    final isSelected = _activeFilterIndex == index;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _activeFilterIndex = index),
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class SurahSelectorTile extends StatelessWidget {
  final int surahNumber;
  final String label;
  final VoidCallback onTap;

  const SurahSelectorTile({
    super.key,
    required this.surahNumber,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';
    final sKey = surahNumber.toString();
    final enName = offlineSurahNamesEn[sKey] ?? 'Surah $surahNumber';
    final arName = offlineSurahNamesAr[sKey] ?? '';
    final thName = offlineSurahNamesTh[sKey] ?? '';
    final totalVerses = qcf.getVerseCount(surahNumber);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.5),
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
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          enName,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          isThai && thName.isNotEmpty
                              ? '$thName · $totalVerses อายะห์'
                              : '$totalVerses verses',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    arName,
                    style: GoogleFonts.amiri(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
