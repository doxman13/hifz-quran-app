// lib/screens/browse_screen.dart
//
// Modern Material 3 Quran Index / Browse screen.
// Allows browsing by Surah (1-114), Juz (1-30), and Page (1-604),
// with instant search and direct entry points to both Mushaf Reading and Hifz Memorization.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;
import '../data/medina_mushaf_pages.dart';

import '../data/offline_surah_names.dart';
import '../data/quran_foundation_repository.dart';
import '../data/quran_repository.dart';
import '../providers/settings_provider.dart';
import '../database/hifz_repository.dart';
import '../models/hifz_session_config.dart';
import 'hifz_new_verses_setup_screen.dart';
import 'hifz_review_setup_screen.dart';
import 'mushaf_reader_screen.dart';
import '../widgets/voice_search_sheet.dart';

class BrowseScreen extends StatefulWidget {
  final QuranRepository repository;
  final QuranFoundationRepository foundationRepository;
  final void Function(int page, {String? highlightVerseKey})? onOpenMushafPage;

  const BrowseScreen({
    super.key,
    required this.repository,
    required this.foundationRepository,
    this.onOpenMushafPage,
  });

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 30 Juz definitions: [startingSurah, startingVerse, page]
  static const List<List<int>> _juzData = [
    [1, 1, 1],
    [2, 142, 22],
    [2, 253, 42],
    [3, 93, 62],
    [4, 24, 82],
    [4, 148, 102],
    [5, 82, 121],
    [6, 111, 142],
    [7, 88, 162],
    [8, 41, 182],
    [9, 93, 201],
    [11, 6, 222],
    [12, 53, 242],
    [15, 1, 262],
    [17, 1, 282],
    [18, 75, 302],
    [21, 1, 322],
    [23, 1, 342],
    [25, 21, 362],
    [27, 56, 382],
    [29, 46, 402],
    [33, 31, 422],
    [36, 28, 442],
    [39, 32, 462],
    [41, 47, 482],
    [46, 1, 502],
    [51, 31, 522],
    [58, 1, 542],
    [67, 1, 562],
    [78, 1, 582],
  ];

