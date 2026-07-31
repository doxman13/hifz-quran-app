import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'remote_content_cache.dart';

class RemoteContentKey {
  static const thaiV3 = 'thai_v3';
  static const quranThemes = 'quran_themes';
  static const mokhtasarTafsir = 'mokhtasar_short_tafsir';

  static const all = [thaiV3, quranThemes, mokhtasarTafsir];
}

class RemoteContentUpdateResult {
  final int checked;
  final int updated;
  final List<String> failedKeys;

  const RemoteContentUpdateResult({
    required this.checked,
    required this.updated,
    required this.failedKeys,
  });

  bool get hasFailures => failedKeys.isNotEmpty;
}

class RemoteContentService {
  static final RemoteContentService instance = RemoteContentService._();

  RemoteContentService._();

  final RemoteContentCache _cache = RemoteContentCache();

  static const _versionPrefix = 'remoteContentVersion_';
  static const _lastAutoCheckKey = 'remoteContentLastAutoCheckAt';
  static const _defaultBucket = 'app-content';
  static const _autoCheckInterval = Duration(hours: 24);

  Future<String> loadString({
    required String contentKey,
    required String bundledAssetPath,
  }) async {
    try {
      final content = await _cache.readContent(contentKey);
      if (content != null) {
        jsonDecode(content);
        return content;
      }
    } catch (_) {
      // Fall back to the bundled asset if the cached file is missing/corrupt.
    }

    return rootBundle.loadString(bundledAssetPath);
  }

  Future<RemoteContentUpdateResult> updateAll() async {
    var checked = 0;
    var updated = 0;
    final failedKeys = <String>[];

    for (final key in RemoteContentKey.all) {
      checked += 1;
      try {
        final didUpdate = await updateOne(key);
        if (didUpdate) updated += 1;
      } catch (_) {
        failedKeys.add(key);
      }
    }

    return RemoteContentUpdateResult(
      checked: checked,
      updated: updated,
      failedKeys: failedKeys,
    );
  }

  Future<RemoteContentUpdateResult?> updateAllIfDue() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = DateTime.tryParse(
      prefs.getString(_lastAutoCheckKey) ?? '',
    );
    final now = DateTime.now();
    if (lastCheck != null && now.difference(lastCheck) < _autoCheckInterval) {
      return null;
    }

    await prefs.setString(_lastAutoCheckKey, now.toIso8601String());
    return updateAll();
  }

  Future<bool> updateOne(String contentKey) async {
    final client = Supabase.instance.client;
    final manifest = await client
        .from('app_content_versions')
        .select('version, storage_bucket, storage_path')
        .eq('content_key', contentKey)
        .eq('is_active', true)
        .maybeSingle();

    if (manifest == null) return false;

    final version = manifest['version']?.toString();
    final storagePath = manifest['storage_path']?.toString();
    final bucket = manifest['storage_bucket']?.toString() ?? _defaultBucket;
    if (version == null ||
        version.isEmpty ||
        storagePath == null ||
        storagePath.isEmpty) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final localVersion = prefs.getString('$_versionPrefix$contentKey');
    if (localVersion == version) return false;

    final bytes = await client.storage.from(bucket).download(storagePath);
    final content = utf8.decode(bytes);
    jsonDecode(content);

    await _cache.writeContent(contentKey, content);
    await prefs.setString('$_versionPrefix$contentKey', version);
    return true;
  }
}
