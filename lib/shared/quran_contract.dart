const defaultReadingProfileSlugs = ['free_read', 'random_read'];
const maxActiveReadingProfiles = 5;
const defaultBookmarkCategoryMaxItems = 9999;
const defaultRecentReadingsLimit = 30;
const translationVersions = ['thai_v3', 'thai_v2', 'english'];
const tafsirKeys = ['thai_mokhtasar'];
const readingProfilePlanModes = ['by_juz', 'by_surah', 'by_ayat', 'custom'];
const reportIssueTypes = [
  'typo',
  'meaning',
  'missing_text',
  'formatting',
  'other',
];
const reportStatuses = ['open', 'reviewing', 'accepted', 'rejected', 'fixed'];
const tadabburVisibilities = ['private', 'public'];
const tadabburStatuses = ['active', 'hidden', 'reported', 'removed'];
const shareOptions = [
  'translation_only',
  'arabic_and_translation',
  'translation_with_quick_note',
  'arabic_translation_with_quick_note',
];

class VerseRef {
  final String surahId;
  final String verseId;
  final String verseKey;

  const VerseRef({
    required this.surahId,
    required this.verseId,
    required this.verseKey,
  });
}

class TranslationRow extends VerseRef {
  final String version;
  final String language;
  final String text;
  final String? source;
  final DateTime? updatedAt;

  const TranslationRow({
    required super.surahId,
    required super.verseId,
    required super.verseKey,
    required this.version,
    required this.language,
    required this.text,
    this.source,
    this.updatedAt,
  });
}

class VerseTafsirRow extends VerseRef {
  final String tafsirKey;
  final String language;
  final String text;
  final String source;
  final String? sourceUrl;
  final DateTime? updatedAt;

  const VerseTafsirRow({
    required super.surahId,
    required super.verseId,
    required super.verseKey,
    required this.tafsirKey,
    required this.language,
    required this.text,
    required this.source,
    this.sourceUrl,
    this.updatedAt,
  });

  Map<String, dynamic> toDbRow() {
    return {
      'surah_id': surahId,
      'verse_id': verseId,
      'tafsir_key': tafsirKey,
      'language': language,
      'text': text,
      'source': source,
      if (sourceUrl != null) 'source_url': sourceUrl,
    };
  }
}

class SurahSummaryRow {
  final String id;
  final String surahId;
  final String language;
  final String? title;
  final String summaryText;
  final String source;
  final String? sourceUrl;
  final DateTime? updatedAt;

  const SurahSummaryRow({
    required this.id,
    required this.surahId,
    required this.language,
    this.title,
    required this.summaryText,
    required this.source,
    this.sourceUrl,
    this.updatedAt,
  });

  Map<String, dynamic> toDbRow() {
    return {
      'surah_id': surahId,
      'language': language,
      if (title != null) 'title': title,
      'summary_text': summaryText,
      'source': source,
      if (sourceUrl != null) 'source_url': sourceUrl,
    };
  }
}

class ReadingProfileInput {
  final String userId;
  final String name;
  final String slug;
  final String? planMode;
  final int? startJuz;
  final int? targetJuz;
  final VerseRef start;
  final VerseRef? target;
  final VerseRef current;
  final int? furthestUnreadIndex;
  final int? lastViewedIndex;
  final int? sortOrder;

  const ReadingProfileInput({
    required this.userId,
    required this.name,
    required this.slug,
    this.planMode,
    this.startJuz,
    this.targetJuz,
    required this.start,
    this.target,
    required this.current,
    this.furthestUnreadIndex,
    this.lastViewedIndex,
    this.sortOrder,
  });

  Map<String, dynamic> toDbRow() {
    return {
      'user_id': userId,
      'name': name,
      'slug': slug,
      if (planMode != null) 'plan_mode': planMode,
      if (startJuz != null) 'start_juz': startJuz,
      if (targetJuz != null) 'target_juz': targetJuz,
      'start_surah_id': start.surahId,
      'start_verse_id': start.verseId,
      if (target != null) 'target_surah_id': target!.surahId,
      if (target != null) 'target_verse_id': target!.verseId,
      'current_surah_id': current.surahId,
      'current_verse_id': current.verseId,
      if (furthestUnreadIndex != null)
        'furthest_unread_index': furthestUnreadIndex,
      if (lastViewedIndex != null) 'last_viewed_index': lastViewedIndex,
      if (sortOrder != null) 'sort_order': sortOrder,
    };
  }
}

