import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../shared/shared.dart';

const shortcutMulkId = '00000000-0000-0000-0000-000000000067';
const shortcutKahfId = '00000000-0000-0000-0000-000000000018';

bool isShortcutProfile(LocalReadingProfile profile) {
  return profile.id == shortcutMulkId ||
      profile.id == shortcutKahfId ||
      profile.slug.startsWith('shortcut_');
}

class StorageException implements Exception {
  final String message;
  const StorageException(this.message);
  @override
  String toString() => message;
}

class LocalReadingProfile {
  final String id;
  final String userId;
  final String name;
  final String slug;
  final String? planMode;
  final int? startJuz;
  final int? targetJuz;
  final VerseRef start;
  final VerseRef? target;
  final VerseRef current;
  final VerseRef lastViewed;
  final int sortOrder;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalReadingProfile({
    required this.id,
    required this.userId,
    required this.name,
    required this.slug,
    this.planMode,
    this.startJuz,
    this.targetJuz,
    required this.start,
    this.target,
    required this.current,
    VerseRef? lastViewed,
    required this.sortOrder,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  }) : lastViewed = lastViewed ?? current;

  VerseRef get furthestUnread => current;
  int get furthestUnreadIndex => absoluteVerseIndex(furthestUnread);
  int get lastViewedIndex => absoluteVerseIndex(lastViewed);

