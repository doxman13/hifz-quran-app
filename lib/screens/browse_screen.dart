// lib/screens/browse_screen.dart
//
// Modern Material 3 Quran Index / Browse screen for HifzSpace.
// Replicates the sleek design of the main Quran app (thai-quran-app)
// with instant search, translation lookups, Arabic voice search,
// and seamless access to Mushaf reading and Hifz memorization (without Meaning mode read).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/medina_mushaf_pages.dart';
import '../data/offline_surah_names.dart';
import '../data/quran_foundation_repository.dart';
import '../data/quran_repository.dart';
import '../database/hifz_repository.dart';
import '../models/hifz_session_config.dart';
import '../providers/local_reading_provider.dart';
import '../providers/mushaf_reading_provider.dart';
import '../providers/settings_provider.dart';
import '../shared/quran_translation_helper.dart';
import '../shared/shared.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_search_sheet.dart';
import 'hifz_wizard_setup_screen.dart';
import 'mushaf_reader_screen.dart';
import 'settings_screen.dart';

class BrowseScreen extends StatefulWidget {
  final QuranRepository repository;
  final QuranFoundationRepository? foundationRepository;
  final AppThemeColors? colors;
  final void Function(String surahId, String verseId)? onOpen;
  final ValueChanged<int>? onOpenPage;
  final void Function(int page, {String? highlightVerseKey})? onOpenMushafPage;

  const BrowseScreen({
    super.key,
    required this.repository,
    this.foundationRepository,
    this.colors,
    this.onOpen,
    this.onOpenPage,
    this.onOpenMushafPage,
  });

  @override
  State<BrowseScreen> createState() => BrowseScreenState();
}

class BrowseScreenState extends State<BrowseScreen> {
  static const List<List<int>> _juzStarts = [
    [1, 1],
    [2, 142],
    [2, 253],
    [3, 93],
    [4, 24],
    [4, 148],
    [5, 82],
    [6, 111],
    [7, 88],
    [8, 41],
    [9, 93],
    [11, 6],
    [12, 53],
    [15, 1],
    [17, 1],
    [18, 75],
    [21, 1],
    [23, 1],
    [25, 21],
    [27, 56],
    [29, 46],
    [33, 31],
    [36, 28],
    [39, 32],
    [41, 47],
    [46, 1],
    [51, 31],
    [58, 1],
    [67, 1],
    [78, 1],
  ];

  static int getJuzStartPage(int juzIndex) {
    final start = _juzStarts[juzIndex];
    return getMedinaMushafPageNumber(start[0], start[1]);
  }

  static int getJuzEndPage(int juzIndex) {
    if (juzIndex < 29) {
      final nextStart = _juzStarts[juzIndex + 1];
      return getMedinaMushafPageNumber(nextStart[0], nextStart[1]) - 1;
    }
    return 604;
  }

  String _mode = 'surah';
  final TextEditingController _searchController = TextEditingController();
  late final QuranFoundationRepository _foundationRepo;
  QuranSearchResult? _apiSearchResult;
  bool _isApiSearching = false;
  Timer? _debounceTimer;

  Map<int, SurahCompletionRecord> _surahRecords = {};