class ReadingProfileRow extends ReadingProfileInput {
  final String id;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const ReadingProfileRow({
    required this.id,
    required this.isArchived,
    required this.createdAt,
    required super.userId,
    required super.name,
    required super.slug,
    super.planMode,
    super.startJuz,
    super.targetJuz,
    required super.start,
    super.target,
    required super.current,
    super.sortOrder,
    this.updatedAt,
  });
}

class BookmarkCategoryInput {
  final String userId;
  final String name;
  final String slug;
  final int? maxItems;
  final int? sortOrder;

  const BookmarkCategoryInput({
    required this.userId,
    required this.name,
    required this.slug,
    this.maxItems,
    this.sortOrder,
  });

  Map<String, dynamic> toDbRow() {
    return {
      'user_id': userId,
      'name': name,
      'slug': slug,
      'max_items': maxItems ?? defaultBookmarkCategoryMaxItems,
      if (sortOrder != null) 'sort_order': sortOrder,
    };
  }
}

class BookmarkInput extends VerseRef {
  final String userId;
  final String categoryId;
  final String? label;
  final String? note;
  final int? sortOrder;

  const BookmarkInput({
    required this.userId,
    required this.categoryId,
    required super.surahId,
    required super.verseId,
    required super.verseKey,
    this.label,
    this.note,
    this.sortOrder,
  });

  Map<String, dynamic> toDbRow() {
    return {
      'user_id': userId,
      'category_id': categoryId,
      'surah_id': surahId,
      'verse_id': verseId,
      if (label != null) 'label': label,
      if (note != null) 'note': note,
      if (sortOrder != null) 'sort_order': sortOrder,
    };
  }
}

class RecentReadingInput extends VerseRef {
  final String userId;
  final String? profileId;
  final DateTime? updatedAt;

  const RecentReadingInput({
    required this.userId,
    required super.surahId,
    required super.verseId,
    required super.verseKey,
    this.profileId,
    this.updatedAt,
  });

  Map<String, dynamic> toDbRow() {
    return {
      'user_id': userId,
      'surah_id': surahId,
      'verse_id': verseId,
      if (profileId != null) 'profile_id': profileId,
      if (updatedAt != null) 'read_at': updatedAt!.toIso8601String(),
    };
  }
}

class ReadingHistoryRow extends VerseRef {
  final String userId;
  final String readDate;
  final DateTime? createdAt;

  const ReadingHistoryRow({
    required this.userId,
    required this.readDate,
    required super.surahId,
    required super.verseId,
    required super.verseKey,
    this.createdAt,
  });
}

class CompletedSurahRow {
  final String userId;
  final String mode;
  final String surahId;
  final DateTime? completedAt;

  const CompletedSurahRow({
    required this.userId,
    required this.mode,
    required this.surahId,
    this.completedAt,
  });
}

class UserSettingsRow {
  final String userId;
  final String themeColor;
  final bool isDarkMode;
  final bool alwaysShowArabic;
  final String arabicFontFamily;
  final double arabicFontSize;
  final String thaiFontFamily;
  final double thaiFontSize;
  final bool showThaiV3;
  final bool showThaiV2;
  final bool showEnglish;
  final DateTime? updatedAt;

  const UserSettingsRow({
    required this.userId,
    required this.themeColor,
    required this.isDarkMode,
    required this.alwaysShowArabic,
    required this.arabicFontFamily,
    required this.arabicFontSize,
    required this.thaiFontFamily,
    required this.thaiFontSize,
    required this.showThaiV3,
    required this.showThaiV2,
    required this.showEnglish,
    this.updatedAt,
  });
}

class TranslationReportInput extends VerseRef {
  final String? userId;
  final String translationVersion;
  final String issueType;
  final String comment;
  final String? suggestedText;
  final String source;

  const TranslationReportInput({
    this.userId,
    required super.surahId,
    required super.verseId,
    required super.verseKey,
    required this.translationVersion,
    required this.issueType,
    required this.comment,
    this.suggestedText,
    required this.source,
  });

  Map<String, dynamic> toDbRow() {
    return {
      if (userId != null) 'user_id': userId,
      'surah_id': surahId,
      'verse_id': verseId,
      'translation_version': translationVersion,
      'issue_type': issueType,
      'comment': comment,
      if (suggestedText != null) 'suggested_text': suggestedText,
      'source': source,
    };
  }
}

