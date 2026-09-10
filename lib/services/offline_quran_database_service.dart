import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

class OfflineQuranDatabaseService {
  static Database? _database;
  static const String _dbName = 'quran_offline.db';
  static const int _targetDbVersion = 36;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    bool shouldCopy = false;
    final exists = await databaseExists(path);

    if (!exists) {
      shouldCopy = true;
    } else {
      // Check existing database version
      try {
        final existingDb = await openDatabase(path, readOnly: true);
        final versionRes = await existingDb.rawQuery('PRAGMA user_version;');
        final version = Sqflite.firstIntValue(versionRes) ?? 0;
        await existingDb.close();

        if (version < _targetDbVersion) {
          debugPrint("Updating quran_offline.db to version $_targetDbVersion (current: $version)");
          shouldCopy = true;
        }
      } catch (e) {
        debugPrint("Error checking db version, forcing copy: $e");
        shouldCopy = true;
      }
    }

    if (shouldCopy) {
      debugPrint("Creating a fresh copy from asset: $_dbName");
      try {
        await Directory(dirname(path)).create(recursive: true);
      } catch (_) {}

      // Copy from asset
      final data = await rootBundle.load('assets/$_dbName');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }

    return await openDatabase(path, readOnly: false);
  }

  /// Get page line mapping records (15 lines per page)
  static Future<List<Map<String, dynamic>>> getPageLines(int pageNumber) async {
    final db = await database;
    return await db.query(
      'pages',
      where: 'page_number = ?',
      whereArgs: [pageNumber],
      orderBy: 'line_number ASC',
    );
  }

  /// Get all verses on a specific page
  static Future<List<Map<String, dynamic>>> getVersesForPage(int pageNumber) async {
    final db = await database;
    return await db.query(
      'verses',
      where: 'page_number = ?',
      whereArgs: [pageNumber],
      orderBy: 'surah_id ASC, verse_id ASC',
    );
  }

  /// Get all word-by-word records for a specific verse ('1:1', '18:74')
  static Future<List<Map<String, dynamic>>> getVerseWords(String verseKey) async {
    final db = await database;
    return await db.query(
      'words',
      where: 'verse_key = ?',
      whereArgs: [verseKey],
      orderBy: 'position ASC',
    );
  }

  /// Get a single verse by verseKey ('1:1', '18:74')
  static Future<Map<String, dynamic>?> getVerse(String verseKey) async {
    final db = await database;
    final results = await db.query(
      'verses',
      where: 'verse_key = ?',
      whereArgs: [verseKey],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get translation for a specific verse and language ('th', 'en', 'ms')
  static Future<String?> getTranslation(String verseKey, {String lang = 'th'}) async {
    try {
      final db = await database;
      final column = switch (lang.toLowerCase()) {
        'en' => 'translation_en',
        'ms' => 'translation_ms',
        _ => 'translation_th',
      };
      final results = await db.query(
        'verses',
        columns: [column],
        where: 'verse_key = ?',
        whereArgs: [verseKey],
        limit: 1,
      );
      if (results.isEmpty) return null;
      return results.first[column] as String?;
    } catch (e) {
      debugPrint("Error getting translation for $verseKey: $e");
      return null;
    }
  }

  /// Get all translations for a language ('th', 'en', 'ms')
  static Future<Map<String, String>> getAllTranslations({String lang = 'th'}) async {
    try {
      final db = await database;
      final column = switch (lang.toLowerCase()) {
        'en' => 'translation_en',
        'ms' => 'translation_ms',
        _ => 'translation_th',
      };
      final results = await db.query(
        'verses',
        columns: ['verse_key', column],
      );
      return {
        for (final row in results)
          if (row['verse_key'] != null && row[column] != null)
            row['verse_key'] as String: row[column] as String,
      };
    } catch (e) {
      debugPrint("Error fetching all translations for lang $lang: $e");
      return {};
    }
  }

  /// Get Tafsir for a specific verse
  static Future<String?> getTafsir(String verseKey) async {
    final db = await database;
    final results = await db.query(
      'verses',
      columns: ['tafsir_th'],
      where: 'verse_key = ?',
      whereArgs: [verseKey],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first['tafsir_th'] as String?;
  }

  /// Get all topic categories
  static Future<List<Map<String, dynamic>>> getTopicCategories() async {
    final db = await database;
    return await db.query(
      'topic_categories',
      orderBy: 'sort_order ASC',
    );
  }

  /// Get topics for a specific category
  static Future<List<Map<String, dynamic>>> getTopicsForCategory(int categoryId) async {
    final db = await database;
    return await db.query(
      'topics',
      where: 'category_id = ?',
      whereArgs: [categoryId],
      orderBy: 'id ASC',
    );
  }

  /// Get all verses for a topic along with their Arabic text and Thai translation
  static Future<List<Map<String, dynamic>>> getVersesForTopic(int topicId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT v.*, tv.sort_order 
      FROM topic_verses tv
      JOIN verses v ON tv.verse_key = v.verse_key
      WHERE tv.topic_id = ?
      ORDER BY tv.sort_order ASC
    ''', [topicId]);
  }

  /// Search topics by Thai title, English title, or category name
  static Future<List<Map<String, dynamic>>> searchTopics(String query) async {
    final db = await database;
    final q = '%${query.trim().toLowerCase()}%';
    return await db.rawQuery('''
      SELECT t.*, c.title_th as category_title_th, c.icon_name as category_icon
      FROM topics t
      JOIN topic_categories c ON t.category_id = c.id
      WHERE LOWER(t.title_th) LIKE ? 
         OR LOWER(t.title_en) LIKE ? 
         OR LOWER(c.title_th) LIKE ?
      ORDER BY t.verses_count DESC
    ''', [q, q, q]);
  }

  /// Get all verses containing words with a specific root ('ر ح م', 'س م و')
  static Future<List<Map<String, dynamic>>> getVersesByRoot(String rootArabic) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT DISTINCT v.* 
      FROM words w
      JOIN verses v ON w.verse_key = v.verse_key
      WHERE w.root_arabic = ?
      ORDER BY v.surah_id ASC, v.verse_id ASC
    ''', [rootArabic]);
  }

  static Set<String>? _mutashabihatVerseKeySet;

  /// Preload / get all verse keys that have Mutashabihat
  static Future<Set<String>> getMutashabihatVerseKeys() async {
    if (_mutashabihatVerseKeySet != null) return _mutashabihatVerseKeySet!;
    try {
      final db = await database;
      final results = await db.rawQuery('SELECT DISTINCT verse_key FROM mutashabihat');
      _mutashabihatVerseKeySet = {
        for (final row in results)
          if (row['verse_key'] != null) row['verse_key'] as String,
      };
      return _mutashabihatVerseKeySet!;
    } catch (e) {
      debugPrint("Error loading mutashabihat keys: $e");
      return {};
    }
  }

  /// Synchronous check if a verse key has Mutashabihat
  static bool hasMutashabihatSync(String verseKey) {
    return _mutashabihatVerseKeySet?.contains(verseKey) ?? false;
  }

  /// Get all similar verses (Mutashabihat) for a specific verseKey ('2:48', etc.)
  static Future<List<Map<String, dynamic>>> getMutashabihat(String verseKey) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT v.*, m.context_type 
      FROM mutashabihat m
      JOIN verses v ON m.matched_verse_key = v.verse_key
      WHERE m.verse_key = ?
      GROUP BY m.matched_verse_key
      ORDER BY v.surah_id ASC, v.verse_id ASC
    ''', [verseKey]);
  }

  /// Check if a verse has any Mutashabihat
  static Future<int> getMutashabihatCount(String verseKey) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT COUNT(DISTINCT matched_verse_key) as count FROM mutashabihat WHERE verse_key = ?
    ''', [verseKey]);
    return (results.first['count'] as int?) ?? 0;
  }

  /// Get QUL Ayah Themes for a specific Surah
  static Future<List<Map<String, dynamic>>> getQulThemesForSurah(int surah) async {
    final db = await database;
    return await db.query(
      'qul_ayah_themes',
      where: 'surah = ?',
      whereArgs: [surah],
      orderBy: 'ayah_from ASC',
    );
  }

  /// Get QUL Ayah Theme for a specific verse
  static Future<Map<String, dynamic>?> getQulThemeForVerse(int surah, int ayah) async {
    final db = await database;
    final results = await db.query(
      'qul_ayah_themes',
      where: 'surah = ? AND ayah_from <= ? AND ayah_to >= ?',
      whereArgs: [surah, ayah, ayah],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get Tajweed text for a specific verse
  static Future<String?> getTajweedText(String verseKey) async {
    final db = await database;
    final results = await db.query(
      'verses',
      columns: ['text_tajweed'],
      where: 'verse_key = ?',
      whereArgs: [verseKey],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first['text_tajweed'] as String?;
  }

  /// Get 114 Surahs
  static Future<List<Map<String, dynamic>>> getSurahs() async {
    final db = await database;
    return await db.query('surahs', orderBy: 'id ASC');
  }

  /// Get metadata value by key
  static Future<String?> getMetadata(String key) async {
    final db = await database;
    final results = await db.query(
      'metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first['value'] as String?;
  }

  /// Dynamic Over-The-Air Update for Thai Translation
  /// Allows updating translation text without reinstalling or waiting for app store releases.
  static Future<bool> updateThaiTranslation(
    Map<String, String> newTranslations, {
    required String newVersion,
  }) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final entry in newTranslations.entries) {
          batch.update(
            'verses',
            {'translation_th': entry.value},
            where: 'verse_key = ?',
            whereArgs: [entry.key],
          );
        }
        batch.insert(
          'metadata',
          {
            'key': 'translation_th_version',
            'value': newVersion,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        batch.insert(
          'metadata',
          {
            'key': 'translation_th_updated_at',
            'value': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await batch.commit(noResult: true);
      });
      debugPrint("Successfully updated Thai translation to $newVersion");
      return true;
    } catch (e) {
      debugPrint("Error updating Thai translation: $e");
      return false;
    }
  }
}
