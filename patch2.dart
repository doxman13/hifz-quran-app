import 'dart:io';

void main() {
  final file = File('lib/screens/hifz_memorize_screen.dart');
  var content = file.readAsStringSync();

  final regex = RegExp(r'void _showRangeSelectionModal\(BuildContext context\) \{.*?(?=\n  void _showGundalReportModal)', dotAll: true);
  
  final newModal = '''void _showRangeSelectionModal(BuildContext context) {
    int tempRepeat = _selectedRepeatStart;
    int tempStart = _selectedStartVerse;
    int tempEnd = _selectedEndVerse;
    bool tempIsSurahMode = _isSurahMode;
    int tempPage = _selectedPage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final colorScheme = Theme.of(context).colorScheme;
            final textTheme = Theme.of(context).textTheme;
            
            // Logic for calculating max ranges depending on mode
            int totalVerses = qcf.getVerseCount(widget.surahNumber);
            int minVerse = 1;
            int maxVerse = totalVerses;
            
            if (!tempIsSurahMode) {
              final pageItems = qcf.getPageData(tempPage);
              if (pageItems.isNotEmpty) {
                 // simplify logic: we assume range starts at first item and ends at last for the modal bounds
                 final first = pageItems.first;
                 final last = pageItems.last;
                 // Since they must select within one Surah, let's limit Page mode to the surah of the first item on that page.
                 if (first['surah'] != widget.surahNumber) {
                     // Not supported for multi-surah perfectly in this simple model, so we stick to the primary surah
                 }
                 minVerse = first['start'];
                 maxVerse = last['end'];
              }
            }

            final count = tempEnd - tempStart + 1;

            return Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
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
                  const SizedBox(height: 16),
                  Text(
                    'Select Memorization Range',
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Surah Mode')),
                        ButtonSegment(value: false, label: Text('Page Mode')),
                      ],
                      selected: {tempIsSurahMode},
                      onSelectionChanged: (val) {
                        setModalState(() {
                          tempIsSurahMode = val.first;
                          if (!tempIsSurahMode) {
                             // Initialize page mode defaults
                             final pageItems = qcf.getPageData(tempPage);
                             if (pageItems.isNotEmpty) {
                               tempStart = pageItems.first['start'];
                               tempRepeat = tempStart;
                               tempEnd = pageItems.last['end'];
                               if (tempEnd - tempStart + 1 > 30) tempEnd = tempStart + 29;
                             }
                          } else {
                             tempStart = 1;
                             tempRepeat = 1;
                             tempEnd = 3;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!tempIsSurahMode) ...[
                    Text('Select Page', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: tempPage,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: List.generate(604, (i) => i + 1).map((v) => DropdownMenuItem(value: v, child: Text('Page \$v'))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() {
                            tempPage = val;
                            final pageItems = qcf.getPageData(tempPage);
                             if (pageItems.isNotEmpty) {
                               tempStart = pageItems.first['start'];
                               tempRepeat = tempStart;
                               tempEnd = pageItems.last['end'];
                               if (tempEnd - tempStart + 1 > 30) tempEnd = tempStart + 29;
                             }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Repeat From',
                              style: textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              value: tempRepeat,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: List.generate(maxVerse - minVerse + 1, (i) => minVerse + i)
                                  .where((v) => v <= tempStart)
                                  .map((v) {
                                return DropdownMenuItem(
                                  value: v,
                                  child: Text('Verse \$v'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() {
                                    tempRepeat = val;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Verse',
                              style: textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              value: tempStart,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: List.generate(maxVerse - minVerse + 1, (i) => minVerse + i).map((v) {
                                return DropdownMenuItem(
                                  value: v,
                                  child: Text('Verse \$v'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() {
                                    tempStart = val;
                                    if (tempRepeat > tempStart) tempRepeat = tempStart;
                                    if (tempEnd < tempStart) tempEnd = tempStart;
                                    if (tempEnd - tempStart + 1 > 30) tempEnd = tempStart + 29;
                                    if (tempEnd > maxVerse) tempEnd = maxVerse;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End Verse',
                              style: textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              value: tempEnd,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: List.generate(maxVerse - minVerse + 1, (i) => minVerse + i)
                                  .where((v) => v >= tempStart && (v - tempStart + 1) <= 30)
                                  .map((v) {
                                return DropdownMenuItem(
                                  value: v,
                                  child: Text('Verse \$v'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() {
                                    tempEnd = val;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Selected Verses:'),
                        Text(
                          '\$count / 30',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: count > 30 ? colorScheme.error : colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedRepeatStart = tempRepeat;
                          _selectedStartVerse = tempStart;
                          _selectedEndVerse = tempEnd;
                          _isSurahMode = tempIsSurahMode;
                          _selectedPage = tempPage;
                          _hifzProvider.initRoutine(tempRepeat, tempStart, tempEnd);
                        });
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Apply Range'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
''';

  content = content.replaceFirst(regex, newModal);
  file.writeAsStringSync(content);
}
