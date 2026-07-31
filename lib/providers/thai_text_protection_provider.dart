import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ThaiTextProtectionProvider extends ChangeNotifier {
  static const String _cacheKey = 'thai_protected_terms_cache_v1';
  static const String _wordJoiner = '\u2060';

  static const List<String> seedTerms = [
    'ฟิรเอานฺ',
    'อัลลอฮฺ',
    'มุฮัมมัด',
    'อิบรอฮีม',
    'อิสมาอีล',
    'อิสฮาก',
    'ยะอฺกูบ',
    'ญิบรีล',
    'ตอรูต',
    'ญาลูต',
    'ฏอลูต',
    'ฮารูน',
    'อีซา',
    'มูซา',
  ];

  List<String> _terms = _normalizeTerms(seedTerms);

  ThaiTextProtectionProvider() {
    load();
  }

  List<String> get terms => List.unmodifiable(_terms);

  Future<void> load() async {
    await _loadCachedTerms();
    await _fetchRemoteTerms();
  }

  String protect(String text) {
    if (text.isEmpty) return text;

    // 1. Replace protected terms with placeholders to keep them clean from syllable breaks
    final placeholders = <String, String>{};
    var processedText = text;

    if (_terms.isNotEmpty) {
      for (var i = 0; i < _terms.length; i++) {
        final term = _terms[i];
        if (processedText.contains(term)) {
          final placeholder = '___TERM_${i}___';
          placeholders[placeholder] = _protectTerm(term);
          processedText = processedText.replaceAll(term, placeholder);
        }
      }
    }

    // 2. Do NOT insert Zero-Width Spaces (\u200B) at syllable boundaries anymore,
    // as modern Flutter text layout engines wrap Thai text correctly at word boundaries
    // when the locale is set to 'th_TH', whereas inserting \u200B at every consonant/vowel group
    // causes words to break incorrectly in the middle of words.
    // processedText = _addThaiSyllableBreaks(processedText);

    // 3. Restore protected terms back into the text, surrounding them with Zero-Width Spaces (\u200B)
    // to provide clear word boundaries so the layout engine can break lines before/after them
    // rather than breaking the surrounding words (e.g., "ของอัลลอฮฺ" wrapping incorrectly as "ของ" and "อัลลอฮฺ").
    placeholders.forEach((placeholder, protectedValue) {
      processedText = processedText.replaceAll(placeholder, '\u200B$protectedValue\u200B');
    });

    return processedText;
  }

  static String _addThaiSyllableBreaks(String text) {
    if (text.isEmpty) return text;
    // Matches:
    // 1. A Thai consonant [\u0E01-\u0E2E] followed by zero or more combining characters/vowels/tone marks.
    // 2. A Thai prepended vowel [\u0E40-\u0E44] followed by a consonant and zero or more combining characters/vowels/tone marks.
    final regex = RegExp(
      r'([\u0E01-\u0E2E][\u0E30-\u0E3A\u0E45-\u0E4E]*|[\u0E40-\u0E44][\u0E01-\u0E2E][\u0E30-\u0E3A\u0E45-\u0E4E]*)',
    );
    return text.replaceAllMapped(regex, (match) => match.group(1)! + '\u200B');
  }

  Future<void> _loadCachedTerms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached == null || cached.isEmpty) return;

      final decoded = jsonDecode(cached);
      if (decoded is! List) return;

      _terms = _normalizeTerms([
        ...seedTerms,
        ...decoded.map((value) => value.toString()),
      ]);
      notifyListeners();
    } catch (error) {
      debugPrint('Thai protected terms cache load failed: $error');
    }
  }

  Future<void> _fetchRemoteTerms() async {
    try {
      final rows = await Supabase.instance.client
          .from('thai_protected_terms')
          .select('term')
          .eq('is_active', true)
          .order('sort_order')
          .order('term');

      final remoteTerms = rows
          .map<String>((row) => row['term']?.toString() ?? '')
          .where((term) => term.trim().isNotEmpty);
      _terms = _normalizeTerms([...seedTerms, ...remoteTerms]);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_terms));
      notifyListeners();
    } catch (error) {
      debugPrint('Thai protected terms remote load failed: $error');
    }
  }

  static List<String> _normalizeTerms(Iterable<String> values) {
    final seen = <String>{};
    final terms = values
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty && seen.add(term))
        .toList();
    terms.sort((a, b) => b.length.compareTo(a.length));
    return terms;
  }

  static String _protectTerm(String term) {
    final runes = term.runes.toList(growable: false);
    if (runes.length < 2) return term;

    final buffer = StringBuffer();
    for (var index = 0; index < runes.length; index += 1) {
      final rune = runes[index];
      if (index > 0 && !_isThaiCombiningMark(rune)) {
        buffer.write(_wordJoiner);
      }
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  static bool _isThaiCombiningMark(int rune) {
    return rune == 0x0E31 ||
        (rune >= 0x0E34 && rune <= 0x0E3A) ||
        (rune >= 0x0E47 && rune <= 0x0E4E);
  }
}
