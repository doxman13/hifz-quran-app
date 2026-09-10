import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_foundation_repository.dart';
import '../models/mushaf_models.dart';

class MushafAudioProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final QuranFoundationRepository _audioRepository = QuranFoundationRepository();

  bool _isPlaying = false;
  bool _isLoading = false;
  String? _currentVerseKey;
  int? _currentPageNumber;
  int? _mushafId;
  bool _isContinuous = false;

  List<MushafVerse> _playlist = [];
  int _playlistIndex = -1;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;

  final Map<int, Map<String, dynamic>> _chapterDataCache = {};

  MushafAudioProvider() {
    _initPlayerStateListener();
    _loadSavedVolume();
  }

  double _volume = 1.0;

  // Getters
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  double get volume => _volume;
  String? get currentVerseKey => _currentVerseKey;
  int? get currentPageNumber => _currentPageNumber;
  int? get mushafId => _mushafId;
  bool get isContinuous => _isContinuous;
  List<MushafVerse> get playlist => _playlist;
  int get playlistIndex => _playlistIndex;

  Future<void> _loadSavedVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVol = prefs.getDouble('mushaf_audio_volume');
      if (savedVol != null) {
        _volume = savedVol.clamp(0.0, 1.0);
      }
      await _audioPlayer.setVolume(_volume);
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load saved audio volume: $e');
    }
  }

  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    _volume = clamped;
    notifyListeners();
    try {
      await _audioPlayer.setVolume(_volume);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('mushaf_audio_volume', _volume);
    } catch (e) {
      debugPrint('Error setting audio player volume: $e');
    }
  }

  bool _isTransitioningPage = false;

  void _initPlayerStateListener() {
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      final processingState = state.processingState;
      _isLoading = processingState == ProcessingState.loading ||
                   processingState == ProcessingState.buffering;

      if (processingState == ProcessingState.completed) {
        _handlePlaybackCompleted();
      }
      notifyListeners();
    });
  }

  void _handlePlaybackCompleted() {
    if (_isContinuous && !_isTransitioningPage) {
      _isTransitioningPage = true;
      _loadAndPlayNextPage().whenComplete(() {
        _isTransitioningPage = false;
      });
    } else if (!_isContinuous) {
      stop();
    }
  }

  Future<void> playPage({
    required int mushafId,
    required int pageNumber,
    required List<MushafVerse> verses,
    int startVerseIndex = 0,
  }) async {
    if (verses.isEmpty) return;

    await stop();

    _mushafId = mushafId;
    _currentPageNumber = pageNumber;
    _playlist = List.from(verses);
    _playlistIndex = startVerseIndex.clamp(0, verses.length - 1);
    _isContinuous = true;
    _currentVerseKey = _playlist[_playlistIndex].verseKey;
    _isLoading = true;
    notifyListeners();

    await _loadAndPlayPlaylist(_playlistIndex);
  }

  Future<void> playVerse({
    required int mushafId,
    required int pageNumber,
    required String verseKey,
    required List<MushafVerse> pageVerses,
    bool continuous = true,
  }) async {
    await stop();

    _mushafId = mushafId;
    _currentPageNumber = pageNumber;
    _playlist = List.from(pageVerses);
    _isContinuous = continuous;

    final index = _playlist.indexWhere((v) => v.verseKey == verseKey);
    final startIndex = index != -1 ? index : 0;
    _playlistIndex = startIndex;
    _currentVerseKey = _playlist[_playlistIndex].verseKey;
    _isLoading = true;
    notifyListeners();

    await _loadAndPlayPlaylist(startIndex);
  }

  Future<void> playSingleIndependentVerse(String verseKey) async {
    await stop();

    _isContinuous = false;
    _currentPageNumber = null;
    _mushafId = null;

    final parts = verseKey.split(':');
    final surahId = parts[0];
    final verseId = parts.length > 1 ? parts[1] : '1';

    final verse = MushafVerse(
      verseKey: verseKey,
      surahId: surahId,
      verseId: verseId,
      words: [],
    );
    _playlist = [verse];
    _playlistIndex = 0;
    _currentVerseKey = verseKey;
    _isLoading = true;
    notifyListeners();

    await _loadAndPlayPlaylist(_playlistIndex);
  }

  Future<void> playRange(
    String surahId,
    List<int> verseIds, {
    int verseRepeat = 1,
    int rangeRepeat = 1,
  }) async {
    await stop();

    _isContinuous = false;
    _currentPageNumber = null;
    _mushafId = null;

    final baseVerses = verseIds.map((vId) {
      return MushafVerse(
        verseKey: '$surahId:$vId',
        surahId: surahId,
        verseId: vId.toString(),
        words: [],
      );
    }).toList();

    if (baseVerses.isEmpty) return;

    final vRep = verseRepeat.clamp(1, 20);
    final rRep = rangeRepeat.clamp(1, 20);

    final List<MushafVerse> expanded = [];
    for (int r = 0; r < rRep; r++) {
      for (final v in baseVerses) {
        for (int vr = 0; vr < vRep; vr++) {
          expanded.add(v);
        }
      }
    }

    _playlist = expanded;
    _playlistIndex = 0;
    _currentVerseKey = _playlist[0].verseKey;
    _isLoading = true;
    notifyListeners();

    await _loadAndPlayPlaylist(0);
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (_currentVerseKey != null) {
        await _audioPlayer.play();
      }
    }
  }

  Future<void> stop() async {
    _currentIndexSubscription?.cancel();
    _currentIndexSubscription = null;
    await _audioPlayer.stop();
    _isPlaying = false;
    _isLoading = false;
    _currentVerseKey = null;
    _playlistIndex = -1;
    notifyListeners();
  }

  Future<void> nextVerse() async {
    if (_playlistIndex + 1 < _playlist.length) {
      await _audioPlayer.seekToNext();
    } else if (_isContinuous) {
      await _loadAndPlayNextPage();
    }
  }

  Future<void> previousVerse() async {
    if (_playlistIndex > 0) {
      await _audioPlayer.seekToPrevious();
    } else if (_isContinuous &&
        _currentPageNumber != null &&
        _currentPageNumber! > 1) {
      await _loadAndPlayPreviousPage();
    }
  }

  Future<void> _loadAndPlayPlaylist(int startVerseIndex) async {
    _isLoading = true;
    notifyListeners();

    try {
      final List<AudioSource> sources = await _buildAudioSources(_playlist);
      if (sources.isEmpty) {
        await stop();
        return;
      }

      _currentIndexSubscription?.cancel();

      await _audioPlayer.setAudioSources(
        sources,
        initialIndex: startVerseIndex.clamp(0, sources.length - 1),
      );

      // Enforce current volume on the newly set audio sources
      await _audioPlayer.setVolume(_volume);

      _currentIndexSubscription = _audioPlayer.currentIndexStream.listen((index) {
        if (index != null && index >= 0 && index < _playlist.length) {
          _playlistIndex = index;
          _currentVerseKey = _playlist[index].verseKey;
          notifyListeners();
        }
      });

      _isLoading = false;
      _isPlaying = true;
      notifyListeners();

      await _audioPlayer.play();
    } catch (e) {
      debugPrint('Failed to load and play playlist: $e');
      await stop();
    }
  }

  Future<void> _loadAndPlayNextPage() async {
    final mushafId = _mushafId ?? 2;
    if (_currentPageNumber == null) return;

    final type = mushafTypeById(mushafId);
    if (_currentPageNumber! >= type.pageCount) {
      await stop();
      return;
    }

    _isLoading = true;
    _currentPageNumber = _currentPageNumber! + 1;
    notifyListeners();

    try {
      final nextPageData = await _audioRepository.fetchPage(
        mushafId: mushafId,
        pageNumber: _currentPageNumber!,
      );

      if (nextPageData.verses.isEmpty) {
        await stop();
        return;
      }

      await _audioPlayer.stop();

      _mushafId = mushafId;
      _playlist = List.from(nextPageData.verses);
      _playlistIndex = 0;
      _currentVerseKey = _playlist[0].verseKey;
      await _loadAndPlayPlaylist(0);
    } catch (e) {
      debugPrint('Failed to load next page: $e');
      await stop();
    }
  }

  Future<void> _loadAndPlayPreviousPage() async {
    final mushafId = _mushafId ?? 2;
    if (_currentPageNumber == null || _currentPageNumber! <= 1) return;

    _isLoading = true;
    _currentPageNumber = _currentPageNumber! - 1;
    notifyListeners();

    try {
      final prevPageData = await _audioRepository.fetchPage(
        mushafId: mushafId,
        pageNumber: _currentPageNumber!,
      );

      if (prevPageData.verses.isEmpty) {
        await stop();
        return;
      }

      await _audioPlayer.stop();

      _mushafId = mushafId;
      _playlist = List.from(prevPageData.verses);
      _playlistIndex = _playlist.length - 1;
      _currentVerseKey = _playlist[_playlistIndex].verseKey;
      await _loadAndPlayPlaylist(_playlistIndex);
    } catch (e) {
      debugPrint('Failed to load previous page: $e');
      await stop();
    }
  }

  Future<Map<String, dynamic>?> _getChapterData(int chapterNumber) async {
    if (_chapterDataCache.containsKey(chapterNumber)) {
      return _chapterDataCache[chapterNumber];
    }
    try {
      final data = await _audioRepository.fetchChapterRecitation(
        reciterId: 161,
        chapterNumber: chapterNumber,
      );
      _chapterDataCache[chapterNumber] = data;
      return data;
    } catch (e) {
      debugPrint('Failed to fetch chapter recitation for $chapterNumber: $e');
      _chapterDataCache[chapterNumber] = {};
      return null;
    }
  }

  Future<List<AudioSource>> _buildAudioSources(List<MushafVerse> verses) async {
    final List<AudioSource> sources = [];
    for (final verse in verses) {
      try {
        final surahNumber = int.parse(verse.surahId);
        final chapterData = await _getChapterData(surahNumber);
        
        final String audioUrl = chapterData?['audio_url'] ?? '';
        final Map<String, Map<String, int>> timestamps = Map<String, Map<String, int>>.from(
          chapterData?['timestamps'] ?? {},
        );
        final verseTime = timestamps[verse.verseKey];

        if (audioUrl.isNotEmpty && verseTime != null) {
          final int fromMs = verseTime['from'] ?? 0;
          final int toMs = verseTime['to'] ?? 0;
          sources.add(
            ClippingAudioSource(
              child: AudioSource.uri(Uri.parse(audioUrl)),
              start: Duration(milliseconds: fromMs),
              end: Duration(milliseconds: toMs),
              tag: MediaItem(
                id: verse.verseKey,
                album: "Mushaf Recitation",
                title: "Surah ${verse.surahId} - Verse ${verse.verseId}",
                artist: "Khalifah Al Tunaiji",
                artUri: Uri.parse(
                  "https://raw.githubusercontent.com/doxman13/thai-quran-app/main/assets/icons/playstore-icon.png",
                ),
              ),
            ),
          );
        } else {
          // Fallback single-ayah source from Quran Foundation
          final fallbackUrl = await _audioRepository.fetchAyahRecitationUrl(
            recitationId: 161,
            verseKey: verse.verseKey,
          );
          sources.add(
            AudioSource.uri(
              Uri.parse(fallbackUrl),
              tag: MediaItem(
                id: verse.verseKey,
                album: "Mushaf Recitation (Fallback)",
                title: "Surah ${verse.surahId} - Verse ${verse.verseId}",
                artist: "Khalifah Al Tunaiji",
                artUri: Uri.parse(
                  "https://raw.githubusercontent.com/doxman13/thai-quran-app/main/assets/icons/playstore-icon.png",
                ),
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('Timing error or fallback failed for ${verse.verseKey}: $e, trying EveryAyah...');
        // EveryAyah Mishari Rashid Alafasy fallback
        final chapter = verse.surahId.padLeft(3, '0');
        final ayah = verse.verseId.padLeft(3, '0');
        final fallbackUrl = 'https://everyayah.com/data/Alafasy_128kbps/$chapter$ayah.mp3';
        sources.add(
          AudioSource.uri(
            Uri.parse(fallbackUrl),
            tag: MediaItem(
              id: verse.verseKey,
              album: "Mushaf Recitation (Fallback)",
              title: "Surah ${verse.surahId} - Verse ${verse.verseId}",
              artist: "Mishari Alafasy",
              artUri: Uri.parse(
                "https://raw.githubusercontent.com/doxman13/thai-quran-app/main/assets/icons/playstore-icon.png",
              ),
            ),
          ),
        );
      }
    }
    return sources;
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _currentIndexSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
