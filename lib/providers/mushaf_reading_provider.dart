import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/quran_foundation_repository.dart';
import '../models/mushaf_models.dart';

class MushafReadingProvider extends ChangeNotifier with WidgetsBindingObserver {
  List<MushafProfile> _profiles = [];
  List<MushafPageBookmark> _pageBookmarks = [];
  List<MushafVerseBookmark> _verseBookmarks = [];
  List<MushafRecentReading> _recentReadings = [];
  final Set<String> _deletedPageBookmarkKeys = {};
  final Set<String> _deletedVerseBookmarkKeys = {};
  String? _activeProfileId;
  int _displayMushafId = 2;
  bool _isLoaded = false;

  StreamSubscription<AuthState>? _authSubscription;
  Timer? _recentReadingSyncTimer;
  Timer? _profileSyncTimer;
  final Completer<void> _loadCompleter = Completer<void>();
  String? _pendingRecentUserId;
  int? _pendingRecentMushafId;
  int? _pendingRecentPageNumber;
  String? _pendingRecentProfileId;
  bool _isFlushingProfileSync = false;
  final Map<String, MushafProfile> _pendingProfileSyncs = {};

  MushafReadingProvider() {
    WidgetsBinding.instance.addObserver(this);
    load();
    _listenToAuthChanges();
    unawaited(_syncExistingSessionAfterLoad());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(flushPendingProfileSyncs());
      unawaited(flushPendingRecentReadingSync());
    }
  }

  void _listenToAuthChanges() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      await _loadCompleter.future;
      final user = data.session?.user;
      if (user != null) {
        try {
          await syncWithSupabase(user.id);
        } catch (e) {
          debugPrint('Error syncing Mushaf after auth change: $e');
        }
      }
    });
  }

  Future<void> _syncExistingSessionAfterLoad() async {
    await _loadCompleter.future;
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await syncWithSupabase(user.id);
      } catch (e) {
        debugPrint('Error syncing Mushaf existing session: $e');
      }
    }
  }

  bool get isLoaded => _isLoaded;
  List<MushafProfile> get profiles => List.unmodifiable(_profiles);
  List<MushafProfile> get activeCustomProfiles =>
      _profiles
          .where((profile) => !profile.isFreeRead && !profile.isArchived)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  List<MushafPageBookmark> get pageBookmarks =>
      List.unmodifiable(_pageBookmarks);
  List<MushafVerseBookmark> get verseBookmarks =>
      List.unmodifiable(_verseBookmarks);
  List<MushafRecentReading> get recentReadings =>
      List.unmodifiable(_recentReadings);
  MushafProfile? get activeProfile => profileById(_activeProfileId);
  int get displayMushafId => _displayMushafId;
  bool get canCreateProfile =>
      activeCustomProfiles.length < maxActiveMushafProfiles;

  MushafProfile? profileById(String? id) {
    if (id == null) return null;
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  MushafProfile freeReadProfileForMushaf(int mushafId) {
    final existing = _profiles.where((profile) {
      return profile.isFreeRead && profile.mushafId == mushafId;
    }).firstOrNull;
    if (existing != null) {
      if (existing.name != 'Just Read') {
        final index = _profiles.indexWhere(
          (profile) => profile.id == existing.id,
        );
        if (index != -1) {
          final updated = existing.copyWith(
            name: 'Just Read',
            updatedAt: DateTime.now(),
          );
          _profiles[index] = updated;
          _save();
          return updated;
        }
      }
      return existing;
    }

    final now = DateTime.now();
    final type = mushafTypeById(mushafId);
    final profile = MushafProfile(
      id: 'mushaf-free-$mushafId',
      userId: 'local',
      name: 'Just Read',
      slug: mushafFreeReadSlug,
      mushafId: mushafId,
      planMode: 'free_read',
      startPage: 1,
      targetPage: type.pageCount,
      currentPage: 1,
      sortOrder: -1,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );
    _profiles.add(profile);
    _save();
    return profile;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(mushafStoreKey);
    if (raw == null || raw.isEmpty) {
      _ensureDefaultProfile();
      _isLoaded = true;
      await _save();
      _completeLoad();
      notifyListeners();
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _profiles = _decodeList(decoded['profiles'], MushafProfile.fromJson);
        _pageBookmarks = _decodeList(
          decoded['pageBookmarks'],
          MushafPageBookmark.fromJson,
        );
        _verseBookmarks = _decodeList(
          decoded['verseBookmarks'],
          MushafVerseBookmark.fromJson,
        );
        _deletedPageBookmarkKeys
          ..clear()
          ..addAll(_decodeStringSet(decoded['deletedPageBookmarkKeys']));
        _deletedVerseBookmarkKeys
          ..clear()
          ..addAll(_decodeStringSet(decoded['deletedVerseBookmarkKeys']));
        _recentReadings = _decodeList(
          decoded['recentReadings'],
          MushafRecentReading.fromJson,
        );
        _activeProfileId = decoded['activeProfileId']?.toString();
        final displayMushafId =
            int.tryParse(decoded['displayMushafId']?.toString() ?? '') ?? 2;
        _displayMushafId = visibleMushafTypeIds.contains(displayMushafId)
            ? displayMushafId
            : 2;
      }
    } catch (_) {
      _profiles = [];
      _pageBookmarks = [];
      _verseBookmarks = [];
      _recentReadings = [];
      _deletedPageBookmarkKeys.clear();
      _deletedVerseBookmarkKeys.clear();
      _activeProfileId = null;
    }

    _ensureDefaultProfile();
    _normalizeFreeReadProfiles();
    if (activeProfile == null) {
      _activeProfileId = _profiles.first.id;
    }
    _isLoaded = true;
    await _save();
    _completeLoad();
    notifyListeners();
  }

  void _completeLoad() {
    if (!_loadCompleter.isCompleted) {
      _loadCompleter.complete();
    }
  }

  Future<MushafProfile> openFreeRead(int mushafId) async {
    final profile = freeReadProfileForMushaf(mushafId);
    _activeProfileId = profile.id;
    await _save();
    notifyListeners();
    return profile;
  }

  Future<MushafProfile> openUnifiedFreeRead() async {
    return openFreeRead(1);
  }

  void _normalizeFreeReadProfiles() {
    var changed = false;
    _profiles = _profiles.map((profile) {
      if (!profile.isFreeRead || profile.name == 'Just Read') {
        return profile;
      }
      changed = true;
      return profile.copyWith(name: 'Just Read');
    }).toList();
    if (changed) {
      _save();
    }
  }

  Future<void> setDisplayMushafId(int mushafId) async {
    if (!visibleMushafTypeIds.contains(mushafId)) return;
    _displayMushafId = mushafId;
    await _save();
    notifyListeners();
  }

  Future<void> setActiveProfile(String profileId) async {
    if (profileById(profileId) == null) return;
    _activeProfileId = profileId;
    await _save();
    notifyListeners();
  }

  Future<void> updateProgress({
    required String profileId,
    required int pageNumber,
  }) async {
    final index = _profiles.indexWhere((profile) => profile.id == profileId);
    if (index == -1) return;
    final profile = _profiles[index];
    final page = _clampInt(pageNumber, profile.startPage, profile.targetPage);
    final furthestPage = page > profile.furthestUnreadPage
        ? page
        : profile.furthestUnreadPage;
    final updated = profile.copyWith(
      currentPage: furthestPage,
      lastViewedPage: page,
      updatedAt: DateTime.now(),
    );
    _profiles[index] = updated;
    _upsertRecentReading(updated);
    await _save();
    notifyListeners();
    _queueProfileSync(updated, delay: Duration.zero);
  }

  Future<void> updateProfile(String profileId, {required String name}) async {
    final index = _profiles.indexWhere((profile) => profile.id == profileId);
    if (index == -1) return;
    final profile = _profiles[index];
    final updated = profile.copyWith(name: name, updatedAt: DateTime.now());
    _profiles[index] = updated;
    await _save();
    notifyListeners();
    _queueProfileSync(updated, delay: Duration.zero);
  }

  Future<void> updateProfileRange({
    required String profileId,
    required String name,
    required String planMode,
    required int startPage,
    required int targetPage,
    bool resetProgress = false,
  }) async {
    final index = _profiles.indexWhere((profile) => profile.id == profileId);
    if (index == -1) return;
    final profile = _profiles[index];
    if (profile.isFreeRead) return;

    final pageCount = mushafTypeById(profile.mushafId).pageCount;
    final start = _clampInt(startPage, 1, pageCount);
    final target = _clampInt(targetPage, start, pageCount);
    final current = resetProgress
        ? start
        : _clampInt(profile.currentPage, start, target);
    final lastViewed = resetProgress
        ? start
        : _clampInt(profile.lastViewedPage, start, target);
    final updated = profile.copyWith(
      name: name,
      planMode: planMode,
      startPage: start,
      targetPage: target,
      currentPage: current,
      lastViewedPage: lastViewed,
      updatedAt: DateTime.now(),
    );
    _profiles[index] = updated;
    _upsertRecentReading(updated);
    await _save();
    notifyListeners();
    _queueProfileSync(updated, delay: Duration.zero);
  }

  Future<void> createPageRangeProfile({
    required String name,
    required int mushafId,
    required int startPage,
    required int targetPage,
    required String planMode,
  }) async {
    if (!canCreateProfile) {
      throw const QuranFoundationException(
        'Only 5 active Mushaf profiles are allowed.',
      );
    }
    final pageCount = mushafTypeById(mushafId).pageCount;
    final start = _clampInt(startPage, 1, pageCount);
    final target = _clampInt(targetPage, start, pageCount);
    final now = DateTime.now();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'local';
    final profile = MushafProfile(
      id: 'mushaf-profile-${now.microsecondsSinceEpoch}',
      userId: userId,
      name: name,
      slug: _slugify(name),
      mushafId: mushafId,
      planMode: planMode,
      startPage: start,
      targetPage: target,
      currentPage: start,
      sortOrder: activeCustomProfiles.length,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );
    _profiles.add(profile);
    _activeProfileId = profile.id;
    await _save();
    notifyListeners();
    _queueProfileSync(profile, delay: Duration.zero);
  }

  Future<void> createSurahProfile({
    required String name,
    required int mushafId,
    required int surahNumber,
    required QuranFoundationRepository repository,
  }) async {
    final pageCount = mushafTypeById(mushafId).pageCount;
    await createPageRangeProfile(
      name: name,
      mushafId: mushafId,
      startPage: _madaniStartPageForSurah(surahNumber),
      targetPage: _madaniEndPageForSurah(surahNumber, pageCount),
      planMode: 'by_surah',
    );
  }

  Future<void> createJuzProfile({
    required String name,
    required int mushafId,
    required int juzNumber,
    required QuranFoundationRepository repository,
  }) async {
    final pageCount = mushafTypeById(mushafId).pageCount;
    await createPageRangeProfile(
      name: name,
      mushafId: mushafId,
      startPage: _madaniStartPageForJuz(juzNumber),
      targetPage: _madaniEndPageForJuz(juzNumber, pageCount),
      planMode: 'by_juz',
    );
  }

  Future<void> archiveProfile(String profileId) async {
    final index = _profiles.indexWhere((profile) => profile.id == profileId);
    if (index == -1 || _profiles[index].isFreeRead) return;
    final updated = _profiles[index].copyWith(
      isArchived: true,
      updatedAt: DateTime.now(),
    );
    _profiles[index] = updated;
    if (_activeProfileId == profileId) {
      _activeProfileId = freeReadProfileForMushaf(_profiles[index].mushafId).id;
    }
    await _save();
    notifyListeners();
    _queueProfileSync(updated, delay: Duration.zero);
  }

  bool isPageBookmarked(int mushafId, int pageNumber) {
    return _pageBookmarks.any(
      (bookmark) =>
          bookmark.mushafId == mushafId && bookmark.pageNumber == pageNumber,
    );
  }

  Future<void> togglePageBookmark(int mushafId, int pageNumber) async {
    final index = _pageBookmarks.indexWhere(
      (bookmark) =>
          bookmark.mushafId == mushafId && bookmark.pageNumber == pageNumber,
    );
    if (index >= 0) {
      _pageBookmarks.removeAt(index);
      final key = _pageBookmarkKey(mushafId, pageNumber);
      _deletedPageBookmarkKeys.add(key);
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          await Supabase.instance.client
              .from('mushaf_page_bookmarks')
              .delete()
              .eq('user_id', user.id)
              .eq('mushaf_id', mushafId)
              .eq('page_number', pageNumber);
          _deletedPageBookmarkKeys.remove(key);
        } catch (e) {
          debugPrint('Error deleting page bookmark from Supabase: $e');
        }
      }
    } else {
      final bookmark = MushafPageBookmark(
        id: 'mushaf-page-bookmark-$mushafId-$pageNumber',
        mushafId: mushafId,
        pageNumber: pageNumber,
        createdAt: DateTime.now(),
      );
      _deletedPageBookmarkKeys.remove(_pageBookmarkKey(mushafId, pageNumber));
      _pageBookmarks.add(bookmark);
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          await Supabase.instance.client.from('mushaf_page_bookmarks').upsert({
            'user_id': user.id,
            'mushaf_id': mushafId,
            'page_number': pageNumber,
            'created_at': bookmark.createdAt.toIso8601String(),
          }, onConflict: 'user_id,mushaf_id,page_number');
        } catch (e) {
          debugPrint('Error saving page bookmark to Supabase: $e');
        }
      }
    }
    await _save();
    notifyListeners();
  }

  bool isVerseBookmarked(int mushafId, int pageNumber, String verseKey) {
    return _verseBookmarks.any(
      (bookmark) =>
          bookmark.mushafId == mushafId &&
          bookmark.pageNumber == pageNumber &&
          bookmark.verseKey == verseKey,
    );
  }

  Future<void> toggleVerseBookmark({
    required int mushafId,
    required int pageNumber,
    required String verseKey,
  }) async {
    final index = _verseBookmarks.indexWhere(
      (bookmark) =>
          bookmark.mushafId == mushafId &&
          bookmark.pageNumber == pageNumber &&
          bookmark.verseKey == verseKey,
    );
    if (index >= 0) {
      _verseBookmarks.removeAt(index);
      final key = _verseBookmarkKey(mushafId, pageNumber, verseKey);
      _deletedVerseBookmarkKeys.add(key);
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          await Supabase.instance.client
              .from('mushaf_verse_bookmarks')
              .delete()
              .eq('user_id', user.id)
              .eq('mushaf_id', mushafId)
              .eq('page_number', pageNumber)
              .eq('verse_key', verseKey);
          _deletedVerseBookmarkKeys.remove(key);
        } catch (e) {
          debugPrint('Error deleting verse bookmark from Supabase: $e');
        }
      }
    } else {
      final bookmark = MushafVerseBookmark(
        id: 'mushaf-verse-bookmark-$mushafId-$pageNumber-$verseKey',
        mushafId: mushafId,
        pageNumber: pageNumber,
        verseKey: verseKey,
        createdAt: DateTime.now(),
      );
      _deletedVerseBookmarkKeys.remove(
        _verseBookmarkKey(mushafId, pageNumber, verseKey),
      );
      _verseBookmarks.add(bookmark);
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          await Supabase.instance.client.from('mushaf_verse_bookmarks').upsert({
            'user_id': user.id,
            'mushaf_id': mushafId,
            'page_number': pageNumber,
            'verse_key': verseKey,
            'created_at': bookmark.createdAt.toIso8601String(),
          }, onConflict: 'user_id,mushaf_id,page_number,verse_key');
        } catch (e) {
          debugPrint('Error saving verse bookmark to Supabase: $e');
        }
      }
    }
    await _save();
    notifyListeners();
  }

  void _ensureDefaultProfile() {
    freeReadProfileForMushaf(1);
    _activeProfileId ??= 'mushaf-free-1';
  }

  void _upsertRecentReading(MushafProfile profile) {
    final page = profile.lastViewedPage;
    _recentReadings.removeWhere(
      (reading) =>
          reading.mushafId == profile.mushafId &&
          (profile.isFreeRead
              ? reading.pageNumber == page
              : reading.profileId == profile.id),
    );
    final recent = MushafRecentReading(
      mushafId: profile.mushafId,
      pageNumber: page,
      profileId: profile.id,
      updatedAt: DateTime.now(),
    );
    _recentReadings.insert(0, recent);
    if (_recentReadings.length > 30) {
      _recentReadings = _recentReadings.take(30).toList();
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _debounceRecentReadingSync(user.id, profile.mushafId, page, profile.id);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      mushafStoreKey,
      jsonEncode({
        'activeProfileId': _activeProfileId,
        'displayMushafId': _displayMushafId,
        'profiles': _profiles.map((profile) => profile.toJson()).toList(),
        'pageBookmarks': _pageBookmarks
            .map((bookmark) => bookmark.toJson())
            .toList(),
        'verseBookmarks': _verseBookmarks
            .map((bookmark) => bookmark.toJson())
            .toList(),
        'deletedPageBookmarkKeys': _deletedPageBookmarkKeys.toList(),
        'deletedVerseBookmarkKeys': _deletedVerseBookmarkKeys.toList(),
        'recentReadings': _recentReadings
            .map((reading) => reading.toJson())
            .toList(),
      }),
    );
  }

  List<T> _decodeList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) decoder,
  ) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => decoder(Map<String, dynamic>.from(item)))
        .toList();
  }

  Set<String> _decodeStringSet(dynamic raw) {
    if (raw is! List) return {};
    return raw
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  String _slugify(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9ก-๙]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (slug.isEmpty) return 'mushaf_profile';
    return slug;
  }

  Future<void> syncWithSupabase(String userId) async {
    final client = Supabase.instance.client;
    try {
      // 1. Sync Profiles
      final remoteProfilesRes = await client
          .from('mushaf_profiles')
          .select('*')
          .eq('user_id', userId);
      final List<dynamic> dbProfiles = remoteProfilesRes;

      final Set<String> matchedRemoteIds = {};
      final List<MushafProfile> reconciledProfiles = [];

      for (final localP in _profiles) {
        if (localP.userId != userId && localP.userId != 'local') {
          reconciledProfiles.add(localP);
          continue;
        }

        final dbP = _firstMapWhereOrNull(
          dbProfiles,
          (item) =>
              item['id'] == localP.id ||
              (item['slug'] == localP.slug &&
                  item['mushaf_id'] == localP.mushafId),
        );

        if (dbP != null) {
          final remoteId = dbP['id'].toString();
          matchedRemoteIds.add(remoteId);
          if (localP.id != remoteId) {
            await _replaceProfileReferences(localP.id, remoteId);
          }

          final remoteUpdatedAt =
              DateTime.tryParse(dbP['updated_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final remoteIsArchived = dbP['is_archived'] == true;
          if (!remoteIsArchived && localP.updatedAt.isAfter(remoteUpdatedAt)) {
            final syncedLocal = localP.copyWith(id: remoteId, userId: userId);
            reconciledProfiles.add(syncedLocal);
            await _syncProfileToSupabase(syncedLocal, userId: userId);
          } else {
            reconciledProfiles.add(
              MushafProfile(
                id: remoteId,
                userId: userId,
                name: dbP['name'],
                slug: dbP['slug'],
                mushafId: dbP['mushaf_id'],
                planMode: dbP['plan_mode'],
                startPage: dbP['start_page'],
                targetPage: dbP['target_page'],
                currentPage: dbP['furthest_unread_page'] ?? dbP['current_page'],
                lastViewedPage:
                    dbP['last_viewed_page'] ??
                    dbP['furthest_unread_page'] ??
                    dbP['current_page'],
                sortOrder: dbP['sort_order'],
                isArchived: dbP['is_archived'] ?? false,
                createdAt:
                    DateTime.tryParse(dbP['created_at']?.toString() ?? '') ??
                    DateTime.now(),
                updatedAt: remoteUpdatedAt,
              ),
            );
          }
        } else {
          final syncedLocal = localP.copyWith(userId: userId);
          final returnedId = await _syncProfileToSupabase(
            syncedLocal,
            userId: userId,
          );
          if (returnedId != null && returnedId != localP.id) {
            await _replaceProfileReferences(localP.id, returnedId);
          }
          reconciledProfiles.add(
            syncedLocal.copyWith(id: returnedId ?? syncedLocal.id),
          );
        }
      }

      for (final dbP in dbProfiles) {
        final remoteId = dbP['id'].toString();
        if (matchedRemoteIds.contains(remoteId)) continue;

        reconciledProfiles.add(
          MushafProfile(
            id: remoteId,
            userId: userId,
            name: dbP['name'],
            slug: dbP['slug'],
            mushafId: dbP['mushaf_id'],
            planMode: dbP['plan_mode'],
            startPage: dbP['start_page'],
            targetPage: dbP['target_page'],
            currentPage: dbP['furthest_unread_page'] ?? dbP['current_page'],
            lastViewedPage:
                dbP['last_viewed_page'] ??
                dbP['furthest_unread_page'] ??
                dbP['current_page'],
            sortOrder: dbP['sort_order'],
            isArchived: dbP['is_archived'] ?? false,
            createdAt:
                DateTime.tryParse(dbP['created_at']?.toString() ?? '') ??
                DateTime.now(),
            updatedAt:
                DateTime.tryParse(dbP['updated_at']?.toString() ?? '') ??
                DateTime.now(),
          ),
        );
      }

      _profiles = reconciledProfiles;
      final active = profileById(_activeProfileId);
      if (active == null || active.isArchived) {
        _activeProfileId = freeReadProfileForMushaf(_displayMushafId).id;
      }

      // 2. Sync Page Bookmarks
      await _flushDeletedPageBookmarks(userId);
      final remotePageBookRes = await client
          .from('mushaf_page_bookmarks')
          .select('*')
          .eq('user_id', userId);
      final List<dynamic> dbPageBook = remotePageBookRes;
      final List<MushafPageBookmark> reconciledPageBook = [];
      final Set<String> matchedPageBookKeys = {};

      for (final localB in _pageBookmarks) {
        final key = _pageBookmarkKey(localB.mushafId, localB.pageNumber);
        if (_deletedPageBookmarkKeys.contains(key)) continue;

        final dbB = _firstMapWhereOrNull(
          dbPageBook,
          (item) =>
              item['mushaf_id'] == localB.mushafId &&
              item['page_number'] == localB.pageNumber,
        );
        if (dbB != null) {
          matchedPageBookKeys.add(key);
        } else {
          await client.from('mushaf_page_bookmarks').upsert({
            'user_id': userId,
            'mushaf_id': localB.mushafId,
            'page_number': localB.pageNumber,
            'created_at': localB.createdAt.toIso8601String(),
          }, onConflict: 'user_id,mushaf_id,page_number');
        }
        reconciledPageBook.add(localB);
      }

      for (final dbB in dbPageBook) {
        final key = _pageBookmarkKey(dbB['mushaf_id'], dbB['page_number']);
        if (matchedPageBookKeys.contains(key)) continue;
        if (_deletedPageBookmarkKeys.contains(key)) continue;
        reconciledPageBook.add(
          MushafPageBookmark(
            id: dbB['id'].toString(),
            mushafId: dbB['mushaf_id'],
            pageNumber: dbB['page_number'],
            createdAt:
                DateTime.tryParse(dbB['created_at']?.toString() ?? '') ??
                DateTime.now(),
          ),
        );
      }
      _pageBookmarks = reconciledPageBook;

      // 3. Sync Verse Bookmarks
      await _flushDeletedVerseBookmarks(userId);
      final remoteVerseBookRes = await client
          .from('mushaf_verse_bookmarks')
          .select('*')
          .eq('user_id', userId);
      final List<dynamic> dbVerseBook = remoteVerseBookRes;
      final List<MushafVerseBookmark> reconciledVerseBook = [];
      final Set<String> matchedVerseBookKeys = {};

      for (final localB in _verseBookmarks) {
        final key = _verseBookmarkKey(
          localB.mushafId,
          localB.pageNumber,
          localB.verseKey,
        );
        if (_deletedVerseBookmarkKeys.contains(key)) continue;

        final dbB = _firstMapWhereOrNull(
          dbVerseBook,
          (item) =>
              item['mushaf_id'] == localB.mushafId &&
              item['page_number'] == localB.pageNumber &&
              item['verse_key'] == localB.verseKey,
        );
        if (dbB != null) {
          matchedVerseBookKeys.add(key);
        } else {
          await client.from('mushaf_verse_bookmarks').upsert({
            'user_id': userId,
            'mushaf_id': localB.mushafId,
            'page_number': localB.pageNumber,
            'verse_key': localB.verseKey,
            'created_at': localB.createdAt.toIso8601String(),
          }, onConflict: 'user_id,mushaf_id,page_number,verse_key');
        }
        reconciledVerseBook.add(localB);
      }

      for (final dbB in dbVerseBook) {
        final key = _verseBookmarkKey(
          dbB['mushaf_id'],
          dbB['page_number'],
          dbB['verse_key'],
        );
        if (matchedVerseBookKeys.contains(key)) continue;
        if (_deletedVerseBookmarkKeys.contains(key)) continue;
        reconciledVerseBook.add(
          MushafVerseBookmark(
            id: dbB['id'].toString(),
            mushafId: dbB['mushaf_id'],
            pageNumber: dbB['page_number'],
            verseKey: dbB['verse_key'],
            createdAt:
                DateTime.tryParse(dbB['created_at']?.toString() ?? '') ??
                DateTime.now(),
          ),
        );
      }
      _verseBookmarks = reconciledVerseBook;

      // 4. Sync Recent Readings
      final remoteRecentRes = await client
          .from('mushaf_recent_readings')
          .select('*')
          .eq('user_id', userId)
          .order('updated_at', ascending: false)
          .limit(20);
      final List<dynamic> dbRecent = remoteRecentRes;
      final List<MushafRecentReading> reconciledRecent = [];
      final Set<String> matchedRecentKeys = {};

      for (final localR in _recentReadings) {
        final dbR = _firstMapWhereOrNull(
          dbRecent,
          (item) =>
              item['mushaf_id'] == localR.mushafId &&
              item['profile_id'] == localR.profileId,
        );

        if (dbR != null) {
          matchedRecentKeys.add('${localR.mushafId}-${localR.profileId}');
          final remoteDate =
              DateTime.tryParse(dbR['updated_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);

          if (localR.updatedAt.isAfter(remoteDate)) {
            // Local is newer, keep it and push it
            reconciledRecent.add(localR);
            _debounceRecentReadingSync(
              userId,
              localR.mushafId,
              localR.pageNumber,
              localR.profileId,
            );
          } else {
            // Remote is newer, keep it
            reconciledRecent.add(
              MushafRecentReading(
                mushafId: dbR['mushaf_id'],
                pageNumber: dbR['page_number'],
                profileId: dbR['profile_id']?.toString(),
                updatedAt: remoteDate,
              ),
            );
          }
        } else {
          // Local only, keep it and push it
          reconciledRecent.add(localR);
          _debounceRecentReadingSync(
            userId,
            localR.mushafId,
            localR.pageNumber,
            localR.profileId,
          );
        }
      }

      for (final dbR in dbRecent) {
        final key = '${dbR['mushaf_id']}-${dbR['profile_id']}';
        if (matchedRecentKeys.contains(key)) continue;
        reconciledRecent.add(
          MushafRecentReading(
            mushafId: dbR['mushaf_id'],
            pageNumber: dbR['page_number'],
            profileId: dbR['profile_id']?.toString(),
            updatedAt:
                DateTime.tryParse(dbR['updated_at']?.toString() ?? '') ??
                DateTime.now(),
          ),
        );
      }
      _recentReadings = reconciledRecent;

      await _save();
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing Mushaf with Supabase: $e');
      rethrow;
    }
  }

  Future<String?> _syncProfileToSupabase(
    MushafProfile p, {
    String? userId,
  }) async {
    final client = Supabase.instance.client;
    final targetUserId =
        userId ??
        client.auth.currentUser?.id ??
        (p.userId == 'local' ? null : p.userId);
    if (targetUserId == null) {
      throw StateError(
        'Cannot sync Mushaf profile without an authenticated user.',
      );
    }

    try {
      final uuidRegExp = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      );
      final bool hasUuid = uuidRegExp.hasMatch(p.id);

      final upsertData = {
        'user_id': targetUserId,
        'name': p.name,
        'slug': p.slug,
        'mushaf_id': p.mushafId,
        'plan_mode': p.planMode,
        'start_page': p.startPage,
        'target_page': p.targetPage,
        'current_page': p.currentPage,
        'furthest_unread_page': p.furthestUnreadPage,
        'last_viewed_page': p.lastViewedPage,
        'sort_order': p.sortOrder,
        'is_archived': p.isArchived,
        'updated_at': p.updatedAt.toIso8601String(),
      };

      if (hasUuid) {
        upsertData['id'] = p.id;
        await client
            .from('mushaf_profiles')
            .upsert(upsertData, onConflict: 'id');
        return p.id;
      } else {
        final response = await client
            .from('mushaf_profiles')
            .insert(upsertData)
            .select('id')
            .single();
        final returnedId = response['id']?.toString();
        if (returnedId != null) {
          final index = _profiles.indexWhere((item) => item.id == p.id);
          if (index != -1) {
            _profiles[index] = _profiles[index].copyWith(
              id: returnedId,
              userId: targetUserId,
            );
            if (_activeProfileId == p.id) {
              _activeProfileId = returnedId;
            }
          }
          await _replaceProfileReferences(p.id, returnedId);
          await _save();
          return returnedId;
        }
      }
    } catch (e) {
      debugPrint('Error syncing Mushaf profile to Supabase: $e');
      rethrow;
    }
    return null;
  }

  Future<void> _replaceProfileReferences(String oldId, String newId) async {
    if (oldId == newId) return;

    var changed = false;
    if (_activeProfileId == oldId) {
      _activeProfileId = newId;
      changed = true;
    }
    if (_pendingRecentProfileId == oldId) {
      _pendingRecentProfileId = newId;
      changed = true;
    }

    final seenKeys = <String>{};
    final updatedRecent = <MushafRecentReading>[];
    for (final reading in _recentReadings) {
      final profileId = reading.profileId == oldId ? newId : reading.profileId;
      final key = '${reading.mushafId}-$profileId';
      if (seenKeys.contains(key)) {
        changed = true;
        continue;
      }
      seenKeys.add(key);

      if (profileId != reading.profileId) {
        changed = true;
        updatedRecent.add(
          MushafRecentReading(
            mushafId: reading.mushafId,
            pageNumber: reading.pageNumber,
            profileId: profileId,
            updatedAt: reading.updatedAt,
          ),
        );
      } else {
        updatedRecent.add(reading);
      }
    }

    if (changed) {
      _recentReadings = updatedRecent;
      await _save();
    }
  }

  Future<void> _flushDeletedPageBookmarks(String userId) async {
    if (_deletedPageBookmarkKeys.isEmpty) return;
    final client = Supabase.instance.client;
    final deletedKeys = Set<String>.from(_deletedPageBookmarkKeys);
    for (final key in deletedKeys) {
      final parts = key.split('-');
      if (parts.length != 2) continue;
      final mushafId = int.tryParse(parts[0]);
      final pageNumber = int.tryParse(parts[1]);
      if (mushafId == null || pageNumber == null) continue;

      await client
          .from('mushaf_page_bookmarks')
          .delete()
          .eq('user_id', userId)
          .eq('mushaf_id', mushafId)
          .eq('page_number', pageNumber);
      _deletedPageBookmarkKeys.remove(key);
    }
  }

  Future<void> _flushDeletedVerseBookmarks(String userId) async {
    if (_deletedVerseBookmarkKeys.isEmpty) return;
    final client = Supabase.instance.client;
    final deletedKeys = Set<String>.from(_deletedVerseBookmarkKeys);
    for (final key in deletedKeys) {
      final parts = key.split('|');
      if (parts.length != 3) continue;
      final mushafId = int.tryParse(parts[0]);
      final pageNumber = int.tryParse(parts[1]);
      final verseKey = parts[2];
      if (mushafId == null || pageNumber == null || verseKey.isEmpty) {
        continue;
      }

      await client
          .from('mushaf_verse_bookmarks')
          .delete()
          .eq('user_id', userId)
          .eq('mushaf_id', mushafId)
          .eq('page_number', pageNumber)
          .eq('verse_key', verseKey);
      _deletedVerseBookmarkKeys.remove(key);
    }
  }

  void _queueProfileSync(
    MushafProfile profile, {
    Duration delay = const Duration(milliseconds: 900),
  }) {
    if (profile.userId == 'local') return;
    if (Supabase.instance.client.auth.currentUser == null) return;

    _pendingProfileSyncs[profile.id] = profile;
    _profileSyncTimer?.cancel();
    _profileSyncTimer = Timer(delay, () {
      unawaited(flushPendingProfileSyncs());
    });
  }

  Future<bool> flushPendingProfileSyncs() async {
    if (_pendingProfileSyncs.isEmpty) return true;
    if (_isFlushingProfileSync) return false;

    _isFlushingProfileSync = true;
    final pending = Map<String, MushafProfile>.from(_pendingProfileSyncs);
    _pendingProfileSyncs.clear();

    try {
      for (final profile in pending.values) {
        await _syncProfileToSupabase(profile);
      }
    } catch (_) {
      _pendingProfileSyncs.addAll(pending);
      return false;
    } finally {
      _isFlushingProfileSync = false;
      if (_pendingProfileSyncs.isNotEmpty) {
        _profileSyncTimer?.cancel();
        _profileSyncTimer = Timer(const Duration(seconds: 5), () {
          unawaited(flushPendingProfileSyncs());
        });
      }
    }
    return _pendingProfileSyncs.isEmpty;
  }

  void _debounceRecentReadingSync(
    String userId,
    int mushafId,
    int pageNumber,
    String? profileId,
  ) {
    _pendingRecentUserId = userId;
    _pendingRecentMushafId = mushafId;
    _pendingRecentPageNumber = pageNumber;
    _pendingRecentProfileId = profileId;

    _recentReadingSyncTimer?.cancel();
    _recentReadingSyncTimer = Timer(const Duration(seconds: 2), () async {
      unawaited(flushPendingRecentReadingSync());
    });
  }

  Future<void> _syncRecentReadingToSupabase(
    String userId,
    int mushafId,
    int pageNumber,
    String? profileId,
  ) async {
    try {
      final uuidRegExp = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      );
      if (profileId == null || !uuidRegExp.hasMatch(profileId)) {
        return;
      }

      final client = Supabase.instance.client;
      await client.from('mushaf_recent_readings').upsert({
        'user_id': userId,
        'mushaf_id': mushafId,
        'page_number': pageNumber,
        'profile_id': profileId,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,mushaf_id,profile_id');
    } catch (e) {
      debugPrint('Error syncing Mushaf recent reading to Supabase: $e');
      rethrow;
    }
  }

  Future<void> flushPendingRecentReadingSync() async {
    _recentReadingSyncTimer?.cancel();
    _recentReadingSyncTimer = null;

    final userId = _pendingRecentUserId;
    final mushafId = _pendingRecentMushafId;
    final pageNumber = _pendingRecentPageNumber;
    final profileId = _pendingRecentProfileId;
    if (userId == null || mushafId == null || pageNumber == null) return;

    _pendingRecentUserId = null;
    _pendingRecentMushafId = null;
    _pendingRecentPageNumber = null;
    _pendingRecentProfileId = null;

    try {
      await _syncRecentReadingToSupabase(
        userId,
        mushafId,
        pageNumber,
        profileId,
      );
    } catch (_) {
      _pendingRecentUserId = userId;
      _pendingRecentMushafId = mushafId;
      _pendingRecentPageNumber = pageNumber;
      _pendingRecentProfileId = profileId;
      rethrow;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    unawaited(flushPendingProfileSyncs());
    unawaited(flushPendingRecentReadingSync());
    super.dispose();
  }
}

int _clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

Map<String, dynamic>? _firstMapWhereOrNull(
  Iterable<dynamic> items,
  bool Function(Map<String, dynamic> item) test,
) {
  for (final item in items) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    if (test(map)) return map;
  }
  return null;
}

String _pageBookmarkKey(dynamic mushafId, dynamic pageNumber) {
  return '$mushafId-$pageNumber';
}

String _verseBookmarkKey(
  dynamic mushafId,
  dynamic pageNumber,
  dynamic verseKey,
) {
  return '$mushafId|$pageNumber|$verseKey';
}

int _madaniStartPageForSurah(int surahNumber) {
  const List<int> surahStartPages = [
    1,
    2,
    50,
    77,
    106,
    128,
    151,
    177,
    187,
    208,
    221,
    235,
    249,
    255,
    262,
    267,
    282,
    293,
    305,
    312,
    322,
    332,
    342,
    350,
    359,
    367,
    377,
    385,
    396,
    404,
    411,
    415,
    418,
    428,
    434,
    440,
    446,
    453,
    458,
    467,
    477,
    483,
    489,
    496,
    499,
    502,
    507,
    511,
    515,
    518,
    520,
    523,
    526,
    528,
    531,
    534,
    537,
    542,
    545,
    549,
    551,
    553,
    554,
    556,
    558,
    560,
    562,
    564,
    566,
    568,
    570,
    572,
    574,
    575,
    577,
    578,
    580,
    582,
    583,
    585,
    586,
    587,
    587,
    589,
    590,
    591,
    591,
    592,
    593,
    594,
    595,
    595,
    596,
    596,
    597,
    597,
    598,
    598,
    599,
    599,
    600,
    600,
    601,
    601,
    601,
    602,
    602,
    602,
    603,
    603,
    603,
    604,
    604,
    604,
  ];
  if (surahNumber < 1 || surahNumber > 114) return 1;
  return surahStartPages[surahNumber - 1];
}

int _madaniEndPageForSurah(int surahNumber, int pageCount) {
  if (surahNumber >= 114) return pageCount;
  return _clampInt(_madaniStartPageForSurah(surahNumber + 1) - 1, 1, pageCount);
}

int _madaniStartPageForJuz(int juzNumber) {
  const juzStartPages = [
    1,
    22,
    42,
    62,
    82,
    102,
    121,
    142,
    162,
    182,
    201,
    222,
    242,
    262,
    282,
    302,
    322,
    342,
    362,
    382,
    402,
    422,
    442,
    462,
    482,
    502,
    522,
    542,
    562,
    582,
  ];
  if (juzNumber < 1 || juzNumber > 30) return 1;
  return juzStartPages[juzNumber - 1];
}

int _madaniEndPageForJuz(int juzNumber, int pageCount) {
  if (juzNumber >= 30) return pageCount;
  return _clampInt(_madaniStartPageForJuz(juzNumber + 1) - 1, 1, pageCount);
}
