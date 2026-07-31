// lib/providers/supabase_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/hifz_repository.dart';

class SupabaseProvider extends ChangeNotifier {
  final _client = Supabase.instance.client;
  User? _user;
  StreamSubscription<AuthState>? _authSubscription;
  String _guestName = 'Reader';

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  String get userEmail => _user?.email ?? '';
  String get userId => _user?.id ?? '';

  String get displayName {
    if (_user != null) {
      final metaName = _user?.userMetadata?['full_name']?.toString() ?? '';
      if (metaName.trim().isNotEmpty) return metaName.trim();
      return _user?.email?.split('@')[0] ?? 'Reader';
    }
    return _guestName;
  }

  SupabaseProvider() {
    _user = _client.auth.currentUser;
    _loadGuestName();
    _authSubscription = _client.auth.onAuthStateChange.listen((data) {
      final oldUser = _user;
      _user = data.session?.user;
      if (oldUser?.id != _user?.id) {
        notifyListeners();
        if (_user != null) {
          bootstrapUser(_user!.id);
        }
      }
    });
  }

  Future<void> _loadGuestName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _guestName = prefs.getString('guest_display_name') ?? 'Reader';
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading guest name: $e');
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  // OTP / Magic Link sign-in request
  Future<void> signInWithOtp(String email) async {
    await _client.auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: 'io.supabase.thaiquran://login-callback',
    );
  }

  // Google sign-in request
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb
          ? null
          : 'io.supabase.thaiquran://login-callback',
    );
  }

  // Sign In with Email & Password
  Future<void> signInWithPassword(String email, String password) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  // Sign Up with Email & Password
  Future<void> signUp(String email, String password, String displayName) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': displayName.trim()},
    );
    if (response.user != null) {
      await bootstrapUser(response.user!.id);
    }
  }

  // Verification of 6-digit OTP code
  Future<void> verifyOtp(String email, String token) async {
    await _client.auth.verifyOTP(
      type: OtpType.magiclink,
      email: email.trim(),
      token: token.trim(),
    );
  }

  // Logout
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // Bootstraps default rows for user if they don't exist
  Future<void> bootstrapUser(String userId) async {
    try {
      final countResult = await _client
          .from('user_reading_profiles')
          .select('id')
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();

      final List<Future> futures = [
        _client
            .from('reading_profiles')
            .upsert(
              {
                'user_id': userId,
                'name': 'Free Read',
                'slug': 'free_read',
                'start_surah_id': '1',
                'start_verse_id': '1',
                'current_surah_id': '1',
                'current_verse_id': '1',
                'furthest_unread_index': 1,
                'last_viewed_index': 1,
                'sort_order': 0,
                'is_archived': false,
              },
              onConflict: 'user_id,slug',
              ignoreDuplicates: true,
            ),
        _client
            .from('bookmark_categories')
            .upsert(
              {
                'user_id': userId,
                'name': 'Saved Verses',
                'slug': 'saved_verses',
                'max_items': 5,
                'sort_order': 0,
              },
              onConflict: 'user_id,slug',
              ignoreDuplicates: true,
            ),
        _client
            .from('user_settings')
            .upsert(
              {'user_id': userId},
              onConflict: 'user_id',
              ignoreDuplicates: true,
            ),
      ];

      // Add Hifz sync
      try {
        futures.add(HifzRepository().syncWithSupabase(userId));
        futures.add(HifzRepository().syncHistoryWithSupabase());
      } catch (e) {
        debugPrint('Error triggering hifz sync: $e');
      }

      if (countResult == null) {
        futures.add(
          _client.from('user_reading_profiles').insert({
            'user_id': userId,
            'profile_name': 'Free Read',
            'current_surah': 1,
            'current_ayah': 1,
            'furthest_unread_index': 1,
            'last_viewed_index': 1,
            'last_read_at': DateTime.now().toIso8601String(),
          }),
        );
      }

      await Future.wait(futures);
    } catch (e) {
      debugPrint('Error bootstrapping Supabase user defaults: $e');
    }
  }

  // Load User Settings from Supabase
  Future<Map<String, dynamic>?> loadUserSettings(String userId) async {
    try {
      final response = await _client
          .from('user_settings')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error loading user settings from Supabase: $e');
      return null;
    }
  }

  // Save/Upsert Settings to Supabase
  Future<void> saveUserSettings(
    String userId,
    Map<String, dynamic> settings,
  ) async {
    try {
      await _client.from('user_settings').upsert({
        'user_id': userId,
        ...settings,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('Error saving user settings to Supabase: $e');
    }
  }

  // Fetch Bookmarks from Supabase
  Future<List<Map<String, dynamic>>> fetchBookmarks(String userId) async {
    try {
      final response = await _client
          .from('bookmarks')
          .select(
            'id, surah_id, verse_id, label, note, sort_order, created_at, category_id',
          )
          .eq('user_id', userId);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching bookmarks from Supabase: $e');
      return [];
    }
  }

  // Save Bookmark to Supabase
  Future<void> saveBookmark(
    String userId,
    String categoryId,
    String surahId,
    String verseId, {
    String? label,
    String? note,
    int sortOrder = 0,
  }) async {
    try {
      // Check if bookmark already exists
      final existing = await _client
          .from('bookmarks')
          .select('id')
          .eq('user_id', userId)
          .eq('category_id', categoryId)
          .eq('surah_id', surahId)
          .eq('verse_id', verseId)
          .maybeSingle();

      if (existing != null) return;

      await _client.from('bookmarks').insert({
        'user_id': userId,
        'category_id': categoryId,
        'surah_id': surahId,
        'verse_id': verseId,
        if (label != null) 'label': label,
        if (note != null) 'note': note,
        'sort_order': sortOrder,
      });
    } catch (e) {
      debugPrint('Error saving bookmark to Supabase: $e');
    }
  }

  // Remove Bookmark from Supabase
  Future<void> removeBookmark(
    String userId,
    String surahId,
    String verseId,
  ) async {
    try {
      await _client
          .from('bookmarks')
          .delete()
          .eq('user_id', userId)
          .eq('surah_id', surahId)
          .eq('verse_id', verseId);
    } catch (e) {
      debugPrint('Error removing bookmark from Supabase: $e');
    }
  }

  // Helper to get category ID for saved_verses
  Future<String?> getDefaultBookmarkCategoryId(String userId) async {
    try {
      final category = await _client
          .from('bookmark_categories')
          .select('id')
          .eq('user_id', userId)
          .eq('slug', 'saved_verses')
          .maybeSingle();

      if (category != null) {
        return category['id']?.toString();
      }

      // Upsert fallback
      final created = await _client
          .from('bookmark_categories')
          .upsert({
            'user_id': userId,
            'name': 'Saved Verses',
            'slug': 'saved_verses',
            'max_items': 5,
            'sort_order': 0,
          }, onConflict: 'user_id,slug')
          .select('id')
          .single();

      return created['id']?.toString();
    } catch (e) {
      debugPrint('Error getting default category ID: $e');
      return null;
    }
  }

  Future<void> updateDisplayName(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;

    if (_user != null) {
      await _client.auth.updateUser(
        UserAttributes(data: {'full_name': trimmed}),
      );
      _user = _client.auth.currentUser;
      notifyListeners();
    } else {
      _guestName = trimmed;
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('guest_display_name', trimmed);
      } catch (e) {
        debugPrint('Error saving guest name: $e');
      }
    }
  }
}