  @override
  void initState() {
    super.initState();
    _foundationRepo =
        widget.foundationRepository ?? QuranFoundationRepository();
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
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchQueryChanged(String query) {
    setState(() {});

    final trimmed = query.trim();

    _debounceTimer?.cancel();
    if (trimmed.length < 2) {
      setState(() {
        _apiSearchResult = null;
        _isApiSearching = false;
      });
      return;
    }

    setState(() {
      _isApiSearching = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      final res = await _foundationRepo.searchQuran(query: trimmed);
      if (mounted && _searchController.text.trim() == trimmed) {
        setState(() {
          _apiSearchResult = res;
          _isApiSearching = false;
        });
      }
    });
  }

  void _openPage(int page, {String? highlightVerseKey}) {
    if (widget.onOpenPage != null) {
      widget.onOpenPage!(page);
      return;
    }
    if (widget.onOpenMushafPage != null) {
      widget.onOpenMushafPage!(page, highlightVerseKey: highlightVerseKey);
      return;
    }

    final mushafProvider = context.read<MushafReadingProvider>();
    final profile = mushafProvider.freeReadProfileForMushaf(1);
    unawaited(mushafProvider.openUnifiedFreeRead());
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MushafReaderScreen(
          quranRepository: widget.repository,
          foundationRepository: _foundationRepo,
          profileId: profile.id,
          initialPage: page,
          initialHighlightVerseKey: highlightVerseKey,
        ),
      ),
    );
  }

  void _openMushafForVerse(String surahId, String verseId) {
    final sId = int.tryParse(surahId) ?? 1;
    final vId = int.tryParse(verseId) ?? 1;
    final pageNumber = getMedinaMushafPageNumber(sId, vId);

    if (widget.onOpenMushafPage != null) {
      widget.onOpenMushafPage!(pageNumber, highlightVerseKey: '$sId:$vId');
      return;
    }

    _openPage(pageNumber, highlightVerseKey: '$sId:$vId');
  }

  void _setMode(String mode) {
    setState(() {
      _mode = mode;
    });
  }

  int _compareRefs(VerseRef left, VerseRef right) {
    final leftSurah = int.tryParse(left.surahId) ?? 0;
    final rightSurah = int.tryParse(right.surahId) ?? 0;
    if (leftSurah != rightSurah) return leftSurah.compareTo(rightSurah);

    final leftVerse = int.tryParse(left.verseId) ?? 0;
    final rightVerse = int.tryParse(right.verseId) ?? 0;
    return leftVerse.compareTo(rightVerse);
  }

  Set<String> _completedSurahs(LocalReadingProvider provider) {
    final completed = <String>{};
    final profiles = [...provider.activeProfiles, ...provider.archivedProfiles];

    for (final profile in profiles) {
      final target = profile.target;
      if (target == null || isFreeReadProfile(profile)) continue;
      if (_compareRefs(profile.current, target) < 0) continue;

      final startSurah = int.tryParse(profile.start.surahId);
      final targetSurah = int.tryParse(target.surahId);
      if (startSurah == null || targetSurah == null) continue;

      for (var surah = startSurah; surah <= targetSurah; surah++) {
        completed.add(surah.toString());
      }
    }

    return completed;
  }

  Future<void> _chooseBrowseDestination(
    String surahId,
    String verseId,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final isThai = context.read<SettingsProvider>().languageCode == 'th';
    final surah = int.tryParse(surahId) ?? 1;
    final verse = int.tryParse(verseId) ?? 1;
    final pageNumber = getMedinaMushafPageNumber(surah, verse);

    final destination = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radius),
        ),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('select_reading_mode'),
                style: GoogleFonts.notoSansThai(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ModeSelectionCard(
                      icon: Icons.import_contacts,
                      title: context.tr('mushaf_page'),
                      subtitle: '${isThai ? 'หน้า' : 'Page'} $pageNumber',
                      onTap: () => Navigator.pop(sheetContext, 'mushaf'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ModeSelectionCard(
                      icon: Icons.psychology_outlined,
                      title: isThai ? 'ท่องจำฮิฟซ์' : 'Hifz Memorize',
                      subtitle: isThai ? 'โหมดฝึกท่องจำ' : 'Memorization Mode',
                      onTap: () => Navigator.pop(sheetContext, 'hifz'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || destination == null) return;
    if (destination == 'mushaf') {
      _openPage(pageNumber, highlightVerseKey: '$surah:$verse');
      return;
    }
    if (destination == 'hifz') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HifzWizardSetupScreen(
            quranRepository: widget.repository,
            foundationRepository: _foundationRepo,
            initialSurah: surah,
            initialStartVerse: verse,
            initialStep: 0,
          ),
        ),
      );
      if (mounted) {
        _loadHifzRecords();
      }
      return;
    }
  }

  void _handleOpen(String surahId, String verseId) {
    if (widget.onOpen != null) {
      widget.onOpen!(surahId, verseId);
    } else {
      _chooseBrowseDestination(surahId, verseId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors ?? context.appColors;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final settings = context.watch<SettingsProvider>();
    final isThai = settings.languageCode == 'th';
    final query = _searchController.text.toLowerCase();
    final isSearching = query.isNotEmpty;
    final completedReadingSurahs = _completedSurahs(
      context.watch<LocalReadingProvider>(),
    );

    // Build surah list with optional search
    final surahs = [
      for (var id = 1; id <= 114; id++)
        (
          id: id.toString(),
          name: widget.repository.getSurahName(id.toString()),
          arabic: offlineSurahNamesAr[id.toString()] ?? '',
          count: widget.repository.getSurahVerses(id.toString()).length,
        ),
    ].where((surah) {
      final sId = surah.id;
      final thName = (offlineSurahNamesTh[sId] ?? '').toLowerCase();
      return query.isEmpty ||
          surah.id.contains(query) ||
          surah.name.toLowerCase().contains(query) ||
          thName.contains(query) ||
          surah.arabic.contains(query);
    }).toList();

    final juz = [
      for (
        var index = 0;
        index < BrowseScreenState._juzStarts.length;
        index++
      )
        (
          id: index + 1,
          startSurah: BrowseScreenState._juzStarts[index][0].toString(),
          startAyah: BrowseScreenState._juzStarts[index][1].toString(),
          startPage: BrowseScreenState.getJuzStartPage(index),
          endPage: BrowseScreenState.getJuzEndPage(index),
        ),
    ].where((item) {
      final name = widget.repository
          .getSurahName(item.startSurah)
          .toLowerCase();
      final thName = (offlineSurahNamesTh[item.startSurah] ?? '').toLowerCase();
      return query.isEmpty ||
          item.id.toString().contains(query) ||
          'juz ${item.id}'.contains(query) ||
          'ญุซอ์ ${item.id}'.contains(query) ||
          name.contains(query) ||
          thName.contains(query);
    }).toList();

    final cleanQuery = query.replaceAll(RegExp(r'\D'), '');
    final int? queriedPage = int.tryParse(cleanQuery);

    final pages = [for (var page = 1; page <= 604; page++) page].where((page) {
      if (query.isEmpty) return true;
      if (queriedPage != null && page == queriedPage) return true;
      return page.toString().contains(query) ||
          'page $page'.contains(query) ||
          'หน้า $page'.contains(query);
    }).toList();

    // Collect verse translation matches
    final List<
      ({
        String surahName,
        String surahId,
        String verseId,
        String translationText,
      })
    >
    verseMatches = [];
    if (isSearching && query.length >= 2) {
      outer:
      for (var id = 1; id <= 114; id++) {
        final verses = widget.repository.getSurahVerses(id.toString());
        for (var verse in verses) {
          final primaryTranslation = resolveVerseTranslationText(
            context: context,
            verseKey: verse.verseKey,
            verse: verse,
            settings: settings,
          );
          if (primaryTranslation.toLowerCase().contains(query) ||
              verse.thaiV3.toLowerCase().contains(query) ||
              verse.thaiV2.toLowerCase().contains(query) ||
              verse.english.toLowerCase().contains(query)) {
            verseMatches.add((
              surahName: widget.repository.getSurahName(verse.surahId),
              surahId: verse.surahId,
              verseId: verse.id,
              translationText: primaryTranslation,
            ));
            if (verseMatches.length >= 30) break outer;
          }
        }
      }
    }

    final popularChips = isThai
        ? ['ความเมตตา', 'ความอดทน', 'การละหมาด', 'สวรรค์', 'นรก', 'ศรัทธา']
        : ['Mercy', 'Patience', 'Prayer', 'Paradise', 'Hellfire', 'Faith'];

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('choose_surah'),
                          style: textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('which_surah_to_read'),
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SettingsScreen(repository: widget.repository),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(24),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.settings,
                        color: colorScheme.onSurface,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Search Field ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0C000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchQueryChanged,
                  decoration: InputDecoration(
                    hintText: isThai
                        ? 'ค้นหา ซูเราะฮ์, ญุซอ์, หน้า...'
                        : 'Search Surah, Juz, Page...',
                    hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 16.0, right: 8.0),
                      child: Icon(
                        Icons.search,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    suffixIcon: query.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: IconButton(
                              icon: Icon(
                                Icons.close,
                                size: 18,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchQueryChanged('');
                              },
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: IconButton(
                              icon: Icon(
                                Icons.mic_rounded,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                              tooltip: isThai
                                  ? 'ค้นหาด้วยเสียง (อัลกุรอานภาษาอาหรับ)'
                                  : 'Voice Search (Arabic Quran)',
                              onPressed: () {
                                VoiceSearchSheet.show(
                                  context,
                                  repository: widget.repository,
                                  onOpenPage: (page, {highlightVerseKey}) {
                                    _openPage(
                                      page,
                                      highlightVerseKey: highlightVerseKey,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Popular Search Chips ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: popularChips.map((chip) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        _searchController.text = chip;
                        _onSearchQueryChanged(chip);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _searchController.text == chip
                              ? colorScheme.primary
                              : colors.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '🔍 $chip',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _searchController.text == chip
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  )).toList(),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Mode tabs (only when not searching) ─────────────────────────
            if (!isSearching)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _TabButton(
                        label: context.tr('surah'),
                        selected: _mode == 'surah',
                        colors: colors,
                        onTap: () => _setMode('surah'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _TabButton(
                        label: context.tr('juz'),
                        selected: _mode == 'juz',
                        colors: colors,
                        onTap: () => _setMode('juz'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _TabButton(
                        label: context.tr('page'),
                        selected: _mode == 'page',
                        colors: colors,
                        onTap: () => _setMode('page'),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // ── Content List ────────────────────────────────────────────────
            Expanded(
              child: ClipRect(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 0,
                  ),
                  children: [
                    if (isSearching) ...[
                      // Surah matches
                      if (surahs.isNotEmpty) ...[
                        Text(
                          context.tr('surah'),
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...surahs.map(
                          (surah) {
                            final sNumber = int.tryParse(surah.id) ?? 0;
                            final isMastered = _surahRecords[sNumber]?.newVersesCompleted == true;
                            final isCompleted = isMastered || completedReadingSurahs.contains(surah.id);
                            return _SimpleLinkRow(
                              colors: colors,
                              index: surah.id,
                              title: surah.name.replaceFirst(RegExp(r'^\d+\.\s*'), ''),
                              arabicTitle: surah.arabic,
                              subtitle: context.tr(
                                'ayat_count',
                                args: {'count': '${surah.count}'},
                              ),
                              icon: Icons.menu_book_outlined,
                              completed: isCompleted,
                              onTap: () => _handleOpen(surah.id, '1'),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Verse / translation matches
                      if (verseMatches.isNotEmpty) ...[
                        Text(
                          isThai
                              ? 'อายะฮ์ที่ตรงกัน (${verseMatches.length})'
                              : 'Matching Verses (${verseMatches.length})',
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...verseMatches.map(
                          (m) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radius,
                              ),
                              child: _SectionCard(
                                colors: colors,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.menu_book_outlined,
                                          color: colors.primary,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${m.surahName}, ${context.tr('ayah_number', args: {'number': m.verseId})}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: textTheme.titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: colors.textStrong,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      m.translationText,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.foreground,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () => _handleOpen(m.surahId, m.verseId),
                                          icon: const Icon(Icons.psychology_rounded, size: 14),
                                          label: Text(
                                            isThai ? 'ท่องจำ' : 'Memorize',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            minimumSize: const Size(0, 32),
                                            side: BorderSide.none,
                                            backgroundColor: colors.surfaceMuted,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton.icon(
                                          onPressed: () => _openMushafForVerse(m.surahId, m.verseId),
                                          icon: const Icon(Icons.import_contacts, size: 14),
                                          label: Text(
                                            isThai ? 'อ่านในมุศฮัฟ' : 'Read in Mushaf',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                          style: FilledButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            minimumSize: const Size(0, 32),
                                            backgroundColor: colors.primary,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],

                      // Live API search matches
                      if (_isApiSearching)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ),
                      if (_apiSearchResult != null && _apiSearchResult!.items.isNotEmpty) ...[
                        Text(
                          isThai
                              ? 'ผลการค้นหาจากอัลกุรอาน (${_apiSearchResult!.items.length})'
                              : 'Quran Search Results (${_apiSearchResult!.items.length})',
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._apiSearchResult!.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppTheme.radius),
                              child: _SectionCard(
                                colors: colors,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primaryContainer,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isThai
                                                ? 'สูเราะฮ์ ${widget.repository.getSurahName(item.surahId).replaceFirst(RegExp(r'^\d+\.\s*'), '')} (${item.verseKey})'
                                                : 'Surah ${widget.repository.getSurahName(item.surahId).replaceFirst(RegExp(r'^\d+\.\s*'), '')} (${item.verseKey})',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.onPrimaryContainer,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (item.arabicText.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          item.arabicText,
                                          textDirection: TextDirection.rtl,
                                          style: GoogleFonts.amiri(
                                            fontSize: 16,
                                            height: 1.8,
                                            color: colors.textStrong,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (item.translationText.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        item.translationText,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.foreground,
                                          fontSize: 12,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () => _handleOpen(item.surahId, item.verseId),
                                          icon: const Icon(Icons.psychology_rounded, size: 14),
                                          label: Text(
                                            isThai ? 'ท่องจำ' : 'Memorize',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            minimumSize: const Size(0, 32),
                                            side: BorderSide.none,
                                            backgroundColor: colors.surfaceMuted,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton.icon(
                                          onPressed: () => _openMushafForVerse(item.surahId, item.verseId),
                                          icon: const Icon(Icons.import_contacts, size: 14),
                                          label: Text(
                                            isThai ? 'อ่านในมุศฮัฟ' : 'Read in Mushaf',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                          style: FilledButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            minimumSize: const Size(0, 32),
                                            backgroundColor: colors.primary,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (surahs.isEmpty &&
                          verseMatches.isEmpty &&
                          (_apiSearchResult == null || _apiSearchResult!.items.isEmpty) &&
                          !_isApiSearching)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              context.tr(
                                'no_results_for',
                                args: {'query': query},
                              ),
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ] else ...[
                      if (_mode == 'surah')
                        ...surahs.map(
                          (surah) {
                            final sNumber = int.tryParse(surah.id) ?? 0;
                            final isMastered = _surahRecords[sNumber]?.newVersesCompleted == true;
                            final isCompleted = isMastered || completedReadingSurahs.contains(surah.id);
                            return _SimpleLinkRow(
                              colors: colors,
                              index: surah.id,
                              title: surah.name.replaceFirst(RegExp(r'^\d+\.\s*'), ''),
                              arabicTitle: surah.arabic,
                              subtitle: context.tr(
                                'ayat_count',
                                args: {'count': '${surah.count}'},
                              ),
                              icon: Icons.menu_book_outlined,
                              completed: isCompleted,
                              onTap: () => _handleOpen(surah.id, '1'),
                            );
                          },
                        )
                      else if (_mode == 'juz')
                        ...juz.map(
                          (item) => _SimpleLinkRow(
                            colors: colors,
                            index: '${item.id}',
                            title: '${context.tr('juz')} ${item.id}',
                            subtitle:
                                '${widget.repository.getSurahName(item.startSurah).replaceFirst(RegExp(r'^\d+\.\s*'), '')}:${item.startAyah} · ${isThai ? 'หน้า' : 'Page'} ${item.startPage} – ${item.endPage}',
                            icon: Icons.view_week_outlined,
                            onTap: () =>
                                _handleOpen(item.startSurah, item.startAyah),
                          ),
                        )
                      else
                        _PageNumberGrid(
                          colors: colors,
                          pages: pages,
                          onOpenPage: _openPage,
                        ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageNumberGrid extends StatelessWidget {
  final AppThemeColors colors;
  final List<int> pages;
  final ValueChanged<int> onOpenPage;

  const _PageNumberGrid({
    required this.colors,
    required this.pages,
    required this.onOpenPage,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pages.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.6,
      ),
      itemBuilder: (context, index) {
        final page = pages[index];
        return FilledButton(
          onPressed: () => onOpenPage(page),
          style: FilledButton.styleFrom(
            backgroundColor: colors.surface,
            foregroundColor: colors.textStrong,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(
            '${context.tr('page')} $page',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final AppThemeColors colors;
  final Widget child;

  const _SectionCard({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: child,
    );
  }
}

class _SimpleLinkRow extends StatelessWidget {
  final AppThemeColors colors;
  final String? index;
  final String title;
  final String? arabicTitle;
  final String subtitle;
  final IconData icon;
  final bool completed;
  final VoidCallback onTap;

  const _SimpleLinkRow({
    required this.colors,
    this.index,
    required this.title,
    this.arabicTitle,
    required this.subtitle,
    required this.icon,
    this.completed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (index != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      index!,
                      style: GoogleFonts.notoSansThai(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                ] else ...[
                  Icon(icon, color: colors.primary),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansThai(
                          color: colors.textStrong,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.notoSansThai(
                          color: colors.foreground,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (arabicTitle != null && arabicTitle!.isNotEmpty) ...[
                  Text(
                    arabicTitle!,
                    style: GoogleFonts.amiri(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(width: 8),
                ],
                if (completed) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                    size: 18,
                  ),
                ],
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.foreground.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final AppThemeColors colors;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: selected ? colors.primary : colors.surface,
        foregroundColor: selected ? colors.textInverse : colors.foreground,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: const StadiumBorder(),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: GoogleFonts.notoSansThai(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _ModeSelectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeSelectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansThai(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansThai(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
