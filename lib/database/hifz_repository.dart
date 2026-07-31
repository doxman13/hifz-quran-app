// lib/database/hifz_repository.dart
//
// Local persistence layer for Hifz session state and Surah completion records.
// Uses sqflite (already in pubspec.yaml) for on-device SQLite storage.
// All methods are async and fire-and-forget safe for the auto-save use case.

import 'dart:convert';
import 'dart:math' as math;

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/hifz_session_config.dart';

class HifzRepository {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------
  static final HifzRepository _instance = HifzRepository._internal();
  factory HifzRepository() => _instance;
  HifzRepository._internal();

  Database? _db;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<Database> get database async {
    _db ??= await _openDatabase();
    return _db!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'hifz_database.db');

    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE active_session (
        session_id TEXT PRIMARY KEY,
        session_type TEXT NOT NULL,
        review_granularity TEXT,
        target_params_json TEXT,
        nv_surah_number INTEGER,
        nv_repeat_start INTEGER,
        nv_start_verse INTEGER,
        nv_end_verse INTEGER,
        current_step_index INTEGER NOT NULL DEFAULT 0,
        current_mode TEXT NOT NULL DEFAULT 'visible',
        current_tally INTEGER NOT NULL DEFAULT 0,
        target_tally INTEGER NOT NULL DEFAULT 10,
        last_updated_timestamp INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE completed_surahs (
        surah_number INTEGER PRIMARY KEY,
        new_verses_completed INTEGER NOT NULL DEFAULT 0,
        review_count INTEGER NOT NULL DEFAULT 0,
        last_completed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE hifz_history (
        id TEXT PRIMARY KEY,
        session_type TEXT NOT NULL,
        surah_number INTEGER,
        title TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        synced_to_cloud INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute('DROP TABLE IF EXISTS hifz_history');
      await db.execute('''
        CREATE TABLE hifz_history (
          id TEXT PRIMARY KEY,
          session_type TEXT NOT NULL,
          surah_number INTEGER,
          title TEXT NOT NULL,
          completed_at TEXT NOT NULL,
          synced_to_cloud INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
  }

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  Future<void> recordHistory(HifzSessionType type, String title, {int? surahNumber}) async {
    try {
      final db = await database;
      final id = const Uuid().v4();
      await db.insert('hifz_history', {
        'id': id,
        'session_type': type.name,
        'surah_number': surahNumber,
        'title': title,
        'completed_at': DateTime.now().toIso8601String(),
        'synced_to_cloud': 0,
      });
      _pushHistoryToSupabaseIfLoggedIn();
    } catch (e) {
      debugLog('HifzRepository.recordHistory error: $e');
    }
  }

  Future<List<HifzHistoryRecord>> getHistory({int limit = 50}) async {
    try {
      final db = await database;
      final rows = await db.query(
        'hifz_history',
        orderBy: 'completed_at DESC',
        limit: limit,
      );
      return rows.map((r) => HifzHistoryRecord(
        id: r['id'] as String,
        sessionType: HifzSessionType.values.firstWhere((e) => e.name == r['session_type']),
        surahNumber: r['surah_number'] as int?,
        title: r['title'] as String,
        completedAt: DateTime.parse(r['completed_at'] as String),
      )).toList();
    } catch (e) {
      debugLog('HifzRepository.getHistory error: $e');
      return [];
    }
  }

  Future<void> deleteHistory(String id) async {
    try {
      final db = await database;
      await db.delete('hifz_history', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugLog('HifzRepository.deleteHistory error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Active Session CRUD
  // ---------------------------------------------------------------------------

  /// Saves or replaces the current active session snapshot.
  /// This is called on every tally increment — fire-and-forget safe.
  Future<void> saveActiveSession(ActiveSessionSnapshot snapshot) async {
    try {
      final db = await database;
      await db.insert(
        'active_session',
        _snapshotToRow(snapshot),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      // Never throw on auto-save — log and continue.
      debugLog('HifzRepository.saveActiveSession error: $e');
    }
  }

  /// Loads the most recently saved active session, if any.
  Future<ActiveSessionSnapshot?> loadActiveSession() async {
    try {
      final db = await database;
      final rows = await db.query(
        'active_session',
        orderBy: 'last_updated_timestamp DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _rowToSnapshot(rows.first);
    } catch (e) {
      debugLog('HifzRepository.loadActiveSession error: $e');
      return null;
    }
  }
  /// Loads the most recently saved active session matching the specific configuration.
  Future<ActiveSessionSnapshot?> loadActiveSessionByConfig({
    required HifzSessionType sessionType,
    int? nvSurahNumber,
    int? nvStartVerse,
    int? nvEndVerse,
    ReviewGranularity? reviewGranularity,
    ReviewTargetParams? reviewTargetParams,
  }) async {
    try {
      final db = await database;
      if (sessionType == HifzSessionType.newVerses) {
        final rows = await db.query(
          'active_session',
          where: 'session_type = ? AND nv_surah_number = ? AND nv_start_verse = ? AND nv_end_verse = ?',
          whereArgs: [sessionType.name, nvSurahNumber, nvStartVerse, nvEndVerse],
          orderBy: 'last_updated_timestamp DESC',
          limit: 1,
        );
        if (rows.isEmpty) return null;
        return _rowToSnapshot(rows.first);
      } else {
        final rows = await db.query(
          'active_session',
          where: 'session_type = ? AND review_granularity = ?',
          whereArgs: [sessionType.name, reviewGranularity?.name],
          orderBy: 'last_updated_timestamp DESC',
        );
        for (final row in rows) {
          final snap = _rowToSnapshot(row);
          if (_areParamsEqual(snap.reviewTargetParams, reviewTargetParams)) {
            return snap;
          }
        }
        return null;
      }
    } catch (e) {
      debugLog('HifzRepository.loadActiveSessionByConfig error: $e');
      return null;
    }
  }

  bool _areParamsEqual(ReviewTargetParams? a, ReviewTargetParams? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.startSurah == b.startSurah &&
        a.endSurah == b.endSurah &&
        a.surahNumber == b.surahNumber &&
        a.startVerse == b.startVerse &&
        a.endVerse == b.endVerse &&
        a.startPage == b.startPage &&
        a.endPage == b.endPage;
  }

  /// Deletes active session (either specific ID or all).
  Future<void> clearActiveSession({String? sessionId}) async {
    try {
      final db = await database;
      if (sessionId != null) {
        await db.delete('active_session', where: 'session_id = ?', whereArgs: [sessionId]);
      } else {
        await db.delete('active_session');
      }
    } catch (e) {
      debugLog('HifzRepository.clearActiveSession error: $e');
    }
  }

  /// Fetches all active sessions.
  Future<List<ActiveSessionSnapshot>> getAllActiveSessions() async {
    try {
      final db = await database;
      final rows = await db.query(
        'active_session',
        orderBy: 'last_updated_timestamp DESC',
      );
      return rows.map(_rowToSnapshot).toList();
    } catch (e) {
      debugLog('HifzRepository.getAllActiveSessions error: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Surah Completion Records
  // ---------------------------------------------------------------------------

  /// Marks a Surah's New Verses routine as completed (sets new_verses_completed = 1).
  Future<void> markNewVersesCompleted(int surahNumber) async {
    try {
      final db = await database;
      final existing = await _getCompletionRow(db, surahNumber);
      if (existing == null) {
        await db.insert('completed_surahs', {
          'surah_number': surahNumber,
          'new_verses_completed': 1,
          'review_count': 0,
          'last_completed_at': DateTime.now().toIso8601String(),
        });
      } else {
        await db.update(
          'completed_surahs',
          {
            'new_verses_completed': 1,
            'last_completed_at': DateTime.now().toIso8601String(),
          },
          where: 'surah_number = ?',
          whereArgs: [surahNumber],
        );
      }
      
      // Push update to cloud if logged in
      _pushToSupabaseIfLoggedIn(surahNumber);
    } catch (e) {
      debugLog('HifzRepository.markNewVersesCompleted error: $e');
    }
  }

  /// Increments the review_count for a Surah.
  Future<void> incrementReviewCount(int surahNumber) async {
    try {
      final db = await database;
      final existing = await _getCompletionRow(db, surahNumber);
      if (existing == null) {
        await db.insert('completed_surahs', {
          'surah_number': surahNumber,
          'new_verses_completed': 0,
          'review_count': 1,
          'last_completed_at': DateTime.now().toIso8601String(),
        });
      } else {
        final currentCount = (existing['review_count'] as int?) ?? 0;
        await db.update(
          'completed_surahs',
          {
            'review_count': currentCount + 1,
            'last_completed_at': DateTime.now().toIso8601String(),
          },
          where: 'surah_number = ?',
          whereArgs: [surahNumber],
        );
      }

      // Push update to cloud if logged in
      _pushToSupabaseIfLoggedIn(surahNumber);
    } catch (e) {
      debugLog('HifzRepository.incrementReviewCount error: $e');
    }
  }

  /// Fetches the completion record for a single Surah, or null if not started.
  Future<SurahCompletionRecord?> getCompletionRecord(int surahNumber) async {
    try {
      final db = await database;
      final row = await _getCompletionRow(db, surahNumber);
      if (row == null) return null;
      return _rowToCompletionRecord(row);
    } catch (e) {
      debugLog('HifzRepository.getCompletionRecord error: $e');
      return null;
    }
  }

  /// Fetches all 114 Surah completion records that have any data in DB.
  Future<List<SurahCompletionRecord>> getAllCompletionRecords() async {
    try {
      final db = await database;
      final rows = await db.query(
        'completed_surahs',
        orderBy: 'surah_number ASC',
      );
      return rows.map(_rowToCompletionRecord).toList();
    } catch (e) {
      debugLog('HifzRepository.getAllCompletionRecords error: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Supabase Cloud Sync
  // ---------------------------------------------------------------------------

  /// Syncs local SQLite progress with Supabase `hifz_progress`.
  /// Call this when the user logs in or periodically.
  Future<void> syncWithSupabase(String userId) async {
    try {
      final supabase = Supabase.instance.client;
      // 1. Fetch cloud data
      final List<dynamic> cloudData = await supabase
          .from('hifz_progress')
          .select()
          .eq('user_id', userId);
      
      final db = await database;
      
      // 2. Load all local data
      final localRecords = await getAllCompletionRecords();
      final Map<int, SurahCompletionRecord> localMap = {
        for (var r in localRecords) r.surahNumber: r
      };

      final Map<int, dynamic> cloudMap = {
        for (var row in cloudData) row['surah_number'] as int: row
      };

      // 3. Merge: Take the max of review_count, and boolean OR for new_verses_completed.
      final Set<int> allSurahs = {...localMap.keys, ...cloudMap.keys};
      
      for (final surah in allSurahs) {
        final local = localMap[surah];
        final cloud = cloudMap[surah];

        final localNewVerses = local?.newVersesCompleted ?? false;
        final cloudNewVerses = (cloud?['new_verses_completed'] as bool?) ?? false;
        final mergedNewVerses = localNewVerses || cloudNewVerses;

        final localReviewCount = local?.reviewCount ?? 0;
        final cloudReviewCount = (cloud?['review_count'] as int?) ?? 0;
        final mergedReviewCount = math.max(localReviewCount, cloudReviewCount);

        final needsLocalUpdate = local == null ||
            local.newVersesCompleted != mergedNewVerses ||
            local.reviewCount != mergedReviewCount;

        final needsCloudUpdate = cloud == null ||
            (cloud['new_verses_completed'] as bool? ?? false) != mergedNewVerses ||
            (cloud['review_count'] as int? ?? 0) != mergedReviewCount;

        // Update local
        if (needsLocalUpdate) {
          if (local == null) {
            await db.insert('completed_surahs', {
              'surah_number': surah,
              'new_verses_completed': mergedNewVerses ? 1 : 0,
              'review_count': mergedReviewCount,
              'last_completed_at': DateTime.now().toIso8601String(),
            });
          } else {
            await db.update(
              'completed_surahs',
              {
                'new_verses_completed': mergedNewVerses ? 1 : 0,
                'review_count': mergedReviewCount,
                'last_completed_at': DateTime.now().toIso8601String(),
              },
              where: 'surah_number = ?',
              whereArgs: [surah],
            );
          }
        }

        // Update cloud
        if (needsCloudUpdate) {
          await supabase.from('hifz_progress').upsert({
            'user_id': userId,
            'surah_number': surah,
            'new_verses_completed': mergedNewVerses,
            'review_count': mergedReviewCount,
            'last_completed_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id,surah_number');
        }
      }
    } catch (e) {
      debugLog('HifzRepository.syncWithSupabase error: $e');
    }
  }

  /// Pushes a specific surah update to Supabase if logged in.
  Future<void> _pushToSupabaseIfLoggedIn(int surahNumber) async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      if (session == null) return;
      
      final db = await database;
      final row = await _getCompletionRow(db, surahNumber);
      if (row != null) {
        await supabase.from('hifz_progress').upsert({
          'user_id': session.user.id,
          'surah_number': surahNumber,
          'new_verses_completed': (row['new_verses_completed'] as int) == 1,
          'review_count': row['review_count'] as int,
          'last_completed_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,surah_number');
      }
    } catch (e) {
      debugLog('HifzRepository._pushToSupabaseIfLoggedIn error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>?> _getCompletionRow(
      Database db, int surahNumber) async {
    final rows = await db.query(
      'completed_surahs',
      where: 'surah_number = ?',
      whereArgs: [surahNumber],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Map<String, dynamic> _snapshotToRow(ActiveSessionSnapshot s) {
    final Map<String, dynamic> row = {
      'session_id': s.sessionId,
      'session_type': s.sessionType.name,
      'review_granularity': s.reviewGranularity?.name,
      'target_params_json':
          s.reviewTargetParams != null ? jsonEncode(s.reviewTargetParams!.toJson()) : null,
      'nv_surah_number': s.nvSurahNumber,
      'nv_repeat_start': s.nvRepeatStart,
      'nv_start_verse': s.nvStartVerse,
      'nv_end_verse': s.nvEndVerse,
      'current_step_index': s.currentStepIndex,
      'current_mode': s.currentMode,
      'current_tally': s.currentTally,
      'target_tally': s.targetTally,
      'last_updated_timestamp': s.lastUpdatedTimestamp,
    };
    return row;
  }

  ActiveSessionSnapshot _rowToSnapshot(Map<String, Object?> row) {
    final sessionTypeStr = row['session_type'] as String? ?? 'newVerses';
    final sessionType = HifzSessionType.values.firstWhere(
      (e) => e.name == sessionTypeStr,
      orElse: () => HifzSessionType.newVerses,
    );

    ReviewGranularity? granularity;
    final granStr = row['review_granularity'] as String?;
    if (granStr != null) {
      granularity = ReviewGranularity.values.firstWhere(
        (e) => e.name == granStr,
        orElse: () => ReviewGranularity.bySurah,
      );
    }

    ReviewTargetParams? targetParams;
    final paramsJson = row['target_params_json'] as String?;
    if (paramsJson != null) {
      try {
        targetParams = ReviewTargetParams.fromJson(
            jsonDecode(paramsJson) as Map<String, dynamic>);
      } catch (_) {}
    }

    return ActiveSessionSnapshot(
      sessionId: row['session_id'] as String,
      sessionType: sessionType,
      nvSurahNumber: row['nv_surah_number'] as int?,
      nvRepeatStart: row['nv_repeat_start'] as int?,
      nvStartVerse: row['nv_start_verse'] as int?,
      nvEndVerse: row['nv_end_verse'] as int?,
      reviewGranularity: granularity,
      reviewTargetParams: targetParams,
      currentStepIndex: (row['current_step_index'] as int?) ?? 0,
      currentMode: (row['current_mode'] as String?) ?? 'visible',
      currentTally: (row['current_tally'] as int?) ?? 0,
      targetTally: (row['target_tally'] as int?) ?? 10,
      lastUpdatedTimestamp: (row['last_updated_timestamp'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
  // ---------------------------------------------------------------------------
  // Supabase Syncing (History)
  // ---------------------------------------------------------------------------

  Future<void> syncHistoryWithSupabase() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final db = await database;

      // 1. Push un-synced local history records
      final unSynced = await db.query('hifz_history', where: 'synced_to_cloud = 0');
      
      if (unSynced.isNotEmpty) {
        final payload = unSynced.map((row) => {
          'id': row['id'],
          'user_id': userId,
          'session_type': row['session_type'],
          'surah_number': row['surah_number'],
          'title': row['title'],
          'completed_at': row['completed_at'],
        }).toList();

        await supabase.from('hifz_history').upsert(payload, onConflict: 'id');

        // Mark as synced locally
        final ids = unSynced.map((r) => "'${r['id']}'").join(',');
        await db.execute('UPDATE hifz_history SET synced_to_cloud = 1 WHERE id IN ($ids)');
      }

      // 2. Pull history records from cloud
      final cloudData = await supabase
          .from('hifz_history')
          .select('id, session_type, surah_number, title, completed_at')
          .eq('user_id', userId);

      // Insert or replace local rows to match cloud exactly (to sync across devices)
      for (final row in cloudData) {
        await db.insert('hifz_history', {
          'id': row['id'],
          'session_type': row['session_type'],
          'surah_number': row['surah_number'],
          'title': row['title'],
          'completed_at': row['completed_at'],
          'synced_to_cloud': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    } catch (e) {
      debugLog('HifzRepository.syncHistoryWithSupabase error: $e');
    }
  }

  void _pushHistoryToSupabaseIfLoggedIn() {
    if (Supabase.instance.client.auth.currentUser != null) {
      syncHistoryWithSupabase();
    }
  }


  SurahCompletionRecord _rowToCompletionRecord(Map<String, Object?> row) =>
      SurahCompletionRecord(
        surahNumber: row['surah_number'] as int,
        newVersesCompleted: (row['new_verses_completed'] as int?) == 1,
        reviewCount: (row['review_count'] as int?) ?? 0,
        lastCompletedAt: row['last_completed_at'] as String?,
      );

  void debugLog(String msg) {
    // ignore: avoid_print
    print('[HifzRepository] $msg');
  }
}
