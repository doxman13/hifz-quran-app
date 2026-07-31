// lib/providers/stats_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StatsProvider extends ChangeNotifier {
  static const String _historyKey = 'reading_history_v1';

  // Date string YYYY-MM-DD -> Set of "surahId:verseId"
  Map<String, Set<String>> _history = {};
  Timer? _saveTimer;
  Timer? _remoteSyncTimer;
  StreamSubscription<AuthState>? _authSubscription;
  late final Future<void> _loadFuture;

  StatsProvider() {
    _loadFuture = _loadHistory();
    unawaited(_syncExistingSessionAfterLoad());
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      await _loadFuture;
      final user = data.session?.user;
      if (user != null) {
        unawaited(syncWithSupabase(user.id));
      }
    });
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString(_historyKey);
      if (savedData != null) {
        final Map<String, dynamic> decoded = json.decode(savedData);
        _history = decoded.map((date, list) {
          final set = (list as List).map((e) => e.toString()).toSet();
          return MapEntry(date, set);
        });
      }
    } catch (e) {
      debugPrint('Error loading stats history: $e');
    }
    notifyListeners();
  }

  String _getDateString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> logVerseRead(String surahId, String verseId) async {
    final dateStr = _getDateString(DateTime.now());
    final verseKey = '$surahId:$verseId';

    _history.putIfAbsent(dateStr, () => {});
    if (_history[dateStr]!.contains(verseKey)) return; // already logged

    _history[dateStr]!.add(verseKey);
    notifyListeners();

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () async {
      await flushPendingSave();
    });
    _debounceRemoteSync();
  }

  Future<void> _syncExistingSessionAfterLoad() async {
    await _loadFuture;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await syncWithSupabase(user.id);
    } catch (e) {
      debugPrint('Error syncing stats existing session: $e');
    }
  }

  void _debounceRemoteSync() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    _remoteSyncTimer?.cancel();
    _remoteSyncTimer = Timer(const Duration(seconds: 3), () async {
      try {
        await syncWithSupabase(user.id);
      } catch (e) {
        debugPrint('Error syncing stats history after read: $e');
      }
    });
  }

  Future<void> flushPendingSave() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final mapToSave = _history.map(
        (date, set) => MapEntry(date, set.toList()),
      );
      await prefs.setString(_historyKey, json.encode(mapToSave));
    } catch (e) {
      debugPrint('Error saving stats history: $e');
    }
  }

  Future<void> syncWithSupabase(String userId) async {
    await flushPendingSave();
    final client = Supabase.instance.client;
    try {
      final rows = await client
          .from('user_reading_history')
          .select('read_date, surah_id, verse_id')
          .eq('user_id', userId);

      var changed = false;
      for (final raw in rows.whereType<Map>()) {
        final row = raw.cast<String, dynamic>();
        final readDate = row['read_date']?.toString();
        final surahId = row['surah_id']?.toString();
        final verseId = row['verse_id']?.toString();
        if (readDate == null || surahId == null || verseId == null) {
          continue;
        }
        final dateKey = readDate.split('T').first;
        final verseKey = '$surahId:$verseId';
        _history.putIfAbsent(dateKey, () => {});
        if (_history[dateKey]!.add(verseKey)) {
          changed = true;
        }
      }

      final upsertRows = <Map<String, dynamic>>[];
      for (final entry in _history.entries) {
        for (final verseKey in entry.value) {
          final parts = verseKey.split(':');
          if (parts.length != 2) continue;
          upsertRows.add({
            'user_id': userId,
            'read_date': entry.key,
            'surah_id': parts[0],
            'verse_id': parts[1],
          });
        }
      }

      if (upsertRows.isNotEmpty) {
        await client
            .from('user_reading_history')
            .upsert(upsertRows, onConflict: 'user_id,read_date,verse_key');
      }

      if (changed) {
        await flushPendingSave();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error syncing stats history with Supabase: $e');
      rethrow;
    }
  }

  int get todayReadCount {
    final todayStr = _getDateString(DateTime.now());
    return _history[todayStr]?.length ?? 0;
  }

  bool hasReadOn(DateTime date) {
    return _history[_getDateString(date)]?.isNotEmpty ?? false;
  }

  int get weekReadCount {
    final now = DateTime.now();
    final uniqueVerses = <String>{};
    for (int i = 0; i < 7; i++) {
      final dateStr = _getDateString(now.subtract(Duration(days: i)));
      if (_history.containsKey(dateStr)) {
        uniqueVerses.addAll(_history[dateStr]!);
      }
    }
    return uniqueVerses.length;
  }

  int get monthReadCount {
    final now = DateTime.now();
    final uniqueVerses = <String>{};
    for (int i = 0; i < 30; i++) {
      final dateStr = _getDateString(now.subtract(Duration(days: i)));
      if (_history.containsKey(dateStr)) {
        uniqueVerses.addAll(_history[dateStr]!);
      }
    }
    return uniqueVerses.length;
  }

  int get streakCount {
    if (_history.isEmpty) return 0;

    final today = DateTime.now();
    final todayStr = _getDateString(today);
    final yesterdayStr = _getDateString(
      today.subtract(const Duration(days: 1)),
    );

    // If no reading today and no reading yesterday, streak is broken/0
    bool readToday =
        _history.containsKey(todayStr) && _history[todayStr]!.isNotEmpty;
    bool readYesterday =
        _history.containsKey(yesterdayStr) &&
        _history[yesterdayStr]!.isNotEmpty;

    if (!readToday && !readYesterday) {
      return 0;
    }

    int streak = 0;
    DateTime checkDate = readToday
        ? today
        : today.subtract(const Duration(days: 1));

    while (true) {
      final checkStr = _getDateString(checkDate);
      if (_history.containsKey(checkStr) && _history[checkStr]!.isNotEmpty) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    return streak;
  }

  @override
  void dispose() {
    if (_saveTimer != null && _saveTimer!.isActive) {
      _saveTimer!.cancel();
      try {
        SharedPreferences.getInstance().then((prefs) {
          final mapToSave = _history.map(
            (date, set) => MapEntry(date, set.toList()),
          );
          prefs.setString(_historyKey, json.encode(mapToSave));
        });
      } catch (e) {
        debugPrint('Error saving stats history on dispose: $e');
      }
    }
    _remoteSyncTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
