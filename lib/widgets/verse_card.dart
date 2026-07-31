// lib/widgets/verse_card.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/verse.dart';
import '../models/tadabbur_note.dart';
import '../data/quran_repository.dart';
import '../data/tadabbur_repository.dart';
import '../providers/settings_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/stats_provider.dart';
import '../providers/translation_manager_provider.dart';
import '../providers/local_reading_provider.dart';
import '../providers/thai_text_protection_provider.dart';
import '../providers/mushaf_audio_provider.dart';
import '../shared/shared.dart';
import '../utils/html_parser.dart';
import 'tadabbur_panel.dart';

class VerseCardController extends ChangeNotifier {
  VoidCallback? toggleTafsir;
  VoidCallback? toggleAudit;
  VoidCallback? playAudio;
  VoidCallback? stopAudio;
  VoidCallback? copyText;
  VoidCallback? shareImage;
  VoidCallback? showCommunityNotes;

  bool isAudioPlaying = false;
  bool isAudioLoading = false;
  bool showTafsirBox = false;
  bool showAuditBox = false;
  bool hasTafsir = false;
  bool hasCommunityNotes = false;
  Future<List<TadabburNote>>? communityNotesFuture;

  void updateState({
    bool? isAudioPlaying,
    bool? isAudioLoading,
    bool? showTafsirBox,
    bool? showAuditBox,
    bool? hasTafsir,
    bool? hasCommunityNotes,
    Future<List<TadabburNote>>? communityNotesFuture,
  }) {
    bool changed = false;
    if (isAudioPlaying != null && this.isAudioPlaying != isAudioPlaying) {
      this.isAudioPlaying = isAudioPlaying;
      changed = true;
    }
    if (isAudioLoading != null && this.isAudioLoading != isAudioLoading) {
      this.isAudioLoading = isAudioLoading;
      changed = true;
    }
    if (showTafsirBox != null && this.showTafsirBox != showTafsirBox) {
      this.showTafsirBox = showTafsirBox;
      changed = true;
    }
    if (showAuditBox != null && this.showAuditBox != showAuditBox) {
      this.showAuditBox = showAuditBox;
      changed = true;
    }
    if (hasTafsir != null && this.hasTafsir != hasTafsir) {
      this.hasTafsir = hasTafsir;
      changed = true;
    }
    if (hasCommunityNotes != null &&
        this.hasCommunityNotes != hasCommunityNotes) {
      this.hasCommunityNotes = hasCommunityNotes;
      changed = true;
    }
    if (communityNotesFuture != null) {
      this.communityNotesFuture = communityNotesFuture;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }
}

class VerseCard extends StatefulWidget {
  final Verse verse;
  final QuranRepository repository;
  final int index;
  final String? progressProfileId;
  final bool useExplicitProgressProfile;
  final VerseCardController? controller;

  const VerseCard({
    super.key,
    required this.verse,
    required this.repository,
    required this.index,
    this.progressProfileId,
    this.useExplicitProgressProfile = false,
    this.controller,
  });

  @override
  State<VerseCard> createState() => _VerseCardState();
}

class _VerseCardState extends State<VerseCard> {
  // Audit and personal notes states
  bool _showAuditBox = false;
  bool _showTafsirBox = false;
  bool _isPreparingShare = false;
  bool _isAudioLoading = false;
  bool _isAudioPlaying = false;

  final GlobalKey _shareBoundaryKey = GlobalKey();
  final GlobalKey _tafsirKey = GlobalKey();
  final GlobalKey _auditKey = GlobalKey();
  final TadabburRepository _tadabburRepository = TadabburRepository();
  final TextEditingController _auditController = TextEditingController();
  late Future<List<TadabburNote>> _communityNotesFuture;

  bool _isSavingAudit = false;
  bool _auditSaved = false;
  final String _shareStatus = '';
  String? _lastTrackedVerseKey;

  bool _isNonThaiPrimary() {
    if (!mounted) return false;
    final settings = Provider.of<SettingsProvider>(context, listen: true);
    final primaryId = settings.primaryTranslationId;
    if (primaryId == 'thai_v3' || primaryId == 'thai_v2') return false;
    
    final transManager = Provider.of<TranslationManagerProvider>(context, listen: false);
    final customId = int.tryParse(primaryId);
    if (customId != null) {
      final translation = transManager.downloadedTranslations.firstWhere(
        (t) => t['id'] == customId,
        orElse: () => <String, dynamic>{},
      );
      final lang = translation['language']?.toString().toLowerCase();
      if (lang == 'th' || lang == 'thai') {
        return false;
      }
    }
    return true;
  }

