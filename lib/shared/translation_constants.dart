
class AppTranslationOption {
  final String id;
  final int? apiId;
  final String name;
  final String? nameTh;
  final String author;
  final String language;
  final bool isBuiltIn;

  const AppTranslationOption({
    required this.id,
    this.apiId,
    required this.name,
    this.nameTh,
    required this.author,
    required this.language,
    this.isBuiltIn = false,
  });

  String displayName(String languageCode) {
    if (languageCode == 'th' && nameTh != null && nameTh!.isNotEmpty) {
      return nameTh!;
    }
    return name;
  }
}

class TranslationConstants {
  // Built-in offline translations located in quran_offline.db
  static const builtInThaiV3 = AppTranslationOption(
    id: 'thai_v3',
    apiId: null,
    name: 'King Fahd Complex (The Arab Alumni Association - Revised)',
    nameTh: 'ภาษาไทย (ฉบับสมาคมนักเรียนเก่าอาหรับ - ปรับปรุงภาษา / Revised)',
    author: 'King Fahd Complex / สมาคมนักเรียนเก่าอาหรับ',
    language: 'thai',
    isBuiltIn: true,
  );

  static const builtInEnUsmani = AppTranslationOption(
    id: 'en_usmani',
    apiId: null,
    name: 'Mufti Taqi Usmani (Offline)',
    nameTh: 'English - Mufti Taqi Usmani (อังกฤษ - ออฟไลน์)',
    author: 'Mufti Taqi Usmani',
    language: 'english',
    isBuiltIn: true,
  );

  static const builtInMsBasmeih = AppTranslationOption(
    id: 'ms_basmeih',
    apiId: 39,
    name: 'Abdullah Muhammad Basmeih (Offline)',
    nameTh: 'Bahasa Melayu - Basmeih (มลายู - ออฟไลน์)',
    author: 'Abdullah Muhammad Basmeih',
    language: 'malay',
    isBuiltIn: true,
  );

  static const List<AppTranslationOption> builtIns = [
    builtInThaiV3,
    builtInEnUsmani,
    builtInMsBasmeih,
  ];

  // Downloadable translations via Quran.com / QDC API
  static const List<AppTranslationOption> downloadableTranslations = [
    AppTranslationOption(
      id: '20',
      apiId: 20,
      name: 'Saheeh International',
      nameTh: 'English - Saheeh International (อังกฤษ - เชิงอรรถ)',
      author: 'Saheeh International',
      language: 'english',
    ),
    AppTranslationOption(
      id: '203',
      apiId: 203,
      name: 'Al-Hilali & Muhsin Khan (King Fahd Complex)',
      nameTh: 'English - Al-Hilali & Muhsin Khan (อังกฤษ - เชิงอรรถ)',
      author: 'Al-Hilali & Muhsin Khan',
      language: 'english',
    ),
    AppTranslationOption(
      id: '149',
      apiId: 149,
      name: "Bridges' Translation (Fadel Soliman - 10 Qira'at)",
      nameTh: "English - Bridges' Translation (อังกฤษ - 10 กิรออาต)",
      author: 'Fadel Soliman',
      language: 'english',
    ),
    AppTranslationOption(
      id: '85',
      apiId: 85,
      name: 'M.A.S. Abdel Haleem',
      nameTh: 'English - M.A.S. Abdel Haleem (อังกฤษ)',
      author: 'Abdul Haleem',
      language: 'english',
    ),
    AppTranslationOption(
      id: '230',
      apiId: 230,
      name: 'Society of Institutes and Universities (Original)',
      nameTh: 'ภาษาไทย (ฉบับสมาคมนักเรียนเก่าอาหรับ - ดั้งเดิม / Original)',
      author: 'Society of Institutes and Universities',
      language: 'thai',
    ),
    AppTranslationOption(
      id: '51',
      apiId: 51,
      name: 'Thai Translation (King Fahad Quran Complex)',
      nameTh: 'ภาษาไทย (ศูนย์กษัตริย์ฟะฮัดเพื่อการพิมพ์อัลกุรอาน)',
      author: 'King Fahad Quran Complex',
      language: 'thai',
    ),
  ];

