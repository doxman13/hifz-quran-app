// lib/shared/translation_hierarchy.dart
//
// Structured 2-Level Translation Hierarchy (Language > Edition)
// Synchronized with thai-quran-web translation architecture.

import 'package:flutter/material.dart';
import 'translation_constants.dart';

class TranslationEdition {
  final String id;
  final int? apiId;
  final String languageId;
  final int versionNumber;
  final String versionBadge;
  final String titleTh;
  final String titleEn;
  final String subtitleTh;
  final String subtitleEn;
  final String authorTh;
  final String authorEn;
  final String? tagTh;
  final String? tagEn;
  final bool isRecommended;
  final bool isBundled;
  final bool isDownloadable;

  const TranslationEdition({
    required this.id,
    this.apiId,
    required this.languageId,
    required this.versionNumber,
    this.versionBadge = 'v1',
    required this.titleTh,
    required this.titleEn,
    required this.subtitleTh,
    required this.subtitleEn,
    required this.authorTh,
    required this.authorEn,
    this.tagTh,
    this.tagEn,
    this.isRecommended = false,
    this.isBundled = false,
    this.isDownloadable = false,
  });

  String title(String languageCode) => languageCode == 'th' ? titleTh : titleEn;
  String subtitle(String languageCode) => languageCode == 'th' ? subtitleTh : subtitleEn;
  String? tag(String languageCode) => languageCode == 'th' ? tagTh : tagEn;
}

class TranslationLanguageGroup {
  final String id;
  final String code;
  final String nameTh;
  final String nameEn;
  final IconData icon;
  final String defaultEditionId;
  final List<TranslationEdition> editions;

  const TranslationLanguageGroup({
    required this.id,
    required this.code,
    required this.nameTh,
    required this.nameEn,
    required this.icon,
    required this.defaultEditionId,
    required this.editions,
  });

  String name(String languageCode) => languageCode == 'th' ? nameTh : nameEn;
}