class TadabburNoteInput extends VerseRef {
  final String userId;
  final String noteText;
  final String visibility;
  final String language;

  const TadabburNoteInput({
    required this.userId,
    required super.surahId,
    required super.verseId,
    required super.verseKey,
    required this.noteText,
    required this.visibility,
    required this.language,
  });

  Map<String, dynamic> toDbRow() {
    return {
      'user_id': userId,
      'surah_id': surahId,
      'verse_id': verseId,
      'note_text': noteText,
      'visibility': visibility,
      'language': language,
    };
  }
}

class SharePayload extends VerseRef {
  final String surahName;
  final String? arabic;
  final String translation;
  final String translationVersion;
  final String? quickNote;
  final String url;

  const SharePayload({
    required super.surahId,
    required super.verseId,
    required super.verseKey,
    required this.surahName,
    this.arabic,
    required this.translation,
    required this.translationVersion,
    this.quickNote,
    required this.url,
  });
}

String createVerseKey(Object surahId, Object verseId) => '$surahId:$verseId';

VerseRef? parseVerseKey(String verseKey) {
  final parts = verseKey.split(':');
  if (parts.length != 2) return null;

  final surahId = parts[0];
  final verseId = parts[1];
  final numeric = RegExp(r'^\d+$');
  if (!numeric.hasMatch(surahId) || !numeric.hasMatch(verseId)) return null;

  return VerseRef(surahId: surahId, verseId: verseId, verseKey: verseKey);
}

VerseRef toVerseRef(Object surahId, Object verseId) {
  final normalizedSurahId = surahId.toString();
  final normalizedVerseId = verseId.toString();
  return VerseRef(
    surahId: normalizedSurahId,
    verseId: normalizedVerseId,
    verseKey: createVerseKey(normalizedSurahId, normalizedVerseId),
  );
}

String slugifyReadingProfileName(String name) {
  final slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9ก-๙]+', caseSensitive: false), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? 'reading_profile' : slug;
}

String? normalizeLegacyProfileSlug(String profile) {
  final normalized = profile.trim().toLowerCase().replaceAll(' ', '_');

  switch (normalized) {
    case 'main_read':
    case 'main_daily_read':
    case 'free_read':
      return 'free_read';
    case 'random_read':
    case 'special_read':
    case 'search':
    case 'read_from_bookmark':
      return 'random_read';
    case 'audit_check':
    case 'last_read':
      return null;
    default:
      return defaultReadingProfileSlugs.contains(normalized)
          ? normalized
          : null;
  }
}

String getTranslationLanguage(String version) =>
    version == 'english' ? 'en' : 'th';

bool canCreateActiveReadingProfile(int activeProfileCount) {
  return activeProfileCount < maxActiveReadingProfiles;
}

List<TranslationRow> normalizeThaiV3Translations(Map<String, dynamic> input) {
  final rows = <TranslationRow>[];

  for (final entry in input.entries) {
    final flatRef = parseVerseKey(entry.key);
    if (flatRef != null && entry.value is String) {
      rows.add(
        TranslationRow(
          surahId: flatRef.surahId,
          verseId: flatRef.verseId,
          verseKey: flatRef.verseKey,
          version: 'thai_v3',
          language: 'th',
          text: entry.value as String,
        ),
      );
      continue;
    }

    final value = entry.value;
    if (value is! Map || value['verses'] is! Map) continue;

    final verses = value['verses'] as Map;
    for (final verseEntry in verses.entries) {
      if (verseEntry.value is! String) continue;
      final verseRef = toVerseRef(entry.key, verseEntry.key);
      rows.add(
        TranslationRow(
          surahId: verseRef.surahId,
          verseId: verseRef.verseId,
          verseKey: verseRef.verseKey,
          version: 'thai_v3',
          language: 'th',
          text: verseEntry.value as String,
        ),
      );
    }
  }

  rows.sort(_compareVerseRows);
  return rows;
}

int _compareVerseRows(VerseRef a, VerseRef b) {
  final surahDiff = int.parse(a.surahId).compareTo(int.parse(b.surahId));
  if (surahDiff != 0) return surahDiff;
  return int.parse(a.verseId).compareTo(int.parse(b.verseId));
}
