// lib/screens/hifz_mushaf_range_picker_screen.dart
//
// Full-screen visual Mushaf verse range picker.
// Lets users browse the Mushaf, flip pages, and tap verses to select
// a start and end ayah range visually instead of picking raw numbers.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;
import '../data/medina_mushaf_pages.dart';

import '../data/quran_foundation_repository.dart';
import '../data/quran_repository.dart';
import '../models/mushaf_models.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'mushaf_reader_screen.dart';
import '../widgets/mushaf_page_skeleton.dart';

/// Result returned from the visual range picker.
class HifzMushafRangePickerResult {
  final int surah;
  final int startVerse;
  final int endVerse;
  final int page;

  const HifzMushafRangePickerResult({
    required this.surah,
    required this.startVerse,
    required this.endVerse,
    required this.page,
  });
}

class HifzMushafRangePickerScreen extends StatefulWidget {
  final QuranRepository quranRepository;
  final QuranFoundationRepository foundationRepository;
  final int initialSurah;
  final int? initialStartVerse;
  final int? initialEndVerse;
  final int? initialPage;

  const HifzMushafRangePickerScreen({
    super.key,
    required this.quranRepository,
    required this.foundationRepository,
    this.initialSurah = 1,
    this.initialStartVerse,
    this.initialEndVerse,
    this.initialPage,
  });

  @override
  State<HifzMushafRangePickerScreen> createState() =>
      _HifzMushafRangePickerScreenState();
}

