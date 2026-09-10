import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/footnote_service.dart';

class HtmlParser {
  static List<TextSpan> parseTranslationText(
    BuildContext context,
    String text,
    TextStyle style,
    Color linkColor, {
    String? verseKey,
    String? translationId,
    bool isInteractive = true,
  }) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final showFootnotes = settings.showFootnotes;

    // Check if offline footnote entry exists
    FootnoteEntry? footnoteEntry;
    if (verseKey != null && translationId != null) {
      footnoteEntry = FootnoteService().getEntry(verseKey, translationId);
    }

    // Determine working text
    String workingText = text;
    if (showFootnotes && footnoteEntry != null && footnoteEntry.annotated.isNotEmpty) {
      workingText = footnoteEntry.annotated;
    }

    // If footnotes are disabled by user, strip any [N] or <sup foot_note=...> tags, but keep grammatical tags
    if (!showFootnotes) {
      workingText = workingText
          .replaceAll(RegExp(r'''<sup\s+[^>]*foot_note\s*=\s*["']?\d+["']?[^>]*>.*?<\/sup>''', caseSensitive: false), '')
          .replaceAll(RegExp(r'''<sup\s+[^>]*class=["']?(?:foot_?note|qiraat)["']?[^>]*>.*?<\/sup>''', caseSensitive: false), '')
          .replaceAll(RegExp(r'\[\d+\]'), '')
          .trim();
    }

    // Pre-clean and normalize Bridges & QDC tags:
    // 1. Bridges `<a class="sup"><sup>sg </sup></a>` or `<a class=sub>pl</a>` -> `<gram>...</gram>`
    workingText = workingText.replaceAllMapped(
      RegExp(r'''<a\s+[^>]*class=["']?(?:sup|sub)["']?[^>]*>(?:\s*<sup[^>]*>)?(.*?)(?:</sup>\s*)?</a>''', caseSensitive: false),
      (m) => '<gram>${m.group(1)}</gram>',
    );

    // 2. Standalone <sup ...> without foot_note attribute -> grammatical tag
    workingText = workingText.replaceAllMapped(
      RegExp(r'''<sup(?![^>]*foot_note)[^>]*>(.*?)</sup>''', caseSensitive: false),
      (m) => '<gram>${m.group(1)}</gram>',
    );

    // 3. Standalone <sub ...> -> grammatical tag
    workingText = workingText.replaceAllMapped(
      RegExp(r'''<sub[^>]*>(.*?)</sub>''', caseSensitive: false),
      (m) => '<gram>${m.group(1)}</gram>',
    );

    // 4. Strip stray unclosed <a ...> or </a>
    workingText = workingText.replaceAll(RegExp(r'''</?a(?:\s+[^>]*)?>''', caseSensitive: false), '');

    // 5. Strip formatting spans, translator italics, and common block wrappers: <span...>, </span>, <i...>, </i>, <b>, <em>, <p>, etc.
    workingText = workingText.replaceAll(RegExp(r'''</?(?:span|i|em|b|strong|p|small|div|font)(?:\s+[^>]*)?>''', caseSensitive: false), '');
    workingText = workingText.replaceAll(RegExp(r'''<br\s*/?>''', caseSensitive: false), ' ');

    final List<TextSpan> spans = [];

