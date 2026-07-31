// lib/widgets/verse_action_sheet.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/notes_provider.dart';
import '../providers/local_reading_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/supabase_provider.dart';
import '../models/verse.dart';

class VerseActionSheet extends StatelessWidget {
  final Verse verse;
  final VoidRefCallback? onTafsirSelected;
  final VoidRefCallback? onEditNoteSelected;
  final VoidRefCallback? onReportErrorSelected;

  const VerseActionSheet({
    Key? key,
    required this.verse,
    this.onTafsirSelected,
    this.onEditNoteSelected,
    this.onReportErrorSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final notesProv = Provider.of<NotesProvider>(context);
    final localReading = Provider.of<LocalReadingProvider>(context);
    
    final primaryColor = settings.getPrimaryColor();
    final colors = settings.getAppColors();

    final note = notesProv.getNoteForVerse(verse.surahId, verse.id);
    final hasNote = note.trim().isNotEmpty;
    final noteCount = hasNote ? 1 : 0;
    
    final isBookmarked = localReading.isBookmarked(verse.surahId, verse.id);

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Verse Actions — ${verse.surahId}:${verse.id}',
                style: GoogleFonts.notoSansThai(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const SizedBox(height: 12),

          // Actions List
          ListTile(
            leading: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border, color: Colors.amber.shade700),
            title: Text(
              isBookmarked ? 'Remove Bookmark' : 'Bookmark Verse',
              style: GoogleFonts.notoSansThai(fontSize: 14, color: colors.textStrong),
            ),
            onTap: () {
              Navigator.pop(context);
              localReading.toggleBookmark(verse.surahId, verse.id);
            },
          ),
          
          if (verse.shortTafsir != null)
            ListTile(
              leading: Icon(Icons.menu_book_outlined, color: primaryColor),
              title: Text(
                'View Short Tafsir',
                style: GoogleFonts.notoSansThai(fontSize: 14, color: colors.textStrong),
              ),
              onTap: () {
                Navigator.pop(context);
                if (onTafsirSelected != null) onTafsirSelected!();
              },
            ),

          ListTile(
            leading: Icon(Icons.edit_outlined, color: primaryColor),
            title: Text(
              'Add/Edit Reflection',
              style: GoogleFonts.notoSansThai(fontSize: 14, color: colors.textStrong),
            ),
            onTap: () {
              Navigator.pop(context);
              if (onEditNoteSelected != null) onEditNoteSelected!();
            },
          ),

          ListTile(
            leading: Icon(Icons.comment_outlined, color: primaryColor),
            title: Text(
              'My Thoughts ($noteCount)',
              style: GoogleFonts.notoSansThai(fontSize: 14, color: colors.textStrong),
            ),
            onTap: () {
              Navigator.pop(context);
              _showThoughtsModal(context, settings, note, verse.surahId, verse.id);
            },
          ),

          ListTile(
            leading: Icon(Icons.people_outline, color: primaryColor),
            title: Text(
              'Community Reflections',
              style: GoogleFonts.notoSansThai(fontSize: 14, color: colors.textStrong),
            ),
            onTap: () async {
              Navigator.pop(context);
              final urlString = 'https://quran.salamthailand.com/tadabbur/community?surah=${verse.surahId}&ayah=${verse.id}';
              final uri = Uri.parse(urlString);
              try {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  debugPrint('Could not launch $urlString');
                }
              } catch (e) {
                debugPrint('Error launching url: $e');
              }
            },
          ),

          ListTile(
            leading: const Icon(Icons.report_problem_outlined, color: Colors.blueGrey),
            title: Text(
              'Report Error',
              style: GoogleFonts.notoSansThai(fontSize: 14, color: colors.textStrong),
            ),
            onTap: () {
              Navigator.pop(context);
              _showReportDialog(context, settings);
            },
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context, SettingsProvider settings) {
    final colors = settings.getAppColors();
    final supabaseProv = Provider.of<SupabaseProvider>(context, listen: false);

    if (!supabaseProv.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเข้าสู่ระบบเพื่อรายงานข้อผิดพลาด (Please log in to report an error)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final commentController = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: colors.borderSoft),
              ),
              title: Text(
                'Report Error (Surah ${verse.surahId}:${verse.id})',
                style: GoogleFonts.notoSansThai(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.redAccent,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reported Verse Text:',
                      style: GoogleFonts.notoSansThai(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.borderSoft),
                      ),
                      child: Text(
                        verse.thaiV3.isNotEmpty ? verse.thaiV3 : verse.thaiV2,
                        style: GoogleFonts.notoSansThai(
                          fontSize: 13,
                          color: colors.textStrong,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your Comment / Explanation:',
                      style: GoogleFonts.notoSansThai(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: commentController,
                      maxLines: 4,
                      style: GoogleFonts.notoSansThai(fontSize: 13, color: colors.textStrong),
                      decoration: InputDecoration(
                        hintText: 'Describe the issue (e.g. translation error, spelling)...',
                        hintStyle: GoogleFonts.notoSansThai(fontSize: 12, color: colors.foreground),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.notoSansThai(color: colors.foreground),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final comment = commentController.text.trim();
                          if (comment.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('กรุณากรอกรายละเอียดข้อผิดพลาด (Please enter comment)'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            final supabase = Supabase.instance.client;
                            await supabase.from('error_reports').insert({
                              'user_id': supabaseProv.userId,
                              'surah_id': int.parse(verse.surahId),
                              'ayah_number': int.parse(verse.id),
                              'reported_verse_text': verse.thaiV3.isNotEmpty ? verse.thaiV3 : verse.thaiV2,
                              'user_comment': comment,
                            });

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('รายงานข้อผิดพลาดสำเร็จ (Error report submitted successfully!)'),
                                  backgroundColor: Colors.teal,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() {
                              isSaving = false;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('เกิดข้อผิดพลาด: $e'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Submit',
                          style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showThoughtsModal(
    BuildContext context,
    SettingsProvider settings,
    String note,
    String surahId,
    String verseId,
  ) {
    final colors = settings.getAppColors();
    final primaryColor = settings.getPrimaryColor();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.borderSoft),
          ),
          title: Text(
            'My Thoughts ($surahId:$verseId)',
            style: GoogleFonts.notoSansThai(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: primaryColor,
            ),
          ),
          content: Container(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Text(
                note.trim().isEmpty ? 'No personal reflection written for this verse.' : note,
                style: GoogleFonts.notoSansThai(
                  fontSize: 14,
                  color: colors.textStrong,
                  height: 1.5,
                ),
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            // Left Action: View Community Reflections
            TextButton(
              onPressed: () async {
                final urlString = 'https://quran.salamthailand.com/tadabbur/community?surah=$surahId&ayah=$verseId';
                final uri = Uri.parse(urlString);
                try {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    debugPrint('Could not launch $urlString');
                  }
                } catch (e) {
                  debugPrint('Error launching url: $e');
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Community Reflections ↗',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            // Right Action: Close
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(
                'Close',
                style: GoogleFonts.notoSansThai(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

typedef VoidRefCallback = void Function();
