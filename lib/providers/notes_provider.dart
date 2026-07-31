// lib/providers/notes_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/tadabbur_repository.dart';
import '../models/tadabbur_note.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotesProvider extends ChangeNotifier {
  static const String _notesKey = 'personal_notes_v2';
  Map<String, TadabburNote> _personalNotes = {};
  final TadabburRepository _repo = TadabburRepository();
  StreamSubscription<AuthState>? _authSubscription;

  Map<String, TadabburNote> get personalNotes => _personalNotes;

  NotesProvider() {
    _loadNotes();
    // Auto-sync on startup if a user session is active
    syncWithSupabase();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (data.session?.user != null) {
        syncWithSupabase();
      }
    });
  }

  Future<void> syncWithSupabase() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final remoteNotes = await _repo.fetchUserNotes();
      final remoteByVerse = {
        for (final note in remoteNotes) '${note.surahId}:${note.verseId}': note,
      };

      for (final entry in Map<String, TadabburNote>.from(
        _personalNotes,
      ).entries) {
        final local = entry.value;
        final remote = remoteByVerse[entry.key];
        if (remote != null && !local.updatedAt.isAfter(remote.updatedAt)) {
          continue;
        }

        final noteToSave = TadabburNote(
          id: remote?.id ?? local.id,
          userId: user.id,
          surahId: local.surahId,
          verseId: local.verseId,
          noteText: local.noteText,
          isPublic: local.isPublic,
          isAnonymous: local.isAnonymous,
          likesCount: remote?.likesCount ?? local.likesCount,
          language: local.language,
          createdAt: remote?.createdAt ?? local.createdAt,
          updatedAt: local.updatedAt,
          userLiked: remote?.userLiked ?? local.userLiked,
          synced: true,
        );
        final saved = await _repo.saveNote(noteToSave);
        if (saved != null) {
          remoteByVerse[entry.key] = saved;
        }
      }

      _personalNotes = {
        ..._personalNotes,
        for (final entry in remoteByVerse.entries) entry.key: entry.value,
      };
      await _saveLocalCache();
      notifyListeners();
    } catch (e) {
      debugPrint('NotesProvider: Error syncing notes: $e');
    }
  }

  Future<void> _loadNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString(_notesKey);
      if (savedData != null) {
        final Map<String, dynamic> decoded = json.decode(savedData);
        _personalNotes = decoded.map(
          (key, value) => MapEntry(
            key,
            TadabburNote.fromJson(value as Map<String, dynamic>),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading notes: $e');
    }
    notifyListeners();
  }

  Future<void> _saveLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> toSave = _personalNotes.map(
        (key, value) => MapEntry(key, value.toJson()),
      );
      await prefs.setString(_notesKey, json.encode(toSave));
    } catch (e) {
      debugPrint('Error saving notes to cache: $e');
    }
  }

  TadabburNote? getNoteObjectForVerse(String surahId, String verseId) {
    return _personalNotes['$surahId:$verseId'];
  }

  String getNoteForVerse(String surahId, String verseId) {
    return _personalNotes['$surahId:$verseId']?.noteText ?? '';
  }

  Future<void> saveNote({
    required String surahId,
    required String verseId,
    required String noteText,
    bool isPublic = false,
    bool isAnonymous = false,
  }) async {
    final key = '$surahId:$verseId';
    final existing = _personalNotes[key];

    final user = Supabase.instance.client.auth.currentUser;
    final isGuest = user == null;

    final note = TadabburNote(
      id: existing?.id ?? 'temp-${DateTime.now().millisecondsSinceEpoch}',
      userId: user?.id ?? 'guest',
      surahId: surahId,
      verseId: verseId,
      noteText: noteText.trim(),
      isPublic: isPublic,
      isAnonymous: isAnonymous,
      likesCount: existing?.likesCount ?? 0,
      language: 'th',
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      userLiked: existing?.userLiked ?? false,
      synced: !isGuest,
    );

    _personalNotes[key] = note;
    notifyListeners();
    await _saveLocalCache();

    if (isGuest) {
      return;
    }

    try {
      final savedNote = await _repo.saveNote(note);
      if (savedNote != null) {
        _personalNotes[key] = savedNote;
        await _saveLocalCache();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error saving note to supabase: $e');
      await _saveLocalCache();
    }
  }

  Future<void> deleteNote(String surahId, String verseId) async {
    final key = '$surahId:$verseId';
    final note = _personalNotes[key];
    if (note == null) return;

    _personalNotes.remove(key);
    notifyListeners();

    try {
      if (!note.id.startsWith('temp-')) {
        await _repo.deleteNote(note.id);
      }
      await _saveLocalCache();
    } catch (e) {
      debugPrint('Error deleting note from supabase: $e');
      // Revert if failed?
    }
  }

  /// Toggle like locally and remotely
  Future<void> toggleLikeLocally(
    TadabburNote note,
    VoidCallback onLikedChanged,
  ) async {
    try {
      await _repo.toggleLike(note.id);
      // We can't mutate the final properties easily, so this should just refresh community notes
      onLikedChanged();
    } catch (e) {
      debugPrint('Failed to toggle like: $e');
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
