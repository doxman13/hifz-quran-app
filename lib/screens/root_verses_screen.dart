import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/translation_manager_provider.dart';
import '../services/offline_quran_database_service.dart';
import '../shared/quran_translation_helper.dart';
import '../widgets/word_by_word_strip.dart';

class RootVersesScreen extends StatefulWidget {
  final String rootArabic;
  final int occurrences;

  const RootVersesScreen({
    super.key,
    required this.rootArabic,
    required this.occurrences,
  });

  @override
  State<RootVersesScreen> createState() => _RootVersesScreenState();
}

class _RootVersesScreenState extends State<RootVersesScreen> {
  List<Map<String, dynamic>>? _verses;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVerses();
  }

  Future<void> _loadVerses() async {
    setState(() => _isLoading = true);
    try {
      final verses = await OfflineQuranDatabaseService.getVersesByRoot(widget.rootArabic);
      if (mounted) {
        setState(() {
          _verses = verses;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading verses by root ${widget.rootArabic}: $e");
      if (mounted) {
        setState(() {
          _verses = [];
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = Provider.of<SettingsProvider>(context);
    final transManager = Provider.of<TranslationManagerProvider>(context);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'รากศัพท์คำ (جذر): ',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    widget.rootArabic,
                    style: const TextStyle(
                      fontFamily: 'Tajweed',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'พบ ${widget.occurrences} ครั้งในอัลกุรอาน',
                style: GoogleFonts.notoSansThai(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.15),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _verses == null || _verses!.isEmpty
              ? Center(
                  child: Text(
                    'ไม่พบโองการ',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _verses!.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final item = _verses![index];
                    final verseKey = item['verse_key'] as String? ?? '';
                    final rawTextUthmani = item['text_uthmani'] as String? ?? '';
                    final verseId = item['verse_id'];
                    final formattedArabic = formatArabicAyahText(
                      rawTextUthmani,
                      verseNumber: verseId,
                    );
                    final translationText = resolveVerseTranslationText(
                      context: context,
                      verseKey: verseKey,
                      verseItem: item,
                      settings: settings,
                      transManager: transManager,
                    );

                    return Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'ซูเราะฮ์ $verseKey',
                                  style: GoogleFonts.notoSansThai(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                              Text(
                                '${index + 1} / ${_verses!.length}',
                                style: GoogleFonts.notoSans(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Arabic Verse Text with circular Ayah mark
                          Text(
                            formattedArabic,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontFamily: 'Tajweed',
                              fontSize: 26,
                              height: 1.8,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Word by word view
                          WordByWordView(
                            verseKey: verseKey,
                            isDarkMode: theme.brightness == Brightness.dark,
                          ),
                          const SizedBox(height: 12),

                          Divider(
                            height: 1,
                            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                          ),
                          const SizedBox(height: 12),

                          // Translation text (following active global settings)
                          Text(
                            translationText,
                            style: getTranslationTextStyle(
                              context,
                              fontSize: 15,
                              height: 1.6,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