  LocalReadingProfile copyWith({
    String? id,
    String? userId,
    String? name,
    String? slug,
    String? planMode,
    int? startJuz,
    int? targetJuz,
    VerseRef? start,
    VerseRef? target,
    bool clearTarget = false,
    VerseRef? current,
    VerseRef? lastViewed,
    bool? isArchived,
    DateTime? updatedAt,
  }) {
    return LocalReadingProfile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      planMode: planMode ?? this.planMode,
      startJuz: startJuz ?? this.startJuz,
      targetJuz: targetJuz ?? this.targetJuz,
      start: start ?? this.start,
      target: clearTarget ? null : target ?? this.target,
      current: current ?? this.current,
      lastViewed: lastViewed ?? this.lastViewed,
      sortOrder: sortOrder,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'slug': slug,
      if (planMode != null) 'planMode': planMode,
      if (startJuz != null) 'startJuz': startJuz,
      if (targetJuz != null) 'targetJuz': targetJuz,
      'startSurahId': start.surahId,
      'startVerseId': start.verseId,
      if (target != null) 'targetSurahId': target!.surahId,
      if (target != null) 'targetVerseId': target!.verseId,
      'currentSurahId': current.surahId,
      'currentVerseId': current.verseId,
      'furthestUnreadIndex': furthestUnreadIndex,
      'lastViewedSurahId': lastViewed.surahId,
      'lastViewedVerseId': lastViewed.verseId,
      'lastViewedIndex': lastViewedIndex,
      'sortOrder': sortOrder,
      'isArchived': isArchived,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory LocalReadingProfile.fromJson(Map<String, dynamic> json) {
    final targetSurahId = json['targetSurahId']?.toString();
    final targetVerseId = json['targetVerseId']?.toString();
    final current = _profileVerseRefFromJson(
      json,
      indexKey: 'furthestUnreadIndex',
      surahKey: 'currentSurahId',
      verseKey: 'currentVerseId',
    );
    final lastViewed = _profileVerseRefFromJson(
      json,
      indexKey: 'lastViewedIndex',
      surahKey: 'lastViewedSurahId',
      verseKey: 'lastViewedVerseId',
      fallback: current,
    );

    return LocalReadingProfile(
      id: json['id'].toString(),
      userId: json['userId']?.toString() ?? 'local',
      name: json['slug'] == 'main_read' || json['name'] == 'Main Read'
          ? 'Free Read'
          : json['name'].toString(),
      slug: json['slug'] == 'main_read' ? 'free_read' : json['slug'].toString(),
      planMode: json['planMode']?.toString(),
      startJuz: int.tryParse(json['startJuz']?.toString() ?? ''),
      targetJuz: int.tryParse(json['targetJuz']?.toString() ?? ''),
      start: toVerseRef(json['startSurahId'], json['startVerseId']),
      target: targetSurahId != null && targetVerseId != null
          ? toVerseRef(targetSurahId, targetVerseId)
          : null,
      current: current,
      lastViewed: lastViewed,
      sortOrder: int.tryParse(json['sortOrder']?.toString() ?? '') ?? 0,
      isArchived: json['isArchived'] == true,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

const List<int> _quranSurahVerseCounts = [
  7,
  286,
  200,
  176,
  120,
  165,
  206,
  75,
  129,
  109,
  123,
  111,
  43,
  52,
  99,
  128,
  111,
  110,
  98,
  135,
  112,
  78,
  118,
  64,
  77,
  227,
  93,
  88,
  69,
  60,
  34,
  30,
  73,
  54,
  45,
  83,
  182,
  88,
  75,
  85,
  54,
  53,
  89,
  59,
  37,
  35,
  38,
  29,
  18,
  45,
  60,
  49,
  62,
  55,
  78,
  96,
  29,
  22,
  24,
  13,
  14,
  11,
  11,
  18,
  12,
  12,
  30,
  52,
  52,
  44,
  28,
  28,
  20,
  56,
  40,
  31,
  50,
  40,
  46,
  42,
  29,
  19,
  36,
  25,
  22,
  17,
  19,
  26,
  30,
  20,
  15,
  21,
  11,
  8,
  8,
  19,
  5,
  8,
  8,
  11,
  11,
  8,
  3,
  9,
  5,
  4,
  7,
  3,
  6,
  3,
  5,
  4,
  5,
  6,
];

int absoluteVerseIndex(VerseRef verse) {
  final surah = int.tryParse(verse.surahId) ?? 1;
  final ayah = int.tryParse(verse.verseId) ?? 1;
  return absoluteVerseIndexFromParts(surah, ayah);
}

int absoluteVerseIndexFromParts(int surah, int ayah) {
  final safeSurah = surah.clamp(1, _quranSurahVerseCounts.length).toInt();
  final maxAyah = _quranSurahVerseCounts[safeSurah - 1];
  final safeAyah = ayah.clamp(1, maxAyah).toInt();
  var index = safeAyah;
  for (var i = 0; i < safeSurah - 1; i++) {
    index += _quranSurahVerseCounts[i];
  }
  return index;
}

VerseRef verseRefFromAbsoluteIndex(int index) {
  var remaining = index.clamp(1, 6236).toInt();
  for (var i = 0; i < _quranSurahVerseCounts.length; i++) {
    final count = _quranSurahVerseCounts[i];
    if (remaining <= count) {
      return toVerseRef(i + 1, remaining);
    }
    remaining -= count;
  }
  return toVerseRef(114, 6);
}

VerseRef _profileVerseRefFromJson(
  Map<String, dynamic> json, {
  required String indexKey,
  required String surahKey,
  required String verseKey,
  VerseRef? fallback,
}) {
  final index = int.tryParse(json[indexKey]?.toString() ?? '');
  if (index != null) return verseRefFromAbsoluteIndex(index);

  final surah = json[surahKey];
  final verse = json[verseKey];
  if (surah != null && verse != null) return toVerseRef(surah, verse);

  return fallback ?? toVerseRef(1, 1);
}

class LocalBookmarkCategory {
  final String id;
  final String userId;
  final String name;
  final String slug;
  final int maxItems;
  final int sortOrder;

  const LocalBookmarkCategory({
    required this.id,
    required this.userId,
    required this.name,
    required this.slug,
    required this.maxItems,
    required this.sortOrder,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'slug': slug,
      'maxItems': maxItems,
      'sortOrder': sortOrder,
    };
  }

  factory LocalBookmarkCategory.fromJson(Map<String, dynamic> json) {
    return LocalBookmarkCategory(
      id: json['id'].toString(),
      userId: json['userId']?.toString() ?? 'local',
      name: json['name'].toString(),
      slug: json['slug'].toString(),
      maxItems:
          int.tryParse(json['maxItems']?.toString() ?? '') ??
          defaultBookmarkCategoryMaxItems,
      sortOrder: int.tryParse(json['sortOrder']?.toString() ?? '') ?? 0,
    );
  }
}

class LocalBookmark {
  final String id;
  final String userId;
  final String categoryId;
  final VerseRef verse;
  final String? label;
  final String? note;
  final int sortOrder;
  final DateTime createdAt;

  const LocalBookmark({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.verse,
    this.label,
    this.note,
    required this.sortOrder,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'categoryId': categoryId,
      'surahId': verse.surahId,
      'verseId': verse.verseId,
      if (label != null) 'label': label,
      if (note != null) 'note': note,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory LocalBookmark.fromJson(Map<String, dynamic> json) {
    return LocalBookmark(
      id: json['id'].toString(),
      userId: json['userId']?.toString() ?? 'local',
      categoryId: json['categoryId'].toString(),
      verse: toVerseRef(json['surahId'], json['verseId']),
      label: json['label']?.toString(),
      note: json['note']?.toString(),
      sortOrder: int.tryParse(json['sortOrder']?.toString() ?? '') ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class LocalRecentReading {
  final String id;
  final String userId;
  final VerseRef verse;
  final String? profileId;
  final DateTime readAt;

  const LocalRecentReading({
    required this.id,
    required this.userId,
    required this.verse,
    this.profileId,
    required this.readAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'surahId': verse.surahId,
      'verseId': verse.verseId,
      if (profileId != null) 'profileId': profileId,
      'readAt': readAt.toIso8601String(),
    };
  }

  factory LocalRecentReading.fromJson(Map<String, dynamic> json) {
    return LocalRecentReading(
      id: json['id'].toString(),
      userId: json['userId']?.toString() ?? 'local',
      verse: toVerseRef(json['surahId'], json['verseId']),
      profileId: json['profileId']?.toString(),
      readAt:
          DateTime.tryParse(json['readAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class LocalReadingProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const _storageKey = 'thai_quran_local_reading_store_v1';
  static const _localUserId = 'local';

  List<LocalReadingProfile> _profiles = [];
  List<LocalBookmarkCategory> _categories = [];
  List<LocalBookmark> _bookmarks = [];
  List<LocalRecentReading> _recentReadings = [];
  Set<String> _readDates = {};
  String? _activeProfileId;
  final Completer<void> _loadCompleter = Completer<void>();

  StreamSubscription<AuthState>? _authSubscription;
  Timer? _saveTimer;
  Timer? _recentReadingSyncTimer;
  Timer? _profileSyncTimer;
  String? _pendingSyncSurahId;
  String? _pendingSyncVerseId;
  String? _pendingSyncUserId;
  bool _isFlushingProfileSync = false;
  final Map<String, LocalReadingProfile> _pendingProfileSyncs = {};

  Timer? _readingStateSyncTimer;
  int? _pendingReadingStateVerseIndex;
  String? _pendingReadingStateUserId;

  String get currentUserId =>
      Supabase.instance.client.auth.currentUser?.id ?? _localUserId;

  List<LocalReadingProfile> get profiles {
    final userProfiles = _profiles
        .where((p) => p.userId == currentUserId && !isShortcutProfile(p))
        .toList();
    final hasCustomActive = userProfiles.any(
      (p) => !isFreeReadProfile(p) && !p.isArchived,
    );
    if (hasCustomActive) {
      return userProfiles.where((p) => !isFreeReadProfile(p)).toList();
    }
    return userProfiles;
  }

  List<LocalReadingProfile> get activeProfiles {
    final allActive = _profiles
        .where(
          (profile) => !profile.isArchived && profile.userId == currentUserId && !isShortcutProfile(profile),
        )
        .toList();
    final hasCustomActive = allActive.any((p) => !isFreeReadProfile(p));
    if (hasCustomActive) {
      return allActive
          .where((p) => !isFreeReadProfile(p))
          .toList(growable: false);
    }
    return allActive;
  }

  List<LocalReadingProfile> get archivedProfiles {
    final allArchived = _profiles
        .where(
          (profile) => profile.isArchived && profile.userId == currentUserId && !isShortcutProfile(profile),
        )
        .toList();
    return allArchived
        .where((p) => !isFreeReadProfile(p))
        .toList(growable: false);
  }

  List<LocalBookmarkCategory> get categories =>
      _categories.where((c) => c.userId == currentUserId).toList();
  List<LocalBookmark> get bookmarks =>
      _bookmarks.where((b) => b.userId == currentUserId).toList();
  List<LocalRecentReading> get recentReadings =>
      _recentReadings.where((r) => r.userId == currentUserId).toList();
  String? get activeProfileId => _activeProfileId;
  LocalReadingProfile? get freeReadProfile => _profiles
      .where((profile) => profile.userId == currentUserId)
      .where(isFreeReadProfile)
      .firstOrNull;

  LocalReadingProfile? profileById(String profileId) {
    return _profiles
        .where((profile) => profile.userId == currentUserId)
        .where((profile) => profile.id == profileId)
        .firstOrNull;
  }

  LocalReadingProfile? get activeProfile {
    final allUserProfiles = _profiles
        .where((p) => p.userId == currentUserId && !p.isArchived)
        .toList();
    final explicitActive = allUserProfiles
        .where((profile) => profile.id == _activeProfileId)
        .firstOrNull;
    if (explicitActive != null) return explicitActive;

    final userProfiles = profiles;
    if (userProfiles.isEmpty) return null;
    final active = userProfiles.where(
      (profile) => profile.id == _activeProfileId,
    );
    if (active.isNotEmpty) return active.first;
    final activeList = activeProfiles;
    return activeList.isNotEmpty ? activeList.first : userProfiles.first;
  }

  bool get canCreateProfile =>
      canCreateActiveReadingProfile(activeProfiles.length);

  bool isVerseInsideProfile(
    LocalReadingProfile profile,
    String surahId,
    String verseId,
  ) {
    if (profile.target == null || isFreeReadProfile(profile)) return true;

    final ref = toVerseRef(surahId, verseId);
    return _compareVerseRefs(ref, profile.start) >= 0 &&
        _compareVerseRefs(ref, profile.target!) <= 0;
  }

  Future<bool> switchToFreeReadIfOutside(String surahId, String verseId) async {
    final profile = activeProfile;
    final freeRead = freeReadProfile;
    if (profile == null ||
        freeRead == null ||
        isVerseInsideProfile(profile, surahId, verseId)) {
      return false;
    }

    final now = DateTime.now();
    final freeReadRef = toVerseRef(surahId, verseId);
    _profiles = _profiles
        .map(
          (item) => item.id == freeRead.id
              ? item.copyWith(current: freeReadRef, updatedAt: now)
              : item,
        )
        .toList();
    _activeProfileId = freeRead.id;
    await _save(immediate: true);
    notifyListeners();
    return true;
  }

  int _compareVerseRefs(VerseRef left, VerseRef right) {
    final leftSurah = int.tryParse(left.surahId) ?? 0;
    final rightSurah = int.tryParse(right.surahId) ?? 0;
    if (leftSurah != rightSurah) return leftSurah.compareTo(rightSurah);

    final leftVerse = int.tryParse(left.verseId) ?? 0;
    final rightVerse = int.tryParse(right.verseId) ?? 0;
    return leftVerse.compareTo(rightVerse);
  }

  LocalReadingProvider() {
    WidgetsBinding.instance.addObserver(this);
    _load();
    _listenToAuthChanges();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(flushPendingProfileSyncs());
      unawaited(flushPendingRecentReadingSync());
      unawaited(flushPendingReadingStateSync());
    }
  }

  void _listenToAuthChanges() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      await _loadCompleter.future;
      final user = data.session?.user;
      if (user != null) {
        await syncBookmarksAndProfilesWithSupabase(user.id);
        await syncReadingStateWithSupabase(user.id);
      } else {
        // Guard logout: ensure guest profiles are preserved and default is active
        _ensureDefaultProfile();
        final guestActive = _profiles
            .where((p) => p.userId == _localUserId && !p.isArchived)
            .firstOrNull;
        _activeProfileId =
            guestActive?.id ??
            _profiles.where((p) => p.userId == _localUserId).firstOrNull?.id;
        await _save(immediate: true);
        notifyListeners();
      }
    });
  }

  LocalReadingProfile? _getLatestReadProfile(
    List<LocalReadingProfile> userProfiles,
  ) {
    final activeList = userProfiles.where((p) => !p.isArchived).toList();
    if (activeList.isEmpty) return null;

    // Sort by updatedAt descending (newest first)
    activeList.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final first = activeList.first;
    if (isFreeReadProfile(first)) {
      // If the newest read profile is "Free Read", look for the 2nd latest (which is NOT Free Read)
      for (int i = 1; i < activeList.length; i++) {
        if (!isFreeReadProfile(activeList[i])) {
          return activeList[i];
        }
      }
    }
    return first;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    unawaited(flushPendingProfileSyncs());
    unawaited(flushPendingRecentReadingSync());
    unawaited(flushPendingReadingStateSync());
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _executeSave();
    }
    super.dispose();
  }

  Future<void> syncBookmarksAndProfilesWithSupabase(String userId) async {
    try {
      final client = Supabase.instance.client;
      // Get the default category ID
      final catQuery = await client
          .from('bookmark_categories')
          .select('id')
          .eq('user_id', userId)
          .eq('slug', 'saved_verses')
          .maybeSingle();

      String? serverCatId = catQuery?['id']?.toString();
      if (serverCatId == null) {
        final upserted = await client
            .from('bookmark_categories')
            .upsert({
              'user_id': userId,
              'name': 'Saved Verses',
              'slug': 'saved_verses',
              'max_items': 9999,
              'sort_order': 0,
            })
            .select('id')
            .single();
        serverCatId = upserted['id']?.toString();
      }

      if (serverCatId != null) {
        // Fetch remote bookmarks
        final response = await client
            .from('bookmarks')
            .select(
              'id, surah_id, verse_id, label, note, sort_order, created_at, category_id',
            )
            .eq('user_id', userId);

        final List<dynamic> dbBookmarks = response;
        final List<LocalBookmark> syncedBookmarks = [];

        for (final dbB in dbBookmarks) {
          syncedBookmarks.add(
            LocalBookmark(
              id: dbB['id'].toString(),
              userId: userId,
              categoryId: dbB['category_id'].toString(),
              verse: toVerseRef(dbB['surah_id'], dbB['verse_id']),
              label: dbB['label']?.toString(),
              note: dbB['note']?.toString(),
              sortOrder: int.tryParse(dbB['sort_order']?.toString() ?? '') ?? 0,
              createdAt:
                  DateTime.tryParse(dbB['created_at']?.toString() ?? '') ??
                  DateTime.now(),
            ),
          );
        }

        final otherBookmarks = _bookmarks
            .where((b) => b.userId != userId)
            .toList();
        _bookmarks = otherBookmarks + syncedBookmarks;

        final otherCategories = _categories
            .where((c) => c.userId != userId)
            .toList();
        _categories =
            otherCategories +
            [
              LocalBookmarkCategory(
                id: serverCatId,
                userId: userId,
                name: 'Saved Verses',
                slug: 'saved_verses',
                maxItems: 5,
                sortOrder: 0,
              ),
            ];

        // Fetch remote recent readings
        try {
          List<dynamic> dbRecent;
          try {
            dbRecent = await client
                .from('recent_readings')
                .select('id, surah_id, verse_id, read_at, profile_id')
                .eq('user_id', userId)
                .order('read_at', ascending: false)
                .limit(20);
          } catch (_) {
            dbRecent = await client
                .from('recent_readings')
                .select('id, surah_id, last_read_verse, updated_at, profile_id')
                .eq('user_id', userId)
                .order('updated_at', ascending: false)
                .limit(20);
          }

          final otherRecent = _recentReadings
              .where((r) => r.userId != userId)
              .toList();
          final userRecent = _recentReadings
              .where((r) => r.userId == userId)
              .toList();

          final List<LocalRecentReading> reconciledRecent = [];
          final Set<String> matchedKeys = {};

          for (final localR in userRecent) {
            final dbR = _firstMapWhereOrNull(
              dbRecent,
              (item) =>
                  item['surah_id'].toString() == localR.verse.surahId &&
                  item['profile_id']?.toString() == localR.profileId,
            );

            if (dbR != null) {
              matchedKeys.add('${localR.verse.surahId}-${localR.profileId}');
              final remoteDate =
                  DateTime.tryParse(
                    (dbR['read_at'] ?? dbR['updated_at'])?.toString() ?? '',
                  ) ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final remoteVerseId = (dbR['verse_id'] ?? dbR['last_read_verse'])
                  .toString();

              if (localR.readAt.isAfter(remoteDate)) {
                // Local is newer, keep it and push it
                reconciledRecent.add(localR);
                _debounceRecentReadingSync(
                  userId,
                  localR.verse.surahId,
                  localR.verse.verseId,
                );
              } else {
                // Remote is newer, keep it
                reconciledRecent.add(
                  LocalRecentReading(
                    id: dbR['id'].toString(),
                    userId: userId,
                    verse: toVerseRef(dbR['surah_id'], remoteVerseId),
                    profileId: dbR['profile_id']?.toString(),
                    readAt: remoteDate,
                  ),
                );
              }
            } else {
              // Local only, keep it and push it
              reconciledRecent.add(localR);
              _debounceRecentReadingSync(
                userId,
                localR.verse.surahId,
                localR.verse.verseId,
              );
            }
          }

          for (final dbR in dbRecent) {
            final key = '${dbR['surah_id']}-${dbR['profile_id']}';
            if (matchedKeys.contains(key)) continue;
            final remoteVerseId = (dbR['verse_id'] ?? dbR['last_read_verse'])
                .toString();

            reconciledRecent.add(
              LocalRecentReading(
                id: dbR['id'].toString(),
                userId: userId,
                verse: toVerseRef(dbR['surah_id'], remoteVerseId),
                profileId: dbR['profile_id']?.toString(),
                readAt:
                    DateTime.tryParse(
                      (dbR['read_at'] ?? dbR['updated_at'])?.toString() ?? '',
                    ) ??
                    DateTime.now(),
              ),
            );
          }

          reconciledRecent.sort((a, b) => b.readAt.compareTo(a.readAt));

          _recentReadings = otherRecent + reconciledRecent;
        } catch (e) {
          debugPrint('Error syncing recent readings: $e');
        }

        // Run reconciliation
        await reconcileProfilesOnBoot(userId);

        await _save(immediate: true);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error syncing bookmarks/profiles with Supabase: $e');
    }
  }

  Future<void> reconcileProfilesOnBoot(String userId) async {
    try {
      final client = Supabase.instance.client;

      // 1. Fetch remote profiles from the shared reading_profiles contract.
      final response = await client
          .from('reading_profiles')
          .select('*')
          .eq('user_id', userId);

      final List<Map<String, dynamic>> dbProfiles = response
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      await _promoteLegacyReadingProfiles(
        client: client,
        userId: userId,
        dbProfiles: dbProfiles,
      );

      // Helper to check if string is a valid UUID
      final uuidRegExp = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      );
      bool isValidUuid(String id) => uuidRegExp.hasMatch(id);

      final List<LocalReadingProfile> reconciledProfiles = [];
      final Set<String> matchedRemoteIds = {};
      final Set<String> profilesToSync = {};
      bool localStateChanged = false;
      bool hasRemoteUpdates = false;

      // Index remote profiles by id and slug/name for fast lookup.
      final Map<String, Map<String, dynamic>> remoteById = {};
      final Map<String, Map<String, dynamic>> remoteBySlug = {};
      for (final dbP in dbProfiles) {
        final rId = dbP['id']?.toString();
        final rSlug = dbP['slug']?.toString();
        if (rId != null) remoteById[rId] = dbP;
        if (rSlug != null) remoteBySlug[rSlug.toLowerCase()] = dbP;
      }

      // Iterate through local profiles
      for (final localP in _profiles) {
        if (localP.userId != userId) {
          // Keep other users' or local guest profiles untouched
          reconciledProfiles.add(localP);
          continue;
        }

        // Try to match local profile with a remote profile
        Map<String, dynamic>? matchedRemote;
        if (isValidUuid(localP.id) && remoteById.containsKey(localP.id)) {
          matchedRemote = remoteById[localP.id];
        } else if (remoteBySlug.containsKey(localP.slug.toLowerCase())) {
          matchedRemote = remoteBySlug[localP.slug.toLowerCase()];
        }

        if (matchedRemote != null) {
          final remoteId = matchedRemote['id'].toString();
          matchedRemoteIds.add(remoteId);

          final remoteUpdatedAt =
              DateTime.tryParse(
                matchedRemote['updated_at']?.toString() ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final localUpdatedAt = localP.updatedAt;

          final remoteIsArchived = matchedRemote['is_archived'] == true;
          if (!remoteIsArchived && localUpdatedAt.isAfter(remoteUpdatedAt)) {
            // Local is newer: keep local and mark for sync to remote
            reconciledProfiles.add(localP.copyWith(id: remoteId));
            profilesToSync.add(remoteId);
          } else {
            // Remote is newer or equal: update local with remote profile state.
            if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
              hasRemoteUpdates = true;
            }

            reconciledProfiles.add(
              _profileFromReadingProfileRow(dbP: matchedRemote),
            );
            localStateChanged = true;
          }
        } else {
          // Local-only: keep local and mark for sync to remote
          reconciledProfiles.add(localP);
          profilesToSync.add(localP.id);
        }
      }

      // 3. Remote-only profiles: insert into local storage
      for (final dbP in dbProfiles) {
        final remoteId = dbP['id'].toString();
        if (matchedRemoteIds.contains(remoteId)) continue;

        final rSlug = dbP['slug']?.toString() ?? '';
        // Double check we don't duplicate by name
        if (reconciledProfiles.any(
          (p) =>
              p.userId == userId && p.slug.toLowerCase() == rSlug.toLowerCase(),
        )) {
          continue;
        }

        reconciledProfiles.add(_profileFromReadingProfileRow(dbP: dbP));
        localStateChanged = true;
        hasRemoteUpdates = true;
      }

      // Update local profiles list
      _profiles = reconciledProfiles;
      _ensureDefaultProfile();

      // Update active profile ID if needed
      final userProfiles = _profiles.where((p) => p.userId == userId).toList();
      final belongsToUser = userProfiles.any((p) => p.id == _activeProfileId);
      if (!belongsToUser || hasRemoteUpdates) {
        final latest = _getLatestReadProfile(userProfiles);
        if (latest != null && latest.id != _activeProfileId) {
          _activeProfileId = latest.id;
          localStateChanged = true;
        }
      }

      if (localStateChanged || profilesToSync.isNotEmpty) {
        await _save(immediate: true);
        notifyListeners();
      }

      // Sync local-newer and local-only profiles to Supabase
      for (final id in profilesToSync) {
        final p = _profiles.where((p) => p.id == id).firstOrNull;
        if (p != null) {
          await _syncProfileToSupabase(p);
        }
      }
    } catch (e) {
      debugPrint('Error in reconcileProfilesOnBoot: $e');
    }
  }

  LocalReadingProfile _profileFromReadingProfileRow({
    required Map<String, dynamic> dbP,
  }) {
    final furthestIndex = int.tryParse(
      dbP['furthest_unread_index']?.toString() ?? '',
    );
    final lastViewedIndex = int.tryParse(
      dbP['last_viewed_index']?.toString() ?? '',
    );
    final current = furthestIndex == null
        ? toVerseRef(
            dbP['current_surah_id']?.toString() ?? '1',
            dbP['current_verse_id']?.toString() ?? '1',
          )
        : verseRefFromAbsoluteIndex(furthestIndex);
    final lastViewed = lastViewedIndex == null
        ? current
        : verseRefFromAbsoluteIndex(lastViewedIndex);
    final targetSurahId = dbP['target_surah_id']?.toString();
    final targetVerseId = dbP['target_verse_id']?.toString();
    final updatedAt =
        DateTime.tryParse(dbP['updated_at']?.toString() ?? '') ??
        DateTime.now();

    return LocalReadingProfile(
      id: dbP['id'].toString(),
      userId: dbP['user_id']?.toString() ?? currentUserId,
      name: dbP['name']?.toString() ?? 'Free Read',
      slug:
          dbP['slug']?.toString() ??
          slugifyReadingProfileName(dbP['name']?.toString() ?? 'Free Read'),
      planMode: dbP['plan_mode']?.toString(),
      startJuz: int.tryParse(dbP['start_juz']?.toString() ?? ''),
      targetJuz: int.tryParse(dbP['target_juz']?.toString() ?? ''),
      start: toVerseRef(
        dbP['start_surah_id']?.toString() ?? '1',
        dbP['start_verse_id']?.toString() ?? '1',
      ),
      target: targetSurahId != null && targetVerseId != null
          ? toVerseRef(targetSurahId, targetVerseId)
          : null,
      current: current,
      lastViewed: lastViewed,
      sortOrder: int.tryParse(dbP['sort_order']?.toString() ?? '') ?? 0,
      isArchived: dbP['is_archived'] == true,
      createdAt:
          DateTime.tryParse(dbP['created_at']?.toString() ?? '') ?? updatedAt,
      updatedAt: updatedAt,
    );
  }

  Future<void> _promoteLegacyReadingProfiles({
    required SupabaseClient client,
    required String userId,
    required List<Map<String, dynamic>> dbProfiles,
  }) async {
    try {
      final legacyRows = await client
          .from('user_reading_profiles')
          .select('*')
          .eq('user_id', userId);
      final existingSlugs = dbProfiles
          .map((row) => row['slug']?.toString().toLowerCase())
          .whereType<String>()
          .toSet();
      final existingIds = dbProfiles
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toSet();

      for (final legacy in legacyRows.whereType<Map>()) {
        final row = legacy.cast<String, dynamic>();
        final legacyId = row['id']?.toString();
        final name = row['profile_name']?.toString() ?? 'Free Read';
        final slug = slugifyReadingProfileName(name);
        if (existingSlugs.contains(slug.toLowerCase()) ||
            (legacyId != null && existingIds.contains(legacyId))) {
          continue;
        }

        final furthestIndex = int.tryParse(
          row['furthest_unread_index']?.toString() ?? '',
        );
        final current = furthestIndex == null
            ? toVerseRef(
                row['current_surah']?.toString() ?? '1',
                row['current_ayah']?.toString() ?? '1',
              )
            : verseRefFromAbsoluteIndex(furthestIndex);
        final lastViewedIndex = int.tryParse(
          row['last_viewed_index']?.toString() ?? '',
        );
        final lastViewed = lastViewedIndex == null
            ? current
            : verseRefFromAbsoluteIndex(lastViewedIndex);
        final updatedAt =
            DateTime.tryParse(row['last_read_at']?.toString() ?? '') ??
            DateTime.now();

        final promoted = LocalReadingProfile(
          id: legacyId ?? _createLocalId(),
          userId: userId,
          name: isFreeReadProfileName(name) ? 'Free Read' : name,
          slug: isFreeReadProfileName(name) ? 'free_read' : slug,
          start: toVerseRef(1, 1),
          current: current,
          lastViewed: lastViewed,
          sortOrder: dbProfiles.length,
          isArchived: false,
          createdAt:
              DateTime.tryParse(row['created_at']?.toString() ?? '') ??
              updatedAt,
          updatedAt: updatedAt,
        );
        await _syncProfileToSupabase(promoted);
        dbProfiles.add(_readingProfileRowFromLocal(promoted));
        existingSlugs.add(promoted.slug.toLowerCase());
        existingIds.add(promoted.id);
      }
    } catch (e) {
      debugPrint('Error promoting legacy reading profiles: $e');
    }
  }

  Map<String, dynamic> _readingProfileRowFromLocal(LocalReadingProfile p) {
    return {
      'id': p.id,
      'user_id': p.userId,
      'name': p.name,
      'slug': p.slug,
      'plan_mode': p.planMode,
      'start_juz': p.startJuz,
      'target_juz': p.targetJuz,
      'start_surah_id': p.start.surahId,
      'start_verse_id': p.start.verseId,
      'target_surah_id': p.target?.surahId,
      'target_verse_id': p.target?.verseId,
      'current_surah_id': p.current.surahId,
      'current_verse_id': p.current.verseId,
      'furthest_unread_index': p.furthestUnreadIndex,
      'last_viewed_index': p.lastViewedIndex,
      'sort_order': p.sortOrder,
      'is_archived': p.isArchived,
      'created_at': p.createdAt.toIso8601String(),
      'updated_at': p.updatedAt.toIso8601String(),
    };
  }

  Future<void> _syncProfileToSupabase(LocalReadingProfile p) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user != null && p.userId != 'local') {
      try {
        final uuidRegExp = RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        );
        final bool hasUuid = uuidRegExp.hasMatch(p.id);

        final upsertData = {
          'user_id': user.id,
          'name': p.name,
          'slug': p.slug,
          'plan_mode': isFreeReadProfile(p) ? null : p.planMode,
          'start_juz': p.startJuz,
          'target_juz': p.targetJuz,
          'start_surah_id': p.start.surahId,
          'start_verse_id': p.start.verseId,
          'target_surah_id': p.target?.surahId,
          'target_verse_id': p.target?.verseId,
          'current_surah_id': p.current.surahId,
          'current_verse_id': p.current.verseId,
          'furthest_unread_index': p.furthestUnreadIndex,
          'last_viewed_index': p.lastViewedIndex,
          'sort_order': p.sortOrder,
          'is_archived': p.isArchived,
          'updated_at': p.updatedAt.toIso8601String(),
        };

        if (hasUuid) {
          upsertData['id'] = p.id;
        }

        final response = hasUuid
            ? await client
                  .from('reading_profiles')
                  .upsert(upsertData, onConflict: 'id')
                  .select('id')
                  .single()
            : await client
                  .from('reading_profiles')
                  .insert(upsertData)
                  .select('id')
                  .single();

        final returnedId = response['id']?.toString();
        if (returnedId != null && returnedId != p.id) {
          // Update profile ID locally
          final index = _profiles.indexWhere((item) => item.id == p.id);
          if (index != -1) {
            final oldP = _profiles[index];
            final newP = LocalReadingProfile(
              id: returnedId,
              userId: oldP.userId,
              name: oldP.name,
              slug: oldP.slug,
              planMode: oldP.planMode,
              startJuz: oldP.startJuz,
              targetJuz: oldP.targetJuz,
              start: oldP.start,
              target: oldP.target,
              current: oldP.current,
              lastViewed: oldP.lastViewed,
              sortOrder: oldP.sortOrder,
              isArchived: oldP.isArchived,
              createdAt: oldP.createdAt,
              updatedAt: oldP.updatedAt,
            );
            _profiles[index] = newP;
            if (_activeProfileId == p.id) {
              _activeProfileId = returnedId;
            }
            await _save(immediate: true);
            notifyListeners();
          }
        }
      } catch (e) {
        debugPrint('Error syncing profile to Supabase: $e');
        rethrow;
      }
    }
  }

  void _queueProfileSync(
    LocalReadingProfile profile, {
    Duration delay = const Duration(milliseconds: 900),
  }) {
    if (profile.userId == _localUserId) return;
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
    final pending = Map<String, LocalReadingProfile>.from(_pendingProfileSyncs);
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

  Future<void> _deleteProfileFromSupabase(LocalReadingProfile profile) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || profile.userId == 'local') return;

    try {
      final archivedAt = DateTime.now().toIso8601String();
      final uuidRegExp = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      );
      if (uuidRegExp.hasMatch(profile.id)) {
        await Supabase.instance.client
            .from('reading_profiles')
            .update({'is_archived': true, 'updated_at': archivedAt})
            .eq('id', profile.id);
      } else {
        await Supabase.instance.client
            .from('reading_profiles')
            .update({'is_archived': true, 'updated_at': archivedAt})
            .eq('user_id', user.id)
            .eq('slug', profile.slug);
      }
      await Supabase.instance.client
          .from('user_reading_profiles')
          .delete()
          .eq('user_id', user.id)
          .eq('profile_name', profile.name);
    } catch (e) {
      debugPrint('Error deleting reading profile from Supabase: $e');
    }
  }

  Future<LocalReadingProfile> createProfile({
    required String name,
    required VerseRef start,
    VerseRef? target,
    VerseRef? current,
    String? planMode,
    int? startJuz,
    int? targetJuz,
    BuildContext? context,
  }) async {
    await _loadCompleter.future;
    if (!canCreateProfile) {
      throw StateError(
        'Only $maxActiveReadingProfiles active reading profiles are allowed.',
      );
    }

    final now = DateTime.now();
    final slug = _uniqueSlug(slugifyReadingProfileName(name));
    final profile = LocalReadingProfile(
      id: _createLocalId(),
      userId: currentUserId,
      name: name,
      slug: slug,
      planMode: planMode,
      startJuz: startJuz,
      targetJuz: targetJuz,
      start: start,
      target: target,
      current: current ?? start,
      sortOrder: activeProfiles.length,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final prefs = await SharedPreferences.getInstance();

      final updatedProfiles = [..._profiles, profile];
      final newActiveProfileId = profile.id;

      final dataString = json.encode({
        'activeProfileId': newActiveProfileId,
        'profiles': updatedProfiles.map((p) => p.toJson()).toList(),
        'categories': _categories.map((c) => c.toJson()).toList(),
        'bookmarks': _bookmarks.map((b) => b.toJson()).toList(),
        'recentReadings': _recentReadings.map((r) => r.toJson()).toList(),
      });

      final success = await prefs.setString(_storageKey, dataString);
      if (!success) {
        throw const StorageException(
          'Failed to write profiles to SharedPreferences.',
        );
      }

      // Succeeded: update in-memory state
      _profiles.add(profile);
      _activeProfileId = profile.id;
      notifyListeners();

      _queueProfileSync(profile, delay: Duration.zero);
      return profile;
    } catch (e) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save to device storage.')),
        );
      }
      debugPrint(
        'local_reading_provider: StorageException in createProfile: $e',
      );
      throw const StorageException('Failed to save to device storage.');
    }
  }

