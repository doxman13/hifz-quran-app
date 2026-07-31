const maxActiveMushafProfiles = 5;
const mushafStoreKey = 'thai_quran_mushaf_store_v1';
const mushafFreeReadSlug = 'mushaf_free_read';
const qcfPackageMushafId = 20;

class MushafType {
  final int id;
  final String name;
  final int pageCount;
  final String description;

  const MushafType({
    required this.id,
    required this.name,
    required this.pageCount,
    required this.description,
  });
}

const mushafTypes = [
  MushafType(
    id: 1,
    name: 'QCF V2',
    pageCount: 604,
    description: 'Medina Mushaf, Quran Complex Font V2',
  ),
  MushafType(
    id: 2,
    name: 'Mushaf Al Madinah (1405)',
    pageCount: 604,
    description: 'Medina Mushaf printed in 1405H',
  ),
  MushafType(
    id: 3,
    name: 'IndoPak',
    pageCount: 604,
    description: 'IndoPak script layout',
  ),
  MushafType(
    id: 4,
    name: 'Uthmani Hafs',
    pageCount: 604,
    description: 'Standard Uthmani Hafs layout',
  ),
  MushafType(
    id: 5,
    name: 'KFGQPC Hafs',
    pageCount: 604,
    description: 'King Fahd Complex Hafs layout',
  ),
  MushafType(
    id: 6,
    name: 'IndoPak',
    pageCount: 610,
    description: 'IndoPak 15-line Mushaf',
  ),
  MushafType(
    id: 7,
    name: 'IndoPak 16-line',
    pageCount: 548,
    description: 'IndoPak 16-line Mushaf',
  ),
  MushafType(
    id: 11,
    name: 'Tajweed',
    pageCount: 604,
    description: 'Color-coded Tajweed layout',
  ),
  MushafType(
    id: 19,
    name: 'Mushaf Al Madinah (1421H) Tajweed',
    pageCount: 604,
    description: 'Medina Tajweed Mushaf printed in 1421H',
  ),
  MushafType(
    id: qcfPackageMushafId,
    name: 'Mushaf Al Madinah (1421H)',
    pageCount: 604,
    description: 'Medina Mushaf printed in 1421H (Offline)',
  ),
];

const visibleMushafTypeIds = {2, 11, 19, qcfPackageMushafId};

List<MushafType> get visibleMushafTypes {
  return mushafTypes
      .where((type) => visibleMushafTypeIds.contains(type.id))
      .toList();
}

MushafType mushafTypeById(int id) {
  return mushafTypes.firstWhere(
    (type) => type.id == id,
    orElse: () => mushafTypes.first,
  );
}

const mushafSurahArabicNames = [
  '',
  'الفاتحة',
  'البقرة',
  'آل عمران',
  'النساء',
  'المائدة',
  'الأنعام',
  'الأعراف',
  'الأنفال',
  'التوبة',
  'يونس',
  'هود',
  'يوسف',
  'الرعد',
  'إبراهيم',
  'الحجر',
  'النحل',
  'الإسراء',
  'الكهف',
  'مريم',
  'طه',
  'الأنبياء',
  'الحج',
  'المؤمنون',
  'النور',
  'الفرقان',
  'الشعراء',
  'النمل',
  'القصص',
  'العنكبوت',
  'الروم',
  'لقمان',
  'السجدة',
  'الأحزاب',
  'سبأ',
  'فاطر',
  'يس',
  'الصافات',
  'ص',
  'الزمر',
  'غافر',
  'فصلت',
  'الشورى',
  'الزخرف',
  'الدخان',
  'الجاثية',
  'الأحقاف',
  'محمد',
  'الفتح',
  'الحجرات',
  'ق',
  'الذاريات',
  'الطور',
  'النجم',
  'القمر',
  'الرحمن',
  'الواقعة',
  'الحديد',
  'المجادلة',
  'الحشر',
  'الممتحنة',
  'الصف',
  'الجمعة',
  'المنافقون',
  'التغابن',
  'الطلاق',
  'التحريم',
  'الملك',
  'القلم',
  'الحاقة',
  'المعارج',
  'نوح',
  'الجن',
  'المزمل',
  'المدثر',
  'القيامة',
  'الإنسان',
  'المرسلات',
  'النبأ',
  'النازعات',
  'عبس',
  'التكوير',
  'الانفطار',
  'المطففين',
  'الانشقاق',
  'البروج',
  'الطارق',
  'الأعلى',
  'الغاشية',
  'الفجر',
  'البلد',
  'الشمس',
  'الليل',
  'الضحى',
  'الشرح',
  'التين',
  'العلق',
  'القدر',
  'البينة',
  'الزلزلة',
  'العاديات',
  'القارعة',
  'التكاثر',
  'العصر',
  'الهمزة',
  'الفيل',
  'قريش',
  'الماعون',
  'الكوثر',
  'الكافرون',
  'النصر',
  'المسد',
  'الإخلاص',
  'الفلق',
  'الناس',
];

