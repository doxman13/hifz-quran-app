// lib/providers/bookmark_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BookmarkProvider extends ChangeNotifier {
  final String _bookmarksKey = 'manual_bookmarks';

  // We'll store bookmarks as a list of "surahId:verseId"
  List<String> _bookmarks = [];

  List<String> get bookmarks => _bookmarks;

  BookmarkProvider() {
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_bookmarksKey);
    if (data != null) {
      _bookmarks = data;
    }
    notifyListeners();
  }

  bool isBookmarked(String surahId, String verseId) {
    return _bookmarks.contains('$surahId:$verseId');
  }

  Future<void> toggleBookmark(String surahId, String verseId) async {
    final key = '$surahId:$verseId';
    if (_bookmarks.contains(key)) {
      _bookmarks.remove(key);
    } else {
      _bookmarks.add(key);
    }
    
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_bookmarksKey, _bookmarks);
  }
}
