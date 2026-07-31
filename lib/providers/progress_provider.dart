// lib/providers/progress_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ProgressProvider extends ChangeNotifier {
  static const List<String> profiles = [
    'Main Daily Read',
    'Special Read',
    'Search',
    'Read from Bookmark',
    'Last Read',
  ];

  String _currentProfile = 'Main Daily Read';

  // Profile progress state maps
  final Map<String, String> _profileSurahs = {};
  final Map<String, int> _profileVerses = {};

  int _totalVerses = 0;
  bool _isInitialized = false;
  bool _isChangingSurah = false; // Flag to disable scroll listener during load
  Timer? _saveTimer;

  int _completedReadCount = 0;
  int _completedCheckCount = 0;

  String get currentProfile => _currentProfile;
  String get currentSurahId => _profileSurahs[_currentProfile] ?? '1';
  int get lastVerseIndex => _profileVerses[_currentProfile] ?? 0;
  bool get isInitialized => _isInitialized;
  bool get isChangingSurah => _isChangingSurah;
  int get completedReadCount => _completedReadCount;
  int get completedCheckCount => _completedCheckCount;

  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  void setTotalVerses(int count) {
    _totalVerses = count;
  }

  void setChangingSurah(bool value) {
    _isChangingSurah = value;
  }

  ProgressProvider() {
    _init();

    // Listen to scrolling to automatically update progress
    itemPositionsListener.itemPositions.addListener(() {
      if (_isChangingSurah) {
        return; // Skip updates when changing surah to avoid overwriting reset
      }

      final positions = itemPositionsListener.itemPositions.value;
      if (positions.isNotEmpty) {
        int topIndex = 0;

        // Check if the completion card (index _totalVerses) is visible and fully/mostly inside the viewport
        bool isLastVisible = false;
        double lastTrailing = 2.0;
        for (var pos in positions) {
          if (pos.index == _totalVerses) {
            isLastVisible = true;
            lastTrailing = pos.itemTrailingEdge;
            break;
          }
        }

        if (isLastVisible && lastTrailing <= 1.05) {
          topIndex = _totalVerses - 1;
        } else {
          // Find the item that covers or is closest to targetY (e.g. 30% from top)
          double targetY = 0.3;
          double minDistance = double.infinity;

          for (var pos in positions) {
            if (pos.index >= _totalVerses) {
              continue; // Skip the completion card index so it is not highlighted or saved as progress
            }

            double itemCenter =
                (pos.itemLeadingEdge + pos.itemTrailingEdge) / 2;
            double dist = (itemCenter - targetY).abs();
            if (dist < minDistance) {
              minDistance = dist;
              topIndex = pos.index;
            }
          }
        }

        _saveProgress(currentSurahId, topIndex);
      }
    });
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    // Load active profile
    _currentProfile =
        prefs.getString('active_reading_profile') ?? 'Main Daily Read';

    // Load progress state for all profiles
    for (var profile in profiles) {
      _profileSurahs[profile] =
          prefs.getString('profile_${profile}_surah_id') ?? '1';
      _profileVerses[profile] =
          prefs.getInt('profile_${profile}_verse_index') ?? 0;
    }

    _completedReadCount = prefs.getInt('completed_read_count') ?? 0;
    _completedCheckCount = prefs.getInt('completed_check_count') ?? 0;

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> switchProfile(String newProfile) async {
    if (!profiles.contains(newProfile)) return;
    _currentProfile = newProfile;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_reading_profile', newProfile);
  }

  void _debouncedSave(String profile, String surahId, int verseIndex) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_${profile}_surah_id', surahId);
      await prefs.setInt('profile_${profile}_verse_index', verseIndex);
    });
  }

  Future<void> _saveProgress(String surahId, int verseIndex) async {
    final currentSurah = currentSurahId;
    final currentVerse = lastVerseIndex;

    if (currentSurah == surahId && currentVerse == verseIndex) return;

    _profileSurahs[_currentProfile] = surahId;
    _profileVerses[_currentProfile] = verseIndex;
    notifyListeners();

    _debouncedSave(_currentProfile, surahId, verseIndex);
  }

  void jumpToSavedPosition() {
    if (itemScrollController.isAttached) {
      itemScrollController.jumpTo(index: lastVerseIndex);
    }
  }

  Future<void> setCurrentSurah(String surahId) async {
    if (currentSurahId != surahId) {
      _profileSurahs[_currentProfile] = surahId;
      _profileVerses[_currentProfile] =
          0; // Reset index when changing surahs manually
      notifyListeners();

      _saveTimer?.cancel();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_${_currentProfile}_surah_id', surahId);
      await prefs.setInt('profile_${_currentProfile}_verse_index', 0);
    }
  }

  // Smooth scroll and set index manually
  Future<void> setVerseIndexAndScroll(int index) async {
    _profileVerses[_currentProfile] = index;
    notifyListeners();

    _saveTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('profile_${_currentProfile}_verse_index', index);

    if (itemScrollController.isAttached) {
      await itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> incrementCompletedRead() async {
    _completedReadCount++;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('completed_read_count', _completedReadCount);
  }

  Future<void> incrementCompletedCheck() async {
    _completedCheckCount++;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('completed_check_count', _completedCheckCount);
  }

  @override
  void dispose() {
    if (_saveTimer != null && _saveTimer!.isActive) {
      _saveTimer!.cancel();
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('profile_${_currentProfile}_surah_id', currentSurahId);
        prefs.setInt('profile_${_currentProfile}_verse_index', lastVerseIndex);
      });
    }
    super.dispose();
  }
}