class TranslationHierarchy {
  // ==========================================
  // STATIC EDITIONS (MATCHING THAI-QURAN-WEB)
  // ==========================================
  static const List<TranslationEdition> staticEditions = [
    // --- THAI (Single Standard Edition) ---
    TranslationEdition(
      id: 'thai_v3',
      languageId: 'thai',
      versionNumber: 1,
      versionBadge: 'v1',
      titleTh: 'ฉบับสมาคมนักเรียนเก่าอาหรับฯ (ปรับปรุงภาษา)',
      titleEn: 'Arab Alumni Association (Revised Edition)',
      subtitleTh: 'ศูนย์กษัตริย์ฟะฮัดเพื่อการพิมพ์อัลกุรอาน · ฉบับทางการในเครื่อง',
      subtitleEn: 'King Fahd Complex / Arab Alumni Association (Official Built-in)',
      authorTh: 'สมาคมนักเรียนเก่าอาหรับในประเทศไทยฯ',
      authorEn: 'Arab Alumni Association in Thailand',
      tagTh: 'ฉบับมาตรฐานในเครื่อง',
      tagEn: 'Standard Built-in',
      isRecommended: true,
      isBundled: true,
    ),

    // --- ENGLISH EDITIONS ---
    TranslationEdition(
      id: '20',
      apiId: 20,
      languageId: 'english',
      versionNumber: 1,
      versionBadge: 'v1',
      titleTh: 'Saheeh International',
      titleEn: 'Saheeh International',
      subtitleTh: 'สำนวนร่วมสมัย ชัดเจน นิยมใช้ทั่วโลก',
      subtitleEn: 'Clear, contemporary standard English translation',
      authorTh: 'Saheeh International',
      authorEn: 'Saheeh International',
      tagTh: 'แนะนำ',
      tagEn: 'Recommended',
      isRecommended: true,
      isDownloadable: true,
    ),
    TranslationEdition(
      id: '203',
      apiId: 203,
      languageId: 'english',
      versionNumber: 2,
      versionBadge: 'v2',
      titleTh: 'Al-Hilali & Muhsin Khan',
      titleEn: 'Al-Hilali & Muhsin Khan',
      subtitleTh: 'King Fahd Complex พร้อมคำอธิบายตัฟซีร',
      subtitleEn: 'King Fahd Complex with commentary & cross references',
      authorTh: 'Dr. Al-Hilali & Dr. Muhsin Khan',
      authorEn: 'Dr. Al-Hilali & Dr. Muhsin Khan',
      tagTh: 'King Fahd',
      tagEn: 'King Fahd',
      isDownloadable: true,
    ),
    TranslationEdition(
      id: '149',
      apiId: 149,
      languageId: 'english',
      versionNumber: 3,
      versionBadge: 'v3',
      titleTh: "Bridges' Translation (10 Qira'at)",
      titleEn: "Bridges' Translation (10 Qira'at)",
      subtitleTh: 'แปลโดย Fadel Soliman แสดงความแตกต่างของ 10 กิรออะฮฺ',
      subtitleEn: 'By Fadel Soliman, indicates variations in the 10 Qiraat',
      authorTh: 'Fadel Soliman',
      authorEn: 'Fadel Soliman',
      tagTh: "10 Qira'at",
      tagEn: "10 Qira'at",
      isDownloadable: true,
    ),
    TranslationEdition(
      id: '85',
      apiId: 85,
      languageId: 'english',
      versionNumber: 4,
      versionBadge: 'v4',
      titleTh: 'M.A.S. Abdel Haleem',
      titleEn: 'M.A.S. Abdel Haleem',
      subtitleTh: 'Oxford World’s Classics ภาษาอังกฤษวรรณกรรมร่วมสมัย',
      subtitleEn: 'Oxford World’s Classics, modern literary style',
      authorTh: 'Prof. M.A.S. Abdel Haleem',
      authorEn: 'Prof. M.A.S. Abdel Haleem',
      tagTh: 'Oxford',
      tagEn: 'Oxford',
      isDownloadable: true,
    ),
    TranslationEdition(
      id: 'en_usmani',
      apiId: 84,
      languageId: 'english',
      versionNumber: 5,
      versionBadge: 'v5',
      titleTh: 'Mufti Taqi Usmani',
      titleEn: 'Mufti Taqi Usmani',
      subtitleTh: 'The Meanings of the Noble Quran สำนวนวิชาการสละสลวย',
      subtitleEn: 'The Meanings of the Noble Quran with brief scholarly notes',
      authorTh: 'Justice Mufti Muhammad Taqi Usmani',
      authorEn: 'Justice Mufti Muhammad Taqi Usmani',
      tagTh: 'ฉบับออฟไลน์ · วิชาการ',
      tagEn: 'Offline Built-in · Academic',
      isBundled: true,
    ),

    // --- MALAY EDITIONS ---
    TranslationEdition(
      id: 'ms_basmeih',
      apiId: 39,
      languageId: 'malay',
      versionNumber: 1,
      versionBadge: 'v1',
      titleTh: 'Abdullah Muhammad Basmeih',
      titleEn: 'Abdullah Muhammad Basmeih',
      subtitleTh: 'Tafsir Pimpinan Ar-Rahman (ฉบับทางการมาเลเซีย)',
      subtitleEn: 'Tafsir Pimpinan Ar-Rahman Kepada Pengertian Al-Quran',
      authorTh: 'Syeikh Abdullah Muhammad Basmeih',
      authorEn: 'Sheikh Abdullah Muhammad Basmeih',
      tagTh: 'แนะนำ · ทางการ',
      tagEn: 'Recommended · Official',
      isRecommended: true,
      isBundled: true,
    ),
  ];

  static const List<TranslationLanguageGroup> staticLanguageGroups = [
    TranslationLanguageGroup(
      id: 'thai',
      code: 'th',
      nameTh: 'ภาษาไทย',
      nameEn: 'Thai',
      icon: Icons.menu_book_rounded,
      defaultEditionId: 'thai_v3',
      editions: [],
    ),
    TranslationLanguageGroup(
      id: 'english',
      code: 'en',
      nameTh: 'English',
      nameEn: 'English',
      icon: Icons.language_rounded,
      defaultEditionId: '20',
      editions: [],
    ),
    TranslationLanguageGroup(
      id: 'malay',
      code: 'ms',
      nameTh: 'Bahasa Melayu',
      nameEn: 'Malay',
      icon: Icons.translate_rounded,
      defaultEditionId: 'ms_basmeih',
      editions: [],
    ),
  ];

  /// Normalizes any translation ID to its canonical language ID.
  static String getLanguageForTranslationId(String? rawId) {
    if (rawId == null || rawId.isEmpty || rawId == 'none') return 'thai';
    final clean = TranslationConstants.resolveTranslationId(rawId).trim().toLowerCase();

    // Check static editions first
    for (final e in staticEditions) {
      if (e.id == clean || (e.apiId != null && e.apiId.toString() == clean)) {
        return e.languageId;
      }
    }

    // Heuristics
    if (clean.startsWith('thai') || clean == 'th' || clean == '230' || clean == '51') {
      return 'thai';
    }
    if (clean.startsWith('en') || ['20', '203', '149', '85', '84'].contains(clean)) {
      return 'english';
    }
    if (clean.startsWith('ms') || clean == '39' || clean.contains('malay') || clean.contains('melayu')) {
      return 'malay';
    }

    return 'other';
  }

