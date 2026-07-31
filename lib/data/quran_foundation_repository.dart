import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../models/mushaf_models.dart';
import '../services/tajweed_service.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;

class QuranFoundationConfig {
  static const liveContentBaseUrl =
      'https://apis.quran.foundation/content/api/v4';
  static const preliveContentBaseUrl =
      'https://apis-prelive.quran.foundation/content/api/v4';
  static const contentBaseUrl = String.fromEnvironment(
    'QURAN_FOUNDATION_CONTENT_BASE_URL',
    defaultValue: '',
  );
  static const authBaseUrl = String.fromEnvironment(
    'QURAN_FOUNDATION_AUTH_BASE_URL',
    defaultValue: 'https://oauth2.quran.foundation',
  );
  static const clientId = String.fromEnvironment('QURAN_FOUNDATION_CLIENT_ID');
  static const authToken = String.fromEnvironment(
    'QURAN_FOUNDATION_AUTH_TOKEN',
  );

  static bool get isConfigured => clientId.isNotEmpty && authToken.isNotEmpty;
}

class _ResolvedQuranFoundationConfig {
  final String contentBaseUrl;
  final String authBaseUrl;
  final String clientId;
  final String authToken;

  const _ResolvedQuranFoundationConfig({
    required this.contentBaseUrl,
    required this.authBaseUrl,
    required this.clientId,
    required this.authToken,
  });

  bool get isConfigured => clientId.isNotEmpty && authToken.isNotEmpty;
}

class QuranSearchResultItem {
  final String verseKey;
  final String surahId;
  final String verseId;
  final String arabicText;
  final String translationText;

  QuranSearchResultItem({
    required this.verseKey,
    required this.surahId,
    required this.verseId,
    required this.arabicText,
    required this.translationText,
  });
}

class QuranSearchResult {
  final String query;
  final int totalResults;
  final List<QuranSearchResultItem> items;

  QuranSearchResult({
    required this.query,
    required this.totalResults,
    required this.items,
  });
}

class QuranFoundationException implements Exception {
  final String message;

  const QuranFoundationException(this.message);

  @override
  String toString() => message;
}

class QuranFoundationRepository {
  static const _cachePrefix = 'quran_foundation_cache_v5';
  final http.Client _client;

  QuranFoundationRepository({http.Client? client})
    : _client = client ?? http.Client();

