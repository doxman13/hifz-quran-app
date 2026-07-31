import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TranslationDatabase {
  static final TranslationDatabase instance = TranslationDatabase._init();

  TranslationDatabase._init();

  static const _translationsKey = 'downloadedTranslations';
  static const _versesPrefix = 'downloadedTranslationVerses_';

  Future<void> addTranslation(
    int id,
    String name,
    String author,
    String language,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final translations = await getDownloadedTranslations();
    final next = [
      ...translations.where((item) => item['id'] != id),
      {
        'id': id,
        'name': name,
        'author_name': author,
        'language_name': language,
      },
    ];
    await prefs.setString(_translationsKey, jsonEncode(next));
  }

  Future<void> removeTranslation(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final translations = await getDownloadedTranslations();
    final next = translations.where((item) => item['id'] != id).toList();
    await prefs.setString(_translationsKey, jsonEncode(next));
    await prefs.remove('$_versesPrefix$id');
  }

  Future<void> insertVerses(
    int translationId,
    Map<String, String> versesMap,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_versesPrefix$translationId',
      jsonEncode(versesMap),
    );
  }

  Future<String?> getVerseTranslation(
    int translationId,
    String verseKey,
  ) async {
    final verses = await getAllVersesForTranslation(translationId);
    return verses[verseKey];
  }

  Future<Map<String, String>> getAllVersesForTranslation(
    int translationId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_versesPrefix$translationId');
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  Future<List<Map<String, dynamic>>> getDownloadedTranslations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_translationsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }

  Future<bool> isDownloaded(int id) async {
    final translations = await getDownloadedTranslations();
    return translations.any((item) => item['id'] == id);
  }
}
