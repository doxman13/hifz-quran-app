import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_background_service/flutter_background_service.dart';
import '../data/translation_database.dart';
import '../services/offline_quran_database_service.dart';
import '../shared/translation_constants.dart';

class TranslationManagerProvider extends ChangeNotifier {
  final TranslationDatabase _db = TranslationDatabase.instance;
  
  List<Map<String, dynamic>> _downloadedTranslations = [];
  final Map<dynamic, Map<String, String>> _activeTranslationsCache = {};
  final Set<dynamic> _loadingIds = {}; // Track currently loading IDs
  final Map<int, double> _downloadProgress = {};

  List<Map<String, dynamic>> get downloadedTranslations => _downloadedTranslations;
  Set<dynamic> get loadingIds => _loadingIds;
  Map<int, double> get downloadProgress => _downloadProgress;

  TranslationManagerProvider() {
    refreshDownloadedList();
    _initBackgroundServiceListener();
  }

  void _initBackgroundServiceListener() {
    try {
      if (kIsWeb) return;
      if (!Platform.isAndroid && !Platform.isIOS) return;
      final service = FlutterBackgroundService();

      service.on('update_progress').listen((event) {
        final id = event?['id'] as int?;
        final progress = event?['progress'] as double?;
        if (id != null && progress != null) {
          _downloadProgress[id] = progress;
          _loadingIds.add(id);
          notifyListeners();
        }
      });

      service.on('download_success').listen((event) async {
        final id = event?['id'] as int?;
        if (id != null) {
          _downloadProgress.remove(id);
          _loadingIds.remove(id);
          await refreshDownloadedList();
        }
      });

      service.on('download_failed').listen((event) {
        final id = event?['id'] as int?;
        if (id != null) {
          _downloadProgress.remove(id);
          _loadingIds.remove(id);
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('Background service listener not initialized: $e');
    }
  }

  Future<void> startBackgroundDownload({
    required int id,
    required String name,
    required String author,
    required String language,
  }) async {
    if (_loadingIds.contains(id)) return;

    _loadingIds.add(id);
    _downloadProgress[id] = 0.0;
    notifyListeners();

    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      // Give it some time to spawn and connect
      await Future.delayed(const Duration(milliseconds: 650));
    }

    service.invoke('start_download', {
      'id': id,
      'name': name,
      'author': author,
      'language': language,
    });
  }

  Future<void> refreshDownloadedList() async {
    try {
      _downloadedTranslations = await _db.getDownloadedTranslations();
      notifyListeners();
    } catch (e) {
      debugPrint('Could not refresh downloaded translations: $e');
    }
  }

  bool isDownloaded(dynamic id) {
    if (id == null) return false;
    if (TranslationConstants.isBuiltIn(id)) return true;
    final apiId = TranslationConstants.resolveApiId(id);
    final canonicalId = TranslationConstants.resolveTranslationId(id);
    return _downloadedTranslations.any((t) {
      final tId = t['id'];
      return tId == apiId ||
          tId.toString() == canonicalId ||
          tId.toString() == id.toString();
    });
  }

  /// Load a translation into memory cache if not already loaded.
  Future<void> loadTranslationIntoCache(dynamic id) async {
    if (id == null) return;
    final canonicalId = TranslationConstants.resolveTranslationId(id);
    final apiId = TranslationConstants.resolveApiId(id);

    if (_activeTranslationsCache.containsKey(id) ||
        _activeTranslationsCache.containsKey(canonicalId) ||
        (apiId != null && _activeTranslationsCache.containsKey(apiId))) {
      return;
    }
    if (_loadingIds.contains(id) || _loadingIds.contains(canonicalId)) return; // Prevent duplicate concurrent loads!
    
    _loadingIds.add(id);
    _loadingIds.add(canonicalId);
    try {
      Map<String, String> verses = {};

      if (canonicalId == 'en_usmani' || canonicalId == 'english') {
        try {
          final jsonStr = await rootBundle.loadString('assets/en_usmani.json');
          final decoded = json.decode(jsonStr) as Map<String, dynamic>;
          verses = decoded.map((k, v) => MapEntry(k, v.toString()));
        } catch (_) {
          verses = await OfflineQuranDatabaseService.getAllTranslations(lang: 'en');
        }
      } else if (canonicalId == 'ms_basmeih' || canonicalId == 'malay') {
        try {
          final jsonStr = await rootBundle.loadString('assets/ms_basmeih.json');
          final decoded = json.decode(jsonStr) as Map<String, dynamic>;
          verses = decoded.map((k, v) => MapEntry(k, v.toString()));
        } catch (_) {
          verses = await OfflineQuranDatabaseService.getAllTranslations(lang: 'ms');
        }
      } else if (canonicalId == 'thai_v3' || canonicalId == 'th') {
        verses = await OfflineQuranDatabaseService.getAllTranslations(lang: 'th');
      } else if (apiId != null) {
        verses = await _db.getAllVersesForTranslation(apiId);
      }

      if (verses.isNotEmpty) {
        _activeTranslationsCache[id] = verses;
        _activeTranslationsCache[canonicalId] = verses;
        if (apiId != null) {
          _activeTranslationsCache[apiId] = verses;
          _activeTranslationsCache[apiId.toString()] = verses;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading translation $id into cache: $e');
    } finally {
      _loadingIds.remove(id);
      _loadingIds.remove(canonicalId);
    }
  }

  /// Remove from memory cache if no longer needed.
  void removeTranslationFromCache(dynamic id) {
    if (id == null) return;
    final canonicalId = TranslationConstants.resolveTranslationId(id);
    final apiId = TranslationConstants.resolveApiId(id);

    _activeTranslationsCache.remove(id);
    _activeTranslationsCache.remove(id.toString());
    _activeTranslationsCache.remove(canonicalId);
    if (apiId != null) {
      _activeTranslationsCache.remove(apiId);
      _activeTranslationsCache.remove(apiId.toString());
    }
    _loadingIds.remove(id);
    _loadingIds.remove(canonicalId);
  }

  /// Get the translation text synchronously from memory.
  /// If it is not in the cache, it schedules a lazy load and returns null.
  String? getVerseTranslation(dynamic id, String verseKey) {
    if (id == null) return null;
    final canonicalId = TranslationConstants.resolveTranslationId(id);
    final apiId = TranslationConstants.resolveApiId(id);

    if (_activeTranslationsCache.containsKey(id)) {
      return _activeTranslationsCache[id]?[verseKey];
    }
    if (_activeTranslationsCache.containsKey(canonicalId)) {
      return _activeTranslationsCache[canonicalId]?[verseKey];
    }
    if (apiId != null && _activeTranslationsCache.containsKey(apiId)) {
      return _activeTranslationsCache[apiId]?[verseKey];
    }

    loadTranslationIntoCache(id);
    return null;
  }

  Future<void> deleteTranslation(int id) async {
    await _db.removeTranslation(id);
    removeTranslationFromCache(id);
    await refreshDownloadedList();
  }
}