  Future<QuranSearchResult> searchQuran({
    required String query,
    String language = 'th',
    int size = 20,
    int page = 1,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return QuranSearchResult(query: '', totalResults: 0, items: []);
    }

    try {
      final uri = Uri.parse(
        'https://api.quran.com/api/v4/search?q=${Uri.encodeComponent(cleanQuery)}&size=$size&page=$page&language=$language',
      );
      final response = await _client.get(
        uri,
        headers: {'accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final search = decoded['search'] as Map<String, dynamic>?;
        if (search != null) {
          final totalResults = search['total_results'] as int? ?? 0;
          final rawResults = search['results'] as List<dynamic>? ?? [];
          final items = <QuranSearchResultItem>[];

          for (final raw in rawResults) {
            if (raw is Map<String, dynamic>) {
              final vk = raw['verse_key']?.toString() ?? '';
              final parts = vk.split(':');
              final sId = parts.isNotEmpty ? parts[0] : '';
              final vId = parts.length > 1 ? parts[1] : '';
              final text = raw['text']?.toString() ?? '';

              String transText = '';
              final translations = raw['translations'] as List<dynamic>?;
              if (translations != null && translations.isNotEmpty) {
                final firstTrans = translations.first;
                if (firstTrans is Map<String, dynamic>) {
                  transText = (firstTrans['text']?.toString() ?? '')
                      .replaceAll(RegExp(r'<[^>]+>'), '')
                      .trim();
                }
              }

              items.add(QuranSearchResultItem(
                verseKey: vk,
                surahId: sId,
                verseId: vId,
                arabicText: text,
                translationText: transText,
              ));
            }
          }

          return QuranSearchResult(
            query: cleanQuery,
            totalResults: totalResults,
            items: items,
          );
        }
      }
    } catch (e) {
      debugPrint('Quran search API error: $e');
    }

    return QuranSearchResult(query: cleanQuery, totalResults: 0, items: []);
  }

  int _contentMushafId(int mushafId) {
    if (mushafId == qcfPackageMushafId) return 1;
    if (mushafId == 19) return 4;
    return mushafId;
  }

  Future<MushafPage> fetchPage({
    required int mushafId,
    required int pageNumber,
  }) async {
    final resolvedMushafId = _contentMushafId(mushafId);
    final pageCount = mushafTypeById(resolvedMushafId).pageCount;
    final safePage = _clampInt(pageNumber, 1, pageCount);

    if (mushafId == 11) {
      final basePage = await fetchPage(mushafId: 2, pageNumber: safePage);
      await TajweedService.load();
      return TajweedService.augmentMushafPage(basePage);
    }

    if (mushafId == qcfPackageMushafId) {
      final List<MushafVerse> verses = [];
      try {
        final pageItems = qcf.getPageData(safePage);
        for (final item in pageItems) {
          final int surah = item['surah'];
          final int start = item['start'];
          final int end = item['end'];
          for (int v = start; v <= end; v++) {
            verses.add(MushafVerse(
              verseKey: '$surah:$v',
              surahId: surah.toString(),
              verseId: v.toString(),
              words: [],
            ));
          }
        }
      } catch (e) {
        debugPrint('Error generating local QCF page data: $e');
      }
      return MushafPage(
        mushafId: mushafId,
        pageNumber: safePage,
        verses: verses,
        lines: [],
      );
    }

    final cacheKey = '$_cachePrefix:page:$mushafId:$resolvedMushafId:$safePage';

    final fontLoadFuture = loadFontForPage(
      mushafId: mushafId,
      pageNumber: safePage,
    );

    if (safePage < pageCount) {
      loadFontForPage(mushafId: mushafId, pageNumber: safePage + 1);
    }
    if (safePage > 1) {
      loadFontForPage(mushafId: mushafId, pageNumber: safePage - 1);
    }

    // Try to load QCF V1 page layout from local assets first
    if (mushafId == 2) {
      try {
        final localPath = 'assets/qcf_v1_pages/page_$safePage.json';
        final jsonStr = await rootBundle.loadString(localPath);
        final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
        final parsed = _parsePage(
          jsonMap,
          mushafId: mushafId,
          pageNumber: safePage,
        );
        await fontLoadFuture;
        return parsed;
      } catch (e) {
        debugPrint('Failed to load local asset for page $safePage: $e');
      }
    }

    final cached = await _readCachedJson(cacheKey);
    if (cached != null) {
      final parsed = _parsePage(
        cached,
        mushafId: mushafId,
        pageNumber: safePage,
      );
      await fontLoadFuture;
      return parsed;
    }

    final config = await _resolveConfig();
    final uri = _uri('/verses/by_page/$safePage', {
      'mushaf': resolvedMushafId.toString(),
      'words': 'true',
      'include_words': 'true',
      if (mushafId == 11 || mushafId == 19) 'fields': 'text_uthmani_tajweed',
      'word_fields':
          'code,code_v1,code_v2,text_uthmani,text_indopak,text_qpc_hafs,text,text_uthmani_tajweed',
    }, config);
    final json = await _getJson(uri, config);
    await _writeCachedJson(cacheKey, json);
    final parsed = _parsePage(json, mushafId: mushafId, pageNumber: safePage);
    await fontLoadFuture;
    return parsed;
  }

  String getFontFamily(int mushafId, int pageNumber) {
    if (mushafId == 1) {
      return 'qcf_v2_p$pageNumber';
    } else if (mushafId == 2) {
      return 'qcf_v1_p$pageNumber';
    } else if (mushafId == 11) {
      return 'Tajweed';
    } else if (mushafId == 19) {
      return 'p$pageNumber-v4';
    } else if (mushafId == 3 || mushafId == 6 || mushafId == 7) {
      return 'IndoPakNastaleeq';
    } else {
      return 'UthmanicHafs';
    }
  }

  String? getFontUrl(int mushafId, int pageNumber) {
    if (mushafId == 1) {
      return 'https://verses.quran.foundation/fonts/quran/hafs/v2/ttf/p$pageNumber.ttf';
    } else if (mushafId == 2) {
      return 'https://verses.quran.foundation/fonts/quran/hafs/v1/ttf/p$pageNumber.ttf';
    } else if (mushafId == 11) {
      return null;
    } else if (mushafId == 19) {
      return 'https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf/p$pageNumber.ttf';
    } else if (mushafId == 3 || mushafId == 6 || mushafId == 7) {
      return 'https://verses.quran.foundation/fonts/quran/hafs/nastaleeq/indopak/indopak-nastaleeq-waqf-lazim-v4.2.1.ttf';
    }
    return null;
  }

  Future<void> loadFontForPage({
    required int mushafId,
    required int pageNumber,
  }) async {
    if (mushafId == qcfPackageMushafId) return;
    final fontFamily = getFontFamily(mushafId, pageNumber);
    final fontUrl = getFontUrl(mushafId, pageNumber);
    if (fontUrl == null) return;

    await DynamicFontLoader.loadFont(fontFamily: fontFamily, url: fontUrl);
  }

  Future<MushafPageRange> lookupBySurah({
    required int mushafId,
    required int surahNumber,
  }) {
    return _lookupRange(
      mushafId: mushafId,
      cacheSuffix: 'surah:$surahNumber',
      query: {'chapter_number': surahNumber.toString()},
    );
  }

  Future<MushafPageRange> lookupByJuz({
    required int mushafId,
    required int juzNumber,
  }) {
    return _lookupRange(
      mushafId: mushafId,
      cacheSuffix: 'juz:$juzNumber',
      query: {'juz_number': juzNumber.toString()},
    );
  }

  Future<MushafPageRange> lookupByVerseRange({
    required int mushafId,
    required String fromVerseKey,
    required String toVerseKey,
  }) {
    return _lookupRange(
      mushafId: mushafId,
      cacheSuffix: 'verses:$fromVerseKey:$toVerseKey',
      query: {'from': fromVerseKey, 'to': toVerseKey},
    );
  }

  Future<MushafPageRange> _lookupRange({
    required int mushafId,
    required String cacheSuffix,
    required Map<String, String> query,
  }) async {
    if (mushafTypeById(mushafId).pageCount == 604) {
      if (cacheSuffix.startsWith('surah:')) {
        final surahNumber = int.parse(cacheSuffix.substring(6));
        final startPage = qcf.getPageNumber(surahNumber, 1);
        final totalVerses = qcf.getVerseCount(surahNumber);
        final endPage = qcf.getPageNumber(surahNumber, totalVerses);
        return MushafPageRange(startPage: startPage, endPage: endPage);
      } else if (cacheSuffix.startsWith('juz:')) {
        final juzNumber = int.parse(cacheSuffix.substring(4));
        const juzStartPages = [
          1, 22, 42, 62, 82, 102, 121, 142, 162, 182,
          201, 222, 242, 262, 282, 302, 322, 342, 362, 382,
          402, 422, 442, 462, 482, 502, 522, 542, 562, 582
        ];
        final startPage = juzStartPages[juzNumber - 1];
        final endPage = juzNumber == 30 ? 604 : juzStartPages[juzNumber] - 1;
        return MushafPageRange(startPage: startPage, endPage: endPage);
      } else if (cacheSuffix.startsWith('verses:')) {
        final parts = cacheSuffix.substring(7).split(':');
        if (parts.length >= 4) {
          final fromSurah = int.parse(parts[0]);
          final fromVerse = int.parse(parts[1]);
          final toSurah = int.parse(parts[2]);
          final toVerse = int.parse(parts[3]);
          final startPage = qcf.getPageNumber(fromSurah, fromVerse);
          final endPage = qcf.getPageNumber(toSurah, toVerse);
          return MushafPageRange(startPage: startPage, endPage: endPage);
        }
      }
    }

    final resolvedMushafId = _contentMushafId(mushafId);
    final cacheKey =
        '$_cachePrefix:lookup:$mushafId:$resolvedMushafId:$cacheSuffix';
    final cached = await _readCachedJson(cacheKey);
    if (cached != null) {
      return _parseRange(cached, mushafId);
    }

    final config = await _resolveConfig();
    final uri = _uri('/pages/lookup', {
      'mushaf': resolvedMushafId.toString(),
      ...query,
    }, config);
    final json = await _getJson(uri, config);
    await _writeCachedJson(cacheKey, json);
    return _parseRange(json, mushafId);
  }

  Future<String> fetchAyahRecitationUrl({
    required int recitationId,
    required String verseKey,
  }) async {
    final config = await _resolveConfig();
    try {
      final json = await _getJson(
        _uri('/quran/recitations/$recitationId', {
          'verse_key': verseKey,
          'fields': 'verse_key,url',
          'per_page': '1',
        }, config),
        config,
      );

      final audioFiles = json['audio_files'];
      if (audioFiles is List && audioFiles.isNotEmpty) {
        final matchingFile = audioFiles.cast<dynamic>().firstWhere((item) {
          return item is Map && item['verse_key']?.toString() == verseKey;
        }, orElse: () => audioFiles.first);

        if (matchingFile is Map && matchingFile['url'] != null) {
          return _normalizeAudioUrl(matchingFile['url'].toString());
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch recitation for reciter $recitationId: $e');
    }

    // Fallback to Mishari Rashid Al-Afasy (ID 7) if the primary reciter fails or is empty
    if (recitationId != 7) {
      debugPrint('Falling back to Mishari Rashid al-Afasy (ID 7) for $verseKey');
      return fetchAyahRecitationUrl(recitationId: 7, verseKey: verseKey);
    }

    throw QuranFoundationException('No audio file found for $verseKey.');
  }

  Future<Map<String, dynamic>> fetchChapterRecitation({
    required int reciterId,
    required int chapterNumber,
  }) async {
    final config = await _resolveConfig();
    final json = await _getJson(
      _uri('/chapter_recitations/$reciterId/$chapterNumber', {
        'segments': 'true',
      }, config),
      config,
    );

    final audioFile = json['audio_file'];
    if (audioFile is! Map) {
      throw const QuranFoundationException('Invalid chapter recitation response.');
    }

    final audioUrl = audioFile['audio_url']?.toString() ?? '';
    final timestampsList = audioFile['timestamps'] as List?;
    
    // Parse timestamps list into a map of verseKey -> (timestampFrom, timestampTo)
    final timestampsMap = <String, Map<String, int>>{};
    if (timestampsList != null) {
      for (final item in timestampsList) {
        if (item is Map) {
          final vk = item['verse_key']?.toString();
          final from = int.tryParse(item['timestamp_from']?.toString() ?? '');
          final to = int.tryParse(item['timestamp_to']?.toString() ?? '');
          if (vk != null && from != null && to != null) {
            timestampsMap[vk] = {
              'from': from,
              'to': to,
            };
          }
        }
      }
    }

    return {
      'audio_url': _normalizeAudioUrl(audioUrl),
      'timestamps': timestampsMap,
    };
  }

  String _normalizeAudioUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    final path = url.replaceFirst(RegExp(r'^/+'), '');
    return 'https://verses.quran.foundation/$path';
  }

  Uri _uri(
    String path,
    Map<String, String> query,
    _ResolvedQuranFoundationConfig config,
  ) {
    final base = config.contentBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = parts[1];
      var normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
      switch (normalized.length % 4) {
        case 0:
          break;
        case 2:
          normalized += '==';
          break;
        case 3:
          normalized += '=';
          break;
        default:
          return true;
      }
      final decoded = utf8.decode(base64.decode(normalized));
      final map = jsonDecode(decoded);
      if (map is Map && map.containsKey('exp')) {
        final exp = map['exp'] as int;
        final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        return DateTime.now()
            .add(const Duration(minutes: 5))
            .isAfter(expiryDate);
      }
    } catch (_) {
      return true;
    }
    return true;
  }

  Future<String> _fetchJwtToken(_ResolvedQuranFoundationConfig config) async {
    final authUrl = config.authBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$authUrl/oauth2/token');
    final credentials = base64Encode(
      utf8.encode('${config.clientId}:${config.authToken}'),
    );

    final response = await _client.post(
      uri,
      headers: {
        'accept': 'application/json',
        'content-type': 'application/x-www-form-urlencoded',
        'authorization': 'Basic $credentials',
      },
      body: {'grant_type': 'client_credentials', 'scope': 'content'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuranFoundationException(
        'Failed to obtain Quran Foundation access token (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> &&
        decoded.containsKey('access_token')) {
      final token = decoded['access_token'] as String;
      if (token.isNotEmpty) {
        return token;
      }
    }
    throw const QuranFoundationException(
      'Invalid token response from Quran Foundation.',
    );
  }

  Future<String> _getOrFetchToken(_ResolvedQuranFoundationConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix:access_token:${config.clientId}';
      final cachedToken = prefs.getString(cacheKey);

      if (cachedToken != null && !_isTokenExpired(cachedToken)) {
        return cachedToken;
      }

      final token = await _fetchJwtToken(config);
      await prefs.setString(cacheKey, token);
      return token;
    } catch (e) {
      debugPrint('Error getting or fetching Quran Foundation token: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri,
    _ResolvedQuranFoundationConfig config,
  ) async {
    if (!config.isConfigured) {
      throw const QuranFoundationException(
        'Quran Foundation credentials are missing. Build with QURAN_FOUNDATION_CLIENT_ID and QURAN_FOUNDATION_AUTH_TOKEN.',
      );
    }

    final token = await _getOrFetchToken(config);

    var response = await _client.get(
      uri,
      headers: {
        'accept': 'application/json',
        'x-client-id': config.clientId,
        'x-auth-token': token,
      },
    );

    if (response.statusCode == 401 ||
        (response.statusCode == 400 &&
            response.body.contains('invalid_token'))) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = '$_cachePrefix:access_token:${config.clientId}';
        await prefs.remove(cacheKey);

        final newToken = await _getOrFetchToken(config);
        response = await _client.get(
          uri,
          headers: {
            'accept': 'application/json',
            'x-client-id': config.clientId,
            'x-auth-token': newToken,
          },
        );
      } catch (retryError) {
        debugPrint('Retry token fetch failed: $retryError');
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuranFoundationException(
        'Quran Foundation request failed (${response.statusCode}) for ${uri.path}. ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const QuranFoundationException(
      'Quran Foundation returned an unexpected response.',
    );
  }

  Future<_ResolvedQuranFoundationConfig> _resolveConfig() async {
    if (QuranFoundationConfig.isConfigured) {
      return _ResolvedQuranFoundationConfig(
        contentBaseUrl: _resolveContentBaseUrl(
          QuranFoundationConfig.contentBaseUrl,
          QuranFoundationConfig.authBaseUrl,
        ),
        authBaseUrl: QuranFoundationConfig.authBaseUrl,
        clientId: QuranFoundationConfig.clientId,
        authToken: QuranFoundationConfig.authToken,
      );
    }

    final localEnv = await _readLocalEnv();
    final resolvedAuthBaseUrl =
        localEnv['QURAN_FOUNDATION_AUTH_BASE_URL'] ??
        localEnv['QURAN_FOUNDATION_BASE_URL'] ??
        QuranFoundationConfig.authBaseUrl;

    return _ResolvedQuranFoundationConfig(
      contentBaseUrl: _resolveContentBaseUrl(
        localEnv['QURAN_FOUNDATION_CONTENT_BASE_URL'] ??
            QuranFoundationConfig.contentBaseUrl,
        resolvedAuthBaseUrl,
      ),
      authBaseUrl: resolvedAuthBaseUrl,
      clientId:
          localEnv['QURAN_FOUNDATION_CLIENT_ID'] ??
          QuranFoundationConfig.clientId,
      authToken:
          localEnv['QURAN_FOUNDATION_AUTH_TOKEN'] ??
          QuranFoundationConfig.authToken,
    );
  }

  String _resolveContentBaseUrl(String configuredContentUrl, String authUrl) {
    final configured = configuredContentUrl.trim();
    final isPrelive = authUrl.toLowerCase().contains('prelive');
    if (isPrelive &&
        (configured.isEmpty ||
            configured == QuranFoundationConfig.liveContentBaseUrl)) {
      return QuranFoundationConfig.preliveContentBaseUrl;
    }
    if (configured.isNotEmpty) return configured;
    return QuranFoundationConfig.liveContentBaseUrl;
  }

  Future<Map<String, String>> _readLocalEnv() async {
    if (kIsWeb) return const {};
    try {
      final file = File('.env');
      if (!await file.exists()) return const {};
      final content = await file.readAsString();
      final values = <String, String>{};
      for (final line in const LineSplitter().convert(content)) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final separator = trimmed.indexOf('=');
        if (separator <= 0) continue;
        final key = trimmed.substring(0, separator).trim();
        final value = trimmed.substring(separator + 1).trim();
        values[key] = value;
      }
      return values;
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, dynamic>?> _readCachedJson(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(key);
      if (cached == null || cached.isEmpty) return null;
      final decoded = jsonDecode(cached);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (error) {
      debugPrint('Mushaf cache read failed: $error');
      return null;
    }
  }

  Future<void> _writeCachedJson(String key, Map<String, dynamic> json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(json));
    } catch (error) {
      debugPrint('Mushaf cache write failed: $error');
    }
  }

  MushafPage _parsePage(
    Map<String, dynamic> json, {
    required int mushafId,
    required int pageNumber,
  }) {
    final rawVerses = _verseList(json);
    final verses = <MushafVerse>[];
    final allWords = <MushafWord>[];

    for (final rawVerse in rawVerses) {
      if (rawVerse is! Map) continue;
      final verseMap = Map<String, dynamic>.from(rawVerse);
      final verseKey = _stringValue(verseMap, ['verse_key', 'verseKey', 'key']);
      final parts = verseKey.split(':');
      final surahId = parts.isNotEmpty
          ? parts.first
          : _stringValue(verseMap, ['chapter_id', 'surah_id', 'chapterNumber']);
      final verseId = parts.length > 1
          ? parts.last
          : _stringValue(verseMap, ['verse_number', 'verse_id', 'id']);
      final rawWords = _wordList(verseMap);
      final textUthmaniTajweed = mushafId == 11 || mushafId == 19
          ? _stringValue(verseMap, ['text_uthmani_tajweed'])
          : '';
      if (kDebugMode &&
          (mushafId == 11 || mushafId == 19) &&
          textUthmaniTajweed.isNotEmpty) {
        _debugTajweedText(mushafId, verseKey, textUthmaniTajweed);
      }
      final tajweedWordParts = textUthmaniTajweed.trim().isNotEmpty
          ? _parseTajweedWordParts(textUthmaniTajweed, mushafId)
          : const <List<MushafTajweedPart>>[];
      final words = <MushafWord>[];
      var wordIndex = 0;

      for (final rawWord in rawWords) {
        if (rawWord is! Map) continue;
        final wordMap = Map<String, dynamic>.from(rawWord);
        final text = _wordText(wordMap, mushafId);
        if (text.trim().isEmpty) continue;
        final wordVerseKey =
            _stringValue(wordMap, ['verse_key', 'verseKey']) == ''
            ? verseKey
            : _stringValue(wordMap, ['verse_key', 'verseKey']);

        final position =
            _intValue(wordMap, [
              'position',
              'word_number',
              'wordNumber',
              'position_in_verse',
            ]) ??
            0;

        List<MushafTajweedPart> tajweedParts =
            wordIndex < tajweedWordParts.length
            ? tajweedWordParts[wordIndex]
            : const <MushafTajweedPart>[];
        wordIndex++;

        if (kDebugMode &&
            (mushafId == 11 || mushafId == 19) &&
            verseKey == '1:7') {
          _debugCleanTajweedParts(mushafId, wordVerseKey, text, tajweedParts);
        }

        final word = MushafWord(
          text: text,
          verseKey: wordVerseKey,
          lineNumber:
              _intValue(wordMap, [
                'line_number',
                'lineNumber',
                'page_line',
                'line',
              ]) ??
              _intValue(verseMap, ['line_number', 'lineNumber', 'page_line']) ??
              1,
          position: position,
          tajweedParts: tajweedParts,
        );
        words.add(word);
        allWords.add(word);
      }

      verses.add(
        MushafVerse(
          verseKey: verseKey,
          surahId: surahId,
          verseId: verseId,
          words: words,
        ),
      );
    }

    final grouped = <int, List<MushafWord>>{};
    for (final word in allWords) {
      grouped.putIfAbsent(word.lineNumber, () => []).add(word);
    }
    final lines = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (rawVerses.isEmpty || allWords.isEmpty) {
      throw QuranFoundationException(
        _pageParseErrorMessage(json, rawVerses.length, allWords.length),
      );
    }

    return MushafPage(
      mushafId: mushafId,
      pageNumber: pageNumber,
      verses: verses,
      lines: lines.map((entry) => entry.value).toList(),
    );
  }

  MushafPageRange _parseRange(Map<String, dynamic> json, int mushafId) {
    final candidates = [
      json['pages'],
      json['data']?['pages'],
      json['page'],
      json['data']?['page'],
      json['pages_range'],
      json['data']?['pages_range'],
    ];
    final pages = <int>[];

    for (final candidate in candidates) {
      if (candidate is List) {
        pages.addAll(
          candidate.map((item) => int.tryParse(item.toString()) ?? 0),
        );
      } else if (candidate is Map) {
        final map = Map<String, dynamic>.from(candidate);
        pages.addAll(
          [
            _intValue(map, ['from', 'start', 'first', 'start_page']),
            _intValue(map, ['to', 'end', 'last', 'end_page']),
          ].whereType<int>(),
        );
      } else if (candidate != null) {
        final page = int.tryParse(candidate.toString());
        if (page != null) pages.add(page);
      }
    }

    final dataMap = _asMap(json['data']);
    final start =
        _intValue(json, ['from', 'start', 'first', 'start_page']) ??
        _intValue(dataMap, ['from', 'start', 'first', 'start_page']);
    final end =
        _intValue(json, ['to', 'end', 'last', 'end_page']) ??
        _intValue(dataMap, ['to', 'end', 'last', 'end_page']);

    if (start != null) pages.add(start);
    if (end != null) pages.add(end);
    pages.removeWhere((page) => page < 1);
    if (pages.isEmpty) {
      throw const QuranFoundationException(
        'Could not determine Mushaf page range from Quran Foundation response.',
      );
    }

    pages.sort();
    final pageCount = mushafTypeById(mushafId).pageCount;
    return MushafPageRange(
      startPage: _clampInt(pages.first, 1, pageCount),
      endPage: _clampInt(pages.last, 1, pageCount),
    );
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    return const [];
  }

  List<dynamic> _verseList(Map<String, dynamic> json) {
    final data = json['data'];
    for (final candidate in [
      json['verses'],
      data is Map ? data['verses'] : null,
      data is List ? data : null,
      json['results'],
      data is Map ? data['results'] : null,
    ]) {
      final list = _asList(candidate);
      if (list.isNotEmpty) return list;
    }
    return const [];
  }

  List<dynamic> _wordList(Map<String, dynamic> verseMap) {
    final data = verseMap['data'];
    for (final candidate in [
      verseMap['words'],
      data is Map ? data['words'] : null,
      verseMap['word'],
      verseMap['words_data'],
      verseMap['word_data'],
    ]) {
      final list = _asList(candidate);
      if (list.isNotEmpty) return list;
    }
    return const [];
  }

  String _pageParseErrorMessage(
    Map<String, dynamic> json,
    int verseCount,
    int wordCount,
  ) {
    final rootKeys = json.keys.take(12).join(', ');
    final data = json['data'];
    final dataKeys = data is Map
        ? Map<String, dynamic>.from(data).keys.take(12).join(', ')
        : data is List
        ? 'list(${data.length})'
        : data.runtimeType.toString();
    return 'Quran Foundation page response had $verseCount verses and $wordCount readable words. Root keys: [$rootKeys]. Data: [$dataKeys].';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  List<List<MushafTajweedPart>> _parseTajweedWordParts(
    String html,
    int mushafId,
  ) {
    final words = <List<MushafTajweedPart>>[];
    var currentWord = <MushafTajweedPart>[];
    var buffer = StringBuffer();
    var bufferClass = '';
    final classStack = <String>[];

    String activeClass() => classStack.isEmpty ? '' : classStack.last;

    void flushBuffer() {
      if (buffer.isEmpty) return;
      currentWord.add(
        MushafTajweedPart(
          text: _normalizeUthmaniGlyphs(
            _decodeHtmlEntities(buffer.toString()),
            stripAnnotationMarks: false,
          ),
          className: bufferClass,
        ),
      );
      buffer = StringBuffer();
    }

    void finishWord() {
      flushBuffer();
      final adjusted = _adjustWordTajweedParts(currentWord);
      adjusted.removeWhere(_shouldDropTajweedPart);
      if (adjusted.isNotEmpty) words.add(adjusted);
      currentWord = <MushafTajweedPart>[];
    }

    void appendVisibleText(String text) {
      for (final rune in text.runes) {
        final char = String.fromCharCode(rune);
        if (char.trim().isEmpty) {
          finishWord();
          continue;
        }

        final nextClass = activeClass();
        if (buffer.isNotEmpty && bufferClass != nextClass) {
          flushBuffer();
        }
        bufferClass = nextClass;
        buffer.write(char);
      }
    }

    var index = 0;
    while (index < html.length) {
      final tagStart = html.indexOf('<', index);
      if (tagStart == -1) {
        appendVisibleText(html.substring(index));
        break;
      }

      if (tagStart > index) {
        appendVisibleText(html.substring(index, tagStart));
      }

      final tagEnd = html.indexOf('>', tagStart + 1);
      if (tagEnd == -1) {
        break;
      }

      final tag = html.substring(tagStart + 1, tagEnd).trim();
      final lowerTag = tag.toLowerCase();
      if (lowerTag.startsWith('/')) {
        if (classStack.isNotEmpty) classStack.removeLast();
      } else if (!lowerTag.startsWith('img') && !lowerTag.endsWith('/')) {
        final className = _extractHtmlClass(tag);
        classStack.add(className.isEmpty ? activeClass() : className);
      }

      index = tagEnd + 1;
    }

    finishWord();
    return words;
  }

  String _extractHtmlClass(String tag) {
    final match = RegExp(r'''class\s*=\s*["']?([^"'>\s]+)''').firstMatch(tag);
    if (match != null) return match.group(1) ?? '';

    final tagName = tag.split(RegExp(r'\s+')).first.toLowerCase();
    const structuralTags = {'span', 'b', 'i', 'u', 'strong', 'em', 'font'};
    return structuralTags.contains(tagName) ? '' : tagName;
  }

  String _decodeHtmlEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&thinsp;', ' ')
        .replaceAll('&zwj;', '\u200d')
        .replaceAll('&zwnj;', '\u200c')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
          final codePoint = int.tryParse(match.group(1)!, radix: 16);
          return codePoint == null
              ? match.group(0)!
              : String.fromCharCode(codePoint);
        })
        .replaceAllMapped(RegExp(r'&#([0-9]+);'), (match) {
          final codePoint = int.tryParse(match.group(1)!);
          return codePoint == null
              ? match.group(0)!
              : String.fromCharCode(codePoint);
        });
  }

  String _normalizeUthmaniGlyphs(
    String text, {
    bool stripAnnotationMarks = false,
  }) {
    var normalized = text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\S+\.png', caseSensitive: false), '')
        // Replace U+06DF first, then strip the Uthmani annotation marks that
        // some fallback fonts render as heavy black dots in Tajweed text.
        // U+0670 is dagger/superscript alif; it can look like a black drop
        // with the fallback font used by the color Tajweed path.
        .replaceAll('\u06df', '\u06e1')
        .replaceAll('\u0672', '\u0670')
        .replaceAll(
          '\u06ed',
          '\u06e2',
        ) // Fix floating Iqlab meem in UthmanicHafs font
        .replaceAll('هَٰٓ', 'هَـٰٓ') // Fix floating dagger alif on Haa ulaa
        .replaceAll('قَىٰ', 'قَـىٰ'); // Fix floating dagger alif on alqa

    if (stripAnnotationMarks) {
      normalized = _stripTajweedAnnotationMarks(normalized);
    }

    return normalized;
  }

  String _stripTajweedAnnotationMarks(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final isQuranicAnnotation =
          (rune >= 0x0610 && rune <= 0x061A) ||
          (rune >= 0x06D6 && rune <= 0x06ED);
      final isDotLikeCombiningMark =
          rune == 0x0653 || rune == 0x0656 || rune == 0x0657 || rune == 0x065F;
      final isTatweelCarrier = rune == 0x0640;
      if (isQuranicAnnotation || isDotLikeCombiningMark || isTatweelCarrier) {
        continue;
      }
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  bool _shouldDropTajweedPart(MushafTajweedPart part) {
    if (part.text.trim().isEmpty) return true;
    var hasBaseGlyph = false;
    for (final rune in part.text.runes) {
      final isArabicLetter =
          (rune >= 0x0620 && rune <= 0x064A) ||
          (rune >= 0x066E && rune <= 0x06D3) ||
          rune == 0x06FA ||
          rune == 0x06FB ||
          rune == 0x06FC ||
          rune == 0x06FF;
      final isArabicIndicDigit =
          (rune >= 0x0660 && rune <= 0x0669) ||
          (rune >= 0x06F0 && rune <= 0x06F9);
      if (isArabicLetter || isArabicIndicDigit) {
        hasBaseGlyph = true;
        break;
      }
    }
    return !hasBaseGlyph;
  }

  String _wordText(Map<String, dynamic> map, int mushafId) {
    final text = () {
      if (mushafId == 1) {
        return _stringValue(map, [
          'code_v2',
          'code',
          'text_qpc_hafs',
          'text_uthmani',
          'text',
        ]);
      } else if (mushafId == 2) {
        return _stringValue(map, [
          'code_v1',
          'code',
          'code_v2',
          'text_qpc_hafs',
          'text_uthmani',
          'text',
        ]);
      } else if (mushafId == 11 || mushafId == 19) {
        if (mushafId == 19) {
          return _stringValue(map, [
            'code',
            'code_v2',
            'code_v1',
            'text_qpc_hafs',
            'text_uthmani',
            'text',
          ]);
        }
        return _stringValue(map, [
          'text_uthmani',
          'text',
          'code_v2',
          'code_v1',
        ]);
      } else if (mushafId == 6 || mushafId == 7) {
        return _stringValue(map, ['text', 'text_indopak', 'text_uthmani']);
      } else if (mushafId == 3) {
        return _stringValue(map, ['text_indopak', 'text_uthmani', 'text']);
      } else {
        return _stringValue(map, ['text_qpc_hafs', 'text_uthmani', 'text']);
      }
    }();

    return _normalizeUthmaniGlyphs(text);
  }

  void _debugTajweedText(int mushafId, String verseKey, String html) {
    final visible = _decodeHtmlEntities(
      html.replaceAll(RegExp(r'<[^>]*>'), ' '),
    );
    final suspicious = visible.runes.where((rune) {
      return (rune >= 0x0610 && rune <= 0x061A) ||
          (rune >= 0x06D6 && rune <= 0x06ED) ||
          rune == 0x0670 ||
          rune == 0x0640 ||
          rune == 0x25CF ||
          rune == 0x2022;
    }).toSet();
    if (suspicious.isEmpty &&
        !html.contains('.png') &&
        !html.contains('<img')) {
      return;
    }
    final codePoints = suspicious
        .map(
          (rune) => 'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}',
        )
        .join(', ');
    debugPrint(
      'Mushaf $mushafId tajweed inspect $verseKey: $codePoints '
      'raw="${html.length > 220 ? '${html.substring(0, 220)}...' : html}"',
    );
  }

  void _debugCleanTajweedParts(
    int mushafId,
    String verseKey,
    String fallbackWordText,
    List<MushafTajweedPart> parts,
  ) {
    if (verseKey != '1:7') return;
    final partsSummary = parts.isEmpty
        ? 'no tajweed parts'
        : parts
              .map((part) {
                final className = part.className.isEmpty
                    ? 'plain'
                    : part.className;
                return '$className="${part.text}" [${_debugCodePoints(part.text)}]';
              })
              .join(' | ');
    debugPrint(
      'TAJWEED CLEAN mushaf=$mushafId 1:7 fallback="$fallbackWordText" '
      'fallbackCodePoints=[${_debugCodePoints(fallbackWordText)}] '
      'parts=$partsSummary',
    );
  }

  String _debugCodePoints(String text) {
    if (text.isEmpty) return 'empty';
    return text.runes
        .map(
          (rune) => 'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}',
        )
        .join(' ');
  }

  String _stringValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return '';
  }

  int? _intValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool _isArabicCombiningMark(int rune) {
    return (rune >= 0x0610 && rune <= 0x061A) ||
        (rune >= 0x064B && rune <= 0x065F) ||
        rune == 0x0670 ||
        (rune >= 0x06D6 && rune <= 0x06DC) ||
        (rune >= 0x06DF && rune <= 0x06E4) ||
        (rune >= 0x06E7 && rune <= 0x06E8) ||
        (rune >= 0x06EA && rune <= 0x06ED);
  }

  List<MushafTajweedPart> _adjustWordTajweedParts(
    List<MushafTajweedPart> parts,
  ) {
    final adjusted = <MushafTajweedPart>[];
    for (final part in parts) {
      adjusted.add(
        MushafTajweedPart(text: part.text, className: part.className),
      );
    }

    for (int i = 1; i < adjusted.length; i++) {
      final current = adjusted[i];
      final currentRunes = current.text.runes.toList();
      if (currentRunes.isEmpty) continue;

      // Check if current part contains only combining marks
      bool onlyCombining = true;
      for (final rune in currentRunes) {
        if (!_isArabicCombiningMark(rune)) {
          onlyCombining = false;
          break;
        }
      }

      if (onlyCombining) {
        // Find a preceding part that has a base character
        int prevIdx = i - 1;
        while (prevIdx >= 0 &&
            adjusted[prevIdx].text.runes.every(_isArabicCombiningMark)) {
          prevIdx--;
        }

        if (prevIdx >= 0) {
          final prevPart = adjusted[prevIdx];
          final prevRunes = prevPart.text.runes.toList();

          // Scan from the end of prevRunes to find the last base character
          int lastBaseIdx = -1;
          for (int r = prevRunes.length - 1; r >= 0; r--) {
            if (!_isArabicCombiningMark(prevRunes[r])) {
              lastBaseIdx = r;
              break;
            }
          }

          if (lastBaseIdx >= 0) {
            // Extract the suffix starting from the last base character
            final prefixRunes = prevRunes.sublist(0, lastBaseIdx);
            final suffixRunes = prevRunes.sublist(lastBaseIdx);

            adjusted[prevIdx] = MushafTajweedPart(
              text: String.fromCharCodes(prefixRunes),
              className: prevPart.className,
            );
            adjusted[i] = MushafTajweedPart(
              text: String.fromCharCodes(suffixRunes) + current.text,
              className: current.className,
            );
          }
        }
      }
    }

    // Filter out empty parts
    return adjusted.where((p) => p.text.isNotEmpty).toList();
  }
}

int _clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

class DynamicFontLoader {
  static final Set<String> _loadedFonts = {};

