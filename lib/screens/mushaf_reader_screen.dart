import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qcf_quran/qcf_quran.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/quran_foundation_repository.dart';
import '../data/quran_repository.dart';
import '../models/mushaf_models.dart';
import '../providers/mushaf_reading_provider.dart';
import '../providers/local_reading_provider.dart';
import '../providers/mushaf_audio_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stats_provider.dart';
import '../providers/translation_manager_provider.dart';
import '../providers/thai_text_protection_provider.dart';
import '../models/verse.dart';
import '../theme/app_theme.dart';
import '../shared/shared.dart';
import '../utils/html_parser.dart';
import '../widgets/tadabbur_panel.dart';

class MushafReaderScreen extends StatefulWidget {
  final QuranRepository quranRepository;
  final QuranFoundationRepository foundationRepository;
  final String? profileId;
  final int? initialPage;
  final String? initialHighlightVerseKey;
  final Set<String>? initialHighlightVerseKeys;
  final String? shortcutId;

  const MushafReaderScreen({
    super.key,
    required this.quranRepository,
    required this.foundationRepository,
    this.profileId,
    this.initialPage,
    this.initialHighlightVerseKey,
    this.initialHighlightVerseKeys,
    this.shortcutId,
  });

  @override
  State<MushafReaderScreen> createState() => _MushafReaderScreenState();
}

class _MushafReaderScreenState extends State<MushafReaderScreen> {
  late int _pageNumber;
  late PageController _pageController;
  bool _isTranslationView = false;
  bool _isMenuVisible = true;
  bool _completionShown = false;
  String? _highlightedVerseKey;
  String? _translationVerseKey;
  String? _translationText;
  bool _translationBookmarked = false;
  Timer? _translationTimer;
  Timer? _highlightTimer;
  Timer? _menuAutoHideTimer;
  int? _lastAudioPageNumber;

  void _startAutoHideTimer() {
    _menuAutoHideTimer?.cancel();
    _menuAutoHideTimer = Timer(const Duration(seconds: 7), () {
      if (mounted && _isMenuVisible) {
        setState(() {
          _isMenuVisible = false;
        });
      }
    });
  }

  void _cancelAutoHideTimer() {
    _menuAutoHideTimer?.cancel();
  }

  MushafProfile? _getProfile() {
    if (widget.shortcutId != null) {
      final lp = context.read<LocalReadingProvider>().profileById(
        widget.shortcutId!,
      );
      if (lp == null) return null;
      final startPage = qcf.getPageNumber(
        int.tryParse(lp.start.surahId) ?? 1,
        int.tryParse(lp.start.verseId) ?? 1,
      );
      final targetPage = lp.target != null
          ? qcf.getPageNumber(
              int.tryParse(lp.target!.surahId) ?? 1,
              int.tryParse(lp.target!.verseId) ?? 1,
            )
          : 604;
      final currentPage = qcf.getPageNumber(
        int.tryParse(lp.current.surahId) ?? 1,
        int.tryParse(lp.current.verseId) ?? 1,
      );
      return MushafProfile(
        id: lp.id,
        userId: lp.userId,
        name: lp.name,
        slug: lp.slug,
        mushafId: 2, // Madani QCF
        planMode: 'custom',
        startPage: startPage,
        targetPage: targetPage,
        currentPage: currentPage,
        lastViewedPage: currentPage,
        sortOrder: 0,
        isArchived: false,
        createdAt: lp.createdAt,
        updatedAt: lp.updatedAt,
      );
    }
    return context.read<MushafReadingProvider>().profileById(widget.profileId) ??
        context.read<MushafReadingProvider>().activeProfile;
  }

