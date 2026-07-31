// lib/data/tadabbur_repository.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tadabbur_note.dart';

class TadabburRepository {
  final _client = Supabase.instance.client;

  /// Fetch all notes belonging to the current user
  Future<List<TadabburNote>> fetchUserNotes() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      debugPrint('TadabburRepository: fetchUserNotes skipped, unauthenticated.');
      return [];
    }

    try {
      final response = await _client
          .from('tadabbur_notes')
          .select()
          .eq('user_id', user.id);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => TadabburNote.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('TadabburRepository: Error fetching user notes: $e');
      rethrow;
    }
  }

  /// Fetch public community notes — matches web fetchPublicTadabburFeed:
  /// includes ALL public notes (including the logged-in user's own),
  /// joins tadabbur_likes to compute user_liked, ordered newest first.
  Future<List<TadabburNote>> fetchCommunityNotes(String surahId, String verseId) async {
    try {
      final user = _client.auth.currentUser;

      var query = _client
          .from('tadabbur_notes')
          .select('*, tadabbur_likes(user_id)')
          .eq('is_public', true);

      if (surahId != '0') {
        query = query.eq('surah_id', surahId);
      }
      if (verseId != '0') {
        query = query.eq('verse_id', verseId);
      }

      final response = await query.order('created_at', ascending: false);
      final List<dynamic> data = response as List<dynamic>;

      return data.map((row) {
        final json = row as Map<String, dynamic>;
        // Compute user_liked from the joined tadabbur_likes rows
        final likes = json['tadabbur_likes'] as List<dynamic>? ?? [];
        final userLiked = user != null
            ? likes.any((like) => (like as Map<String, dynamic>)['user_id'] == user.id)
            : false;
        return TadabburNote.fromJson({
          ...json,
          'user_liked': userLiked,
        });
      }).toList();
    } catch (e) {
      debugPrint('TadabburRepository: Error fetching community notes: $e');
      return [];
    }
  }

  /// Upsert a single personal note to Supabase
  Future<TadabburNote?> saveNote(TadabburNote note) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final data = note.toJson();
      // Remove created_at if we are updating, or let DB handle defaults
      if (!data.containsKey('created_at') || data['created_at'] == null) {
        data['created_at'] = DateTime.now().toIso8601String();
      }
      data['updated_at'] = DateTime.now().toIso8601String();

      // If id is empty or a placeholder, remove it so DB generates one
      if (data['id'] == '' || data['id'].startsWith('temp-')) {
        data.remove('id');
      }

      final response = await _client.from('tadabbur_notes').upsert(data).select().single();
      return TadabburNote.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      debugPrint('TadabburRepository: Error saving note to Supabase: $e');
      rethrow;
    }
  }

  /// Delete a personal note by ID
  Future<void> deleteNote(String noteId) async {
    try {
      await _client.from('tadabbur_notes').delete().eq('id', noteId);
    } catch (e) {
      debugPrint('TadabburRepository: Error deleting note: $e');
      rethrow;
    }
  }

  /// Toggle like for a note
  Future<bool> toggleLike(String noteId) async {
    try {
      final response = await _client.rpc('toggle_tadabbur_like', params: {'note_id_param': noteId});
      return response as bool; // true if liked, false if unliked
    } catch (e) {
      debugPrint('TadabburRepository: Error toggling like: $e');
      rethrow;
    }
  }
}