    // Combined regex to find:
    // 1) <sup foot_note="123">1</sup> (with optional class, quotes, or whitespace)
    // 2) [1]
    // 3) Grammatical floating tags <gram>pl</gram>
    final regex = RegExp(
      r'''<sup\s+[^>]*foot_note\s*=\s*["']?(\d+)["']?[^>]*>(.*?)<\/sup>|\[(\d+)\]|<gram>(.*?)<\/gram>''',
      caseSensitive: false,
    );
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(workingText)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: workingText.substring(lastMatchEnd, match.start), style: style));
      }

      // Check for grammatical floating tag
      if (match.group(4) != null) {
        final rawGramTag = match.group(4)!.trim();
        final floatingTag = _toSuperscript(rawGramTag);
        spans.add(
          TextSpan(
            text: floatingTag,
            style: style.copyWith(
              fontSize: (style.fontSize ?? 14) * 0.75,
              fontWeight: FontWeight.w600,
              color: (style.color ?? Colors.black).withValues(alpha: 0.65),
            ),
          ),
        );
        lastMatchEnd = match.end;
        continue;
      }

      // Footnote marker
      int fnId = 1;
      String? rawOrigId;

      if (match.group(1) != null) {
        rawOrigId = match.group(1);
        fnId = int.tryParse(match.group(2) ?? '1') ?? 1;
      } else if (match.group(3) != null) {
        fnId = int.tryParse(match.group(3)!) ?? 1;
      }

      spans.add(
        TextSpan(
          text: '[$fnId]',
          style: style.copyWith(
            color: linkColor,
            fontWeight: FontWeight.bold,
            fontSize: (style.fontSize ?? 14) * 0.75,
          ),
          recognizer: isInteractive
              ? (TapGestureRecognizer()
                ..onTap = () {
                  _showFootnoteModal(
                    context,
                    fnId: fnId,
                    rawOrigId: rawOrigId,
                    footnoteEntry: footnoteEntry,
                    textColor: style.color ?? Colors.black,
                    translationId: translationId,
                  );
                })
              : null,
        ),
      );

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < workingText.length) {
      spans.add(TextSpan(text: workingText.substring(lastMatchEnd), style: style));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: workingText, style: style));
    }

    return spans;
  }

  static const Map<String, String> _superscriptMap = {
    'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ', 'f': 'ᶠ', 'g': 'ᵍ', 'h': 'ʰ',
    'i': 'ⁱ', 'j': 'ʲ', 'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'n': 'ⁿ', 'o': 'ᵒ', 'p': 'ᵖ',
    'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ', 'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ',
    'z': 'ᶻ', '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶',
    '7': '⁷', '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾'
  };

  static String _toSuperscript(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      final lower = char.toLowerCase();
      buffer.write(_superscriptMap[lower] ?? char);
    }
    return buffer.toString();
  }

  static Future<void> _showFootnoteModal(
    BuildContext context, {
    required int fnId,
    String? rawOrigId,
    FootnoteEntry? footnoteEntry,
    required Color textColor,
    String? translationId,
  }) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isThai = settings.languageCode == 'th';

    // Check offline footnote
    String? offlineText;
    if (footnoteEntry != null) {
      for (final f in footnoteEntry.footnotes) {
        if (f.id == fnId) {
          offlineText = f.text;
          break;
        }
      }
    }

    String editionTitle;
    final tid = translationId?.toLowerCase() ?? '';
    if (tid == 'en_hilali_khan' || tid == '203' || tid.contains('hilali')) {
      editionTitle = 'Al-Hilali & Muhsin Khan (King Fahd Complex)';
    } else if (tid == 'en_bridges' || tid == '149' || tid.contains('bridges')) {
      editionTitle = "Bridges' Translation (10 Qira'at)";
    } else if (tid == 'en_saheeh' || tid == 'english' || tid == '20') {
      editionTitle = 'Saheeh International';
    } else {
      editionTitle = 'King Fahd Complex (ฉบับสมาคมนักเรียนเก่าอาหรับ)';
    }

    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      elevation: 0,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        Widget content;
        if (offlineText != null && offlineText.isNotEmpty) {
          content = SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text(
              offlineText,
              style: GoogleFonts.notoSansThai(fontSize: 15, height: 1.6, color: colorScheme.onSurface),
            ),
          );
        } else if (rawOrigId != null) {
          content = FutureBuilder<String>(
            future: _fetchFootnote(rawOrigId),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary)),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: Text(
                      isThai ? 'โหลดเชิงอรรถล้มเหลว' : 'Failed to load footnote.',
                      style: GoogleFonts.notoSansThai(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                );
              }
              final clean = snapshot.data!.replaceAll(RegExp(r'<[^>]*>'), '');
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Text(
                  clean,
                  style: GoogleFonts.notoSansThai(fontSize: 15, height: 1.6, color: colorScheme.onSurface),
                ),
              );
            },
          );
        } else {
          content = Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Text(
                isThai ? 'ไม่พบข้อมูลเชิงอรรถ' : 'Footnote not found.',
                style: GoogleFonts.notoSansThai(color: colorScheme.onSurfaceVariant),
              ),
            ),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isThai ? 'เชิงอรรถ [$fnId]' : 'Footnote [$fnId]',
                            style: GoogleFonts.notoSansThai(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            editionTitle,
                            style: GoogleFonts.notoSansThai(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              Flexible(child: content),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  static Future<String> _fetchFootnote(String footnoteId) async {
    try {
      final res = await http.get(Uri.parse('https://api.quran.com/api/v4/foot_notes/$footnoteId'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['foot_note']?['text'] ?? 'Footnote text not found.';
      }
    } catch (_) {}
    return 'Footnote text not found.';
  }
}