  String? _getTafsir() {
    return _isNonThaiPrimary() ? widget.verse.shortTafsirEn : widget.verse.shortTafsir;
  }

  String? _getTafsirSource() {
    return _isNonThaiPrimary() ? widget.verse.shortTafsirSourceEn : widget.verse.shortTafsirSource;
  }

  @override
  void initState() {
    super.initState();
    _communityNotesFuture = _tadabburRepository.fetchCommunityNotes(
      widget.verse.surahId,
      widget.verse.id,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      if (settings.showArabicText) {
        _loadArabic();
      }
      _bindController();
    });
  }

  @override
  void didUpdateWidget(VerseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verse != widget.verse ||
        oldWidget.controller != widget.controller) {
      _communityNotesFuture = _tadabburRepository.fetchCommunityNotes(
        widget.verse.surahId,
        widget.verse.id,
      );
      _bindController();
    }
  }

  void _bindController() {
    if (widget.controller != null) {
      widget.controller!.toggleTafsir = () {
        if (_getTafsir() != null) {
          setState(() {
            _showTafsirBox = !_showTafsirBox;
            _showAuditBox = false;
            _updateControllerState();
          });
          if (_showTafsirBox) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_tafsirKey.currentContext != null) {
                Scrollable.ensureVisible(
                  _tafsirKey.currentContext!,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                );
              }
            });
          }
        }
      };
      widget.controller!.toggleAudit = () {
        setState(() {
          _showAuditBox = !_showAuditBox;
          _showTafsirBox = false;
          _updateControllerState();
        });
        if (_showAuditBox) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_auditKey.currentContext != null) {
              Scrollable.ensureVisible(
                _auditKey.currentContext!,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
              );
            }
          });
        }
      };
      widget.controller!.playAudio = _toggleAyahAudio;
      widget.controller!.stopAudio = () async {
        final mushafAudio = Provider.of<MushafAudioProvider>(context, listen: false);
        await mushafAudio.stop();
      };
      widget.controller!.copyText = _copyVerseText;
      widget.controller!.shareImage = _shareVerseImage;
      widget.controller!.showCommunityNotes = () {
        _communityNotesFuture.then((notes) {
          if (mounted && notes.isNotEmpty) {
            _showCommunityNotesModal(notes);
          }
        });
      };

      _updateControllerState();
    }
  }

  void _updateControllerState() {
    if (widget.controller != null) {
      widget.controller!.updateState(
        isAudioPlaying: _isAudioPlaying,
        isAudioLoading: _isAudioLoading,
        showTafsirBox: _showTafsirBox,
        showAuditBox: _showAuditBox,
        hasTafsir: _getTafsir() != null,
        hasCommunityNotes: true,
        communityNotesFuture: _communityNotesFuture,
      );
    }
  }

  @override
  void dispose() {
    _auditController.dispose();
    super.dispose();
  }

  void _openTadabburModal() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: TadabburPanel(
            surahId: widget.verse.surahId,
            verseId: widget.verse.id,
            onClose: () => Navigator.pop(ctx),
          ),
        );
      },
    );
  }

  Future<void> _handleFavoriteTap(
    NotesProvider notesProv,
    TadabburNote? noteObj,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasNoteText = noteObj?.noteText.trim().isNotEmpty ?? false;

    if (noteObj == null) {
      await notesProv.saveNote(
        surahId: widget.verse.surahId,
        verseId: widget.verse.id,
        noteText: '',
      );
      if (!mounted) return;

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            backgroundColor: isDark
                ? const Color(0xFF1E293B)
                : const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFF1E293B),
                width: 1,
              ),
            ),
            content: Text(
              'Verse saved as favorite',
              style: GoogleFonts.notoSansThai(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            action: SnackBarAction(
              label: 'Add note',
              textColor: const Color(0xFFFBBF24),
              onPressed: _openTadabburModal,
            ),
          ),
        );
      return;
    }

    if (!hasNoteText) {
      await notesProv.deleteNote(widget.verse.surahId, widget.verse.id);
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Removed from favorites')));
      return;
    }

    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final settings = Provider.of<SettingsProvider>(ctx, listen: false);
        final colors = settings.getAppColors();
        return AlertDialog(
          title: Text(
            'Remove favorite?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900),
          ),
          content: Text(
            'This verse has a note. Removing it will delete the saved note too.',
            style: GoogleFonts.inter(color: colors.foreground),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Remove',
                style: GoogleFonts.inter(
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
      await notesProv.deleteNote(widget.verse.surahId, widget.verse.id);
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Removed from favorites')));
    }
  }

  Future<void> _loadArabic() async {
    if (widget.verse.arabic.isNotEmpty) {
      return;
    }

    setState(() {
      widget.verse.isArabicLoading = true;
    });

    final fetched = await widget.repository.fetchArabicVerse(
      widget.verse.surahId,
      widget.verse.id,
    );

    if (mounted) {
      setState(() {
        widget.verse.arabic = fetched;
        widget.verse.isArabicLoading = false;
      });
    }
  }

  Future<void> _submitAuditComment() async {
    final comment = _auditController.text.trim();
    if (comment.isEmpty) return;

    setState(() {
      _isSavingAudit = true;
    });

    final surahNum = int.tryParse(widget.verse.surahId) ?? 0;
    final verseNum = int.tryParse(widget.verse.id) ?? 0;

    bool success = false;
    Object? saveError;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw StateError('Please log in to submit an error report.');
      }

      final reportedVerseText = widget.verse.thaiV3.isNotEmpty
          ? widget.verse.thaiV3
          : widget.verse.thaiV2;

      await Supabase.instance.client.from('error_reports').insert({
        'user_id': user.id,
        'surah_id': surahNum,
        'ayah_number': verseNum,
        'reported_verse_text': reportedVerseText,
        'user_comment': comment,
      });
      success = true;
      debugPrint('Audit saved to Supabase error_reports');
    } catch (supabaseError) {
      saveError = supabaseError;
      debugPrint('Supabase error report save failed: $supabaseError');
    }

    if (mounted) {
      setState(() {
        _isSavingAudit = false;
        _auditSaved = success;
        if (success) _auditController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Report submitted successfully!'
                : saveError is StateError
                ? 'Please log in to report an error.'
                : 'Could not submit the report. Please try again.',
          ),
          backgroundColor: success ? Colors.teal : Colors.redAccent,
        ),
      );

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _auditSaved = false;
          });
        }
      });
    }
  }

  void _copyVerseText() {
    final text = StringBuffer();
    if (widget.verse.arabic.trim().isNotEmpty) {
      text.writeln(widget.verse.arabic.split(' | ').join(' '));
      text.writeln();
    }
    if (widget.verse.thaiV3.trim().isNotEmpty) {
      text.writeln(widget.verse.thaiV3.trim());
    } else if (widget.verse.thaiV2.trim().isNotEmpty) {
      text.writeln(widget.verse.thaiV2.trim());
    } else if (widget.verse.english.trim().isNotEmpty) {
      text.writeln(widget.verse.english.trim());
    }
    final currentTafsir = _getTafsir();
    if (_showTafsirBox && currentTafsir?.trim().isNotEmpty == true) {
      text
        ..writeln()
        ..writeln('Short tafsir')
        ..writeln(currentTafsir!.trim());
    }
    text
      ..writeln()
      ..write('${widget.verse.surahId}:${widget.verse.id}');

    Clipboard.setData(ClipboardData(text: text.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied verse text'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _shareVerseImage() async {
    setState(() => _isPreparingShare = true);
    await WidgetsBinding.instance.endOfFrame;

    try {
      final boundary =
          _shareBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) return;

      if (kIsWeb) {
        final xFile = XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: 'ayah_${widget.verse.surahId}_${widget.verse.id}.png',
        );
        await SharePlus.instance.share(
          ShareParams(
            files: [xFile],
            text: '${widget.verse.surahId}:${widget.verse.id}',
          ),
        );
        return;
      }

      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/ayah_${widget.verse.surahId}_${widget.verse.id}.png',
      );
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '${widget.verse.surahId}:${widget.verse.id}',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not prepare share image: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPreparingShare = false);
      }
    }
  }

  Future<void> _toggleAyahAudio() async {
    if (_isAudioLoading) return;

    final mushafAudio = Provider.of<MushafAudioProvider>(context, listen: false);
    final verseKey = '${widget.verse.surahId}:${widget.verse.id}';

    if (_isAudioPlaying) {
      await mushafAudio.stop();
      return;
    }

    try {
      await mushafAudio.playSingleIndependentVerse(verseKey);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play ayah audio: $e')),
      );
    }
  }

  void _showCommunityNotesModal(List<TadabburNote> notes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.58,
          minChildSize: 0.35,
          maxChildSize: 0.88,
          builder: (context, controller) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Community notes - ${widget.verse.surahId}:${widget.verse.id}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      controller: controller,
                      itemCount: notes.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                note.noteText,
                                locale: const Locale('th', 'TH'),
                                style: GoogleFonts.notoSansThai(
                                  fontSize: 14,
                                  height: 1.6,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.favorite_rounded,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${note.likesCount}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<MushafAudioProvider>(context);
    final verseKey = '${widget.verse.surahId}:${widget.verse.id}';
    final isCurrentVerse = audioProvider.currentVerseKey == verseKey;
    final isPlaying = isCurrentVerse && audioProvider.isPlaying;
    final isLoading = isCurrentVerse && audioProvider.isLoading;

    if (isPlaying != _isAudioPlaying || isLoading != _isAudioLoading) {
      _isAudioPlaying = isPlaying;
      _isAudioLoading = isLoading;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateControllerState();
        }
      });
    }

    final settings = Provider.of<SettingsProvider>(context);
    final notesProv = Provider.of<NotesProvider>(context, listen: false);
    final localReading = Provider.of<LocalReadingProvider>(
      context,
      listen: false,
    );
    final thaiTextProtection = Provider.of<ThaiTextProtectionProvider>(
      context,
      listen: false,
    );
    final statsProv = Provider.of<StatsProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isHighlighted = context.select<ProgressProvider, bool>(
      (progress) => widget.index == progress.lastVerseIndex,
    );

    // Bind controller if this card is currently highlighted/active
    if (isHighlighted && widget.controller != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _bindController();
        }
      });
    }

    final colors = settings.getAppColors();
    final themeColor = settings.getPrimaryColor();
    final bodyTextColor = colors.textStrong;
    final arabicTextColor = isDark
        ? const Color(0xFFD7E0EA)
        : const Color(0xFF334155);
    final colorScheme = Theme.of(context).colorScheme;

    final showArabicText = true;

    final verseRef = toVerseRef(widget.verse.surahId, widget.verse.id);

    // Select only this specific verse's bookmark status
    final isBookmarked = context.select<LocalReadingProvider, bool>(
      (lr) => lr.isBookmarked(verseRef.surahId, verseRef.verseId),
    );

    if (isHighlighted && _lastTrackedVerseKey != verseRef.verseKey) {
      _lastTrackedVerseKey = verseRef.verseKey;
      // Log reading stat
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        statsProv.logVerseRead(widget.verse.surahId, widget.verse.id);
        final localReading = Provider.of<LocalReadingProvider>(
          context,
          listen: false,
        );
        final progressProfile = widget.useExplicitProgressProfile
            ? (widget.progressProfileId == null
                  ? null
                  : localReading.profileById(widget.progressProfileId!))
            : localReading.activeProfile;
        if (progressProfile != null) {
          localReading.updateProfileProgress(
            progressProfile.id,
            verseRef,
            context: context,
          );
          localReading.addRecentReading(
            verse: verseRef,
            profileId: progressProfile.id,
          );
        }
      });
    }

    final arabicStyle = TextStyle(
      fontFamily: 'UthmanicHafs',
      fontSize: settings.arabicFontSize,
      height: 2.0,
      color: arabicTextColor,
    );

    // Force load if Arabic should be visible (globally or locally) and is not loaded yet
    if (showArabicText &&
        widget.verse.arabic.isEmpty &&
        !widget.verse.isArabicLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadArabic();
        }
      });
    }

    // Select only this specific verse's favorite note status
    final isFavorited = context.select<NotesProvider, bool>(
      (notes) =>
          notes.getNoteObjectForVerse(widget.verse.surahId, widget.verse.id) !=
          null,
    );

    return RepaintBoundary(
      key: _shareBoundaryKey,
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: _isPreparingShare ? 24 : 0,
          vertical: 16,
        ),
        decoration: _isPreparingShare
            ? BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(
                      alpha: isDark ? 0.12 : 0.04,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              )
            : null,
        child: Padding(
          padding: _isPreparingShare
              ? const EdgeInsets.all(24)
              : EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        colors.primary.withValues(alpha: isDark ? 0.12 : 0.06),
                        colors.background,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderSoft, width: 1),
                    ),
                    child: Text(
                      context.tr(
                        'ayah_number',
                        args: {'number': widget.verse.id},
                      ),
                      style: GoogleFonts.notoSansThai(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_shareStatus.isNotEmpty)
                        Text(
                          _shareStatus,
                          style: GoogleFonts.notoSansThai(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      _buildActionIcon(
                        tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark',
                        icon: isBookmarked
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        active: isBookmarked,
                        color: colorScheme.tertiary,
                        onPressed: () async {
                          await localReading.toggleBookmark(
                            verseRef.surahId,
                            verseRef.verseId,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),

              // Arabic Text Area
              if (showArabicText) ...[
                const SizedBox(height: 16),
                if (widget.verse.isArabicLoading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                else
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: RichText(
                      text: TextSpan(
                        style: arabicStyle,
                        children: [
                          TextSpan(
                            text: widget.verse.arabic.split(' | ').join(' '),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Divider(color: colorScheme.outlineVariant),
              ],

              const SizedBox(height: 14),

              // Translations Container
              if (true) ...[
                if (settings.primaryTranslationId.isNotEmpty)
                  _buildDynamicTranslation(
                    context,
                    settings.primaryTranslationId,
                    settings,
                    isDark,
                    bodyTextColor,
                    thaiTextProtection,
                    isPrimary: true,
                  ),
                if (settings.secondaryTranslationId != null)
                  _buildDynamicTranslation(
                    context,
                    settings.secondaryTranslationId!,
                    settings,
                    isDark,
                    bodyTextColor,
                    thaiTextProtection,
                    isPrimary: false,
                  ),
              ],

              const SizedBox(height: 12),

              // Heart (favorite) button row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildActionIcon(
                    tooltip: isFavorited
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                    icon: isFavorited
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    active: isFavorited,
                    color: colorScheme.error,
                    onPressed: () {
                      final currentNoteObj = notesProv.getNoteObjectForVerse(
                        widget.verse.surahId,
                        widget.verse.id,
                      );
                      _handleFavoriteTap(notesProv, currentNoteObj);
                    },
                  ),
                ],
              ),

              // Collapsible Short Tafsir
              if (_showTafsirBox && _getTafsir() != null) ...[
                const SizedBox(height: 8),
                Container(
                  key: _tafsirKey,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? Colors.blueGrey.shade800
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Short tafsir',
                            style: GoogleFonts.notoSansThai(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: themeColor,
                            ),
                          ),
                          Text(
                            _getTafsirSource() ??
                                'QuranEnc Thai Mokhtasar',
                            style: GoogleFonts.notoSansThai(
                              fontSize: 10,
                              color: isDark
                                  ? Colors.blueGrey.shade300
                                  : Colors.blueGrey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isNonThaiPrimary() 
                            ? _getTafsir()!
                            : thaiTextProtection.protect(_getTafsir()!),
                        locale: _isNonThaiPrimary() ? null : const Locale('th', 'TH'),
                        style: _isNonThaiPrimary()
                          ? GoogleFonts.inter(
                              fontSize: 15,
                              height: 1.5,
                              color: isDark
                                  ? const Color(0xFFE2E8F0)
                                  : const Color(0xFF334155),
                              fontWeight: FontWeight.w400,
                            )
                          : GoogleFonts.notoSansThai(
                              fontSize: 17,
                              height: 1.7,
                              color: isDark
                                  ? const Color(0xFFE2E8F0)
                                  : const Color(0xFF334155),
                              fontWeight: FontWeight.w400,
                            ),
                      ),
                    ],
                  ),
                ),
              ],

              // Collapsible Audit Input
              if (_showAuditBox) ...[
                const SizedBox(height: 8),
                Container(
                  key: _auditKey,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TextField(
                        controller: _auditController,
                        minLines: 3,
                        maxLines: 6,
                        style: GoogleFonts.notoSansThai(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Enter audit error report/fix details...',
                          hintStyle: GoogleFonts.notoSansThai(fontSize: 14),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.all(10),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              _showAuditBox = false;
                              _updateControllerState();
                            }),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.notoSansThai(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _isSavingAudit
                                ? null
                                : _submitAuditComment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                            ),
                            child: _isSavingAudit
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _auditSaved ? 'Saved ✓' : 'Submit Audit',
                                    style: GoogleFonts.notoSansThai(
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicTranslation(
    BuildContext context,
    String translationId,
    SettingsProvider settings,
    bool isDark,
    Color bodyTextColor,
    ThaiTextProtectionProvider thaiTextProtection, {
    required bool isPrimary,
  }) {
    String label = '';
    String text = '';
    Locale? locale;

    if (translationId == 'thai_v3') {
      label = context.tr('thai_v3');
      text = thaiTextProtection.protect(widget.verse.thaiV3);
      locale = const Locale('th', 'TH');
    } else if (translationId == 'thai_v2') {
      label = context.tr('thai_v2');
      text = thaiTextProtection.protect(widget.verse.thaiV2);
      locale = const Locale('th', 'TH');
    } else if (translationId == 'english') {
      label = context.tr('english');
      text = widget.verse.english;
    } else {
      final transManager = Provider.of<TranslationManagerProvider>(context);
      final idInt = int.tryParse(translationId) ?? -1;
      final tInfo = transManager.downloadedTranslations.firstWhere(
        (t) => t['id'] == idInt,
        orElse: () => <String, dynamic>{},
      );

      final customText = transManager.getVerseTranslation(
        idInt,
        widget.verse.verseKey,
      );
      text = customText ?? 'Loading translation...';

      final language = (tInfo['language_name'] ?? tInfo['language'])?.toString().toLowerCase() ?? '';
      final author = (tInfo['author_name'] ?? tInfo['author'] ?? tInfo['name'])?.toString() ?? '';

      if (language == 'thai' || language == 'th') {
        locale = const Locale('th', 'TH');
        text = thaiTextProtection.protect(text);

        if (translationId == '51') {
          label = 'ภาษาไทย (ศูนย์กษัตริย์ฟาฮัด)';
        } else if (translationId == '230') {
          label = 'ภาษาไทย (สมาคมศิษย์เก่าอาหรับ)';
        } else {
          label = 'ภาษาไทย ($author)';
        }
      } else {
        final capitalizedLanguage = language.isNotEmpty
            ? language[0].toUpperCase() + language.substring(1).toLowerCase()
            : 'Translation';
        label = '$capitalizedLanguage\n$author';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: _buildTranslationBlock(
        label: label,
        text: text,
        locale: locale,
        labelFg: isDark ? Colors.blueGrey.shade500 : Colors.blueGrey.shade400,
        textStyle: GoogleFonts.notoSansThai(
          fontSize: settings.translationFontSize + (isPrimary ? 1.0 : -1.0),
          height: 1.65,
          color: bodyTextColor,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildTranslationBlock({
    required String label,
    required String text,
    required Color labelFg,
    required TextStyle textStyle,
    Locale? locale,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          locale: locale,
          softWrap: true,
          overflow: TextOverflow.visible,
          text: TextSpan(
            children: HtmlParser.parseTranslationText(
              context,
              text,
              textStyle,
              Theme.of(context).primaryColor,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: GoogleFonts.notoSansThai(
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: labelFg,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionIcon({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool active = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = onPressed == null;
    return IconButton(
      tooltip: tooltip,
      iconSize: 20,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: active && !disabled
            ? color.withValues(alpha: 0.12)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: active && !disabled
                ? color.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1,
          ),
        ),
      ),
      icon: Icon(
        icon,
        color: disabled
            ? Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
            : active
            ? color
            : (isDark ? Colors.blueGrey.shade300 : Colors.blueGrey.shade600),
      ),
      onPressed: onPressed,
    );
  }
}
