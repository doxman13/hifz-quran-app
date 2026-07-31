import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/translation_database.dart';

class TranslationDownloader {
  static const String _baseUrl = 'https://api.quran.com/api/v4';

  /// Downloads the translation and stores it in the local SQLite database.
  /// Uses a callback to report progress (0.0 to 1.0).
  static Future<bool> downloadTranslation(
      int translationId, String name, String author, String language,
      {Function(double)? onProgress}) async {
    try {
      final db = TranslationDatabase.instance;
      final Map<String, String> verseMap = {};
      
      for (int surah = 1; surah <= 114; surah++) {
        int page = 1;
        int totalPages = 1;
        do {
          final res = await http.get(Uri.parse(
              '$_baseUrl/verses/by_chapter/$surah?translations=$translationId&page=$page&per_page=50'));
              
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final verses = data['verses'] as List;
            final pagination = data['pagination'];
            totalPages = pagination['total_pages'];
            
            for (final v in verses) {
              final verseKey = v['verse_key'] as String;
              final transList = v['translations'] as List?;
              if (transList != null && transList.isNotEmpty) {
                final transText = transList[0]['text'] as String;
                verseMap[verseKey] = transText;
              }
            }
          } else {
            return false;
          }
          page++;
        } while (page <= totalPages);
        
        if (onProgress != null) {
          onProgress(surah / 114.0);
        }
      }
      
      if (verseMap.isNotEmpty) {
        await db.addTranslation(translationId, name, author, language);
        await db.insertVerses(translationId, verseMap);
        return true;
      }
      return false;
      
    } catch (e) {
      print('Error downloading translation by chapters: $e');
      return false;
    }
  }
}