  Map<int, SurahCompletionRecord> _surahRecords = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHifzRecords();
  }

  Future<void> _loadHifzRecords() async {
    final records = await HifzRepository().getAllCompletionRecords();
    if (mounted) {
      setState(() {
        _surahRecords = {for (var r in records) r.surahNumber: r};
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openPage(int page, {String? highlightVerseKey}) {
    if (widget.onOpenMushafPage != null) {
      widget.onOpenMushafPage!(page, highlightVerseKey: highlightVerseKey);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MushafReaderScreen(
            quranRepository: widget.repository,
            foundationRepository: widget.foundationRepository,
            initialPage: page,
            initialHighlightVerseKey: highlightVerseKey,
          ),
        ),
      );
    }
  }

  void _openHifzForSurah(int surahNumber) async {
    final startPage = getMedinaMushafPageNumber(surahNumber, 1);
    final totalVerses = qcf.getVerseCount(surahNumber);
    final endPage = getMedinaMushafPageNumber(surahNumber, totalVerses);
    final isThai = context.read<SettingsProvider>().languageCode == 'th';
    final enName = offlineSurahNamesEn[surahNumber.toString()] ??
        widget.repository.getSurahName(surahNumber.toString());
    final thName = offlineSurahNamesTh[surahNumber.toString()] ?? '';
    final arName = offlineSurahNamesAr[surahNumber.toString()] ??
        qcf.getSurahNameArabic(surahNumber);
    final record = _surahRecords[surahNumber];
    final isMastered = record?.newVersesCompleted == true;

    final selectedMode = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isMastered
                            ? colorScheme.primaryContainer
                            : colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        isMastered
                            ? Icons.check_circle_outline_rounded
                            : Icons.auto_stories_rounded,
                        color: isMastered
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSecondaryContainer,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                enName,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                arName,
                                style: GoogleFonts.amiri(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                            ],
                          ),
                          Text(
                            isThai && thName.isNotEmpty
                                ? '$thName · $totalVerses อายะห์ · หน้า $startPage'
                                : '$totalVerses verses · Page $startPage',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Option 1: Takrar (New Verses)
                Material(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(ctx, 'new'),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.psychology_rounded,
                              color: colorScheme.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isThai
                                      ? 'ท่องจำอายะห์ใหม่ (Takrar)'
                                      : 'New Verses (Takrar)',
                                  style: textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isThai
                                      ? 'ท่องจำอายะห์ใหม่ทีละชุด กำหนดจำนวนรอบและการซ้ำ'
                                      : 'Memorize new verse sets with custom repetitions',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Option 2: Muraja'ah (Review Mode)
                Material(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(ctx, 'review'),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isMastered
                              ? colorScheme.primary.withValues(alpha: 0.5)
                              : colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.replay_rounded,
                              color: colorScheme.secondary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      isThai
                                          ? 'ทบทวนฮิฟซ์ (Muraja\'ah)'
                                          : 'Review Mode (Muraja\'ah)',
                                      style: textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    if (isMastered) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isThai ? 'แนะนำ' : 'Recommended',
                                          style: textTheme.labelSmall?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isThai
                                      ? 'ทบทวนซูเราะฮ์นี้ที่จำได้แล้ว (เห็น 2× / ซ่อน 2×)'
                                      : 'Review memorized verses (2× Visible / 2× Hidden)',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedMode == 'new' && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HifzNewVersesSetupScreen(
            quranRepository: widget.repository,
            foundationRepository: widget.foundationRepository,
            initialSurah: surahNumber,
            initialStartVerse: 1,
            initialEndVerse: totalVerses > 3 ? 3 : totalVerses,
            initialRepeatStart: 1,
            initialPage: startPage,
            initialIsSurahMode: true,
          ),
        ),
      );
      if (mounted) {
        _loadHifzRecords();
      }
    } else if (selectedMode == 'review' && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HifzReviewSetupScreen(
            quranRepository: widget.repository,
            foundationRepository: widget.foundationRepository,
            initialStartSurah: surahNumber,
            initialEndSurah: surahNumber,
            initialVersesSurah: surahNumber,
            initialVersesStart: 1,
            initialVersesEnd: totalVerses,
            initialStartPage: startPage,
            initialEndPage: endPage,
            initialTabIndex: 0,
          ),
        ),
      );
      if (mounted) {
        _loadHifzRecords();
      }
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
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text(
          isThai ? 'สารบัญอัลกุรอาน' : 'Quran Index',
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              // Search Field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    textAlignVertical: TextAlignVertical.center,
                    style: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: isThai
                          ? 'ค้นหาซูเราะฮ์, อายะห์, หรือหน้า...'
                          : 'Search Surah name, number, or page...',
                      hintStyle: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : IconButton(
                              icon: Icon(
                                Icons.mic_rounded,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                              tooltip: isThai ? 'ค้นหาด้วยเสียง (อัลกุรอานภาษาอาหรับ)' : 'Voice Search (Arabic Quran)',
                              onPressed: () {
                                VoiceSearchSheet.show(
                                  context,
                                  repository: widget.repository,
                                  onOpenPage: _openPage,
                                );
                              },
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // TabBar (Surah, Juz, Page)
              TabBar(
                controller: _tabController,
                indicatorColor: colorScheme.primary,
                indicatorWeight: 3,
                labelColor: colorScheme.primary,
                unselectedLabelColor: colorScheme.onSurfaceVariant,
                labelStyle: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  Tab(text: isThai ? 'ซูเราะฮ์ (114)' : 'Surahs (114)'),
                  Tab(text: isThai ? 'ญุซอ์ (30)' : 'Juz (30)'),
                  Tab(text: isThai ? 'หน้า (604)' : 'Pages (604)'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSurahsTab(colorScheme, textTheme, isThai),
          _buildJuzTab(colorScheme, textTheme, isThai),
          _buildPagesTab(colorScheme, textTheme, isThai),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Surahs
  // ---------------------------------------------------------------------------

  Widget _buildSurahsTab(
    ColorScheme colorScheme,
    TextTheme textTheme,
    bool isThai,
  ) {
    final query = _searchQuery.toLowerCase();
    final surahIndices = List.generate(114, (i) => i + 1).where((s) {
      if (query.isEmpty) return true;
      final numStr = s.toString();
      final enName = (offlineSurahNamesEn[numStr] ?? '').toLowerCase();
      final arName = offlineSurahNamesAr[numStr] ?? '';
      final thName = (offlineSurahNamesTh[numStr] ?? '').toLowerCase();
      return numStr == query ||
          enName.contains(query) ||
          arName.contains(query) ||
          thName.contains(query);
    }).toList();

    if (surahIndices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              isThai ? 'ไม่พบซูเราะฮ์ที่ค้นหา' : 'No Surah found',
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: surahIndices.length,
      separatorBuilder: (context, i) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final surahNumber = surahIndices[index];
        final sKey = surahNumber.toString();
        final enName = offlineSurahNamesEn[sKey] ?? 'Surah $surahNumber';
        final thName = offlineSurahNamesTh[sKey] ?? '';
        final totalVerses = qcf.getVerseCount(surahNumber);
        final startPage = getMedinaMushafPageNumber(surahNumber, 1);
        final hifzRecord = _surahRecords[surahNumber];
        final isMastered = hifzRecord?.newVersesCompleted == true;
        final reviewCount = hifzRecord?.reviewCount ?? 0;

        return Material(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => _openPage(startPage, highlightVerseKey: '$surahNumber:1'),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Surah Number Badge
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isMastered
                          ? colorScheme.primary
                          : colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: isMastered
                        ? Icon(
                            Icons.check_rounded,
                            color: colorScheme.onPrimary,
                            size: 22,
                          )
                        : Text(
                            '$surahNumber',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),

                  // Surah English, Badges & Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                enName,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isMastered) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isThai ? 'ท่องจำแล้ว' : 'Mastered',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ] else if (reviewCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer
                                      .withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isThai ? 'ทบทวน $reviewCount×' : '$reviewCount× Rev',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSecondaryContainer,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isThai && thName.isNotEmpty
                              ? '$thName · $totalVerses อายะห์ · หน้า $startPage'
                              : '$totalVerses verses · Page $startPage',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Calligraphic Surah Name (QcfSurahName)
                  Text(
                    String.fromCharCode(0xe000 + surahNumber),
                    style: TextStyle(
                      fontFamily: 'QcfSurahName',
                      fontSize: 28,
                      color: isMastered ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Memorize / Review Shortcut Button
                  Container(
                    decoration: BoxDecoration(
                      color: isMastered
                          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      tooltip: isThai
                          ? (isMastered ? 'ทบทวนซูเราะฮ์นี้' : 'ท่องจำซูเราะฮ์นี้')
                          : (isMastered ? 'Review this Surah' : 'Memorize this Surah'),
                      icon: Icon(
                        isMastered ? Icons.replay_rounded : Icons.psychology_rounded,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                      onPressed: () => _openHifzForSurah(surahNumber),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Juz
  // ---------------------------------------------------------------------------

  Widget _buildJuzTab(
    ColorScheme colorScheme,
    TextTheme textTheme,
    bool isThai,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 30,
      separatorBuilder: (context, i) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final juzNumber = index + 1;
        final info = _juzData[index];
        final startSurah = info[0];
        final startVerse = info[1];
        final startPage = info[2];
        final endPage = juzNumber < 30 ? _juzData[index + 1][2] - 1 : 604;
        final surahName =
            offlineSurahNamesEn[startSurah.toString()] ?? 'Surah $startSurah';

        return Material(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => _openPage(
              startPage,
              highlightVerseKey: '$startSurah:$startVerse',
            ),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$juzNumber',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${isThai ? 'ญุซอ์' : 'Juz'} $juzNumber',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$surahName : $startVerse · ${isThai ? 'หน้า' : 'Page'} $startPage – $endPage',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Pages
  // ---------------------------------------------------------------------------

  Widget _buildPagesTab(
    ColorScheme colorScheme,
    TextTheme textTheme,
    bool isThai,
  ) {
    final query = _searchQuery.replaceAll(RegExp(r'\D'), '');
    final int? queriedPage = int.tryParse(query);

    final pages = [for (var p = 1; p <= 604; p++) p].where((p) {
      if (query.isEmpty) return true;
      if (queriedPage != null) return p.toString().startsWith(query);
      return true;
    }).toList();

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.15,
      ),
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final pageNum = pages[index];

        return Material(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => _openPage(pageNum),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$pageNum',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  Text(
                    isThai ? 'หน้า' : 'Page',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