  /// Language priority for sorting translations
  static int _languageSortOrder(String language) {
    switch (language.toLowerCase()) {
      case 'thai':
      case 'th':
        return 0;
      case 'english':
      case 'en':
        return 1;
      case 'malay':
      case 'ms':
        return 2;
      default:
        return 3;
    }
  }

  /// Consistent comparator across all app screens
  static int compareOptions(AppTranslationOption a, AppTranslationOption b) {
    if (a.id == builtInThaiV3.id && b.id != builtInThaiV3.id) return -1;
    if (b.id == builtInThaiV3.id && a.id != builtInThaiV3.id) return 1;

    final langA = _languageSortOrder(a.language);
    final langB = _languageSortOrder(b.language);
    if (langA != langB) return langA.compareTo(langB);

    if (a.isBuiltIn && !b.isBuiltIn) return -1;
    if (!a.isBuiltIn && b.isBuiltIn) return 1;

    return a.name.compareTo(b.name);
  }

  /// Unified source of truth for all translation options
  static List<AppTranslationOption> getAllOptions({List<dynamic>? downloadedTranslations}) {
    final map = <String, AppTranslationOption>{};
    for (final opt in builtIns) {
      map[opt.id] = opt;
    }
    for (final opt in downloadableTranslations) {
      map[opt.id] = opt;
    }
    if (downloadedTranslations != null) {
      for (final item in downloadedTranslations) {
        final id = item['id'].toString();
        if (!map.containsKey(id)) {
          map[id] = AppTranslationOption(
            id: id,
            apiId: int.tryParse(id),
            name: item['name']?.toString() ?? 'Downloaded translation',
            author: item['author_name']?.toString() ?? '',
            language: item['language_name']?.toString() ?? '',
          );
        }
      }
    }
    final list = map.values.toList();
    list.sort(compareOptions);
    return list;
  }

  /// Normalize any legacy string alias to its canonical ID.
  static String resolveTranslationId(dynamic id) {
    if (id == null) return 'thai_v3';
    final s = id.toString().trim().toLowerCase();
    switch (s) {
      case 'en_saheeh':
      case 'saheeh':
      case '20':
        return '20';
      case 'en_hilali_khan':
      case 'hilali':
      case '203':
        return '203';
      case 'en_bridges':
      case 'bridges':
      case '149':
        return '149';
      case 'abdel_haleem':
      case '85':
        return '85';
      case 'thai_orig':
      case '230':
        return '230';
      case '51':
        return '51';
      case 'thai_v2':
      case 'thai_v3':
      case 'th':
      case 'thai':
        return 'thai_v3';
      case 'en_usmani':
      case 'english':
      case 'en':
        return 'en_usmani';
      case 'ms_basmeih':
      case 'malay':
      case 'ms':
      case '39':
        return 'ms_basmeih';
      default:
        return id.toString();
    }
  }

  /// Resolve API numeric ID for downloadable translations.
  static int? resolveApiId(dynamic id) {
    if (id == null) return null;
    if (id is int) return id;
    final canonical = resolveTranslationId(id);
    return int.tryParse(canonical);
  }

  /// Check if an ID is built-in offline
  static bool isBuiltIn(dynamic id) {
    final canonical = resolveTranslationId(id);
    return canonical == 'thai_v3' || canonical == 'en_usmani' || canonical == 'ms_basmeih';
  }

  /// Get known translation option
  static AppTranslationOption? getKnownOption(dynamic id) {
    final canonical = resolveTranslationId(id);
    for (final opt in builtIns) {
      if (opt.id == canonical) return opt;
    }
    for (final opt in downloadableTranslations) {
      if (opt.id == canonical) return opt;
    }
    return null;
  }
}
