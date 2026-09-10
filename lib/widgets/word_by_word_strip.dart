import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import '../services/offline_quran_database_service.dart';
import '../screens/root_verses_screen.dart';
import '../providers/settings_provider.dart';
import '../providers/translation_manager_provider.dart';

/// Helper function to resolve the word-by-word language automatically
/// based on the currently selected translation in the app.
String resolveEffectiveWbwLanguage(BuildContext context) {
  try {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final primaryId = settings.primaryTranslationId.toLowerCase().trim();

    if (primaryId == 'english' || primaryId == 'en_usmani' || primaryId.startsWith('en')) {
      return 'en';
    }
    if (primaryId == 'ms_basmeih' || primaryId == 'malay' || primaryId.startsWith('ms')) {
      return 'ms';
    }
    if (primaryId == 'thai_v3' || primaryId == 'thai_v2' || primaryId.startsWith('th')) {
      if (settings.languageCode == 'en') return 'en';
      if (settings.languageCode == 'ms') return 'ms';
      return 'th';
    }

    final transManager = Provider.of<TranslationManagerProvider>(context, listen: false);
    final customId = int.tryParse(primaryId);
    if (customId != null) {
      final t = transManager.downloadedTranslations.firstWhere(
        (item) => item['id'] == customId,
        orElse: () => <String, dynamic>{},
      );
      final lang = (t['language_name'] ?? t['language'] ?? '').toString().toLowerCase();
      if (lang.contains('en') || lang.contains('eng')) return 'en';
      if (lang.contains('ms') || lang.contains('malay') || lang.contains('melayu') || lang.contains('indonesi')) return 'ms';
      if (lang.contains('th') || lang.contains('thai')) return 'th';
    }

    if (settings.languageCode == 'en') return 'en';
    if (settings.languageCode == 'ms') return 'ms';
  } catch (_) {}
  return 'th';
}

/// A modern, wrapped Word-by-Word view that uses [Wrap] instead of horizontal scroll overflow.
class WordByWordView extends StatefulWidget {
  final String verseKey;
  final bool isDarkMode;
  final String? languageOverride;
  final ValueChanged<int>? onWordTap;
  final EdgeInsetsGeometry padding;
  final bool isHidden;

  const WordByWordView({
    super.key,
    required this.verseKey,
    this.isDarkMode = false,
    this.languageOverride,
    this.onWordTap,
    this.padding = EdgeInsets.zero,
    this.isHidden = false,
  });

  @override
  State<WordByWordView> createState() => _WordByWordViewState();
}