  @override
  void initState() {
    super.initState();
    final profile = _getProfile();
    _pageNumber = widget.initialPage ?? profile?.currentPage ?? 1;
    _pageController = PageController(
      initialPage: _pageToIndex(profile, _pageNumber),
    );
    _highlightedVerseKey = widget.initialHighlightVerseKey;

    _startAutoHideTimer();

    // Enable Wakelock if keepAwake setting is true
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final settings = Provider.of<SettingsProvider>(context, listen: false);
        if (settings.keepAwake) {
          WakelockPlus.enable();
        }
        final currentProfile = _getProfile();
        if (currentProfile != null) {
          if (widget.shortcutId != null) {
            final pageData = await widget.foundationRepository.fetchPage(
              mushafId: 2,
              pageNumber: _pageNumber,
            );
            if (mounted && pageData.verses.isNotEmpty) {
              final firstVerse = pageData.verses.first;
              final verseRef = toVerseRef(
                firstVerse.surahId.toString(),
                firstVerse.verseId.toString(),
              );
              await context.read<LocalReadingProvider>().updateShortcutProgress(
                widget.shortcutId!,
                verseRef,
              );
            }
          } else {
            context.read<MushafReadingProvider>().updateProgress(
              profileId: currentProfile.id,
              pageNumber: _pageNumber,
            );
          }
          unawaited(_logMushafPageRead(currentProfile.mushafId, _pageNumber));
        }

        if (widget.initialHighlightVerseKey != null) {
          if (!mounted) return;
          final profileForTranslation =
              currentProfile ?? context.read<MushafReadingProvider>().activeProfile;
          if (profileForTranslation != null) {
            _showVerseTranslation(
              profileForTranslation,
              widget.initialHighlightVerseKey!,
              _pageNumber,
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _translationTimer?.cancel();
    _highlightTimer?.cancel();
    _menuAutoHideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  int _pageToIndex(MushafProfile? profile, int page) {
    if (profile == null) return 0;
    return _clampInt(page, profile.startPage, profile.targetPage) -
        profile.startPage;
  }

  int _indexToPage(MushafProfile profile, int index) {
    return _clampInt(
      profile.startPage + index,
      profile.startPage,
      profile.targetPage,
    );
  }

  Future<void> _handlePageChanged(MushafProfile profile, int page) async {
    _dismissTranslation();
    setState(() => _pageNumber = page);
    if (widget.shortcutId != null) {
      final pageData = await widget.foundationRepository.fetchPage(
        mushafId: 2,
        pageNumber: page,
      );
      if (mounted && pageData.verses.isNotEmpty) {
        final firstVerse = pageData.verses.first;
        final verseRef = toVerseRef(
          firstVerse.surahId.toString(),
          firstVerse.verseId.toString(),
        );
        await context.read<LocalReadingProvider>().updateShortcutProgress(
          widget.shortcutId!,
          verseRef,
        );
      }
    } else {
      await context.read<MushafReadingProvider>().updateProgress(
        profileId: profile.id,
        pageNumber: page,
      );
    }
    unawaited(_logMushafPageRead(profile.mushafId, page));
    if (!profile.isFreeRead && page == profile.targetPage) {
      _showCompletionOnce();
    }
  }

  Future<void> _logMushafPageRead(int mushafId, int pageNumber) async {
    try {
      final page = await widget.foundationRepository.fetchPage(
        mushafId: mushafId,
        pageNumber: pageNumber,
      );
      if (!mounted || page.verses.isEmpty) return;
      final verse = page.verses.first;
      await context.read<StatsProvider>().logVerseRead(
        verse.surahId,
        verse.verseId,
      );
    } catch (e) {
      debugPrint('Error logging Mushaf page read: $e');
    }
  }

  Future<void> _goToPage(int page) async {
    final profile = _getProfile();
    if (profile == null) return;
    final safePage = _clampInt(page, profile.startPage, profile.targetPage);
    final index = _pageToIndex(profile, safePage);
    _dismissTranslation();
    if (_pageController.hasClients) {
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    } else {
      await _handlePageChanged(profile, safePage);
    }
  }

  void _showCompletionOnce() {
    if (_completionShown || !mounted) return;
    _completionShown = true;
    setState(() {});
  }

  void _dismissTranslation() {
    _translationTimer?.cancel();
    _highlightTimer?.cancel();
    if (_translationText == null && _highlightedVerseKey == null) return;
    setState(() {
      _translationVerseKey = null;
      _translationText = null;
      _highlightedVerseKey = null;
      _translationBookmarked = false;
    });
  }

  Future<void> _playCurrentPage() async {
    final audioProvider = context.read<MushafAudioProvider>();
    if (audioProvider.isPlaying &&
        audioProvider.currentPageNumber == _pageNumber &&
        audioProvider.isContinuous) {
      await audioProvider.togglePlayPause();
      return;
    }

    final displayMushafId = context
        .read<MushafReadingProvider>()
        .displayMushafId;
    _lastAudioPageNumber = _pageNumber;
    try {
      final pageData = await widget.foundationRepository.fetchPage(
        mushafId: displayMushafId,
        pageNumber: _pageNumber,
      );
      if (pageData.verses.isNotEmpty) {
        await audioProvider.playPage(
          mushafId: displayMushafId,
          pageNumber: _pageNumber,
          verses: pageData.verses,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load page audio: $e')),
        );
      }
    }
  }

  void _beginVersePress(
    MushafProfile profile,
    String verseKey,
    int pageNumber,
  ) {
    _highlightTimer?.cancel();
    setState(() => _highlightedVerseKey = verseKey);
  }

  void _toggleVerseHighlight(String verseKey) {
    _highlightTimer?.cancel();
    if (_translationText != null) {
      final profile = _getProfile();
      if (profile != null) {
        unawaited(_showVerseTranslation(profile, verseKey, _pageNumber));
        return;
      }
    }
    setState(() {
      _highlightedVerseKey = _highlightedVerseKey == verseKey ? null : verseKey;
      if (_highlightedVerseKey == null) {
        _translationVerseKey = null;
      }
    });
  }

  Future<void> _showVerseTranslation(
    MushafProfile profile,
    String verseKey,
    int pageNumber,
  ) async {
    final parts = verseKey.split(':');
    if (parts.length != 2) return;
    final verse = widget.quranRepository.getVerse(parts[0], parts[1]);

    final settings = context.read<SettingsProvider>();
    final transManager = context.read<TranslationManagerProvider>();
    String translation = 'Translation not found.';

    if (verse != null) {
      if (settings.primaryTranslationId == 'english') {
        translation = verse.english;
      } else if (settings.primaryTranslationId == 'thai_v2') {
        translation = verse.thaiV2;
      } else if (settings.primaryTranslationId == 'thai_v3') {
        translation = verse.thaiV3;
      } else {
        final idInt = int.tryParse(settings.primaryTranslationId) ?? -1;
        final customTrans = transManager.getVerseTranslation(idInt, verseKey);
        if (customTrans != null) {
          translation = customTrans;
        } else {
          translation = verse.thaiV3; // Fallback
        }
      }
    }
    final isBookmarked = context
        .read<MushafReadingProvider>()
        .isVerseBookmarked(profile.mushafId, pageNumber, verseKey);

    _translationTimer?.cancel();
    setState(() {
      _highlightedVerseKey = verseKey;
      _translationVerseKey = verseKey;
      _translationText = translation;
      _translationBookmarked = isBookmarked;
    });
    _translationTimer = Timer(const Duration(seconds: 9), _dismissTranslation);
  }

  Future<void> _toggleCurrentVerseBookmark(MushafProfile profile) async {
    final verseKey = _translationVerseKey;
    if (verseKey == null) return;
    await _toggleVerseBookmark(profile, verseKey);
  }

  Future<void> _toggleVerseBookmark(
    MushafProfile profile,
    String verseKey,
  ) async {
    await context.read<MushafReadingProvider>().toggleVerseBookmark(
      mushafId: profile.mushafId,
      pageNumber: _pageNumber,
      verseKey: verseKey,
    );
    if (!mounted) return;
    if (_translationVerseKey == verseKey) {
      setState(() {
        _translationBookmarked = context
            .read<MushafReadingProvider>()
            .isVerseBookmarked(profile.mushafId, _pageNumber, verseKey);
      });
    }
  }

  Future<void> _playVerseOnCurrentPage(String verseKey) async {
    final audioProvider = context.read<MushafAudioProvider>();
    final displayMushafId = context
        .read<MushafReadingProvider>()
        .displayMushafId;
    if (audioProvider.isPlaying && audioProvider.currentVerseKey == verseKey) {
      await audioProvider.togglePlayPause();
      return;
    }

    final pageData = await widget.foundationRepository.fetchPage(
      mushafId: displayMushafId,
      pageNumber: _pageNumber,
    );
    await audioProvider.playVerse(
      mushafId: displayMushafId,
      pageNumber: _pageNumber,
      verseKey: verseKey,
      pageVerses: pageData.verses,
    );
  }

  Future<void> _openTadabburModalForVerse(
    String surahId,
    String verseId,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: TadabburPanel(
            surahId: surahId,
            verseId: verseId,
            onClose: () => Navigator.pop(ctx),
          ),
        );
      },
    );
  }

  Future<void> _askToAddNote(String surahId, String verseId) async {
    final addNote = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = context.read<SettingsProvider>().getAppColors();
        return AlertDialog(
          title: Text(
            context.tr('add_note_title'),
            style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w900),
          ),
          content: Text(
            context.tr('favorite_add_note_prompt'),
            style: GoogleFonts.notoSansThai(color: colors.foreground),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                context.tr('later'),
                style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                context.tr('add_note'),
                style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (addNote == true && mounted) {
      await _openTadabburModalForVerse(surahId, verseId);
    }
  }

  Future<void> _toggleCurrentVerseFavorite({bool askForNote = false}) async {
    final verseKey = _translationVerseKey ?? _highlightedVerseKey;
    await _toggleVerseFavorite(verseKey, askForNote: askForNote);
  }

  Future<void> _toggleVerseFavorite(
    String? verseKey, {
    bool askForNote = false,
  }) async {
    final parts = verseKey?.split(':') ?? const <String>[];
    if (parts.length != 2) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.tr('tap_ayah_first'))));
      return;
    }

    final notes = context.read<NotesProvider>();
    final existing = notes.getNoteObjectForVerse(parts[0], parts[1]);
    final hasNoteText = existing?.noteText.trim().isNotEmpty ?? false;
    if (existing == null) {
      await notes.saveNote(surahId: parts[0], verseId: parts[1], noteText: '');
      if (!mounted) return;
      if (askForNote) {
        await _askToAddNote(parts[0], parts[1]);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(context.tr('verse_saved_favorite'))),
          );
      }
      return;
    }

    if (!hasNoteText) {
      await notes.deleteNote(parts[0], parts[1]);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.tr('removed_from_favorites'))),
        );
      return;
    }

    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = context.read<SettingsProvider>().getAppColors();
        return AlertDialog(
          title: Text(
            context.tr('remove_favorite_title'),
            style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w900),
          ),
          content: Text(
            context.tr('remove_favorite_with_note'),
            style: GoogleFonts.notoSansThai(color: colors.foreground),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                context.tr('cancel'),
                style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                context.tr('remove'),
                style: GoogleFonts.notoSansThai(
                  fontWeight: FontWeight.w800,
                  color: Colors.red.shade500,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (remove == true) {
      await notes.deleteNote(parts[0], parts[1]);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.tr('removed_from_favorites'))),
        );
    }
  }

  Future<void> _showReaderSettings(MushafProfile profile) async {
    _dismissTranslation();
    _cancelAutoHideTimer();
    final action = await showModalBottomSheet<_MushafSettingsAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _MushafReaderSettingsSheet(
          displayMushafId: context
              .read<MushafReadingProvider>()
              .displayMushafId,
          currentPage: _pageNumber,
          profileName: profile.name,
          onDisplayMushafChanged: (mushafId) => context
              .read<MushafReadingProvider>()
              .setDisplayMushafId(mushafId),
          onSeeAllProfiles: () {
            Navigator.pop(sheetContext, _MushafSettingsAction.seeAllProfiles);
          },
        );
      },
    );
    if (!mounted) return;
    if (_isMenuVisible) {
      _startAutoHideTimer();
    }
    if (action == _MushafSettingsAction.seeAllProfiles) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _showSurahSelector(
    BuildContext context,
    QuranRepository quranRepository,
  ) async {
    _dismissTranslation();
    _cancelAutoHideTimer();
    final selectedSurah = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final colors = context.read<SettingsProvider>().getAppColors();
        return _SurahSelectorSheet(
          colors: colors,
          quranRepository: quranRepository,
        );
      },
    );
    if (mounted && _isMenuVisible) {
      _startAutoHideTimer();
    }
    if (selectedSurah != null) {
      _jumpToSurah(selectedSurah);
    }
  }

  Future<void> _jumpToSurah(int surahNumber) async {
    final provider = context.read<MushafReadingProvider>();
    final currentProfile = _getProfile();
    if (currentProfile == null) return;

    final startPage = getStartPageForSurah(surahNumber);
    final freeProfile = await provider.openFreeRead(currentProfile.mushafId);

    await provider.updateProgress(
      profileId: freeProfile.id,
      pageNumber: startPage,
    );
    await provider.setActiveProfile(freeProfile.id);

    if (!mounted) return;

    if (widget.profileId != freeProfile.id) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MushafReaderScreen(
            quranRepository: widget.quranRepository,
            foundationRepository: widget.foundationRepository,
            profileId: freeProfile.id,
          ),
        ),
      );
    } else {
      final index = startPage - freeProfile.startPage;
      _pageController.jumpToPage(index);
      setState(() {
        _pageNumber = startPage;
      });
    }
  }

  Future<bool> _handleBack() async {
    if (_translationText != null) {
      _dismissTranslation();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final colors = settings.getAppColors();
    final provider = Provider.of<MushafReadingProvider>(context);
    final profile = _getProfile();
    final audioProvider = context.watch<MushafAudioProvider>();

    if (profile == null) {
      return Scaffold(
        backgroundColor: colors.background,
        body: const Center(child: Text('Mushaf profile not found.')),
      );
    }

    final audioPage = audioProvider.currentPageNumber;
    if (audioPage != null && audioPage != _lastAudioPageNumber) {
      _lastAudioPageNumber = audioPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageNumber != audioPage) {
          _goToPage(audioPage);
        }
      });
    }

    final activeHighlightKey = audioProvider.isPlaying
        ? audioProvider.currentVerseKey
        : _highlightedVerseKey;

    final displayMushafId = provider.displayMushafId;
    final type = mushafTypeById(displayMushafId);
    final pageCount = profile.targetPage - profile.startPage + 1;
    final favoriteVerseKey = _translationVerseKey ?? _highlightedVerseKey;
    final favoriteParts = favoriteVerseKey?.split(':') ?? const <String>[];
    final verseFavorited =
        favoriteParts.length == 2 &&
        context.watch<NotesProvider>().getNoteObjectForVerse(
              favoriteParts[0],
              favoriteParts[1],
            ) !=
            null;

    final topMenuInset = _isMenuVisible ? 56.0 : 36.0;
    final bottomMenuInset = _isMenuVisible ? 64.0 : 8.0;

    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        backgroundColor: _mushafPageColor(context),
        body: Listener(
          onPointerDown: (_) {
            if (_isMenuVisible) {
              _startAutoHideTimer();
            }
          },
          child: Stack(
            children: [
              // 1. Full Screen Reading Area
              Positioned.fill(
                child: SafeArea(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedPadding(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          padding: EdgeInsets.only(
                            top: topMenuInset,
                            bottom: bottomMenuInset,
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              if (_translationText != null) {
                                _dismissTranslation();
                              } else {
                                setState(() {
                                  _isMenuVisible = !_isMenuVisible;
                                  if (_isMenuVisible) {
                                    _startAutoHideTimer();
                                  } else {
                                    _cancelAutoHideTimer();
                                  }
                                });
                              }
                            },
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Directionality(
                                    textDirection: TextDirection.rtl,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onHorizontalDragEnd: (details) {
                                        final velocity =
                                            details.primaryVelocity;
                                        if (velocity != null) {
                                          // Swiped Right (velocity > 0) -> Next Page in RTL
                                          if (velocity > 200) {
                                            if (_pageNumber <
                                                profile.targetPage) {
                                              _goToPage(_pageNumber + 1);
                                              if (_isMenuVisible) {
                                                setState(() {
                                                  _isMenuVisible = false;
                                                });
                                                _cancelAutoHideTimer();
                                              }
                                            }
                                          }
                                          // Swiped Left (velocity < 0) -> Previous Page in RTL
                                          else if (velocity < -200) {
                                            if (_pageNumber >
                                                profile.startPage) {
                                              _goToPage(_pageNumber - 1);
                                              if (_isMenuVisible) {
                                                setState(() {
                                                  _isMenuVisible = false;
                                                });
                                                _cancelAutoHideTimer();
                                              }
                                            }
                                          }
                                        }
                                      },
                                      onVerticalDragEnd: (details) {
                                        final velocity =
                                            details.primaryVelocity;
                                        if (velocity != null &&
                                            velocity.abs() > 100) {
                                          setState(() {
                                            _isMenuVisible = !_isMenuVisible;
                                            if (_isMenuVisible) {
                                              _startAutoHideTimer();
                                            } else {
                                              _cancelAutoHideTimer();
                                            }
                                          });
                                        }
                                      },
                                      child: PageView.builder(
                                        controller: _pageController,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: pageCount,
                                        onPageChanged: (index) =>
                                            _handlePageChanged(
                                              profile,
                                              _indexToPage(profile, index),
                                            ),
                                        itemBuilder: (context, index) {
                                          final page = _indexToPage(
                                            profile,
                                            index,
                                          );
                                          final renderPage = _clampInt(
                                            page,
                                            1,
                                            type.pageCount,
                                          );
                                          if (_isTranslationView) {
                                            return _PageTranslationListView(
                                              pageNumber: renderPage,
                                              mushafId: displayMushafId,
                                              foundationRepository:
                                                  widget.foundationRepository,
                                              quranRepository:
                                                  widget.quranRepository,
                                              settings: settings,
                                              highlightedVerseKey:
                                                  activeHighlightKey,
                                              onVerseTap: _toggleVerseHighlight,
                                              onVerseLongPress: (verseKey) =>
                                                  _showVerseTranslation(
                                                    profile,
                                                    verseKey,
                                                    page,
                                                  ),
                                              onPlayVerse:
                                                  _playVerseOnCurrentPage,
                                              onBookmarkVerse: (verseKey) =>
                                                  _toggleVerseBookmark(
                                                    profile,
                                                    verseKey,
                                                  ),
                                              onFavoriteVerse: (verseKey) =>
                                                  _toggleVerseFavorite(
                                                    verseKey,
                                                    askForNote: true,
                                                  ),
                                            );
                                          }
                                          if (displayMushafId ==
                                              qcfPackageMushafId) {
                                            return _QcfPackagePageView(
                                              colors: colors,
                                              pageNumber: renderPage,
                                              highlightedVerseKey:
                                                  activeHighlightKey,
                                              onVerseLongPressStart:
                                                  (surah, verse) =>
                                                      _beginVersePress(
                                                        profile,
                                                        '$surah:$verse',
                                                        page,
                                                      ),
                                              onVerseLongPress:
                                                  (surah, verse) =>
                                                      _showVerseTranslation(
                                                        profile,
                                                        '$surah:$verse',
                                                        page,
                                                      ),
                                            );
                                          }
                                          return _MushafRemotePageView(
                                            colors: colors,
                                            pageNumber: renderPage,
                                            mushafId: displayMushafId,
                                            repository:
                                                widget.foundationRepository,
                                            highlightedVerseKey:
                                                activeHighlightKey,
                                            highlightedVerseKeys: widget.initialHighlightVerseKeys,
                                            onVerseTap: _toggleVerseHighlight,
                                            onVerseLongPressStart: (verseKey) =>
                                                _beginVersePress(
                                                  profile,
                                                  verseKey,
                                                  page,
                                                ),
                                            onVerseLongPress: (verseKey) =>
                                                _showVerseTranslation(
                                                  profile,
                                                  verseKey,
                                                  page,
                                                ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                if (!profile.isFreeRead &&
                                    _pageNumber == profile.targetPage)
                                  Positioned(
                                    left: 16,
                                    right: 16,
                                    bottom: _translationText != null
                                        ? 178
                                        : (audioProvider.currentVerseKey !=
                                                      null &&
                                                  audioProvider.isContinuous
                                              ? 102
                                              : 12),
                                    child: _CompletionCard(
                                      colors: colors,
                                      profile: profile,
                                    ),
                                  ),
                                if (_translationText != null)
                                  Positioned(
                                    left: 14,
                                    right: 14,
                                    bottom: 12,
                                    child: _TranslationPanel(
                                      colors: colors,
                                      verseKey: _translationVerseKey ?? '',
                                      translation: _translationText!,
                                      bookmarked: _translationBookmarked,
                                      favorited: verseFavorited,
                                      onBookmark: () =>
                                          _toggleCurrentVerseBookmark(profile),
                                      onFavorite: () =>
                                          _toggleCurrentVerseFavorite(
                                            askForNote: true,
                                          ),
                                      onClose: _dismissTranslation,
                                      fontSize: context
                                          .read<SettingsProvider>()
                                          .translationFontSize,
                                      isAudioPlaying:
                                          audioProvider.isPlaying &&
                                          audioProvider.currentVerseKey ==
                                              _translationVerseKey,
                                      isAudioLoading:
                                          audioProvider.isLoading &&
                                          audioProvider.currentVerseKey ==
                                              _translationVerseKey,
                                      onPlay: () async {
                                        if (audioProvider.isPlaying &&
                                            audioProvider.currentVerseKey ==
                                                _translationVerseKey) {
                                          await audioProvider.togglePlayPause();
                                        } else {
                                          final pageData = await widget
                                              .foundationRepository
                                              .fetchPage(
                                                mushafId: displayMushafId,
                                                pageNumber: _pageNumber,
                                              );
                                          await audioProvider.playVerse(
                                            mushafId: displayMushafId,
                                            pageNumber: _pageNumber,
                                            verseKey: _translationVerseKey!,
                                            pageVerses: pageData.verses,
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                if (_translationText == null &&
                                    audioProvider.currentVerseKey != null &&
                                    audioProvider.isContinuous)
                                  Positioned(
                                    left: 14,
                                    right: 14,
                                    bottom: 12,
                                    child: _FloatingAudioControlBar(
                                      colors: colors,
                                      audioProvider: audioProvider,
                                      quranRepository: widget.quranRepository,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (!_isMenuVisible &&
                          _translationText == null &&
                          audioProvider.currentVerseKey == null)
                        Positioned(
                          top: 4,
                          left: 16,
                          right: 16,
                          child: _BookPageIndicator(
                            colors: colors,
                            pageNumber: _pageNumber,
                            quranRepository: widget.quranRepository,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // 2. Animated Top Bar Custom Container
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_isMenuVisible,
                  child: AnimatedSlide(
                    offset: _isMenuVisible ? Offset.zero : const Offset(0, -1),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _mushafPageColor(context),
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: _ReaderTopBar(
                          colors: colors,
                          profile: profile,
                          type: type,
                          pageNumber: _pageNumber,
                          onBack: () => Navigator.of(context).maybePop(),
                          pageBookmarked: provider.isPageBookmarked(
                            displayMushafId,
                            _pageNumber,
                          ),
                          onSettings: () => _showReaderSettings(profile),
                          onBookmarkPage: () => provider.togglePageBookmark(
                            displayMushafId,
                            _pageNumber,
                          ),
                          verseFavorited: verseFavorited,
                          onFavoriteVerse: () => _toggleCurrentVerseFavorite(),
                          quranRepository: widget.quranRepository,
                          canSelectSurah: profile.isFreeRead,
                          onTitleTap: () {
                            if (!profile.isFreeRead) {
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      context.tr('mushaf_goal_surah_locked'),
                                    ),
                                  ),
                                );
                              return;
                            }
                            _showSurahSelector(context, widget.quranRepository);
                          },
                          isAudioPlaying:
                              audioProvider.isPlaying &&
                              audioProvider.currentPageNumber == _pageNumber &&
                              audioProvider.isContinuous,
                          isAudioLoading:
                              audioProvider.isLoading &&
                              audioProvider.currentPageNumber == _pageNumber &&
                              audioProvider.isContinuous,
                          onPlay: _playCurrentPage,
                          showTranslationList: _isTranslationView,
                          onToggleTranslation: () => setState(
                            () => _isTranslationView = !_isTranslationView,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 3. Animated Bottom Bar Custom Container
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_isMenuVisible,
                  child: AnimatedSlide(
                    offset: _isMenuVisible ? Offset.zero : const Offset(0, 1),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _mushafPageColor(context),
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: _ReaderBottomBar(
                          colors: colors,
                          onNext: _pageNumber < profile.targetPage
                              ? () => _goToPage(_pageNumber + 1)
                              : null,
                          onDone: () async {
                            if (widget.shortcutId != null) {
                              final pageData = await widget.foundationRepository
                                  .fetchPage(
                                    mushafId: 2,
                                    pageNumber: _pageNumber,
                                  );
                              if (context.mounted &&
                                  pageData.verses.isNotEmpty) {
                                final firstVerse = pageData.verses.first;
                                final verseRef = toVerseRef(
                                  firstVerse.surahId.toString(),
                                  firstVerse.verseId.toString(),
                                );
                                await context
                                    .read<LocalReadingProvider>()
                                    .updateShortcutProgress(
                                      widget.shortcutId!,
                                      verseRef,
                                    );
                              }
                            } else {
                              await provider.updateProgress(
                                profileId: profile.id,
                                pageNumber: _pageNumber,
                              );
                            }
                            await provider.flushPendingRecentReadingSync();
                            await provider.flushPendingProfileSyncs();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          onPrevious: _pageNumber > profile.startPage
                              ? () => _goToPage(_pageNumber - 1)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int _clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

Color _mushafPageColor(BuildContext context) {
  return Theme.of(context).colorScheme.surface;
}

enum _MushafSettingsAction { seeAllProfiles }

class _MushafReaderSettingsSheet extends StatefulWidget {
  final int displayMushafId;
  final int currentPage;
  final String profileName;
  final ValueChanged<int> onDisplayMushafChanged;
  final VoidCallback onSeeAllProfiles;

  const _MushafReaderSettingsSheet({
    required this.displayMushafId,
    required this.currentPage,
    required this.profileName,
    required this.onDisplayMushafChanged,
    required this.onSeeAllProfiles,
  });

  @override
  State<_MushafReaderSettingsSheet> createState() =>
      _MushafReaderSettingsSheetState();
}

class _MushafReaderSettingsSheetState
    extends State<_MushafReaderSettingsSheet> {
  late int _mushafId;

  @override
  void initState() {
    super.initState();
    _mushafId = widget.displayMushafId;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final colors = settings.getAppColors();
    final type = mushafTypeById(_mushafId);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.tr('mushaf_settings'),
                style: GoogleFonts.notoSansThai(
                  color: colors.textStrong,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Current Profile Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.person_outline, color: colors.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('current_profile'),
                              style: GoogleFonts.notoSansThai(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: widget.onSeeAllProfiles,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 0,
                              ),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              context.tr('see_all'),
                              style: GoogleFonts.notoSansThai(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.profileName,
                        style: GoogleFonts.notoSansThai(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.textStrong,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Dark Mode Toggle Card
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: colors.borderSoft),
            ),
            child: SwitchListTile(
              activeColor: colors.primary,
              secondary: Icon(
                settings.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                color: colors.primary,
              ),
              title: Text(
                context.tr('dark_mode'),
                style: GoogleFonts.notoSansThai(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: colors.textStrong,
                ),
              ),
              subtitle: Text(
                context.tr('optimize_brightness'),
                style: GoogleFonts.notoSansThai(
                  fontSize: 12,
                  color: colors.foreground,
                ),
              ),
              value: settings.isDarkMode,
              onChanged: (val) {
                settings.toggleDarkMode(val);
              },
            ),
          ),
          const SizedBox(height: 16),

          // Display Mushaf Selection Label
          Text(
            context.tr('mushaf_font_layout'),
            style: GoogleFonts.notoSansThai(
              color: colors.textStrong,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),

          // Modern Styled Dropdown Container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: colors.borderSoft),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _mushafId,
                dropdownColor: colors.surface,
                icon: Icon(Icons.keyboard_arrow_down, color: colors.foreground),
                isExpanded: true,
                items: visibleMushafTypes
                    .map(
                      (type) => DropdownMenuItem(
                        value: type.id,
                        child: Text(
                          type.name,
                          style: GoogleFonts.notoSansThai(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textStrong,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null || value == _mushafId) return;
                  setState(() => _mushafId = value);
                  widget.onDisplayMushafChanged(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'current_view',
              args: {
                'name': type.name,
                'page': '${widget.currentPage.clamp(1, type.pageCount)}',
              },
            ),
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansThai(
              color: colors.foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String getSurahNameForPage(int pageNumber, QuranRepository quranRepository) {
  int surahId = 1;
  for (int i = 1; i <= 114; i++) {
    if (getStartPageForSurah(i) <= pageNumber) {
      surahId = i;
    } else {
      break;
    }
  }
  return quranRepository.getSurahName(surahId.toString());
}

class _ReaderTopBar extends StatelessWidget {
  final AppThemeColors colors;
  final MushafProfile profile;
  final MushafType type;
  final int pageNumber;
  final VoidCallback onBack;
  final bool pageBookmarked;
  final VoidCallback onSettings;
  final VoidCallback onBookmarkPage;
  final bool verseFavorited;
  final VoidCallback onFavoriteVerse;
  final QuranRepository quranRepository;
  final bool canSelectSurah;
  final VoidCallback onTitleTap;
  final bool isAudioPlaying;
  final bool isAudioLoading;
  final VoidCallback onPlay;
  final bool showTranslationList;
  final VoidCallback onToggleTranslation;

  const _ReaderTopBar({
    required this.colors,
    required this.profile,
    required this.type,
    required this.pageNumber,
    required this.onBack,
    required this.pageBookmarked,
    required this.onSettings,
    required this.onBookmarkPage,
    required this.verseFavorited,
    required this.onFavoriteVerse,
    required this.quranRepository,
    required this.canSelectSurah,
    required this.onTitleTap,
    required this.isAudioPlaying,
    required this.isAudioLoading,
    required this.onPlay,
    required this.showTranslationList,
    required this.onToggleTranslation,
  });

  @override
  Widget build(BuildContext context) {
    final surahName = getSurahNameForPage(pageNumber, quranRepository);
    final juz = getOfflineJuzForPage(pageNumber);
    final hizb = getOfflineHizbForPage(pageNumber);
    final hizbLabel = context.read<SettingsProvider>().languageCode == 'th'
        ? 'ฮิซบ์'
        : 'Hizb';

    return AppBar(
      primary: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      leadingWidth: 48,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: colors.textStrong),
        onPressed: onBack,
      ),
      title: InkWell(
        onTap: onTitleTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    surahName,
                    style: GoogleFonts.notoSansThai(
                      color: colors.textStrong,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (canSelectSurah)
                    Icon(
                      Icons.arrow_drop_down,
                      color: colors.primary,
                      size: 18,
                    ),
                ],
              ),
              Text(
                '${context.tr('page')} $pageNumber • ${context.tr('juz')} $juz • $hizbLabel $hizb',
                style: GoogleFonts.notoSansThai(
                  color: colors.foreground.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: pageBookmarked ? 'Remove page bookmark' : 'Bookmark page',
          onPressed: onBookmarkPage,
          icon: Icon(
            pageBookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            color: pageBookmarked ? colors.primary : colors.foreground,
            size: 24,
          ),
        ),
        IconButton(
          tooltip: isAudioPlaying ? 'Pause recitation' : 'Play recitation',
          onPressed: onPlay,
          icon: isAudioLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                )
              : Icon(
                  isAudioPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: colors.primary,
                ),
        ),
        IconButton(
          tooltip: 'Toggle Translation',
          icon: Icon(
            showTranslationList
                ? Icons.menu_book_rounded
                : Icons.view_list_rounded,
            color: showTranslationList ? colors.primary : colors.foreground,
          ),
          onPressed: onToggleTranslation,
        ),
        IconButton(
          tooltip: context.tr('mushaf_settings'),
          icon: Icon(Icons.settings_rounded, color: colors.primary),
          onPressed: onSettings,
        ),
      ],
    );
  }
}

class _BookPageIndicator extends StatelessWidget {
  final AppThemeColors colors;
  final int pageNumber;
  final QuranRepository quranRepository;

  const _BookPageIndicator({
    required this.colors,
    required this.pageNumber,
    required this.quranRepository,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surahName = getSurahNameForPage(pageNumber, quranRepository);
    return SizedBox(
      height: 28,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              surahName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansThai(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${context.tr('page')} $pageNumber',
              style: GoogleFonts.notoSansThai(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  final AppThemeColors colors;
  final VoidCallback? onNext;
  final VoidCallback onDone;
  final VoidCallback? onPrevious;

  const _ReaderBottomBar({
    required this.colors,
    required this.onNext,
    required this.onDone,
    required this.onPrevious,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SizedBox(
        height: 44,
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            Expanded(
              flex: 2,
              child: _SmallReaderButton(
                icon: Icons.keyboard_arrow_left_rounded,
                label: context.tr('next_ayah'),
                onPressed: onNext,
                backgroundColor: colorScheme.surfaceContainerLow,
                foregroundColor: colorScheme.primary,
                disabledBackgroundColor: colorScheme.surfaceContainerLow
                    .withValues(alpha: 0.5),
                disabledForegroundColor: colorScheme.onSurface.withValues(
                  alpha: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: _SmallReaderButton(
                icon: Icons.check_rounded,
                label: context.tr('save_progress'),
                onPressed: onDone,
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _SmallReaderButton(
                icon: Icons.keyboard_arrow_right_rounded,
                label: context.tr('previous_ayah'),
                onPressed: onPrevious,
                iconOnRight: true,
                backgroundColor: colorScheme.surfaceContainerLow,
                foregroundColor: colorScheme.primary,
                disabledBackgroundColor: colorScheme.surfaceContainerLow
                    .withValues(alpha: 0.5),
                disabledForegroundColor: colorScheme.onSurface.withValues(
                  alpha: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallReaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool iconOnRight;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? disabledBackgroundColor;
  final Color? disabledForegroundColor;

  const _SmallReaderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconOnRight = false,
    required this.backgroundColor,
    required this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final labelWidget = Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: GoogleFonts.notoSansThai(
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final iconWidget = Icon(icon, size: 16);
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        disabledBackgroundColor: disabledBackgroundColor,
        disabledForegroundColor: disabledForegroundColor,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!iconOnRight) ...[iconWidget, const SizedBox(width: 4)],
          labelWidget,
          if (iconOnRight) ...[const SizedBox(width: 4), iconWidget],
        ],
      ),
    );
  }
}

class _QcfPackagePageView extends StatelessWidget {
  final AppThemeColors colors;
  final int pageNumber;
  final String? highlightedVerseKey;
  final void Function(int surahNumber, int verseNumber) onVerseLongPressStart;
  final void Function(int surahNumber, int verseNumber) onVerseLongPress;

  const _QcfPackagePageView({
    required this.colors,
    required this.pageNumber,
    required this.highlightedVerseKey,
    required this.onVerseLongPressStart,
    required this.onVerseLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = 8.0;
        final topPadding = 28.0;
        final bottomPadding = 44.0;

        final paddedWidth = (constraints.maxWidth - (horizontalPadding * 2))
            .clamp(100.0, double.infinity);
        final paddedHeight =
            (constraints.maxHeight - (topPadding + bottomPadding)).clamp(
              100.0,
              double.infinity,
            );

        final qcfFontSize = (paddedWidth / 20.2).clamp(16.0, 21.0);
        return ColoredBox(
          color: _mushafPageColor(context),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              topPadding,
              horizontalPadding,
              bottomPadding,
            ),
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(size: Size(paddedWidth, paddedHeight)),
              child: QcfPage(
                pageNumber: pageNumber,
                fontSize: qcfFontSize,
                sp: 0.93,
                h: 0.94,
                theme: QcfThemeData(
                  pageBackgroundColor: _mushafPageColor(context),
                  verseTextColor: textColor,
                  verseNumberColor: colors.primary,
                  basmalaColor: textColor,
                  headerTextColor: textColor,
                  headerBackgroundColor: Colors.transparent,
                  customHeaderBuilder: (surahNumber) => QcfSurahHeader(
                    surahNumber: surahNumber,
                    colors: colors,
                    showBismillahText: false,
                  ),
                ),
                verseBackgroundColor: (surah, verse) {
                  return highlightedVerseKey == '$surah:$verse'
                      ? colors.primaryLight.withValues(alpha: 0.75)
                      : null;
                },
                onLongPressDown:
                    (surah, verse, LongPressStartDetails details) =>
                        onVerseLongPressStart(surah, verse),
                onLongPress: onVerseLongPress,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MushafRemotePageView extends StatefulWidget {
  final AppThemeColors colors;
  final int pageNumber;
  final int mushafId;
  final QuranFoundationRepository repository;
  final String? highlightedVerseKey;
  final Set<String>? highlightedVerseKeys;
  final ValueChanged<String> onVerseTap;
  final ValueChanged<String> onVerseLongPressStart;
  final ValueChanged<String> onVerseLongPress;

  const _MushafRemotePageView({
    required this.colors,
    required this.pageNumber,
    required this.mushafId,
    required this.repository,
    required this.highlightedVerseKey,
    this.highlightedVerseKeys,
    required this.onVerseTap,
    required this.onVerseLongPressStart,
    required this.onVerseLongPress,
  });

  @override
  State<_MushafRemotePageView> createState() => _MushafRemotePageViewState();
}

class _MushafRemotePageViewState extends State<_MushafRemotePageView> {
  late Future<MushafPage> _future;

  @override
  void initState() {
    super.initState();
    _initFuture();
  }

  @override
  void didUpdateWidget(_MushafRemotePageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mushafId != widget.mushafId ||
        oldWidget.pageNumber != widget.pageNumber) {
      _initFuture();
    }
  }

  void _initFuture() {
    _future = widget.repository.fetchPage(
      mushafId: widget.mushafId,
      pageNumber: widget.pageNumber,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MushafPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(color: widget.colors.primary),
          );
        }
        if (snapshot.hasError) {
          return _MushafError(
            colors: widget.colors,
            message: snapshot.error.toString(),
            onRetry: () {},
          );
        }
        final page = snapshot.data;
        if (page == null || page.lines.isEmpty) {
          return _MushafError(
            colors: widget.colors,
            message: 'No words found for this Mushaf page.',
            onRetry: () {},
          );
        }
        return MushafPageView(
          colors: widget.colors,
          page: page,
          fontFamily: widget.repository.getFontFamily(
            widget.mushafId,
            widget.pageNumber,
          ),
          mushafId: widget.mushafId,
          highlightedVerseKey: widget.highlightedVerseKey,
          highlightedVerseKeys: widget.highlightedVerseKeys,
          onVerseTap: widget.onVerseTap,
          onVerseLongPressStart: widget.onVerseLongPressStart,
          onVerseLongPress: widget.onVerseLongPress,
        );
      },
    );
  }
}

class MushafPageView extends StatelessWidget {
  final AppThemeColors colors;
  final MushafPage page;
  final String fontFamily;
  final int mushafId;
  final String? highlightedVerseKey;
  final Set<String>? highlightedVerseKeys;
  final ValueChanged<String> onVerseTap;
  final ValueChanged<String> onVerseLongPressStart;
  final ValueChanged<String> onVerseLongPress;

  const MushafPageView({
    required this.colors,
    required this.page,
    required this.fontFamily,
    required this.mushafId,
    required this.highlightedVerseKey,
    this.highlightedVerseKeys,
    required this.onVerseTap,
    required this.onVerseLongPressStart,
    required this.onVerseLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final surahStartsByLine = _surahStartsByLine(page);
    final layout = MushafLayoutProfile.forMushaf(mushafId);
    final verseEndWords = _verseEndWords(page);
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = SizedBox(
          width: layout.pageWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final line in page.lines) ...[
                for (final surahId
                    in surahStartsByLine[line.first.lineNumber] ??
                        const <String>[])
                  QcfSurahHeader(
                    surahNumber: int.tryParse(surahId) ?? 0,
                    colors: colors,
                  ),
                Builder(
                  builder: (context) {
                    return MushafLine(
                      line: line,
                      fontFamily: fontFamily,
                      mushafId: mushafId,
                      pageNumber: page.pageNumber,
                      lineWidth: layout.lineWidth,
                      lineHeight: layout.lineHeight,
                      lineVerticalPadding: layout.lineVerticalPadding,
                      wordPadding: layout.wordPadding,
                      verseEndWords: verseEndWords,
                      surahStartsByLine: surahStartsByLine,
                      highlightedVerseKey: highlightedVerseKey,
                      highlightedVerseKeys: highlightedVerseKeys,
                      onVerseTap: onVerseTap,
                      onVerseLongPressStart: onVerseLongPressStart,
                      onVerseLongPress: onVerseLongPress,
                    );
                  },
                ),
              ],
            ],
          ),
        );
        final topPadding = MediaQuery.paddingOf(context).top;
        final availableWidth =
            (constraints.maxWidth - (layout.horizontalPadding * 2)).clamp(
              1.0,
              double.infinity,
            );
        final availableHeight = (constraints.maxHeight - 8 - topPadding).clamp(
          1.0,
          double.infinity,
        );

        return Padding(
          padding: EdgeInsets.only(
            left: layout.horizontalPadding,
            right: layout.horizontalPadding,
            top: 4 + topPadding,
            bottom: 4,
          ),
          child: SizedBox(
            width: availableWidth,
            height: availableHeight,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.center,
              child: content,
            ),
          ),
        );
      },
    );
  }

  Map<int, List<String>> _surahStartsByLine(MushafPage page) {
    final starts = <int, List<String>>{};
    for (final verse in page.verses) {
      if (verse.verseId != '1' || verse.words.isEmpty) continue;
      final lineNumber = verse.words.first.lineNumber;
      starts.putIfAbsent(lineNumber, () => []).add(verse.surahId);
    }
    return starts;
  }

  Set<MushafWord> _verseEndWords(MushafPage page) {
    final ends = <MushafWord>{};
    for (final verse in page.verses) {
      if (verse.words.isNotEmpty) {
        ends.add(verse.words.last);
      }
    }
    return ends;
  }
}

class MushafLayoutProfile {
  final double pageWidth;
  final double lineWidth;
  final double lineHeight;
  final double lineVerticalPadding;
  final double horizontalPadding;
  final double wordPadding;

  const MushafLayoutProfile({
    required this.pageWidth,
    required this.lineWidth,
    required this.lineHeight,
    required this.lineVerticalPadding,
    required this.horizontalPadding,
    required this.wordPadding,
  });

  factory MushafLayoutProfile.forMushaf(int mushafId) {
    return switch (mushafId) {
      // QCF page fonts already carry their own spacing; keep padding at zero
      // and the canonical canvas tight so phone/tablet screens do not feel tiny.
      1 => const MushafLayoutProfile(
        pageWidth: 410,
        lineWidth: 410,
        lineHeight: 1.90,
        lineVerticalPadding: 3.0,
        horizontalPadding: 16,
        wordPadding: 0,
      ),
      2 => const MushafLayoutProfile(
        pageWidth: 412,
        lineWidth: 412,
        lineHeight: 1.35, // Reduced to shrink the highlight box vertical size
        lineVerticalPadding: 7.5, // Increased to compensate for line spacing
        horizontalPadding: 14,
        wordPadding: 0,
      ),
      11 => const MushafLayoutProfile(
        pageWidth: 412, 
        lineWidth: 412,
        lineHeight: 1.25, // Significantly reduced to shrink highlight box
        lineVerticalPadding: 11.0, // Increased to maintain the line gap
        horizontalPadding: 14, // Good side margins
        wordPadding: 0,
      ),
      19 => const MushafLayoutProfile(
        pageWidth: 410,
        lineWidth: 410,
        lineHeight: 1.7,
        lineVerticalPadding: 1.5,
        horizontalPadding: 16,
        wordPadding: 0,
      ),
      4 => const MushafLayoutProfile(
        pageWidth: 390,
        lineWidth: 358,
        lineHeight: 1.8,
        lineVerticalPadding: 3,
        horizontalPadding: 16,
        wordPadding: 0.0,
      ),
      6 => const MushafLayoutProfile(
        pageWidth: 390,
        lineWidth: 358,
        lineHeight: 1.7,
        lineVerticalPadding: 2,
        horizontalPadding: 16,
        wordPadding: 0.0,
      ),
      _ => const MushafLayoutProfile(
        pageWidth: 390,
        lineWidth: 358,
        lineHeight: 1.7,
        lineVerticalPadding: 2,
        horizontalPadding: 16,
        wordPadding: 0.0,
      ),
    };
  }
}

class QcfSurahHeader extends StatelessWidget {
  final int surahNumber;
  final AppThemeColors colors;
  final bool showBismillahText;

  const QcfSurahHeader({
    required this.surahNumber,
    required this.colors,
    this.showBismillahText = true,
  });

  @override
  Widget build(BuildContext context) {
    if (surahNumber <= 0 || surahNumber > 114) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerTextColor = const Color(0xFF111827);
    final bismillahColor = isDark
        ? const Color(0xFFE5E7EB)
        : const Color(0xFF111827);
    final showBismillah =
        showBismillahText && surahNumber != 1 && surahNumber != 9;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          ColorFiltered(
            colorFilter: isDark
                ? const ColorFilter.matrix([
                    -0.2126,
                    -0.7152,
                    -0.0722,
                    0,
                    255,
                    -0.2126,
                    -0.7152,
                    -0.0722,
                    0,
                    255,
                    -0.2126,
                    -0.7152,
                    -0.0722,
                    0,
                    255,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ])
                : const ColorFilter.matrix([
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ]),
            child: Opacity(
              opacity: isDark ? 0.82 : 1,
              child: HeaderWidget(
                suraNumber: surahNumber,
                theme: QcfThemeData(
                  headerTextColor: headerTextColor,
                  headerBackgroundColor: Colors.transparent,
                  headerWidthSmall: 455,
                  headerWidthLarge: 400,
                  headerFontSizeSmall: 34,
                  headerFontSizeLarge: 22,
                ),
              ),
            ),
          ),
          if (showBismillah)
            Padding(
              padding: const EdgeInsets.only(top: 7, bottom: 2),
              child: Text(
                '\ufc41  \ufc42\ufc43\ufc44',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: 'QCF_P001',
                  package: 'qcf_quran',
                  fontSize: 23,
                  height: 1.05,
                  color: bismillahColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MushafLine extends StatelessWidget {
  final List<MushafWord> line;
  final String fontFamily;
  final int mushafId;
  final int pageNumber;
  final double lineWidth;
  final double lineHeight;
  final double lineVerticalPadding;
  final double wordPadding;
  final Set<MushafWord> verseEndWords;
  final Map<int, List<String>> surahStartsByLine;
  final String? highlightedVerseKey;
  final Set<String>? highlightedVerseKeys;
  final ValueChanged<String> onVerseTap;
  final ValueChanged<String> onVerseLongPressStart;
  final ValueChanged<String> onVerseLongPress;
  final bool Function(String)? isVerseHidden;
  final bool isPeekActive;

  const MushafLine({
    required this.line,
    required this.fontFamily,
    required this.mushafId,
    required this.pageNumber,
    required this.lineWidth,
    required this.lineHeight,
    required this.lineVerticalPadding,
    required this.wordPadding,
    required this.verseEndWords,
    required this.surahStartsByLine,
    required this.highlightedVerseKey,
    this.highlightedVerseKeys,
    required this.onVerseTap,
    required this.onVerseLongPressStart,
    required this.onVerseLongPress,
    this.isVerseHidden,
    this.isPeekActive = false,
  });

  @override
  Widget build(BuildContext context) {
    bool isShortLine = false;

    if (line.isNotEmpty) {
      final isLastLineOfSurahOnPage = surahStartsByLine.containsKey(
        line.first.lineNumber + 1,
      );

      if (pageNumber == 1 || pageNumber == 2) {
        isShortLine = true;
      } else if (pageNumber >= 582) {
        // Juz 30
        isShortLine = true;
      } else if (isLastLineOfSurahOnPage) {
        isShortLine = true;
      } else if (line.length < 4) {
        isShortLine = true;
      }
    }

    final fontSize = switch (mushafId) {
      1 => pageNumber <= 2 ? 34.0 : 25.2,
      2 => pageNumber <= 2 ? 38.0 : 30.5,
      4 => 23.5,
      6 => 25.0,
      11 => pageNumber <= 2 ? 34.0 : 29.5,
      19 => 25.2,
      _ => 22.5,
    };
    final bool isQcf = mushafId == 1 || mushafId == 2 || mushafId == 19 || mushafId == 11;
    final isUthmaniTajweed = mushafId == 11;
    final baseStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: isQcf ? lineHeight : null,
      color: Theme.of(context).textTheme.bodyMedium?.color,
      fontWeight: isUthmaniTajweed ? FontWeight.w500 : FontWeight.w400,
    );
    final strutStyle = isQcf
        ? StrutStyle.fromTextStyle(baseStyle, forceStrutHeight: true)
        : null;
    final textHeightBehavior = isQcf
        ? const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          )
        : null;

    final textSpans = <InlineSpan>[];
    for (int i = 0; i < line.length; i++) {
      final word = line[i];
      final isEndWord = verseEndWords.contains(word);
      final isWordHidden = (isVerseHidden?.call(word.verseKey) ?? false) && !isPeekActive && !isEndWord;
      final isHighlighted = (highlightedVerseKeys?.contains(word.verseKey) ?? false) || highlightedVerseKey == word.verseKey;
      final isDarkMode = Theme.of(context).brightness == Brightness.dark;
      final highlightColor = isHighlighted
          ? Theme.of(context).colorScheme.primary.withValues(alpha: isDarkMode ? 0.20 : 0.10)
          : null;

      final wordColor = isWordHidden
          ? Colors.transparent
          : null;

      final recognizer = TapGestureRecognizer()
        ..onTap = () => onVerseTap(word.verseKey);

      if ((mushafId == 11) && word.tajweedParts.isNotEmpty) {
        for (final part in word.tajweedParts) {
          textSpans.add(
            TextSpan(
              text: part.text,
              style: baseStyle.copyWith(
                color: wordColor ?? _getTajweedColor(part.className, context),
                backgroundColor: highlightColor,
              ),
              recognizer: recognizer,
            ),
          );
        }
        textSpans.add(
          TextSpan(
            text: ' ',
            style: baseStyle.copyWith(backgroundColor: highlightColor),
            recognizer: recognizer,
          ),
        );
      } else {
        final overrideFont = (mushafId == 11 && isEndWord) ? 'qcf_v1_p$pageNumber' : null;
        final overrideFontSize = (mushafId == 11 && isEndWord) ? (pageNumber <= 2 ? 38.0 : 30.5) : baseStyle.fontSize;
        textSpans.add(
          TextSpan(
            text: '${word.text} ',
            style: baseStyle.copyWith(
              color: wordColor,
              backgroundColor: highlightColor,
              fontFamily: overrideFont,
              fontSize: overrideFontSize,
            ),
            recognizer: recognizer,
          ),
        );
      }

      if (_shouldShowIndopakVerseMarker(word)) {
        final verseNumber = int.tryParse(word.verseKey.split(':').last) ?? 0;
        final marker =
            '${String.fromCharCode(0x06dd)}${_arabicIndicDigits(verseNumber)}';
        textSpans.add(
          TextSpan(
            text: marker,
            style: TextStyle(
              fontFamily: 'UthmanicHafs',
              fontSize: 13,
              height: 1,
              color: isWordHidden
                  ? Colors.transparent
                  : Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withValues(alpha: 0.78),
              backgroundColor: highlightColor,
            ),
            recognizer: recognizer,
          ),
        );
      }
    }

    final richText = RichText(
      textAlign: isShortLine ? TextAlign.center : TextAlign.justify,
      textDirection: TextDirection.rtl,
      strutStyle: strutStyle,
      textHeightBehavior: textHeightBehavior,
      softWrap:
          false, // ensures it calculates width identically to Row without wrapping
      text: TextSpan(children: textSpans),
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: lineVerticalPadding),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) {
          if (highlightedVerseKey != null) {
            onVerseLongPressStart(highlightedVerseKey!);
          }
        },
        onLongPress: () {
          if (highlightedVerseKey != null) {
            onVerseLongPress(highlightedVerseKey!);
          }
        },
        child: SizedBox(
          width: lineWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: lineWidth),
              child: richText,
            ),
          ),
        ),
      ),
    );
  }

  bool _shouldShowIndopakVerseMarker(MushafWord word) {
    if (mushafId != 3 && mushafId != 6 && mushafId != 7) return false;
    if (!verseEndWords.contains(word)) return false;
    return !RegExp(
      '[\u06dd\u06de\u0660-\u0669\u06f0-\u06f9\uf500-\uf8ff]',
    ).hasMatch(word.text);
  }

  Color? _getTajweedColor(String className, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (className.toLowerCase()) {
      case 'ghunnah':
      case 'ikhfa':
      case 'ikhafa': // From api.quran.com
      case 'ikhfa_shafawi':
      case 'ikhafa_shafawi': // From api.quran.com
      case 'idgham_ghunnah':
      case 'idgham_wo_ghunnah': // From api.quran.com
      case 'idgham_shafawi': // From api.quran.com
      case 'idgham_muthamaasilayn':
      case 'iqlab':
        return isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
      case 'qalqalah':
      case 'qalaqah': // From api.quran.com
        return isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);
      case 'madda_normal':
      case 'madda_permissible':
      case 'madda_necessary':
      case 'madda_obligatory':
      case 'madda_obligatory_monfasel': // From api.quran.com
      case 'madda_obligatory_mottasel': // From api.quran.com
        return isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
      case 'ham_wasl':
      case 'laam_shamsiyah':
      case 'silent':
      case 'slnt': // From api.quran.com
        return const Color(0xFF94A3B8);
      default:
        return null;
    }
  }

  String _arabicIndicDigits(int value) {
    const digits = [
      0x0660,
      0x0661,
      0x0662,
      0x0663,
      0x0664,
      0x0665,
      0x0666,
      0x0667,
      0x0668,
      0x0669,
    ];
    return value
        .toString()
        .split('')
        .map((digit) => String.fromCharCode(digits[int.parse(digit)]))
        .join();
  }
}

class _TranslationPanel extends StatelessWidget {
  final AppThemeColors colors;
  final String verseKey;
  final String translation;
  final bool bookmarked;
  final bool favorited;
  final VoidCallback onBookmark;
  final VoidCallback onFavorite;
  final VoidCallback onClose;
  final double fontSize;
  final bool isAudioPlaying;
  final bool isAudioLoading;
  final VoidCallback onPlay;

  const _TranslationPanel({
    required this.colors,
    required this.verseKey,
    required this.translation,
    required this.bookmarked,
    required this.favorited,
    required this.onBookmark,
    required this.onFavorite,
    required this.onClose,
    required this.fontSize,
    required this.isAudioPlaying,
    required this.isAudioLoading,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      elevation: 16,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 210),
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 14),
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderSoft),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    verseKey,
                    style: GoogleFonts.notoSansThai(
                      color: colors.textStrong,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isAudioPlaying ? 'Pause verse' : 'Play verse',
                  onPressed: onPlay,
                  icon: isAudioLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary,
                          ),
                        )
                      : Icon(
                          isAudioPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                          color: colors.primary,
                        ),
                ),
                IconButton(
                  tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark verse',
                  onPressed: onBookmark,
                  icon: Icon(
                    bookmarked ? Icons.bookmark : Icons.bookmark_border,
                    color: colors.primary,
                  ),
                ),
                IconButton(
                  tooltip: favorited ? 'Remove favorite' : 'Favorite verse',
                  onPressed: onFavorite,
                  icon: Icon(
                    favorited
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: favorited ? Colors.redAccent : colors.primary,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: RichText(
                  locale: const Locale('th', 'TH'),
                  softWrap: true,
                  text: TextSpan(
                    children: HtmlParser.parseTranslationText(
                      context,
                      translation,
                      GoogleFonts.notoSansThai(
                        color: colors.foreground,
                        fontSize: fontSize,
                        height: 1.55,
                      ),
                      colors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  final AppThemeColors colors;
  final MushafProfile profile;

  const _CompletionCard({required this.colors, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryLight,
        border: Border.all(color: colors.primaryLightBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.celebration_outlined, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${profile.name} complete',
              style: GoogleFonts.notoSansThai(
                color: colors.textStrong,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MushafError extends StatelessWidget {
  final AppThemeColors colors;
  final String message;
  final VoidCallback onRetry;

  const _MushafError({
    required this.colors,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: colors.primary, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansThai(
                color: colors.foreground,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int getStartPageForSurah(int surahNumber) {
  const List<int> surahStartPages = [
    1,
    2,
    50,
    77,
    106,
    128,
    151,
    177,
    187,
    208,
    221,
    235,
    249,
    255,
    262,
    267,
    282,
    293,
    305,
    312,
    322,
    332,
    342,
    350,
    359,
    367,
    377,
    385,
    396,
    404,
    411,
    415,
    418,
    428,
    434,
    440,
    446,
    453,
    458,
    467,
    477,
    483,
    489,
    496,
    499,
    502,
    507,
    511,
    515,
    518,
    520,
    523,
    526,
    528,
    531,
    534,
    537,
    542,
    545,
    549,
    551,
    553,
    554,
    556,
    558,
    560,
    562,
    564,
    566,
    568,
    570,
    572,
    574,
    575,
    577,
    578,
    580,
    582,
    583,
    585,
    586,
    587,
    587,
    589,
    590,
    591,
    591,
    592,
    593,
    594,
    595,
    595,
    596,
    596,
    597,
    597,
    598,
    598,
    599,
    599,
    600,
    600,
    601,
    601,
    601,
    602,
    602,
    602,
    603,
    603,
    603,
    604,
    604,
    604,
  ];
  if (surahNumber < 1 || surahNumber > 114) return 1;
  return surahStartPages[surahNumber - 1];
}

class _SurahSelectorSheet extends StatefulWidget {
  final AppThemeColors colors;
  final QuranRepository quranRepository;

  const _SurahSelectorSheet({
    required this.colors,
    required this.quranRepository,
  });

  @override
  State<_SurahSelectorSheet> createState() => _SurahSelectorSheetState();
}

class _SurahSelectorSheetState extends State<_SurahSelectorSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surahs = List.generate(114, (index) => index + 1).where((
      surahNumber,
    ) {
      final name = widget.quranRepository
          .getSurahName(surahNumber.toString())
          .toLowerCase();
      return name.contains(_query.toLowerCase()) ||
          surahNumber.toString().contains(_query);
    }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(
            'Select Surah',
            style: GoogleFonts.notoSansThai(
              color: widget.colors.textStrong,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _query = val),
            decoration: InputDecoration(
              hintText: 'Search Surah...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: widget.colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                borderSide: BorderSide(color: widget.colors.borderSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                borderSide: BorderSide(color: widget.colors.borderSoft),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: surahs.length,
              itemBuilder: (context, index) {
                final surahNumber = surahs[index];
                final name = widget.quranRepository.getSurahName(
                  surahNumber.toString(),
                );
                return ListTile(
                  title: Text(
                    name,
                    style: GoogleFonts.notoSansThai(
                      color: widget.colors.textStrong,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: widget.colors.foreground,
                  ),
                  onTap: () => Navigator.pop(context, surahNumber),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

int getOfflineJuzForPage(int pageNumber) {
  const starts = [
    1,
    22,
    42,
    62,
    82,
    102,
    122,
    142,
    162,
    182,
    202,
    222,
    242,
    262,
    282,
    302,
    322,
    342,
    362,
    382,
    402,
    422,
    442,
    462,
    482,
    502,
    522,
    542,
    562,
    582,
  ];
  for (int i = starts.length - 1; i >= 0; i--) {
    if (pageNumber >= starts[i]) return i + 1;
  }
  return 1;
}

int getOfflineHizbForPage(int pageNumber) {
  final juz = getOfflineJuzForPage(pageNumber);
  const starts = [
    1,
    22,
    42,
    62,
    82,
    102,
    122,
    142,
    162,
    182,
    202,
    222,
    242,
    262,
    282,
    302,
    322,
    342,
    362,
    382,
    402,
    422,
    442,
    462,
    482,
    502,
    522,
    542,
    562,
    582,
  ];
  final juzIndex = juz - 1;
  final startPage = starts[juzIndex];
  final endPage = juzIndex < 29 ? starts[juzIndex + 1] - 1 : 604;
  final midPage = startPage + (endPage - startPage) ~/ 2;

  if (pageNumber > midPage) {
    return juz * 2;
  } else {
    return juz * 2 - 1;
  }
}

class _FloatingAudioControlBar extends StatelessWidget {
  final AppThemeColors colors;
  final MushafAudioProvider audioProvider;
  final QuranRepository quranRepository;

  const _FloatingAudioControlBar({
    required this.colors,
    required this.audioProvider,
    required this.quranRepository,
  });

  @override
  Widget build(BuildContext context) {
    final currentKey = audioProvider.currentVerseKey ?? '';
    final parts = currentKey.split(':');
    final surahName = parts.isNotEmpty
        ? quranRepository.getSurahName(parts[0])
        : '';
    final verseText = parts.length > 1 ? 'อายะฮ์ ${parts[1]}' : '';

    return Material(
      color: Colors.transparent,
      elevation: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.borderSoft, width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        surahName,
                        style: GoogleFonts.notoSansThai(
                          color: colors.textStrong,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        verseText,
                        style: GoogleFonts.notoSansThai(
                          color: colors.foreground.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded),
                  color: colors.primary,
                  onPressed: audioProvider.previousVerse,
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: audioProvider.isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary,
                          ),
                        )
                      : Icon(
                          audioProvider.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                  color: colors.primary,
                  iconSize: 32,
                  onPressed: audioProvider.togglePlayPause,
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded),
                  color: colors.primary,
                  onPressed: audioProvider.nextVerse,
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.stop_rounded),
                  color: Colors.redAccent,
                  onPressed: audioProvider.stop,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageTranslationListView extends StatefulWidget {
  final int pageNumber;
  final int mushafId;
  final QuranFoundationRepository foundationRepository;
  final QuranRepository quranRepository;
  final SettingsProvider settings;
  final String? highlightedVerseKey;
  final ValueChanged<String> onVerseTap;
  final ValueChanged<String> onVerseLongPress;
  final ValueChanged<String> onPlayVerse;
  final ValueChanged<String> onBookmarkVerse;
  final ValueChanged<String> onFavoriteVerse;

  const _PageTranslationListView({
    required this.pageNumber,
    required this.mushafId,
    required this.foundationRepository,
    required this.quranRepository,
    required this.settings,
    required this.highlightedVerseKey,
    required this.onVerseTap,
    required this.onVerseLongPress,
    required this.onPlayVerse,
    required this.onBookmarkVerse,
    required this.onFavoriteVerse,
  });

  @override
  State<_PageTranslationListView> createState() =>
      _PageTranslationListViewState();
}

class _PageTranslationListViewState extends State<_PageTranslationListView> {
  late Future<MushafPage> _pageFuture;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _verseKeys = {};
  String? _lastScrolledVerseKey;

  @override
  void initState() {
    super.initState();
    _pageFuture = _fetchPage();
  }

  @override
  void didUpdateWidget(_PageTranslationListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageNumber != widget.pageNumber ||
        oldWidget.mushafId != widget.mushafId) {
      _pageFuture = _fetchPage();
      _verseKeys.clear();
      _lastScrolledVerseKey = null;
    }
    if (oldWidget.highlightedVerseKey != widget.highlightedVerseKey) {
      _scheduleScrollToHighlighted();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<MushafPage> _fetchPage() {
    return widget.foundationRepository.fetchPage(
      mushafId: widget.mushafId,
      pageNumber: widget.pageNumber,
    );
  }

  GlobalKey _keyForVerse(String verseKey) {
    return _verseKeys.putIfAbsent(verseKey, GlobalKey.new);
  }

  void _scheduleScrollToHighlighted() {
    final verseKey = widget.highlightedVerseKey;
    if (verseKey == null || verseKey == _lastScrolledVerseKey) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _verseKeys[verseKey]?.currentContext;
      if (context == null) return;
      _lastScrolledVerseKey = verseKey;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.26,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.settings.getAppColors();
    final audioProvider = context.watch<MushafAudioProvider>();
    final readingProvider = context.watch<MushafReadingProvider>();
    final notesProvider = context.watch<NotesProvider>();
    return FutureBuilder<MushafPage>(
      future: _pageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError ||
            snapshot.data == null ||
            snapshot.data!.verses.isEmpty) {
          return const Center(child: Text('Failed to load page translations.'));
        }
        final verses = snapshot.data!.verses;
        _scheduleScrollToHighlighted();
        return Directionality(
          textDirection: TextDirection.ltr,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth < 430
                  ? 32.0
                  : 48.0;
              return ListView.separated(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  24,
                  horizontalPadding,
                  120,
                ),
                itemCount: verses.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final mv = verses[index];
                  final surahId = mv.surahId;
                  final verseId = mv.verseId;
                  final verseKey = '$surahId:$verseId';
                  final surahVerses = widget.quranRepository.getSurahVerses(
                    surahId,
                  );
                  final verse = surahVerses.firstWhere(
                    (v) => v.id == verseId,
                    orElse: () => Verse(
                      id: verseId,
                      surahId: surahId,
                      arabic: '',
                      thaiV3: '',
                      thaiV2: '',
                      english: '',
                    ),
                  );
                  final isHighlighted =
                      widget.highlightedVerseKey == verseKey ||
                      audioProvider.currentVerseKey == verseKey;
                  final isAudioActive =
                      audioProvider.currentVerseKey == verseKey;
                  final bookmarked = readingProvider.isVerseBookmarked(
                    widget.mushafId,
                    widget.pageNumber,
                    verseKey,
                  );
                  final favorited =
                      notesProvider.getNoteObjectForVerse(surahId, verseId) !=
                      null;

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: _TranslationVerseRow(
                        key: _keyForVerse(verseKey),
                        verse: verse,
                        verseKey: verseKey,
                        quranRepository: widget.quranRepository,
                        settings: widget.settings,
                        colors: colors,
                        isHighlighted: isHighlighted,
                        isAudioPlaying:
                            audioProvider.isPlaying && isAudioActive,
                        isAudioLoading:
                            audioProvider.isLoading && isAudioActive,
                        bookmarked: bookmarked,
                        favorited: favorited,
                        onTap: () => widget.onVerseTap(verseKey),
                        onLongPress: () => widget.onVerseLongPress(verseKey),
                        onPlay: () => widget.onPlayVerse(verseKey),
                        onBookmark: () => widget.onBookmarkVerse(verseKey),
                        onFavorite: () => widget.onFavoriteVerse(verseKey),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _TranslationVerseRow extends StatefulWidget {
  final Verse verse;
  final String verseKey;
  final QuranRepository quranRepository;
  final SettingsProvider settings;
  final AppThemeColors colors;
  final bool isHighlighted;
  final bool isAudioPlaying;
  final bool isAudioLoading;
  final bool bookmarked;
  final bool favorited;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onPlay;
  final VoidCallback onBookmark;
  final VoidCallback onFavorite;

  const _TranslationVerseRow({
    super.key,
    required this.verse,
    required this.verseKey,
    required this.quranRepository,
    required this.settings,
    required this.colors,
    required this.isHighlighted,
    required this.isAudioPlaying,
    required this.isAudioLoading,
    required this.bookmarked,
    required this.favorited,
    required this.onTap,
    required this.onLongPress,
    required this.onPlay,
    required this.onBookmark,
    required this.onFavorite,
  });

  @override
  State<_TranslationVerseRow> createState() => _TranslationVerseRowState();
}

class _TranslationVerseRowState extends State<_TranslationVerseRow> {
  late Future<String> _arabicTextFuture;

  @override
  void initState() {
    super.initState();
    _arabicTextFuture = widget.verse.arabic.isNotEmpty
        ? Future.value(widget.verse.arabic)
        : widget.quranRepository.fetchArabicVerse(
            widget.verse.surahId,
            widget.verse.id,
          );
  }

  @override
  void didUpdateWidget(_TranslationVerseRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verse.id != widget.verse.id ||
        oldWidget.verse.surahId != widget.verse.surahId) {
      _arabicTextFuture = widget.verse.arabic.isNotEmpty
          ? Future.value(widget.verse.arabic)
          : widget.quranRepository.fetchArabicVerse(
              widget.verse.surahId,
              widget.verse.id,
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    final arabicStyle = TextStyle(
      fontFamily: 'UthmanicHafs',
      fontSize: widget.settings.arabicFontSize,
      height: 2.0,
      color: widget.colors.textStrong,
    );

    final primaryId = widget.settings.primaryTranslationId;
    String rawTranslation = '';
    if (primaryId == 'thai_v3') {
      rawTranslation = widget.verse.thaiV3;
    } else if (primaryId == 'thai_v2') {
      rawTranslation = widget.verse.thaiV2;
    } else if (primaryId == 'english' || primaryId == 'en_sahih') {
      rawTranslation = widget.verse.english;
    } else {
      rawTranslation = widget.verse.thaiV3.isNotEmpty
          ? widget.verse.thaiV3
          : widget.verse.thaiV2;
    }

    final thaiTextProtection = Provider.of<ThaiTextProtectionProvider>(context);
    final translation = thaiTextProtection.protect(rawTranslation);

    return Material(
      color: widget.isHighlighted
          ? widget.colors.primaryLight.withValues(alpha: 0.64)
          : widget.colors.surface.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isHighlighted
                  ? widget.colors.primary.withValues(alpha: 0.32)
                  : widget.colors.borderSoft.withValues(alpha: 0.68),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.verseKey,
                      textAlign: TextAlign.left,
                      style: GoogleFonts.notoSansThai(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: widget.colors.primary.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                  _VerseActionMenu(
                    colors: widget.colors,
                    isAudioPlaying: widget.isAudioPlaying,
                    isAudioLoading: widget.isAudioLoading,
                    bookmarked: widget.bookmarked,
                    favorited: widget.favorited,
                    onPlay: widget.onPlay,
                    onBookmark: widget.onBookmark,
                    onFavorite: widget.onFavorite,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FutureBuilder<String>(
                future: _arabicTextFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.colors.primary,
                        ),
                      ),
                    );
                  }
                  final text = snapshot.data ?? '';
                  final cleanArabicText = text.split(' | ').join(' ');
                  return Directionality(
                    textDirection: TextDirection.rtl,
                    child: RichText(
                      textAlign: TextAlign.right,
                      text: TextSpan(
                        style: arabicStyle,
                        children: [TextSpan(text: cleanArabicText)],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  translation,
                  textAlign: TextAlign.left,
                  style: GoogleFonts.notoSansThai(
                    fontSize: widget.settings.translationFontSize,
                    height: 1.5,
                    color: widget.colors.foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerseActionMenu extends StatelessWidget {
  final AppThemeColors colors;
  final bool isAudioPlaying;
  final bool isAudioLoading;
  final bool bookmarked;
  final bool favorited;
  final VoidCallback onPlay;
  final VoidCallback onBookmark;
  final VoidCallback onFavorite;

  const _VerseActionMenu({
    required this.colors,
    required this.isAudioPlaying,
    required this.isAudioLoading,
    required this.bookmarked,
    required this.favorited,
    required this.onPlay,
    required this.onBookmark,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Verse actions',
      icon: isAudioLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            )
          : Icon(
              Icons.more_horiz_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      onSelected: (value) {
        if (value == 'play') {
          onPlay();
        } else if (value == 'bookmark') {
          onBookmark();
        } else if (value == 'favorite') {
          onFavorite();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'play',
          child: _VerseActionMenuItem(
            icon: isAudioPlaying
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_fill_rounded,
            label: isAudioPlaying ? 'Pause verse' : 'Play verse',
            colors: colors,
          ),
        ),
        PopupMenuItem(
          value: 'bookmark',
          child: _VerseActionMenuItem(
            icon: bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border,
            label: bookmarked ? 'Remove bookmark' : 'Bookmark',
            colors: colors,
          ),
        ),
        PopupMenuItem(
          value: 'favorite',
          child: _VerseActionMenuItem(
            icon: favorited
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: favorited ? 'Remove favorite' : 'Favorite',
            colors: colors,
          ),
        ),
      ],
    );
  }
}

class _VerseActionMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppThemeColors colors;

  const _VerseActionMenuItem({
    required this.icon,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: colors.primary),
        const SizedBox(width: 12),
        Text(
          label,
          style: GoogleFonts.notoSansThai(
            color: colors.textStrong,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
