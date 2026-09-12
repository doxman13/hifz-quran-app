import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/medina_mushaf_pages.dart';

import '../data/offline_surah_names.dart';
import '../data/quran_repository.dart';
import '../providers/settings_provider.dart';
import '../services/ctc_matcher.dart';
import '../services/offline_quran_database_service.dart';
import '../services/recitation_engine.dart';

/// Interactive Material 3 Modal Bottom Sheet for "Recite-to-Search" (Voice Quran Search).
class VoiceSearchSheet extends StatefulWidget {
  final QuranRepository repository;
  final void Function(int page, {String? highlightVerseKey}) onOpenPage;

  const VoiceSearchSheet({
    super.key,
    required this.repository,
    required this.onOpenPage,
  });

  static Future<void> show(
    BuildContext context, {
    required QuranRepository repository,
    required void Function(int page, {String? highlightVerseKey}) onOpenPage,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => VoiceSearchSheet(
        repository: repository,
        onOpenPage: onOpenPage,
      ),
    );
  }

  @override
  State<VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

class _VoiceSearchSheetState extends State<VoiceSearchSheet>
    with SingleTickerProviderStateMixin {
  final RecitationEngine _engine = RecitationEngine();

  bool _isListening = false;
  bool _isProcessing = false;
  double _audioLevel = 0.0;
  String _recognizedText = '';
  String? _errorMessage;
  List<VerseSearchResult> _searchResults = [];
  final Map<String, Map<String, dynamic>> _verseDetailsCache = {};

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Automatically start listening after sheet slides up
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVoiceSearch();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _engine.stopListening();
    super.dispose();
  }

  Future<void> _startVoiceSearch() async {
    if (!mounted) return;
    setState(() {
      _isListening = true;
      _isProcessing = false;
      _errorMessage = null;
      _audioLevel = 0.0;
    });

    try {
      await _engine.startVoiceSearch(
        onAudioLevel: (level) {
          if (mounted) {
            setState(() => _audioLevel = level);
          }
        },
        onResults: (results, text) async {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _isProcessing = true;
            _recognizedText = text;
            _searchResults = results;
          });

          // Fetch full verse details (Uthmani text and translations) from local DB
          for (final r in results) {
            final key = '${r.surah}:${r.ayah}';
            if (!_verseDetailsCache.containsKey(key)) {
              final data = await OfflineQuranDatabaseService.getVerse(key);
              if (data != null && mounted) {
                _verseDetailsCache[key] = data;
              }
            }
          }

          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
          }
        },
        onError: (err) {
          if (mounted) {
            setState(() {
              _isListening = false;
              _isProcessing = false;
              _errorMessage = err;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _isProcessing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _stopVoiceSearch() async {
    await _engine.stopListening();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title Header
            Row(
              children: [
                Icon(
                  Icons.mic_none_rounded,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  isThai ? 'ค้นหาด้วยเสียง (อัลกุรอานภาษาอาหรับ)' : 'Voice Search (Arabic Quran)',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Mic & Wave Stage
            _buildMicStage(colorScheme, textTheme, isThai),
            const SizedBox(height: 16),

            // Spoken text pill
            if (_recognizedText.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.record_voice_over_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _recognizedText,
                        style: TextStyle(
                          fontFamily: 'UthmanicHafs',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                          height: 1.6,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Results Header or Error
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _errorMessage!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              )
            else if (_isProcessing)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: colorScheme.primary,
                  ),
                ),
              )
            else if (_searchResults.isNotEmpty)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _searchResults.length,
                  separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    return _buildResultCard(item, colorScheme, textTheme, isThai);
                  },
                ),
              )
            else if (!_isListening && _recognizedText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    isThai
                        ? 'ไม่พบอายะห์ที่ตรงกัน ลองอ่านใหม่อีกครั้ง'
                        : 'No matching verse found. Please try reciting again.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicStage(
    ColorScheme colorScheme,
    TextTheme textTheme,
    bool isThai,
  ) {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              if (_isListening) {
                _stopVoiceSearch();
              } else {
                _startVoiceSearch();
              }
            },
            child: ScaleTransition(
              scale: _isListening ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHigh,
                  boxShadow: _isListening
                      ? [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.35 + _audioLevel * 0.35),
                            blurRadius: 18 + _audioLevel * 14,
                            spreadRadius: 4 + _audioLevel * 8,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: _isListening ? colorScheme.onPrimary : colorScheme.onSurface,
                  size: 32,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isListening
                ? (isThai
                    ? 'กำลังฟัง... อ่านอายะฮฺภาษาอาหรับใดก็ได้'
                    : 'Listening... Recite any Arabic verse or phrase')
                : (isThai ? 'แตะไมโครโฟนเพื่อเริ่มอ่าน' : 'Tap microphone to recite'),
            style: textTheme.bodyMedium?.copyWith(
              color: _isListening
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(
    VerseSearchResult item,
    ColorScheme colorScheme,
    TextTheme textTheme,
    bool isThai,
  ) {
    final key = '${item.surah}:${item.ayah}';
    final details = _verseDetailsCache[key];
    final pageNumber = details?['page_number'] as int? ??
        getMedinaMushafPageNumber(item.surah, item.ayah);

    final surahNameEn = offlineSurahNamesEn[item.surah.toString()] ??
        widget.repository.getSurahName(item.surah.toString());
    final surahNameTh = offlineSurahNamesTh[item.surah.toString()] ?? surahNameEn;
    final displayName = isThai ? surahNameTh : surahNameEn;

    final uthmaniText = details?['text_uthmani'] as String? ?? item.text;
    final translation = isThai
        ? (details?['translation_th'] as String? ?? '')
        : (details?['translation_en'] as String? ?? '');

    final confidencePct = (item.score * 100).toInt().clamp(1, 100);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.pop(context);
            widget.onOpenPage(pageNumber, highlightVerseKey: key);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top header: Surah & Ayah badge + confidence
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$displayName ${item.surah}:${item.ayah}',
                        style: textTheme.labelMedium?.copyWith(
                           color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      String.fromCharCode(0xe000 + item.surah),
                      style: TextStyle(
                        fontFamily: 'QcfSurahName',
                        fontSize: 22,
                        color: colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$confidencePct% match',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Arabic verse preview
                Text(
                  uthmaniText,
                  style: TextStyle(
                    fontFamily: 'UthmanicHafs',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                    height: 1.8,
                  ),
                  textDirection: TextDirection.rtl,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (translation.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    translation,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      isThai ? 'หน้า $pageNumber' : 'Page $pageNumber',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
