// lib/data/quran_repository.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/verse.dart';
import '../services/remote_content_service.dart';
import '../shared/quran_contract.dart';
import 'offline_surah_names.dart';

class QuranRepository {
  Map<String, dynamic>? _quranData;
  Map<String, dynamic>? _mergedQuranData;
  Map<String, dynamic>? _tafsirData;
  Map<String, dynamic>? _tafsirDataEn;
  Map<String, String> _offlineArabicData = {};
  
  static bool globalIsThaiName = true;
  final Map<String, String> surahNames = {};

  // Loads all Surahs from the local JSON asset and fetches Surah Names
  Future<void> init() async {
    if (_quranData != null) {
      if (_mergedQuranData == null) {
        try {
          final String mergedResponse = await rootBundle.loadString(
            'assets/merged_quran.json',
          );
          _mergedQuranData = json.decode(mergedResponse);
        } catch (e) {
          print('Error loading merged_quran.json: $e');
        }
      }

      if (_tafsirData == null) {
        try {
          final String tafsirResponse = await RemoteContentService.instance
              .loadString(
                contentKey: RemoteContentKey.mokhtasarTafsir,
                bundledAssetPath: 'assets/tafsir_thai_mokhtasar.json',
              );
          _tafsirData = json.decode(tafsirResponse);
        } catch (e) {
          print('Error loading tafsir_thai_mokhtasar.json: $e');
        }
      }

      if (_tafsirDataEn == null) {
        try {
          final String tafsirEnResponse = await rootBundle.loadString(
            'assets/tafsir_eng_mokhtasar.json',
          );
          _tafsirDataEn = json.decode(tafsirEnResponse);
        } catch (e) {
          print('Error loading tafsir_eng_mokhtasar.json: $e');
        }
      }

      // Offline surah names are loaded synchronously via offline_surah_names.dart
      return;
    }

    // If init() is called directly without initOfflineMushaf, call initOfflineMushaf() to handle everything.
    await initOfflineMushaf();
  }

  // Removed _loadSurahNames() as it is now offline

  Future<void> initOfflineMushaf() async {
    if (_offlineArabicData.isNotEmpty && _quranData != null) return;
    try {
      final String arabicJsonStr = await rootBundle.loadString(
        'assets/quran_arabic.json',
      );
      final String thaiJsonStr = await RemoteContentService.instance.loadString(
        contentKey: RemoteContentKey.thaiV3,
        bundledAssetPath: 'assets/thai_v3.json',
      );

      final input = OfflineMushafInput(arabicJsonStr, thaiJsonStr);
      final result = await compute(_parseAndMergeMushaf, input);

      _offlineArabicData = result.arabicMap;
      _quranData = result.thaiMap;
    } catch (e) {
      print('Error initializing offline Mushaf: $e');
      if (_quranData == null) {
        try {
          final String response = await RemoteContentService.instance
              .loadString(
                contentKey: RemoteContentKey.thaiV3,
                bundledAssetPath: 'assets/thai_v3.json',
              );
          _quranData = json.decode(response);
        } catch (err) {
          print('Error loading fallback thai_v3.json: $err');
        }
      }
    }

    if (_mergedQuranData == null) {
      try {
        final String mergedResponse = await rootBundle.loadString(
          'assets/merged_quran.json',
        );
        _mergedQuranData = json.decode(mergedResponse);
      } catch (e) {
        print('Error loading merged_quran.json: $e');
      }
    }

    if (_tafsirData == null) {
      try {
        final String tafsirResponse = await RemoteContentService.instance
            .loadString(
              contentKey: RemoteContentKey.mokhtasarTafsir,
              bundledAssetPath: 'assets/tafsir_thai_mokhtasar.json',
            );
        _tafsirData = json.decode(tafsirResponse);
      } catch (e) {
        print('Error loading tafsir_thai_mokhtasar.json: $e');
      }
    }

    if (_tafsirDataEn == null) {
      try {
        final String tafsirEnResponse = await rootBundle.loadString(
          'assets/tafsir_eng_mokhtasar.json',
        );
        _tafsirDataEn = json.decode(tafsirEnResponse);
      } catch (e) {
        print('Error loading tafsir_eng_mokhtasar.json: $e');
      }
    }

    // Offline surah names are loaded synchronously via offline_surah_names.dart
  }