class _WordByWordViewState extends State<WordByWordView> {
  List<Map<String, dynamic>>? _words;
  bool _isLoading = true;
  int? _activeWordIndex;
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  @override
  void didUpdateWidget(covariant WordByWordView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verseKey != widget.verseKey) {
      _loadWords();
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _loadWords() async {
    setState(() => _isLoading = true);
    try {
      final words = await OfflineQuranDatabaseService.getVerseWords(widget.verseKey);
      if (mounted) {
        setState(() {
          _words = words;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading words for ${widget.verseKey}: $e");
      if (mounted) {
        setState(() {
          _words = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _playWordAudio(String? audioPath, int index) async {
    if (audioPath == null || audioPath.isEmpty) return;
    setState(() => _activeWordIndex = index);

    try {
      _player ??= AudioPlayer();
      final fullUrl = audioPath.startsWith('http')
          ? audioPath
          : 'https://audio.qurancdn.com/$audioPath';
      await _player!.setAudioSource(
        AudioSource.uri(
          Uri.parse(fullUrl),
          tag: MediaItem(
            id: fullUrl,
            title: 'Word Audio',
            album: 'Quran Word by Word',
          ),
        ),
      );
      await _player!.play();
    } catch (e) {
      debugPrint("Error playing word audio: $e");
    } finally {
      if (mounted) {
        setState(() => _activeWordIndex = null);
      }
    }
  }

  String _getWordTranslation(Map<String, dynamic> word, String lang) {
    String translation = '';
    if (lang == 'ms') {
      translation = (word['translation_ms'] as String?) ?? '';
    } else if (lang == 'en') {
      translation = (word['translation_en'] as String?) ?? (word['translation'] as String?) ?? '';
    } else {
      translation = (word['translation_th'] as String?) ?? '';
    }

    if (translation.trim().isEmpty) {
      translation = (word['translation_th'] as String?) ??
          (word['translation_en'] as String?) ??
          (word['translation'] as String?) ??
          (word['transliteration'] as String?) ?? '';
    }
    return translation;
  }

  String _getCanonicalWordAudioUrl(String verseKey, int wordIndexOneBased) {
    final parts = verseKey.split(':');
    if (parts.length >= 2) {
      final s = int.tryParse(parts[0]);
      final v = int.tryParse(parts[1]);
      if (s != null && v != null && wordIndexOneBased > 0) {
        final sPad = s.toString().padLeft(3, '0');
        final vPad = v.toString().padLeft(3, '0');
        final wPad = wordIndexOneBased.toString().padLeft(3, '0');
        return 'https://audio.qurancdn.com/wbw/${sPad}_${vPad}_$wPad.mp3';
      }
    }
    return '';
  }

  static final RegExp _waqfRegex = RegExp(
    r'[\u06D6-\u06DC\u06DE-\u06E0\u06E2\u06E3\u06E8\u06E9\u06EA-\u06ED]',
  );

  static String _cleanWordArabicText(String text) {
    return text.replaceAll(_waqfRegex, '').trim();
  }

  void _showWordDetailSheet(BuildContext context, Map<String, dynamic> word, int wordIndexOneBased) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveLang = widget.languageOverride ?? resolveEffectiveWbwLanguage(context);

    final rawTextUthmani = word['text_uthmani'] as String? ?? '';
    final textUthmani = _cleanWordArabicText(rawTextUthmani);
    final translationTh = word['translation_th'] as String? ?? '';
    final translationEn = word['translation_en'] as String? ?? word['translation'] as String? ?? '';
    final translationMs = word['translation_ms'] as String? ?? '';
    final transliteration = word['transliteration'] as String? ?? '';
    final rootArabic = word['root_arabic'] as String?;
    final rootOccurrences = word['root_occurrences'] as int? ?? 0;
    final partOfSpeech = word['part_of_speech'] as String?;
    final audioUrl = _getCanonicalWordAudioUrl(
      word['verse_key']?.toString() ?? widget.verseKey,
      wordIndexOneBased,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header indicator
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Word in Large Arabic Font with Audio Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.volume_up_rounded),
                    onPressed: () {
                      _playWordAudio(audioUrl, -1);
                    },
                  ),
                  Expanded(
                    child: Text(
                      textUthmani,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: 'Tajweed',
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Transliteration & Multilingual Meaning Box (Borderless Surface Container)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (transliteration.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.record_voice_over_outlined, size: 15, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            transliteration,
                            style: GoogleFonts.notoSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    // If English is selected: Show English ONLY
                    if (effectiveLang == 'en') ...[
                      if (translationEn.isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🇬🇧 ', style: TextStyle(fontSize: 13)),
                            Expanded(
                              child: Text(
                                translationEn,
                                style: GoogleFonts.notoSans(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ]
                    // If Malay is selected: Show Malay & English (for reference)
                    else if (effectiveLang == 'ms') ...[
                      if (translationMs.isNotEmpty) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🇲🇾 ', style: TextStyle(fontSize: 13)),
                            Expanded(
                              child: Text(
                                translationMs,
                                style: GoogleFonts.notoSans(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (translationEn.isNotEmpty) const SizedBox(height: 8),
                      ],
                      if (translationEn.isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🇬🇧 ', style: TextStyle(fontSize: 13)),
                            Expanded(
                              child: Text(
                                translationEn,
                                style: GoogleFonts.notoSans(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ]
                    // Default / Thai: Show Thai & English (for reference)
                    else ...[
                      if (translationTh.isNotEmpty) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🇹🇭 ', style: TextStyle(fontSize: 13)),
                            Expanded(
                              child: Text(
                                translationTh,
                                style: GoogleFonts.notoSansThai(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (translationEn.isNotEmpty) const SizedBox(height: 8),
                      ],
                      if (translationEn.isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🇬🇧 ', style: TextStyle(fontSize: 13)),
                            Expanded(
                              child: Text(
                                translationEn,
                                style: GoogleFonts.notoSans(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Morphology & Root Word Section (Borderless Surface Container)
              if (rootArabic != null || partOfSpeech != null) ...[
                Text(
                  'ไวยากรณ์และรากศัพท์ (Morphology & Root)',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      if (rootArabic != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'รากศัพท์คำ (جذر)',
                              style: GoogleFonts.notoSansThai(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                rootArabic,
                                style: TextStyle(
                                  fontFamily: 'Tajweed',
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (partOfSpeech != null) const SizedBox(height: 12),
                      ],
                      if (partOfSpeech != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'หน้าที่ของคำ (POS)',
                              style: GoogleFonts.notoSansThai(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              partOfSpeech,
                              style: GoogleFonts.notoSansThai(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Button to view all occurrences by root
              if (rootArabic != null && rootOccurrences > 0) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RootVersesScreen(
                          rootArabic: rootArabic,
                          occurrences: rootOccurrences,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.saved_search_rounded, size: 18),
                  label: Text(
                    'ดูทั้ง $rootOccurrences โองการที่มีรากศัพท์นี้ ($rootArabic)',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveLang = widget.languageOverride ?? resolveEffectiveWbwLanguage(context);

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_words == null || _words!.isEmpty) {
      return const SizedBox.shrink();
    }

    final wordList = _words!.where((w) => w['char_type'] != 'end').toList();

    return Padding(
      padding: widget.padding,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(
          spacing: 8,
          runSpacing: 10,
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (int i = 0; i < wordList.length; i++)
              _buildWordCard(context, wordList[i], i, effectiveLang, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildWordCard(
    BuildContext context,
    Map<String, dynamic> word,
    int index,
    String effectiveLang,
    ColorScheme colorScheme,
  ) {
    final theme = Theme.of(context);
    final isHidden = widget.isHidden;
    final isDark = theme.brightness == Brightness.dark;
    final rawTextUthmani = word['text_uthmani'] as String? ?? '';
    final textUthmani = _cleanWordArabicText(rawTextUthmani);
    var translation = _getWordTranslation(word, effectiveLang);
    if (RegExp(r'^\(\d+\)$').hasMatch(translation.trim())) {
      translation = (word['translation_en'] as String?) ??
          (word['translation'] as String?) ??
          (word['transliteration'] as String?) ??
          '';
    }
    final transliteration = word['transliteration'] as String? ?? '';
    final isPlaying = _activeWordIndex == index;
    final wordIndexOneBased = index + 1;
    final audioUrl = _getCanonicalWordAudioUrl(widget.verseKey, wordIndexOneBased);

    final baseColor = isDark
        ? colorScheme.surfaceContainer
        : colorScheme.surfaceContainerHigh.withValues(alpha: 0.65);
    final activeColor = colorScheme.primaryContainer;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isHidden
            ? null
            : () {
                widget.onWordTap?.call(index);
                _playWordAudio(audioUrl, index);
              },
        onLongPress: isHidden
            ? null
            : () {
                _showWordDetailSheet(context, word, wordIndexOneBased);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(minWidth: 56),
          decoration: BoxDecoration(
            color: isPlaying ? activeColor : baseColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Arabic Word
              Text(
                textUthmani,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: 'Tajweed',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: isHidden
                      ? Colors.transparent
                      : (isPlaying
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface),
                ),
              ),
              const SizedBox(height: 5),
              // Word Translation (in selected translation language)
              Text(
                translation.isNotEmpty ? translation : transliteration,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansThai(
                  fontSize: 11.5,
                  fontWeight: FontWeight.normal,
                  color: isHidden
                      ? Colors.transparent
                      : (isPlaying
                          ? colorScheme.onPrimaryContainer.withValues(alpha: 0.85)
                          : colorScheme.onSurfaceVariant),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Backwards compatibility alias for [WordByWordView]
class WordByWordStrip extends StatelessWidget {
  final String verseKey;
  final bool isDarkMode;
  final ValueChanged<int>? onWordTap;
  final bool isHidden;

  const WordByWordStrip({
    super.key,
    required this.verseKey,
    this.isDarkMode = false,
    this.onWordTap,
    this.isHidden = false,
  });

  @override
  Widget build(BuildContext context) {
    return WordByWordView(
      verseKey: verseKey,
      isDarkMode: isDarkMode,
      onWordTap: onWordTap,
      isHidden: isHidden,
    );
  }
}

/// Modal Bottom Sheet for inspecting Word by Word on demand
class WordByWordSheet extends StatefulWidget {
  final String verseKey;
  final String? verseTextUthmani;
  final String? translationText;

  const WordByWordSheet({
    super.key,
    required this.verseKey,
    this.verseTextUthmani,
    this.translationText,
  });

  static Future<void> show(
    BuildContext context, {
    required String verseKey,
    String? verseTextUthmani,
    String? translationText,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WordByWordSheet(
        verseKey: verseKey,
        verseTextUthmani: verseTextUthmani,
        translationText: translationText,
      ),
    );
  }

  @override
  State<WordByWordSheet> createState() => _WordByWordSheetState();
}

class _WordByWordSheetState extends State<WordByWordSheet> {
  late String _currentLang;
  String? _fullTranslationText;
  bool _isLoadingTranslation = false;

  @override
  void initState() {
    super.initState();
    _currentLang = resolveEffectiveWbwLanguage(context);
    _fetchTranslation(_currentLang);
  }

  Future<void> _fetchTranslation(String lang) async {
    setState(() => _isLoadingTranslation = true);
    final text = await OfflineQuranDatabaseService.getTranslation(
      widget.verseKey,
      lang: lang,
    );
    if (mounted) {
      setState(() {
        _fullTranslationText = (text != null && text.isNotEmpty)
            ? text
            : widget.translationText;
        _isLoadingTranslation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final headerTitle = switch (_currentLang) {
      'en' => 'Word by Word ${widget.verseKey}',
      'ms' => 'Perkata demi perkataan ${widget.verseKey}',
      _ => 'แปลคำต่อคำ ${widget.verseKey}',
    };

    final translationHeader = switch (_currentLang) {
      'en' => 'Full Translation:',
      'ms' => 'Terjemahan Penuh:',
      _ => 'ความหมายรวม (Translation):',
    };

    final tipText = switch (_currentLang) {
      'en' => 'Tap word to play audio • Long press to view root word & grammar',
      'ms' => 'Ketik perkataan untuk audio • Tekan lama untuk kata dasar & tatabahasa',
      _ => 'แตะที่คำเพื่อฟังเสียงอ่าน • แตะค้างเพื่อดูรากศัพท์และไวยากรณ์',
    };

    final translationToShow = _fullTranslationText ?? widget.translationText;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Top drag indicator
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Verse badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.translate_rounded, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            headerTitle,
                            style: GoogleFonts.notoSansThai(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Close Button
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: _currentLang == 'en' ? 'Close' : (_currentLang == 'ms' ? 'Tutup' : 'ปิด'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),

              // Body content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Word by word wrapped view
                    WordByWordView(
                      verseKey: widget.verseKey,
                      isDarkMode: theme.brightness == Brightness.dark,
                      languageOverride: _currentLang,
                    ),

                    const SizedBox(height: 20),

                    // Full translation text if provided
                    if (translationToShow != null && translationToShow.isNotEmpty) ...[
                      Divider(
                        height: 1,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            translationHeader,
                            style: GoogleFonts.notoSansThai(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (_isLoadingTranslation) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        translationToShow,
                        style: GoogleFonts.notoSansThai(
                          fontSize: 14.5,
                          height: 1.6,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Tip banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tipText,
                              style: GoogleFonts.notoSansThai(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
