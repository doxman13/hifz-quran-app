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

class RemoteContentBundledVersions {
  static const Map<String, String> versions = {
    RemoteContentKey.thaiV3: '1.0.2',
    RemoteContentKey.quranThemes: '1.0.0',
    RemoteContentKey.mokhtasarTafsir: '1.0.0',
  };
}

int compareVersions(String v1, String v2) {
  final parts1 = v1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final parts2 = v2.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final maxLength = parts1.length > parts2.length ? parts1.length : parts2.length;
  for (var i = 0; i < maxLength; i++) {
    final p1 = i < parts1.length ? parts1[i] : 0;
    final p2 = i < parts2.length ? parts2[i] : 0;
    if (p1 > p2) return 1;
    if (p1 < p2) return -1;
  }
  return 0;
}

class RemoteContentService {
  static final RemoteContentService instance = RemoteContentService._();

  RemoteContentService._();

  final RemoteContentCache _cache = RemoteContentCache();

  static const int appBuildCode = 17;
  static const _versionPrefix = 'remoteContentVersion_';
  static const _lastAutoCheckKey = 'remoteContentLastAutoCheckAt';
  static const _lastKnownBuildKey = 'lastKnownAppBuildCode';
  static const _defaultBucket = 'app-content';
  static const _autoCheckInterval = Duration(hours: 24);

  /// Automatically wipes all downloaded .json cache whenever the app itself is updated to a new build.
  Future<void> cleanOnAppUpgrade() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastKnownBuild = prefs.getInt(_lastKnownBuildKey) ?? 0;
      if (lastKnownBuild < appBuildCode) {
        await _cache.clearAll();
        for (final key in RemoteContentKey.all) {
          await prefs.remove('$_versionPrefix$key');
        }
        await prefs.setInt(_lastKnownBuildKey, appBuildCode);
      }
    } catch (_) {}
  }

  Future<String> loadString({
    required String contentKey,
    required String bundledAssetPath,
  }) async {
    try {
      final bundledVersion =
          RemoteContentBundledVersions.versions[contentKey] ?? '1.0.0';
      final prefs = await SharedPreferences.getInstance();
      final localCachedVersion = prefs.getString('$_versionPrefix$contentKey');

      // If the app bundle has a version equal to or newer than the cached OTA version,
      // purge the old downloaded cache so the app always uses the fresh bundled asset!
      if (localCachedVersion != null &&
          compareVersions(bundledVersion, localCachedVersion) >= 0) {
        await _cache.deleteContent(contentKey);
        await prefs.setString('$_versionPrefix$contentKey', bundledVersion);
        return rootBundle.loadString(bundledAssetPath);
      }

      // If cached version is strictly newer than bundled asset, read OTA cache
      if (localCachedVersion != null &&
          compareVersions(localCachedVersion, bundledVersion) > 0) {
        final content = await _cache.readContent(contentKey);
        if (content != null) {
          jsonDecode(content);
          return content;
        }
      }
    } catch (_) {
      // Fall back to the bundled asset if reading cache fails
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

    final remoteVersion = manifest['version']?.toString();
    final storagePath = manifest['storage_path']?.toString();
    final bucket = manifest['storage_bucket']?.toString() ?? _defaultBucket;
    if (remoteVersion == null ||
        remoteVersion.isEmpty ||
        storagePath == null ||
        storagePath.isEmpty) {
      return false;
    }

    final bundledVersion =
        RemoteContentBundledVersions.versions[contentKey] ?? '1.0.0';
    final prefs = await SharedPreferences.getInstance();
    final localCachedVersion =
        prefs.getString('$_versionPrefix$contentKey') ?? bundledVersion;

    // Only download if the remote version is strictly newer than both bundled and local cached versions
    final isNewerThanCached =
        compareVersions(remoteVersion, localCachedVersion) > 0;
    final isNewerThanBundled =
        compareVersions(remoteVersion, bundledVersion) > 0;

    if (!isNewerThanCached || !isNewerThanBundled) {
      return false;
    }

    final bytes = await client.storage.from(bucket).download(storagePath);
    final content = utf8.decode(bytes);
    jsonDecode(content);

    await _cache.writeContent(contentKey, content);
    await prefs.setString('$_versionPrefix$contentKey', remoteVersion);
    return true;
  }
}