  Future<void> reloadRemoteContent() async {
    _quranData = null;
    _tafsirData = null;
    _tafsirDataEn = null;
    _offlineArabicData = {};
    await initOfflineMushaf();
  }

  String getSurahName(String surahId, {bool? isThai}) {
    final useThai = isThai ?? globalIsThaiName;
    final name = useThai
        ? offlineSurahNamesTh[surahId]
        : offlineSurahNamesEn[surahId];
    return '$surahId. ${name ?? 'Surah $surahId'}';
  }

  // Gets the verses for a specific Surah
  List<Verse> getSurahVerses(String surahId) {
    final versesMap = _getVersesMap(surahId);
    if (versesMap.isEmpty) {
      return [];
    }

    final List<Verse> versesList = [];

    final sortedKeys = versesMap.keys.toList()
      ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

    for (var key in sortedKeys) {
      final verseKey = createVerseKey(surahId, key);
      final mergedVerse = _mergedQuranData?[verseKey];
      final shortTafsir = _tafsirData?[surahId]?[key]?.toString();
      final enTafsirRaw = _tafsirDataEn?['$surahId:$key'];
      final shortTafsirEn = enTafsirRaw is Map ? enTafsirRaw['text']?.toString() : enTafsirRaw?.toString();

      versesList.add(
        Verse(
          id: key,
          surahId: surahId,
          thaiV3: versesMap[key].toString(),
          thaiV2:
              mergedVerse?['thai_v2']?.toString() ??
              mergedVerse?['thai_v1']?.toString() ??
              versesMap[key].toString(),
          english: mergedVerse?['english']?.toString() ?? 'N/A',
          shortTafsir: shortTafsir?.trim().isEmpty == true ? null : shortTafsir,
          shortTafsirSource: shortTafsir == null
              ? null
              : 'QuranEnc Thai Mokhtasar',
          shortTafsirEn: shortTafsirEn?.trim().isEmpty == true ? null : shortTafsirEn,
          shortTafsirSourceEn: shortTafsirEn == null ? null : 'QuranEnc English Mokhtasar',
          arabic: '', // Initially empty, will be fetched via API
        ),
      );
    }

    return versesList;
  }

  Verse? getVerse(String surahId, String verseId) {
    final versesMap = _getVersesMap(surahId);
    final thaiV3Text = versesMap[verseId];
    if (thaiV3Text == null) return null;

    final verseKey = createVerseKey(surahId, verseId);
    final mergedVerse = _mergedQuranData?[verseKey];
    final shortTafsir = _tafsirData?[surahId]?[verseId]?.toString();
    final enTafsirRaw = _tafsirDataEn?['$surahId:$verseId'];
    final shortTafsirEn = enTafsirRaw is Map ? enTafsirRaw['text']?.toString() : enTafsirRaw?.toString();

    return Verse(
      id: verseId,
      surahId: surahId,
      thaiV3: thaiV3Text.toString(),
      thaiV2:
          mergedVerse?['thai_v2']?.toString() ??
          mergedVerse?['thai_v1']?.toString() ??
          thaiV3Text.toString(),
      english: mergedVerse?['english']?.toString() ?? 'N/A',
      shortTafsir: shortTafsir?.trim().isEmpty == true ? null : shortTafsir,
      shortTafsirSource: shortTafsir == null ? null : 'QuranEnc Thai Mokhtasar',
      shortTafsirEn: shortTafsirEn?.trim().isEmpty == true ? null : shortTafsirEn,
      shortTafsirSourceEn: shortTafsirEn == null ? null : 'QuranEnc English Mokhtasar',
      arabic: '',
    );
  }

  Map<String, String> _getVersesMap(String surahId) {
    final quranData = _quranData;
    if (quranData == null) return {};

    final oldSurahData = quranData[surahId];
    if (oldSurahData is Map<String, dynamic>) {
      final oldVerses = oldSurahData['verses'];
      if (oldVerses is Map<String, dynamic>) {
        return oldVerses.map(
          (verseId, verseText) => MapEntry(verseId, verseText.toString()),
        );
      }
    }

    final versePrefix = '$surahId:';
    final verses = <String, String>{};

    for (final entry in quranData.entries) {
      final key = entry.key;
      if (!key.startsWith(versePrefix)) continue;

      final verseId = key.substring(versePrefix.length);
      if (int.tryParse(verseId) == null) continue;

      verses[verseId] = entry.value.toString();
    }

    return verses;
  }