String mushafSurahArabicName(String surahId) {
  final id = int.tryParse(surahId) ?? 0;
  if (id > 0 && id < mushafSurahArabicNames.length) {
    return mushafSurahArabicNames[id];
  }
  return surahId;
}

class MushafWord {
  final String text;
  final String verseKey;
  final int lineNumber;
  final int position;
  final String? textTajweed;
  final List<MushafTajweedPart> tajweedParts;

  const MushafWord({
    required this.text,
    required this.verseKey,
    required this.lineNumber,
    required this.position,
    this.textTajweed,
    this.tajweedParts = const [],
  });
}

class MushafTajweedPart {
  final String text;
  final String className;

  const MushafTajweedPart({required this.text, required this.className});
}

class MushafVerse {
  final String verseKey;
  final String surahId;
  final String verseId;
  final List<MushafWord> words;

  const MushafVerse({
    required this.verseKey,
    required this.surahId,
    required this.verseId,
    required this.words,
  });
}

class MushafPage {
  final int mushafId;
  final int pageNumber;
  final List<MushafVerse> verses;
  final List<List<MushafWord>> lines;

  const MushafPage({
    required this.mushafId,
    required this.pageNumber,
    required this.verses,
    required this.lines,
  });
}

class MushafPageRange {
  final int startPage;
  final int endPage;

  const MushafPageRange({required this.startPage, required this.endPage});
}

class MushafProfile {
  final String id;
  final String userId;
  final String name;
  final String slug;
  final int mushafId;
  final String planMode;
  final int startPage;
  final int targetPage;
  final int currentPage;
  final int lastViewedPage;
  final int sortOrder;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MushafProfile({
    required this.id,
    required this.userId,
    required this.name,
    required this.slug,
    required this.mushafId,
    required this.planMode,
    required this.startPage,
    required this.targetPage,
    required this.currentPage,
    int? lastViewedPage,
    required this.sortOrder,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  }) : lastViewedPage = lastViewedPage ?? currentPage;

  bool get isFreeRead => slug == mushafFreeReadSlug;
  bool get isComplete => !isFreeRead && currentPage >= targetPage;
  int get furthestUnreadPage => currentPage;