  Future<void> updateProfile({
    required String profileId,
    required String name,
    required VerseRef start,
    VerseRef? target,
    String? planMode,
    int? startJuz,
    int? targetJuz,
  }) async {
    await _loadCompleter.future;
    final profile = _profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null || isFreeReadProfile(profile)) return;

    final updated = profile.copyWith(
      name: name,
      planMode: planMode,
      startJuz: startJuz,
      targetJuz: targetJuz,
      start: start,
      target: target,
      clearTarget: target == null,
      current: start,
      updatedAt: DateTime.now(),
    );

    _profiles = _profiles
        .map((item) => item.id == profileId ? updated : item)
        .toList();
    await _save(immediate: true);
    notifyListeners();

    _queueProfileSync(updated, delay: Duration.zero);
  }

  Future<void> deleteProfile(String profileId) async {
    await archiveProfile(profileId);
  }

  Future<void> setActiveProfile(String profileId) async {
    await _loadCompleter.future;
    if (!_profiles.any((profile) => profile.id == profileId)) return;
    _activeProfileId = profileId;
    await _save(immediate: true);
    notifyListeners();
  }

  Future<void> updateProfileProgress(
    String profileId,
    VerseRef current, {
    BuildContext? context,
  }) async {
    await _loadCompleter.future;
    final existingProfile = _profiles
        .where((profile) => profile.id == profileId)
        .firstOrNull;
    if (existingProfile == null ||
        !isVerseInsideProfile(
          existingProfile,
          current.surahId,
          current.verseId,
        )) {
      return;
    }

    final now = DateTime.now();
    markReadToday();
    final currentIndex = absoluteVerseIndex(current);
    final furthestIndex = existingProfile.furthestUnreadIndex;
    final shouldAdvanceFurthest = currentIndex > furthestIndex;

    // 1. Prepare updated profiles list (cloned in memory)
    final updatedProfiles = _profiles.map((profile) {
      if (profile.id == profileId) {
        return profile.copyWith(
          current: shouldAdvanceFurthest ? current : profile.current,
          lastViewed: current,
          updatedAt: now,
        );
      }
      return profile;
    }).toList();

    // 2. Enforce Disk-First Guarantee: Attempt to save to disk first
    try {
      final prefs = await SharedPreferences.getInstance();

      // Update reading state timestamp on disk
      final timestampSuccess = await prefs.setString(
        'user_reading_state_updated_at',
        now.toIso8601String(),
      );
      if (!timestampSuccess) {
        throw const StorageException(
          'Failed to write timestamp to SharedPreferences.',
        );
      }

      // Serialize and write profiles list to disk
      final dataString = json.encode({
        'activeProfileId': _activeProfileId,
        'profiles': updatedProfiles.map((p) => p.toJson()).toList(),
        'categories': _categories.map((c) => c.toJson()).toList(),
        'bookmarks': _bookmarks.map((b) => b.toJson()).toList(),
        'recentReadings': _recentReadings.map((r) => r.toJson()).toList(),
      });

      final success = await prefs.setString(_storageKey, dataString);
      if (!success) {
        throw const StorageException(
          'Failed to write profiles to SharedPreferences.',
        );
      }

      // 3. Disk write succeeded: update in-memory state and notify listeners
      _profiles = updatedProfiles;
      notifyListeners();

      // Sync to Supabase
      final updatedProfile = _profiles
          .where((item) => item.id == profileId)
          .firstOrNull;
      if (updatedProfile != null) {
        _queueProfileSync(updatedProfile, delay: Duration.zero);
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && isFreeReadProfile(existingProfile)) {
        _debounceReadingStateSync(user.id, currentIndex);
      }
    } catch (e) {
      // 4. Failed: emit SnackBar & throw exception (in-memory state was not mutated)
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save to device storage.')),
        );
      }
      debugPrint(
        'local_reading_provider: StorageException in updateProfileProgress: $e',
      );
      throw const StorageException('Failed to save to device storage.');
    }
  }

  Future<void> archiveProfile(String profileId) async {
    await _loadCompleter.future;
    final profile = _profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null || isFreeReadProfile(profile)) return;

    final updated = profile.copyWith(
      isArchived: true,
      updatedAt: DateTime.now(),
    );
    _profiles = _profiles.map((p) => p.id == profileId ? updated : p).toList();

    if (_activeProfileId == profileId) {
      final userProfiles = _profiles
          .where((p) => p.userId == currentUserId)
          .toList();
      final latest = _getLatestReadProfile(userProfiles);
      _activeProfileId = latest?.id;
    }

    await _save(immediate: true);
    notifyListeners();

    await _deleteProfileFromSupabase(updated);
  }

  Future<void> restoreProfile(String profileId) async {
    await _loadCompleter.future;
    if (!canCreateProfile) {
      throw StateError(
        'Only $maxActiveReadingProfiles active reading profiles are allowed.',
      );
    }

    final profile = _profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null) return;

    final updated = profile.copyWith(
      isArchived: false,
      updatedAt: DateTime.now(),
    );
    _profiles = _profiles.map((p) => p.id == profileId ? updated : p).toList();
    await _save(immediate: true);
    notifyListeners();

    _queueProfileSync(updated, delay: Duration.zero);
  }

  Future<LocalBookmarkCategory> ensureBookmarkCategory({
    String name = 'Saved Verses',
    int maxItems = defaultBookmarkCategoryMaxItems,
  }) async {
    await _loadCompleter.future;
    final slug = slugifyReadingProfileName(name);
    final curUserId = currentUserId;
    final existing = _categories
        .where(
          (category) => category.slug == slug && category.userId == curUserId,
        )
        .firstOrNull;
    if (existing != null) return existing;

    final category = LocalBookmarkCategory(
      id: _createLocalId(),
      userId: curUserId,
      name: name,
      slug: slug,
      maxItems: maxItems,
      sortOrder: _categories.length,
    );

    _categories.add(category);
    await _save(immediate: true);
    notifyListeners();
    return category;
  }

  bool isBookmarked(String surahId, String verseId) {
    final numericSurah = int.tryParse(surahId) ?? 0;
    final numericVerse = int.tryParse(verseId) ?? 0;
    final uid = currentUserId;
    return _bookmarks.any((b) {
      final bSurah = int.tryParse(b.verse.surahId) ?? 0;
      final bVerse = int.tryParse(b.verse.verseId) ?? 0;
      return bSurah == numericSurah &&
          bVerse == numericVerse &&
          b.userId == uid;
    });
  }

  Future<void> toggleBookmark(String surahId, String verseId) async {
    final numericSurah = int.tryParse(surahId) ?? 0;
    final numericVerse = int.tryParse(verseId) ?? 0;
    final uid = currentUserId;
    final existing = _bookmarks.where((b) {
      final bSurah = int.tryParse(b.verse.surahId) ?? 0;
      final bVerse = int.tryParse(b.verse.verseId) ?? 0;
      // Only consider bookmarks belonging to the current user
      return bSurah == numericSurah &&
          bVerse == numericVerse &&
          b.userId == uid;
    }).firstOrNull;

    if (existing != null) {
      await removeBookmark(existing.id);
    } else {
      // Let StateError (e.g. bookmark limit) propagate so callers can show feedback
      await addBookmark(verse: toVerseRef(surahId, verseId));
    }
  }

  Future<LocalBookmark> addBookmark({
    required VerseRef verse,
    String? categoryId,
    String? label,
    String? note,
  }) async {
    await _loadCompleter.future;
    final category = categoryId == null
        ? await ensureBookmarkCategory()
        : _categories.firstWhere((item) => item.id == categoryId);
    final categoryBookmarks = _bookmarks
        .where((bookmark) => bookmark.categoryId == category.id)
        .toList();

    final existing = categoryBookmarks
        .where((bookmark) => bookmark.verse.verseKey == verse.verseKey)
        .firstOrNull;
    if (existing != null) return existing;

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user != null) {
      try {
        final inserted = await client
            .from('bookmarks')
            .insert({
              'user_id': user.id,
              'category_id': category.id,
              'surah_id': verse.surahId,
              'verse_id': verse.verseId,
              if (label != null) 'label': label,
              if (note != null) 'note': note,
              'sort_order': categoryBookmarks.length,
            })
            .select('id')
            .single();

        final bookmark = LocalBookmark(
          id: inserted['id'].toString(),
          userId: user.id,
          categoryId: category.id,
          verse: verse,
          label: label,
          note: note,
          sortOrder: categoryBookmarks.length,
          createdAt: DateTime.now(),
        );

        _bookmarks.add(bookmark);
        await _save(immediate: true);
        notifyListeners();
        return bookmark;
      } catch (e) {
        debugPrint('Error adding bookmark to Supabase: $e');
      }
    }

    final bookmark = LocalBookmark(
      id: _createLocalId(),
      userId: _localUserId,
      categoryId: category.id,
      verse: verse,
      label: label,
      note: note,
      sortOrder: categoryBookmarks.length,
      createdAt: DateTime.now(),
    );

    _bookmarks.add(bookmark);
    await _save(immediate: true);
    notifyListeners();
    return bookmark;
  }

  Future<void> removeBookmark(String bookmarkId) async {
    await _loadCompleter.future;
    final bookmark = _bookmarks
        .where((bookmark) => bookmark.id == bookmarkId)
        .firstOrNull;
    if (bookmark == null) return;

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user != null && bookmark.userId != 'local') {
      try {
        await client.from('bookmarks').delete().eq('id', bookmarkId);
      } catch (e) {
        debugPrint('Error removing bookmark from Supabase: $e');
      }
    }

    _bookmarks = _bookmarks
        .where((bookmark) => bookmark.id != bookmarkId)
        .toList();
    await _save(immediate: true);
    notifyListeners();
  }

  void _debounceRecentReadingSync(
    String userId,
    String surahId,
    String verseId,
  ) {
    _pendingSyncUserId = userId;
    _pendingSyncSurahId = surahId;
    _pendingSyncVerseId = verseId;

    _recentReadingSyncTimer?.cancel();
    _recentReadingSyncTimer = Timer(const Duration(seconds: 2), () async {
      unawaited(flushPendingRecentReadingSync());
    });
  }

  Future<void> _syncRecentReadingToSupabase(
    String userId,
    String surahId,
    String verseId,
  ) async {
    try {
      final client = Supabase.instance.client;
      final now = DateTime.now().toIso8601String();
      await client.from('recent_readings').upsert({
        'user_id': userId,
        'surah_id': surahId,
        'verse_id': verseId,
        'read_at': now,
      }, onConflict: 'user_id,surah_id');
    } catch (e) {
      if (!e.toString().contains('verse_id') &&
          !e.toString().contains('read_at')) {
        debugPrint('Error syncing recent reading to Supabase: $e');
        return;
      }
      try {
        final client = Supabase.instance.client;
        await client.from('recent_readings').upsert({
          'user_id': userId,
          'surah_id': surahId,
          'last_read_verse': verseId,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,surah_id');
      } catch (fallbackError) {
        debugPrint('Error syncing recent reading to Supabase: $fallbackError');
      }
    }
  }

  Future<void> flushPendingRecentReadingSync() async {
    _recentReadingSyncTimer?.cancel();
    _recentReadingSyncTimer = null;

    final userId = _pendingSyncUserId;
    final surahId = _pendingSyncSurahId;
    final verseId = _pendingSyncVerseId;
    if (userId == null || surahId == null || verseId == null) return;

    _pendingSyncUserId = null;
    _pendingSyncSurahId = null;
    _pendingSyncVerseId = null;
    await _syncRecentReadingToSupabase(userId, surahId, verseId);
  }

  Future<void> addRecentReading({
    required VerseRef verse,
    String? profileId,
    int limit = defaultRecentReadingsLimit,
  }) async {
    await _loadCompleter.future;
    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;
    final String currentUserId = currentUser?.id ?? _localUserId;
    final taggedProfile = profileId == null
        ? null
        : _profiles.where((profile) => profile.id == profileId).firstOrNull;
    final safeProfileId =
        taggedProfile != null &&
            isVerseInsideProfile(taggedProfile, verse.surahId, verse.verseId)
        ? profileId
        : null;

    // Local update: find if there is an existing entry for this user_id and surah_id
    final existingIndex = _recentReadings.indexWhere(
      (item) =>
          item.userId == currentUserId && item.verse.surahId == verse.surahId,
    );

    final updatedReading = LocalRecentReading(
      id: existingIndex != -1
          ? _recentReadings[existingIndex].id
          : _createLocalId(),
      userId: currentUserId,
      verse: verse,
      profileId: safeProfileId,
      readAt: DateTime.now(),
    );

    if (existingIndex != -1) {
      _recentReadings.removeAt(existingIndex);
    }
    _recentReadings.insert(0, updatedReading);

    if (_recentReadings.length > limit) {
      _recentReadings = _recentReadings.take(limit).toList();
    }

    await _save();
    notifyListeners();

    if (currentUser != null) {
      _debounceRecentReadingSync(currentUser.id, verse.surahId, verse.verseId);
    }
  }

  void _debounceReadingStateSync(String userId, int currentVerseIndex) {
    _pendingReadingStateUserId = userId;
    _pendingReadingStateVerseIndex = currentVerseIndex;

    _readingStateSyncTimer?.cancel();
    _readingStateSyncTimer = Timer(const Duration(seconds: 2), () async {
      unawaited(flushPendingReadingStateSync());
    });
  }

  Future<void> _syncReadingStateToSupabase(
    String userId,
    int viewedIndex,
  ) async {
    try {
      final client = Supabase.instance.client;
      final existing = await client
          .from('user_reading_state')
          .select('furthest_unread_index')
          .eq('user_id', userId)
          .maybeSingle();
      final existingFurthest = int.tryParse(
        existing?['furthest_unread_index']?.toString() ?? '',
      );
      final nextFurthest =
          existingFurthest == null || viewedIndex > existingFurthest
          ? viewedIndex
          : existingFurthest;
      final viewedRef = verseRefFromAbsoluteIndex(viewedIndex);
      await client.from('user_reading_state').upsert({
        'user_id': userId,
        'surah_id': int.tryParse(viewedRef.surahId) ?? 1,
        'verse_id': int.tryParse(viewedRef.verseId) ?? 1,
        'last_viewed_index': viewedIndex,
        'furthest_unread_index': nextFurthest,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('Error syncing reading state to Supabase: $e');
    }
  }

  Future<void> flushPendingReadingStateSync() async {
    _readingStateSyncTimer?.cancel();
    _readingStateSyncTimer = null;

    final userId = _pendingReadingStateUserId;
    final viewedIndex = _pendingReadingStateVerseIndex;
    if (userId == null || viewedIndex == null) return;

    _pendingReadingStateUserId = null;
    _pendingReadingStateVerseIndex = null;
    await _syncReadingStateToSupabase(userId, viewedIndex);
  }

  Future<void> syncReadingStateWithSupabase(String userId) async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('user_reading_state')
          .select(
            'surah_id, verse_id, furthest_unread_index, last_viewed_index, updated_at',
          )
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null) {
        final remoteFurthestIndex = int.tryParse(
          response['furthest_unread_index']?.toString() ?? '',
        );
        final remoteLastViewedIndex = int.tryParse(
          response['last_viewed_index']?.toString() ?? '',
        );
        final int remoteSurahId =
            int.tryParse(response['surah_id']?.toString() ?? '') ?? 1;
        final int remoteVerseId =
            int.tryParse(response['verse_id']?.toString() ?? '') ?? 1;
        final DateTime remoteUpdatedAt = DateTime.parse(
          response['updated_at'].toString(),
        );

        final prefs = await SharedPreferences.getInstance();
        final localUpdatedAtStr = prefs.getString(
          'user_reading_state_updated_at',
        );
        final localUpdatedAt = localUpdatedAtStr != null
            ? DateTime.tryParse(localUpdatedAtStr) ??
                  DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.fromMillisecondsSinceEpoch(0);

        if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
          final remoteFurthestRef = remoteFurthestIndex == null
              ? toVerseRef(remoteSurahId.toString(), remoteVerseId.toString())
              : verseRefFromAbsoluteIndex(remoteFurthestIndex);
          final remoteLastViewedRef = remoteLastViewedIndex == null
              ? remoteFurthestRef
              : verseRefFromAbsoluteIndex(remoteLastViewedIndex);

          final targetProfile = freeReadProfile;
          if (targetProfile != null) {
            _profiles = _profiles.map((p) {
              if (p.id == targetProfile.id) {
                return p.copyWith(
                  current: remoteFurthestRef,
                  lastViewed: remoteLastViewedRef,
                  updatedAt: remoteUpdatedAt,
                );
              }
              return p;
            }).toList();
          }

          await prefs.setString(
            'user_reading_state_updated_at',
            remoteUpdatedAt.toIso8601String(),
          );
          await _save(immediate: true);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error syncing reading state with Supabase: $e');
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) {
        _ensureDefaultProfile();
        await _migrateLegacyBookmarks();
        await _save(immediate: true);
        notifyListeners();
        return;
      }

      final decoded = json.decode(raw) as Map<String, dynamic>;
      var loadedProfiles = _decodeList(
        decoded['profiles'],
        LocalReadingProfile.fromJson,
      );

      // Deduplicate "Free Read" profiles (keep the oldest/first one)
      final freeReads = loadedProfiles
          .where((p) => p.name == 'Free Read')
          .toList();
      if (freeReads.length > 1) {
        freeReads.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final toKeep = freeReads.first;
        loadedProfiles = loadedProfiles
            .where((p) => p.name != 'Free Read' || p.id == toKeep.id)
            .toList();
      }
      _profiles = loadedProfiles;
      _categories = _decodeList(
        decoded['categories'],
        LocalBookmarkCategory.fromJson,
      );
      _bookmarks = _decodeList(decoded['bookmarks'], LocalBookmark.fromJson);
      _recentReadings = _decodeList(
        decoded['recentReadings'],
        LocalRecentReading.fromJson,
      );
      if (decoded['readDates'] != null) {
        _readDates = Set<String>.from(decoded['readDates'] as List);
      }
      _activeProfileId = decoded['activeProfileId']?.toString();
      _ensureDefaultProfile();
      _profiles = _profiles
          .map(
            (profile) =>
                profile.target != null &&
                    !isFreeReadProfile(profile) &&
                    !isVerseInsideProfile(
                      profile,
                      profile.current.surahId,
                      profile.current.verseId,
                    )
                ? profile.copyWith(current: profile.start)
                : profile,
          )
          .toList();
      if (activeProfile == null) {
        final userProfiles = _profiles
            .where((p) => p.userId == currentUserId)
            .toList();
        final latest = _getLatestReadProfile(userProfiles);
        _activeProfileId = latest?.id;
      }
      await _migrateLegacyBookmarks();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading local reading store: $e');
      _ensureDefaultProfile();
      notifyListeners();
    } finally {
      if (!_loadCompleter.isCompleted) {
        _loadCompleter.complete();
      }
    }
  }

  Future<void> _migrateLegacyBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getStringList('manual_bookmarks');
      if (legacy != null && legacy.isNotEmpty) {
        final category = await ensureBookmarkCategory();
        for (final item in legacy) {
          final parts = item.split(':');
          if (parts.length == 2) {
            final verse = toVerseRef(parts[0], parts[1]);
            if (!_bookmarks.any((b) => b.verse.verseKey == verse.verseKey)) {
              final bookmark = LocalBookmark(
                id: _createLocalId(),
                userId: _localUserId,
                categoryId: category.id,
                verse: verse,
                sortOrder: _bookmarks.length,
                createdAt: DateTime.now(),
              );
              _bookmarks.add(bookmark);
            }
          }
        }
        await prefs.remove('manual_bookmarks');
        await _save(immediate: true);
      }
    } catch (e) {
      debugPrint('Error migrating legacy bookmarks: $e');
    }
  }

  Future<void> _save({bool immediate = false}) async {
    if (immediate) {
      _saveTimer?.cancel();
      _saveTimer = null;
      await _executeSave();
    } else {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(seconds: 1), () {
        _executeSave();
      });
    }
  }

  Future<void> _executeSave() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      json.encode({
        'activeProfileId': _activeProfileId,
        'profiles': _profiles.map((profile) => profile.toJson()).toList(),
        'categories': _categories.map((category) => category.toJson()).toList(),
        'bookmarks': _bookmarks.map((bookmark) => bookmark.toJson()).toList(),
        'recentReadings': _recentReadings
            .map((reading) => reading.toJson())
            .toList(),
        'readDates': _readDates.toList(),
      }),
    );
  }

  bool hasReadOn(DateTime date) {
    return _readDates.contains(date.toIso8601String().split('T')[0]);
  }

  void markReadToday() {
    final today = DateTime.now().toIso8601String().split('T')[0];
    if (!_readDates.contains(today)) {
      _readDates.add(today);
      _save(immediate: true);
      // Removed notifyListeners() here to avoid redundant rebuilds,
      // since markReadToday is usually called alongside other state updates.
    }
  }

  List<T> _decodeList<T>(
    Object? value,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  String _uniqueSlug(String slug) {
    final existingSlugs = _profiles.map((profile) => profile.slug).toSet();
    if (!existingSlugs.contains(slug)) return slug;

    var index = 2;
    var next = '${slug}_$index';
    while (existingSlugs.contains(next)) {
      index += 1;
      next = '${slug}_$index';
    }
    return next;
  }

  String _createLocalId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_profiles.length}_${_bookmarks.length}';

  void _ensureDefaultProfile() {
    _ensureShortcutProfiles();

    if (_profiles.any(
      (p) => isFreeReadProfile(p) && p.userId == currentUserId,
    )) {
      return;
    }

    final now = DateTime.now();
    final profile = LocalReadingProfile(
      id: _createLocalId(),
      userId: currentUserId,
      name: 'Just Read',
      slug: 'free_read',
      start: toVerseRef(1, 1),
      current: toVerseRef(1, 1),
      sortOrder: 0,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );

    _profiles.insert(0, profile);
    _activeProfileId ??= profile.id;
  }

  void _ensureShortcutProfiles() {
    final now = DateTime.now();
    
    // 1. Al-Mulk
    final hasMulk = _profiles.any((p) => p.id == shortcutMulkId);
    if (!hasMulk) {
      _profiles.add(LocalReadingProfile(
        id: shortcutMulkId,
        userId: currentUserId,
        name: 'Al-Mulk Shortcut',
        slug: 'shortcut_mulk',
        start: toVerseRef(67, 1),
        target: toVerseRef(67, 30),
        current: toVerseRef(67, 1),
        sortOrder: 1000,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      ));
    } else {
      final idx = _profiles.indexWhere((p) => p.id == shortcutMulkId);
      if (idx != -1 && _profiles[idx].userId != currentUserId) {
        _profiles[idx] = _profiles[idx].copyWith(userId: currentUserId);
      }
    }

    // 2. Al-Kahf
    final hasKahf = _profiles.any((p) => p.id == shortcutKahfId);
    if (!hasKahf) {
      _profiles.add(LocalReadingProfile(
        id: shortcutKahfId,
        userId: currentUserId,
        name: 'Al-Kahf Shortcut',
        slug: 'shortcut_kahf',
        start: toVerseRef(18, 1),
        target: toVerseRef(18, 110),
        current: toVerseRef(18, 1),
        sortOrder: 1001,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      ));
    } else {
      final idx = _profiles.indexWhere((p) => p.id == shortcutKahfId);
      if (idx != -1 && _profiles[idx].userId != currentUserId) {
        _profiles[idx] = _profiles[idx].copyWith(userId: currentUserId);
      }
    }
  }

  DateTime getLastMulkResetTime(DateTime now) {
    final todayReset = DateTime(now.year, now.month, now.day, 19, 45); // 7:45 PM
    if (now.isAfter(todayReset) || now.isAtSameMomentAs(todayReset)) {
      return todayReset;
    } else {
      return todayReset.subtract(const Duration(days: 1));
    }
  }

  DateTime getLastKahfResetTime(DateTime now) {
    var temp = DateTime(now.year, now.month, now.day, 19, 45); // Thursday 7:45 PM
    while (temp.weekday != DateTime.thursday) {
      temp = temp.subtract(const Duration(days: 1));
    }
    if (now.isBefore(temp)) {
      temp = temp.subtract(const Duration(days: 7));
    }
    return temp;
  }

  void checkAndResetShortcutProfiles() {
    final now = DateTime.now();
    var changed = false;

    // Check Mulk
    final mulkIndex = _profiles.indexWhere((p) => p.id == shortcutMulkId);
    if (mulkIndex != -1) {
      final p = _profiles[mulkIndex];
      final resetTime = getLastMulkResetTime(now);
      if (p.updatedAt.isBefore(resetTime)) {
        _profiles[mulkIndex] = p.copyWith(
          current: toVerseRef(67, 1),
          lastViewed: toVerseRef(67, 1),
          updatedAt: resetTime,
        );
        changed = true;
      }
    }

    // Check Kahf
    final kahfIndex = _profiles.indexWhere((p) => p.id == shortcutKahfId);
    if (kahfIndex != -1) {
      final p = _profiles[kahfIndex];
      final resetTime = getLastKahfResetTime(now);
      if (p.updatedAt.isBefore(resetTime)) {
        _profiles[kahfIndex] = p.copyWith(
          current: toVerseRef(18, 1),
          lastViewed: toVerseRef(18, 1),
          updatedAt: resetTime,
        );
        changed = true;
      }
    }

    if (changed) {
      _save(immediate: true);
      notifyListeners();
      // Sync reset to Supabase
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        if (mulkIndex != -1) _queueProfileSync(_profiles[mulkIndex], delay: Duration.zero);
        if (kahfIndex != -1) _queueProfileSync(_profiles[kahfIndex], delay: Duration.zero);
      }
    }
  }

  Future<void> updateShortcutProgress(String shortcutId, VerseRef current) async {
    await _loadCompleter.future;
    final idx = _profiles.indexWhere((p) => p.id == shortcutId);
    if (idx == -1) return;

    final now = DateTime.now();
    final profile = _profiles[idx];
    
    final currentIndex = absoluteVerseIndex(current);
    final furthestIndex = profile.furthestUnreadIndex;
    final shouldAdvanceFurthest = currentIndex > furthestIndex;

    final updated = profile.copyWith(
      current: shouldAdvanceFurthest ? current : profile.current,
      lastViewed: current,
      updatedAt: now,
    );
    _profiles[idx] = updated;

    await _save(immediate: true);
    notifyListeners();

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _queueProfileSync(updated, delay: Duration.zero);
    }
  }

  Future<LocalReadingProfile> ensureShortcutProfile(String shortcutId, int surahNumber) async {
    await _loadCompleter.future;
    final existing = profileById(shortcutId);
    if (existing != null) {
      if (existing.userId != currentUserId) {
        final updated = existing.copyWith(userId: currentUserId);
        final index = _profiles.indexWhere((p) => p.id == shortcutId);
        if (index != -1) {
          _profiles[index] = updated;
          await _save(immediate: true);
          notifyListeners();
        }
        return updated;
      }
      return existing;
    }

    final p = LocalReadingProfile(
      id: shortcutId,
      userId: currentUserId,
      name: 'Shortcut Surah $surahNumber',
      slug: 'shortcut_$surahNumber',
      start: toVerseRef(surahNumber.toString(), '1'),
      current: toVerseRef(surahNumber.toString(), '1'),
      lastViewed: toVerseRef(surahNumber.toString(), '1'),
      sortOrder: 0,
      isArchived: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _profiles.add(p);
    await _save(immediate: true);
    notifyListeners();

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _queueProfileSync(p, delay: Duration.zero);
    }
    return p;
  }
}

bool isFreeReadProfile(LocalReadingProfile profile) {
  return profile.slug == 'free_read' ||
      profile.slug == 'main_read' ||
      profile.name == 'Just Read' ||
      profile.name == 'Free Read';
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

bool isFreeReadProfileName(String name) {
  return name == 'Just Read' || name == 'Free Read' || name == 'Main Read';
}