  /// Retrieves edition info for a given translation ID.
  static TranslationEdition? getEditionInfo(
    String? rawId, {
    List<Map<String, dynamic>>? downloadedTranslations,
  }) {
    if (rawId == null || rawId.isEmpty || rawId == 'none') return null;
    final clean = TranslationConstants.resolveTranslationId(rawId).trim().toLowerCase();

    // Search static editions
    for (final e in staticEditions) {
      if (e.id == clean || (e.apiId != null && e.apiId.toString() == clean)) {
        return e;
      }
    }

    // Dynamic search in downloaded translations
    if (downloadedTranslations != null) {
      for (final item in downloadedTranslations) {
        final id = item['id'].toString();
        if (id == clean || id == rawId) {
          final name = item['name']?.toString() ?? 'Downloaded Translation';
          final author = item['author_name']?.toString() ?? '';
          final lang = item['language_name']?.toString() ?? 'other';
          return TranslationEdition(
            id: id,
            apiId: int.tryParse(id),
            languageId: getLanguageForTranslationId(lang),
            versionNumber: 99,
            titleTh: name,
            titleEn: name,
            subtitleTh: author,
            subtitleEn: author,
            authorTh: author,
            authorEn: author,
            tagTh: 'ดาวน์โหลดแล้ว',
            tagEn: 'Downloaded',
            isDownloadable: true,
          );
        }
      }
    }

    // Fallback from known option
    final known = TranslationConstants.getKnownOption(rawId);
    if (known != null) {
      return TranslationEdition(
        id: known.id,
        apiId: known.apiId,
        languageId: getLanguageForTranslationId(known.language),
        versionNumber: 99,
        titleTh: known.nameTh ?? known.name,
        titleEn: known.name,
        subtitleTh: known.author,
        subtitleEn: known.author,
        authorTh: known.author,
        authorEn: known.author,
        isDownloadable: !known.isBuiltIn,
        isBundled: known.isBuiltIn,
      );
    }

    return null;
  }

  /// Builds populated language groups for the 2-level UI selector.
  static List<TranslationLanguageGroup> getAllLanguageGroups({
    List<Map<String, dynamic>>? downloadedTranslations,
  }) {
    final allEditions = List<TranslationEdition>.from(staticEditions);

    // If there are downloaded translations in other languages, add them
    if (downloadedTranslations != null) {
      for (final item in downloadedTranslations) {
        final id = item['id'].toString();
        final alreadyInStatic = allEditions.any(
          (e) => e.id == id || (e.apiId != null && e.apiId.toString() == id),
        );
        if (!alreadyInStatic) {
          final lang = item['language_name']?.toString() ?? 'other';
          final langId = getLanguageForTranslationId(lang);
          // Streamline: Never add extra Thai editions beyond official thai_v3
          if (langId != 'thai') {
            final name = item['name']?.toString() ?? 'Downloaded Translation';
            final author = item['author_name']?.toString() ?? '';
            allEditions.add(
              TranslationEdition(
                id: id,
                apiId: int.tryParse(id),
                languageId: langId,
                versionNumber: 99,
                titleTh: name,
                titleEn: name,
                subtitleTh: author,
                subtitleEn: author,
                authorTh: author,
                authorEn: author,
                tagTh: 'ดาวน์โหลดแล้ว',
                tagEn: 'Downloaded',
                isDownloadable: true,
              ),
            );
          }
        }
      }
    }

    // Build language groups
    final groups = <TranslationLanguageGroup>[];
    for (final base in staticLanguageGroups) {
      final inGroup = allEditions.where((e) => e.languageId == base.id).toList();
      inGroup.sort((a, b) => a.versionNumber.compareTo(b.versionNumber));
      groups.add(
        TranslationLanguageGroup(
          id: base.id,
          code: base.code,
          nameTh: base.nameTh,
          nameEn: base.nameEn,
          icon: base.icon,
          defaultEditionId: base.defaultEditionId,
          editions: inGroup,
        ),
      );
    }

    // Check for other languages
    final others = allEditions.where(
      (e) => !staticLanguageGroups.any((g) => g.id == e.languageId),
    ).toList();
    if (others.isNotEmpty) {
      groups.add(
        TranslationLanguageGroup(
          id: 'other',
          code: 'other',
          nameTh: 'ภาษาอื่นๆ ที่ดาวน์โหลด',
          nameEn: 'Other Downloaded',
          icon: Icons.public_rounded,
          defaultEditionId: others.first.id,
          editions: others,
        ),
      );
    }

    return groups.where((g) => g.editions.isNotEmpty).toList();
  }
}