class _HifzMushafRangePickerScreenState
    extends State<HifzMushafRangePickerScreen> {
  late int _currentPage;
  late int _selectedSurah;
  int? _startVerse;
  int? _endVerse;
  Set<String> _highlightedVerseKeys = {};
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _selectedSurah = widget.initialSurah;
    _startVerse = widget.initialStartVerse;
    _endVerse = widget.initialEndVerse ?? widget.initialStartVerse;

    if (widget.initialPage != null &&
        widget.initialPage! >= 1 &&
        widget.initialPage! <= 604) {
      _currentPage = widget.initialPage!;
    } else if (_startVerse != null) {
      _currentPage = getMedinaMushafPageNumber(_selectedSurah, _startVerse!);
    } else {
      _currentPage = getMedinaMushafPageNumber(_selectedSurah, 1);
    }

    _pageController =
        PageController(initialPage: (_currentPage - 1).clamp(0, 603));
    _updateHighlightedKeys();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _updateHighlightedKeys() {
    if (_startVerse == null) {
      _highlightedVerseKeys = {};
      return;
    }
    final s = _startVerse!;
    final e = _endVerse ?? _startVerse!;
    final minV = s < e ? s : e;
    final maxV = s < e ? e : s;
    _highlightedVerseKeys = {
      for (int v = minV; v <= maxV; v++) '$_selectedSurah:$v'
    };
  }

  void _handleVerseTap(String verseKey) {
    final parts = verseKey.split(':');
    if (parts.length != 2) return;
    final surah = int.tryParse(parts[0]);
    final verse = int.tryParse(parts[1]);
    if (surah == null || verse == null) return;

    setState(() {
      if (_startVerse == null) {
        // Step 1: Set start verse
        _selectedSurah = surah;
        _startVerse = verse;
        _endVerse = null;
        HapticFeedback.lightImpact();
      } else if (_endVerse == null) {
        // Step 2: Set end verse
        if (surah != _selectedSurah) {
          _selectedSurah = surah;
          _startVerse = verse;
          _endVerse = null;
          HapticFeedback.lightImpact();
        } else {
          if (verse >= _startVerse!) {
            _endVerse = verse;
          } else {
            _endVerse = _startVerse;
            _startVerse = verse;
          }
          HapticFeedback.mediumImpact();
        }
      } else {
        // Step 3: Range already set, smart adjust or change
        if (surah != _selectedSurah) {
          _selectedSurah = surah;
          _startVerse = verse;
          _endVerse = null;
          HapticFeedback.lightImpact();
        } else {
          if (verse > _endVerse!) {
            _endVerse = verse;
          } else if (verse < _startVerse!) {
            _startVerse = verse;
          } else if (verse == _startVerse! && verse == _endVerse!) {
            _startVerse = null;
            _endVerse = null;
          } else {
            _endVerse = verse;
          }
          HapticFeedback.lightImpact();
        }
      }
      _updateHighlightedKeys();
    });
  }

  void _resetSelection() {
    setState(() {
      _startVerse = null;
      _endVerse = null;
      _highlightedVerseKeys = {};
    });
    HapticFeedback.selectionClick();
  }

  void _confirmSelection() {
    if (_startVerse == null) return;
    final s = _startVerse!;
    final e = _endVerse ?? _startVerse!;
    final minV = s < e ? s : e;
    final maxV = s < e ? e : s;
    final page = getMedinaMushafPageNumber(_selectedSurah, minV);

    Navigator.pop(
      context,
      HifzMushafRangePickerResult(
        surah: _selectedSurah,
        startVerse: minV,
        endVerse: maxV,
        page: page,
      ),
    );
  }

  void _showSurahSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.read<SettingsProvider>().languageCode == 'th';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredSurahs = List.generate(114, (i) => i + 1).where((s) {
              if (query.trim().isEmpty) return true;
              final name = widget.quranRepository.getSurahName(s.toString()).toLowerCase();
              final numStr = s.toString();
              final q = query.trim().toLowerCase();
              return name.contains(q) || numStr.contains(q);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Text(
                        isThai ? 'เลือกซูเราะฮ์' : 'Select Surah',
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: isThai
                              ? 'ค้นหาชื่อซูเราะฮ์ หรือหมายเลข...'
                              : 'Search surah name or number...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (val) {
                          setModalState(() => query = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          itemCount: filteredSurahs.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final surahNum = filteredSurahs[idx];
                            final name = widget.quranRepository
                                .getSurahName(surahNum.toString());
                            final totalVerses = qcf.getVerseCount(surahNum);
                            final startPage = getMedinaMushafPageNumber(surahNum, 1);
                            final isCurrent = surahNum == _selectedSurah;

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isCurrent
                                    ? colorScheme.primary
                                    : colorScheme.surfaceContainerHigh,
                                foregroundColor: isCurrent
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                                child: Text(
                                  '$surahNum',
                                  style: textTheme.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(
                                name,
                                style: textTheme.bodyLarge?.copyWith(
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isCurrent ? colorScheme.primary : null,
                                ),
                              ),
                              subtitle: Text(
                                '$totalVerses ${isThai ? 'อายะห์' : 'verses'} · ${isThai ? 'หน้า' : 'Page'} $startPage',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _selectedSurah = surahNum;
                                  _currentPage = startPage;
                                });
                                if (_pageController.hasClients) {
                                  _pageController.jumpToPage(startPage - 1);
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showPageJumpDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.read<SettingsProvider>().languageCode == 'th';
    final controller = TextEditingController(text: '$_currentPage');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            isThai ? 'ไปยังหน้าที่' : 'Jump to Page',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '1 - 604',
              filled: true,
              fillColor: colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final page = int.tryParse(controller.text);
                if (page != null && page >= 1 && page <= 604) {
                  Navigator.pop(ctx);
                  setState(() => _currentPage = page);
                  if (_pageController.hasClients) {
                    _pageController.jumpToPage(page - 1);
                  }
                }
              },
              child: Text(isThai ? 'ไป' : 'Go'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMushafPickerPage(BuildContext context, int pageNumber) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availWidth = constraints.maxWidth;
        final isTablet = constraints.maxWidth > 600 || constraints.maxHeight > 900;
        final double paddedWidth =
            isTablet ? availWidth.clamp(300.0, 600.0) : availWidth;

        return Center(
          child: SizedBox(
            width: paddedWidth,
            height: constraints.maxHeight,
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 3.0,
              child: FutureBuilder<MushafPage>(
                future: widget.foundationRepository
                    .fetchPage(mushafId: 2, pageNumber: pageNumber),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const MushafPageSkeleton();
                  }
                  final mushafPage = snapshot.data!;
                  const actualMushafId = 2;
                  final layout = MushafLayoutProfile.forMushaf(actualMushafId);
                  final fontFamily = widget.foundationRepository
                      .getFontFamily(actualMushafId, pageNumber);

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
                    padding: EdgeInsets.symmetric(
                      horizontal: layout.horizontalPadding,
                      vertical: 12.0,
                    ),
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
                                        Brightness.dark,
                                  ),
                                  showSurahFrame: true,
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
                                highlightedVerseKeys: _highlightedVerseKeys,
                                onVerseTap: _handleVerseTap,
                                onVerseLongPressStart: (_) {},
                                onVerseLongPress: (_) {},
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
        );
      },
    );
  }

  Widget _buildFloatingBottomBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';

    final surahName =
        widget.quranRepository.getSurahName(_selectedSurah.toString());
    final hasSelection = _startVerse != null;
    final isRangeComplete = _startVerse != null && _endVerse != null;

    final s = _startVerse ?? 1;
    final e = _endVerse ?? s;
    final minV = s < e ? s : e;
    final maxV = s < e ? e : s;
    final verseCount = hasSelection ? (maxV - minV + 1) : 0;
    final startPage = hasSelection ? getMedinaMushafPageNumber(_selectedSurah, minV) : _currentPage;
    final endPage = hasSelection ? getMedinaMushafPageNumber(_selectedSurah, maxV) : _currentPage;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: SafeArea(
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(24),
          color: colorScheme.surface,
          shadowColor: Colors.black.withValues(alpha: 0.15),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!hasSelection) ...[
                  Row(
                    children: [
                      Icon(Icons.touch_app_rounded,
                          color: colorScheme.primary, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isThai
                                  ? 'แตะอายะห์เพื่อกำหนดจุดเริ่มต้น'
                                  : 'Tap an ayah to set range start',
                              style: textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              isThai
                                  ? 'ปัดซ้าย-ขวาเพื่อเปิดหน้า หรือเปลี่ยนซูเราะฮ์ด้านบน'
                                  : 'Swipe left/right to browse, or jump to surah above',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.bookmark_added_rounded,
                          color: colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              surahName,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            Text(
                              isRangeComplete
                                  ? '${isThai ? 'อายะห์' : 'Ayat'} $minV – $maxV ($verseCount ${isThai ? 'อายะห์' : 'verses'} · ${isThai ? 'หน้า' : 'P.'} $startPage${startPage != endPage ? '–$endPage' : ''})'
                                  : '${isThai ? 'อายะห์เริ่ม' : 'Start Ayah'}: $minV · ${isThai ? 'แตะอายะห์สิ้นสุด' : 'Tap ending ayah'}',
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _resetSelection,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(isThai ? 'รีเซ็ต' : 'Reset'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _confirmSelection,
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: Text(
                            isRangeComplete
                                ? (isThai ? 'ยืนยันช่วงนี้' : 'Confirm Range')
                                : (isThai
                                    ? 'เลือก 1 อายะห์นี้'
                                    : 'Select Single Ayah'),
                          ),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';

    final surahName =
        widget.quranRepository.getSurahName(_selectedSurah.toString());

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: false,
        title: InkWell(
          onTap: _showSurahSelector,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  surahName,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down_rounded,
                    color: colorScheme.primary, size: 24),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _showPageJumpDialog,
            icon: const Icon(Icons.auto_stories_outlined, size: 18),
            label: Text(
              '${isThai ? 'หน้า' : 'P.'} $_currentPage',
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            reverse: true,
            itemCount: 604,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index + 1;
              });
            },
            itemBuilder: (context, index) {
              final pageNumber = index + 1;
              return _buildMushafPickerPage(context, pageNumber);
            },
          ),
          _buildFloatingBottomBar(context),
        ],
      ),
    );
  }
}