  static Future<void> loadFont({
    required String fontFamily,
    required String url,
  }) async {
    if (_loadedFonts.contains(fontFamily)) return;

    try {
      // Try to load QCF V1 font from local assets first
      if (fontFamily.startsWith('qcf_v1_p')) {
        final pageNum = fontFamily.substring(8);
        final assetPath = 'assets/qcf_v1_fonts/p$pageNum.ttf';
        try {
          final fontData = await rootBundle.load(assetPath);
          final fontLoader = FontLoader(fontFamily);
          fontLoader.addFont(Future.value(fontData));
          await fontLoader.load();
          _loadedFonts.add(fontFamily);
          return;
        } catch (e) {
          debugPrint('Failed to load local asset font for $fontFamily: $e');
        }
      }

      if (kIsWeb) {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final fontData = ByteData.view(response.bodyBytes.buffer);
          final fontLoader = FontLoader(fontFamily);
          fontLoader.addFont(Future.value(fontData));
          await fontLoader.load();
          _loadedFonts.add(fontFamily);
        } else {
          debugPrint(
            'Failed to load font $fontFamily from $url: ${response.statusCode}',
          );
        }
        return;
      }

      final supportDir = await getApplicationSupportDirectory();
      final fontsDir = Directory('${supportDir.path}/fonts');
      if (!await fontsDir.exists()) {
        await fontsDir.create(recursive: true);
      }

      final fileExtension = url.split('.').last.split('?').first;
      final localFile = File('${fontsDir.path}/$fontFamily.$fileExtension');

      ByteData fontData;
      if (await localFile.exists()) {
        final bytes = await localFile.readAsBytes();
        fontData = ByteData.view(bytes.buffer);
      } else {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;
          await localFile.writeAsBytes(bytes);
          fontData = ByteData.view(bytes.buffer);
        } else {
          debugPrint(
            'Failed to load font $fontFamily from $url: ${response.statusCode}',
          );
          return;
        }
      }

      final fontLoader = FontLoader(fontFamily);
      fontLoader.addFont(Future.value(fontData));
      await fontLoader.load();
      _loadedFonts.add(fontFamily);
    } catch (e) {
      debugPrint('Error loading font $fontFamily from $url: $e');
    }
  }
}
