import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

class HtmlParser {
  static List<TextSpan> parseTranslationText(
    BuildContext context,
    String text,
    TextStyle style,
    Color linkColor,
  ) {
    final List<TextSpan> spans = [];
    // Basic regex to find <sup foot_note="1234">1</sup>
    final regex = RegExp(r'<sup foot_note="?(\d+)"?>(.*?)<\/sup>');
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start), style: style));
      }
      
      final footNoteId = match.group(1);
      final supText = match.group(2);
      
      if (footNoteId != null && supText != null) {
        spans.add(
          TextSpan(
            text: '[$supText]',
            style: style.copyWith(
              color: linkColor,
              fontWeight: FontWeight.bold,
              fontSize: (style.fontSize ?? 14) * 0.8,
            ),
            recognizer: TapGestureRecognizer()..onTap = () {
              _showFootnoteModal(context, footNoteId, style.color ?? Colors.black);
            },
          ),
        );
      }
      
      lastMatchEnd = match.end;
    }
    
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd), style: style));
    }

    // fallback if text has no footnotes
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: style));
    }

    return spans;
  }

  static Future<void> _showFootnoteModal(BuildContext context, String footnoteId, Color textColor) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return FutureBuilder<String>(
          future: _fetchFootnote(footnoteId),
          builder: (ctx, snapshot) {
            Widget content;
            if (snapshot.connectionState == ConnectionState.waiting) {
              content = const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError || !snapshot.hasData) {
              content = Center(
                child: Text('Failed to load footnote.', style: GoogleFonts.inter(color: textColor)),
              );
            } else {
              // The API returns a string which itself might have HTML (like <i>).
              // For simplicity, we just strip basic tags for the modal or render them.
              final cleanText = snapshot.data!.replaceAll(RegExp(r'<[^>]*>'), '');
              content = SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Text(
                  cleanText,
                  style: GoogleFonts.inter(fontSize: 16, height: 1.6, color: textColor),
                ),
              );
            }
            
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Footnote', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
                  const Divider(),
                  Flexible(child: content),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Future<String> _fetchFootnote(String footnoteId) async {
    final res = await http.get(Uri.parse('https://api.quran.com/api/v4/foot_notes/$footnoteId'));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['foot_note']?['text'] ?? 'Footnote text not found.';
    }
    throw Exception('Failed to load footnote');
  }
}