  // Fetches Arabic text from the Quran Foundation API.
  // Prefers text_qpc_hafs from word data to ensure correct sukun rendering with UthmanicHafs font.
  String _normalizeArabicText(String text) {
    // Replace ARABIC SMALL HIGH ROUNDED ZERO (U+06DF) with standard ARABIC SUKUN (U+0652)
    // to fix combining character black circle rendering bugs in the Flutter text engine.
    return text.replaceAll('\u06DF', '\u0652');
  }

  Future<String> fetchArabicVerse(String surahId, String verseId) async {
    // 0. Check in-memory offline Arabic mushaf data first
    final offlineKey = '$surahId:$verseId';
    final offlineText = _offlineArabicData[offlineKey];
    if (offlineText != null && offlineText.isNotEmpty) {
      return _normalizeArabicText(offlineText);
    }

    final cacheKey = 'arabic_qpc_v3_${surahId}_$verseId';
    final prefs = await SharedPreferences.getInstance();

    // 1. Check local cache first (using new cache key to avoid old cache)
    final cached = prefs.getString(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      return _normalizeArabicText(cached);
    }

    // 2. Fetch from internet if not cached
    try {
      // Try to load QPC Hafs word-by-word data first
      final url = Uri.parse(
        'https://api.quran.com/api/v4/verses/by_key/$surahId:$verseId?words=true&word_fields=text_qpc_hafs,text_uthmani',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final words = data['verse']?['words'] as List?;
        if (words != null && words.isNotEmpty) {
          final List<String> mainWords = [];
          String endGlyph = '';

          for (var w in words) {
            final qpc = w['text_qpc_hafs']?.toString();
            final uthmani = w['text_uthmani']?.toString();
            final text = (qpc != null && qpc.isNotEmpty)
                ? qpc
                : (uthmani ?? '');
            if (text.isNotEmpty) {
              if (w['char_type_name'] == 'end') {
                endGlyph = text;
              } else {
                mainWords.add(text);
              }
            }
          }

          if (mainWords.isNotEmpty) {
            final qpcText = endGlyph.isNotEmpty
                ? '${mainWords.join(' ')} | $endGlyph'
                : mainWords.join(' ');
            await prefs.setString(cacheKey, qpcText);
            return _normalizeArabicText(qpcText);
          }
        }
      }
    } catch (e) {
      // Fallback to text_uthmani below if QPC Hafs fetching fails
    }

    // 3. Fallback: load Uthmani text if QPC Hafs loading failed
    try {
      final fallbackUrl = Uri.parse(
        'https://api.quran.com/api/v4/verses/by_key/$surahId:$verseId?fields=text_uthmani',
      );
      final response = await http.get(fallbackUrl);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final arabicText = data['verse']?['text_uthmani'] as String?;

        if (arabicText != null && arabicText.isNotEmpty) {
          await prefs.setString(cacheKey, arabicText);
          return _normalizeArabicText(arabicText);
        }
      }
    } catch (e) {
      // Return empty if completely offline or error
      return '';
    }
    return '';
  }
}

class OfflineMushafInput {
  final String arabicJsonStr;
  final String thaiJsonStr;

  const OfflineMushafInput(this.arabicJsonStr, this.thaiJsonStr);
}

class OfflineMushafResult {
  final Map<String, String> arabicMap;
  final Map<String, dynamic> thaiMap;

  const OfflineMushafResult(this.arabicMap, this.thaiMap);
}

OfflineMushafResult _parseAndMergeMushaf(OfflineMushafInput input) {
  final Map<String, dynamic> decodedThai = json.decode(input.thaiJsonStr);
  final List<dynamic> decodedArabic = json.decode(input.arabicJsonStr);

  final Map<String, String> arabicMap = {};
  for (var item in decodedArabic) {
    if (item is Map) {
      final sId = item['surah_id'].toString();
      final aNum = item['ayah_number'].toString();
      final text = item['uthmani_text'].toString();
      arabicMap['$sId:$aNum'] = text;
    }
  }

  return OfflineMushafResult(arabicMap, decodedThai);
}
