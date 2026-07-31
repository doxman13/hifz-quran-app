import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class TranslationDatabase {
  static final TranslationDatabase instance = TranslationDatabase._init();
  static Database? _database;

  TranslationDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('translations.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE translations (
        id INTEGER PRIMARY KEY,
        name TEXT,
        author_name TEXT,
        language_name TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE verses (
        translation_id INTEGER,
        verse_key TEXT,
        text TEXT,
        PRIMARY KEY (translation_id, verse_key)
      )
    ''');
  }

  Future<void> addTranslation(
    int id,
    String name,
    String author,
    String language,
  ) async {
    final db = await instance.database;
    await db.insert('translations', {
      'id': id,
      'name': name,
      'author_name': author,
      'language_name': language,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeTranslation(int id) async {
    final db = await instance.database;
    await db.delete('translations', where: 'id = ?', whereArgs: [id]);
    await db.delete('verses', where: 'translation_id = ?', whereArgs: [id]);
  }

  Future<void> insertVerses(
    int translationId,
    Map<String, String> versesMap,
  ) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final entry in versesMap.entries) {
      batch.insert('verses', {
        'translation_id': translationId,
        'verse_key': entry.key,
        'text': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<String?> getVerseTranslation(
    int translationId,
    String verseKey,
  ) async {
    final db = await instance.database;
    final maps = await db.query(
      'verses',
      columns: ['text'],
      where: 'translation_id = ? AND verse_key = ?',
      whereArgs: [translationId, verseKey],
    );

    if (maps.isNotEmpty) {
      return maps.first['text'] as String?;
    } else {
      return null;
    }
  }

  Future<Map<String, String>> getAllVersesForTranslation(
    int translationId,
  ) async {
    final db = await instance.database;
    final maps = await db.query(
      'verses',
      columns: ['verse_key', 'text'],
      where: 'translation_id = ?',
      whereArgs: [translationId],
    );

    return {
      for (final map in maps) map['verse_key'] as String: map['text'] as String,
    };
  }

  Future<List<Map<String, dynamic>>> getDownloadedTranslations() async {
    final db = await instance.database;
    return db.query('translations');
  }

  Future<bool> isDownloaded(int id) async {
    final db = await instance.database;
    final maps = await db.query(
      'translations',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return maps.isNotEmpty;
  }
}