  MushafProfile copyWith({
    String? id,
    String? userId,
    String? name,
    String? slug,
    int? mushafId,
    String? planMode,
    int? startPage,
    int? targetPage,
    int? currentPage,
    int? lastViewedPage,
    bool? isArchived,
    DateTime? updatedAt,
  }) {
    return MushafProfile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      mushafId: mushafId ?? this.mushafId,
      planMode: planMode ?? this.planMode,
      startPage: startPage ?? this.startPage,
      targetPage: targetPage ?? this.targetPage,
      currentPage: currentPage ?? this.currentPage,
      lastViewedPage: lastViewedPage ?? this.lastViewedPage,
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
      'mushafId': mushafId,
      'planMode': planMode,
      'startPage': startPage,
      'targetPage': targetPage,
      'currentPage': currentPage,
      'furthestUnreadPage': furthestUnreadPage,
      'lastViewedPage': lastViewedPage,
      'sortOrder': sortOrder,
      'isArchived': isArchived,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory MushafProfile.fromJson(Map<String, dynamic> json) {
    final mushafId = int.tryParse(json['mushafId']?.toString() ?? '') ?? 1;
    final pageCount = mushafTypeById(mushafId).pageCount;
    final startPage = _clampInt(
      int.tryParse(json['startPage']?.toString() ?? '') ?? 1,
      1,
      pageCount,
    );
    final targetPage = _clampInt(
      int.tryParse(json['targetPage']?.toString() ?? '') ?? pageCount,
      1,
      pageCount,
    );
    final currentPage = _clampInt(
      int.tryParse(
            json['furthestUnreadPage']?.toString() ??
                json['currentPage']?.toString() ??
                '',
          ) ??
          startPage,
      startPage,
      targetPage,
    );
    final lastViewedPage = _clampInt(
      int.tryParse(json['lastViewedPage']?.toString() ?? '') ?? currentPage,
      startPage,
      targetPage,
    );

    return MushafProfile(
      id: json['id']?.toString() ?? 'mushaf-free-$mushafId',
      userId: json['userId']?.toString() ?? 'local',
      name: json['name']?.toString() ?? 'Just Read',
      slug: json['slug']?.toString() ?? mushafFreeReadSlug,
      mushafId: mushafId,
      planMode: json['planMode']?.toString() ?? 'free_read',
      startPage: startPage,
      targetPage: targetPage,
      currentPage: currentPage,
      lastViewedPage: lastViewedPage,
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

int _clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

class MushafPageBookmark {
  final String id;
  final int mushafId;
  final int pageNumber;
  final DateTime createdAt;

  const MushafPageBookmark({
    required this.id,
    required this.mushafId,
    required this.pageNumber,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mushafId': mushafId,
      'pageNumber': pageNumber,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MushafPageBookmark.fromJson(Map<String, dynamic> json) {
    return MushafPageBookmark(
      id: json['id']?.toString() ?? '',
      mushafId: int.tryParse(json['mushafId']?.toString() ?? '') ?? 1,
      pageNumber: int.tryParse(json['pageNumber']?.toString() ?? '') ?? 1,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class MushafVerseBookmark {
  final String id;
  final int mushafId;
  final int pageNumber;
  final String verseKey;
  final DateTime createdAt;

  const MushafVerseBookmark({
    required this.id,
    required this.mushafId,
    required this.pageNumber,
    required this.verseKey,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mushafId': mushafId,
      'pageNumber': pageNumber,
      'verseKey': verseKey,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MushafVerseBookmark.fromJson(Map<String, dynamic> json) {
    return MushafVerseBookmark(
      id: json['id']?.toString() ?? '',
      mushafId: int.tryParse(json['mushafId']?.toString() ?? '') ?? 1,
      pageNumber: int.tryParse(json['pageNumber']?.toString() ?? '') ?? 1,
      verseKey: json['verseKey']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class MushafRecentReading {
  final int mushafId;
  final int pageNumber;
  final String? profileId;
  final DateTime updatedAt;

  const MushafRecentReading({
    required this.mushafId,
    required this.pageNumber,
    this.profileId,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'mushafId': mushafId,
      'pageNumber': pageNumber,
      if (profileId != null) 'profileId': profileId,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory MushafRecentReading.fromJson(Map<String, dynamic> json) {
    return MushafRecentReading(
      mushafId: int.tryParse(json['mushafId']?.toString() ?? '') ?? 1,
      pageNumber: int.tryParse(json['pageNumber']?.toString() ?? '') ?? 1,
      profileId: json['profileId']?.toString(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
