import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/translation_manager_provider.dart';
import '../services/background_download_service.dart';
import '../shared/shared.dart';
import '../theme/app_theme.dart';

class TranslationManagerSection extends StatefulWidget {
  final AppThemeColors colors;
  const TranslationManagerSection({super.key, required this.colors});

  @override
  State<TranslationManagerSection> createState() =>
      _TranslationManagerSectionState();
}

class _TranslationManagerSectionState extends State<TranslationManagerSection> {
  static final List<AppTranslationOption> _availableTranslations =
      TranslationConstants.downloadableTranslations
          .where((t) => t.language.toLowerCase() != 'thai' && t.id != '230' && t.id != '51')
          .toList();

  int? _activeDownloadingId;
  Map<int, double> get _downloadProgress =>
      context.read<TranslationManagerProvider>().downloadProgress;
  OverlayEntry? _progressOverlayEntry;
  ValueNotifier<double>? _activeProgressNotifier;

  @override
  void dispose() {
    _progressOverlayEntry?.remove();
    _progressOverlayEntry = null;
    _activeProgressNotifier?.dispose();
    _activeProgressNotifier = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transManager = context.watch<TranslationManagerProvider>();
    final settings = context.watch<SettingsProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    // Sync progress overlay if active
    if (_progressOverlayEntry != null && _activeProgressNotifier != null && _activeDownloadingId != null) {
      final progress = transManager.downloadProgress[_activeDownloadingId!];
      if (progress != null) {
        _activeProgressNotifier!.value = progress;
      } else {
        // Not in progress anymore. Check if it succeeded by looking at downloaded options
        final succeeded = transManager.downloadedTranslations.any((t) => t['id'] == _activeDownloadingId);
        if (succeeded) {
          _activeProgressNotifier!.value = 1.0;
        } else {
          // Failed or canceled, remove the overlay
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_progressOverlayEntry != null) {
              _progressOverlayEntry?.remove();
              _progressOverlayEntry = null;
              _activeProgressNotifier?.dispose();
              _activeProgressNotifier = null;
              _activeDownloadingId = null;
            }
          });
        }
      }
    }

    final downloadedOptions = _downloadedOptions(transManager);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(colorScheme, context.tr('active_translations')),
            _sectionTitle(
              colorScheme,
              settings.languageCode == 'th'
                  ? 'คำแปลอัลกุรอาน (ออฟไลน์ 100%)'
                  : 'Quran Translations (100% Offline)',
            ),
            const SizedBox(height: 4),
            Text(
              settings.languageCode == 'th'
                  ? 'เลือกคำแปลหลักและคำแปลรองสำหรับอ่านเปรียบเทียบ พร้อมใช้งานทันที'
                  : 'Select primary and secondary translations. Ready offline anytime.',
              style: GoogleFonts.notoSansThai(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // PRIMARY TRANSLATION SLOT
            _buildSlotCard(
              context: context,
              slot: 'primary',
              settings: settings,
              transManager: transManager,
              colorScheme: colorScheme,
              languageGroups: TranslationHierarchy.getAllLanguageGroups(
                downloadedTranslations: transManager.downloadedTranslations,
              ),
            ),

            const SizedBox(height: 16),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),

            // SECONDARY TRANSLATION SLOT
            _buildSlotCard(
              context: context,
              slot: 'secondary',
              settings: settings,
              transManager: transManager,
              colorScheme: colorScheme,
              languageGroups: TranslationHierarchy.getAllLanguageGroups(
                downloadedTranslations: transManager.downloadedTranslations,
              ),
            ),
            const SizedBox(height: 20),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            _sectionTitle(colorScheme, context.tr('download_more')),
            const SizedBox(height: 8),
            ..._groupedAvailableTranslations().entries.expand((entry) {
              return [
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 6),
                  child: Text(
                    _languageLabel(entry.key, settings.languageCode),
                    style: GoogleFonts.notoSansThai(
                      color: colorScheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ...entry.value.map((option) {
                  final isDownloaded = downloadedOptions.any(
                    (item) => item.id == option.id,
                  );
                  final progress = option.apiId == null
                      ? null
                      : _downloadProgress[option.apiId];

                  return _buildTranslationRow(
                    option: option,
                    settings: settings,
                    colorScheme: colorScheme,
                    isDownloaded: isDownloaded,
                    isDownloadList: true,
                    showSelector: false,
                    progress: progress,
                    onDownload: option.apiId == null || isDownloaded
                        ? null
                        : () => _downloadTranslation(option),
                    onDelete: isDownloaded
                        ? () => _deleteTranslation(
                            option.apiId!,
                            transManager,
                            settings,
                          )
                        : null,
                  );
                }),
              ];
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotCard({
    required BuildContext context,
    required String slot,
    required SettingsProvider settings,
    required TranslationManagerProvider transManager,
    required ColorScheme colorScheme,
    required List<TranslationLanguageGroup> languageGroups,
  }) {
    final isPrimary = slot == 'primary';
    final isThai = settings.languageCode == 'th';
    final currentSelectedId = isPrimary
        ? TranslationConstants.resolveTranslationId(settings.primaryTranslationId)
        : (settings.secondaryTranslationId != null
            ? TranslationConstants.resolveTranslationId(settings.secondaryTranslationId)
            : null);
    final otherSelectedId = isPrimary
        ? (settings.secondaryTranslationId != null
            ? TranslationConstants.resolveTranslationId(settings.secondaryTranslationId)
            : null)
        : TranslationConstants.resolveTranslationId(settings.primaryTranslationId);

    final isNoneSelected = !isPrimary &&
        (currentSelectedId == null ||
            currentSelectedId.isEmpty ||
            currentSelectedId == 'none');

    final currentLangId = isNoneSelected
        ? 'none'
        : TranslationHierarchy.getLanguageForTranslationId(currentSelectedId);

    final activeGroup = isNoneSelected
        ? null
        : languageGroups.firstWhere(
            (g) => g.id == currentLangId,
            orElse: () => languageGroups.first,
          );

    final activeEdition = isNoneSelected
        ? null
        : TranslationHierarchy.getEditionInfo(
            currentSelectedId,
            downloadedTranslations: transManager.downloadedTranslations,
          );

    final slotNumber = isPrimary ? '1' : '2';
    final slotBadgeBg = isPrimary ? colorScheme.primary : colorScheme.tertiary;
    final slotBadgeFg = isPrimary ? colorScheme.onPrimary : colorScheme.onTertiary;
    final statusBg = isPrimary
        ? colorScheme.primaryContainer
        : (!isNoneSelected
            ? colorScheme.tertiaryContainer
            : colorScheme.surfaceContainerHigh);
    final statusFg = isPrimary
        ? colorScheme.onPrimaryContainer
        : (!isNoneSelected
            ? colorScheme.onTertiaryContainer
            : colorScheme.onSurfaceVariant);
    final statusText = isPrimary
        ? (isThai ? 'เปิดใช้งาน' : 'Active')
        : (!isNoneSelected
            ? (isThai ? 'เปิดใช้งาน' : 'Active')
            : (isThai ? 'ปิดอยู่' : 'Disabled'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Slot Header Row
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: slotBadgeBg,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                slotNumber,
                style: GoogleFonts.notoSansThai(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: slotBadgeFg,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPrimary
                        ? (isThai ? 'คำแปลหลัก (Primary Translation)' : 'Primary Translation')
                        : (isThai ? 'คำแปลรอง (Secondary Translation)' : 'Secondary Translation'),
                    style: GoogleFonts.notoSansThai(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isPrimary
                        ? (isThai ? 'แสดงข้อความหลักใต้ภาษาอาหรับ' : 'Displayed directly below Arabic verses')
                        : (isThai ? 'สำหรับอ่านเทียบสองภาษาพร้อมกัน (ตัวเลือกเสริม)' : 'For bilingual reading side-by-side (Optional)'),
                    style: GoogleFonts.notoSansThai(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusText,
                style: GoogleFonts.notoSansThai(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: statusFg,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // LEVEL 1: LANGUAGE SELECTION
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.language_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  isPrimary
                      ? (isThai ? 'ภาษาคำแปลหลัก' : 'Primary Language')
                      : (isThai ? 'ภาษาคำแปลรอง' : 'Secondary Language'),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (!isPrimary && !isNoneSelected)
              InkWell(
                onTap: () {
                  settings.updateTranslationSlot('secondary', null);
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    isThai ? 'ปิดคำแปลรอง' : 'Disable',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),

        // Level 1 Dropdown
        DropdownButtonFormField<String>(
          initialValue: isNoneSelected ? 'none' : currentLangId,
          dropdownColor: colorScheme.surfaceContainerLow,
          isExpanded: true,
          decoration: _inputDecoration(colorScheme),
          items: [
            if (!isPrimary)
              DropdownMenuItem<String>(
                value: 'none',
                child: Text(
                  isThai ? '— ไม่แสดงคำแปลรอง (None) —' : '— None (Single translation only) —',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ...languageGroups.map((group) {
              final isOnlyEditionUsedAsPrimary = !isPrimary &&
                  group.editions.length == 1 &&
                  otherSelectedId != null &&
                  group.editions.any((e) =>
                      e.id == otherSelectedId ||
                      (e.apiId != null && e.apiId.toString() == otherSelectedId));

              return DropdownMenuItem<String>(
                value: group.id,
                enabled: !isOnlyEditionUsedAsPrimary,
                child: Text(
                  group.name(settings.languageCode) +
                      (isOnlyEditionUsedAsPrimary
                          ? (isThai ? ' (ใช้งานเป็นคำแปลหลักอยู่)' : ' (In use as primary)')
                          : ''),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    fontWeight: isOnlyEditionUsedAsPrimary ? FontWeight.normal : FontWeight.w600,
                    color: isOnlyEditionUsedAsPrimary
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                        : colorScheme.onSurface,
                  ),
                ),
              );
            }),
          ],
          onChanged: (newLangId) async {
            if (newLangId == null) return;
            if (!isPrimary && newLangId == 'none') {
              settings.updateTranslationSlot('secondary', null);
              return;
            }

            final group = languageGroups.firstWhere((g) => g.id == newLangId);
            if (group.editions.isEmpty) return;

            // Pick first edition not used in the other slot
            final availableEdition = group.editions.firstWhere(
              (e) =>
                  e.id != otherSelectedId &&
                  (e.apiId == null || e.apiId.toString() != otherSelectedId),
              orElse: () => group.editions.first,
            );

            await _selectEdition(
              slot: slot,
              edition: availableEdition,
              settings: settings,
              transManager: transManager,
            );
          },
        ),

        // LEVEL 2: EDITION SELECTION
        if (!isNoneSelected && activeGroup != null && activeGroup.editions.length > 1) ...[
          const SizedBox(height: 12),
          Text(
            isThai
                ? 'เลือกฉบับ / สำนวนแปล (${activeGroup.nameTh})'
                : 'Choose Edition (${activeGroup.nameEn})',
            style: GoogleFonts.notoSansThai(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: activeGroup.editions.any((e) =>
                    e.id == currentSelectedId ||
                    (e.apiId != null && e.apiId.toString() == currentSelectedId))
                ? (activeGroup.editions
                    .firstWhere((e) =>
                        e.id == currentSelectedId ||
                        (e.apiId != null && e.apiId.toString() == currentSelectedId))
                    .id)
                : activeGroup.editions.first.id,
            dropdownColor: colorScheme.surfaceContainerLow,
            isExpanded: true,
            decoration: _inputDecoration(colorScheme),
            items: activeGroup.editions.map((edition) {
              final isUsed = otherSelectedId != null &&
                  (otherSelectedId == edition.id ||
                      (edition.apiId != null && otherSelectedId == edition.apiId.toString()));
              final isDownloaded = transManager.isDownloaded(edition.id) ||
                  (edition.apiId != null && transManager.isDownloaded(edition.apiId));
              final tagText = edition.tag(settings.languageCode);

              return DropdownMenuItem<String>(
                value: edition.id,
                enabled: !isUsed,
                child: Row(
                  children: [
                    if (!isDownloaded) ...[
                      Icon(Icons.download_for_offline_outlined,
                          size: 14, color: colorScheme.primary),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        '${edition.versionNumber}. ${edition.title(settings.languageCode)}${tagText != null ? ' · $tagText' : ''}${isUsed ? (isPrimary ? (isThai ? ' [ใช้ในคำแปลรอง]' : ' [In secondary]') : (isThai ? ' [ใช้ในคำแปลหลัก]' : ' [In primary]')) : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansThai(
                          fontSize: 13,
                          fontWeight: isUsed ? FontWeight.normal : FontWeight.w600,
                          color: isUsed
                              ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                              : (isDownloaded ? colorScheme.onSurface : colorScheme.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (newEditionId) async {
              if (newEditionId == null) return;
              final edition =
                  activeGroup.editions.firstWhere((e) => e.id == newEditionId);
              await _selectEdition(
                slot: slot,
                edition: edition,
                settings: settings,
                transManager: transManager,
              );
            },
          ),
          if (activeEdition != null) ...[
            const SizedBox(height: 8),
            _buildEditionDetailsCard(
              edition: activeEdition,
              languageCode: settings.languageCode,
              colorScheme: colorScheme,
            ),
          ],
        ],

        // SINGLE EDITION INFO
        if (!isNoneSelected &&
            activeGroup != null &&
            activeGroup.editions.length == 1 &&
            activeEdition != null) ...[
          const SizedBox(height: 8),
          _buildSingleEditionCard(
            edition: activeEdition,
            languageCode: settings.languageCode,
            colorScheme: colorScheme,
          ),
        ],

        // DISABLED NOTICE
        if (isNoneSelected && !isPrimary) ...[
          const SizedBox(height: 6),
          Text(
            isThai
                ? 'เลือกภาษาด้านบนเพื่อเปิดคำแปลภาษาที่สองสำหรับอ่านเทียบ'
                : 'Select a language above to read side-by-side with secondary translation.',
            style: GoogleFonts.notoSansThai(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _selectEdition({
    required String slot,
    required TranslationEdition edition,
    required SettingsProvider settings,
    required TranslationManagerProvider transManager,
  }) async {
    final editionId = edition.id;
    final isDownloaded = transManager.isDownloaded(editionId) ||
        (edition.apiId != null && transManager.isDownloaded(edition.apiId));

    if (isDownloaded) {
      settings.updateTranslationSlot(slot, editionId);
      transManager.loadTranslationIntoCache(editionId);
    } else {
      final opt = TranslationConstants.getKnownOption(editionId) ??
          AppTranslationOption(
            id: editionId,
            apiId: edition.apiId,
            name: edition.titleEn,
            nameTh: edition.titleTh,
            author: edition.authorEn,
            language: edition.languageId,
          );
      await _downloadTranslation(opt);
      settings.updateTranslationSlot(slot, editionId);
    }
  }

  Widget _buildEditionDetailsCard({
    required TranslationEdition edition,
    required String languageCode,
    required ColorScheme colorScheme,
  }) {
    final tagText = edition.tag(languageCode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  edition.title(languageCode),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  edition.subtitle(languageCode),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (tagText != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tagText,
                style: GoogleFonts.notoSansThai(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSingleEditionCard({
    required TranslationEdition edition,
    required String languageCode,
    required ColorScheme colorScheme,
  }) {
    final isThai = languageCode == 'th';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  edition.title(languageCode),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  edition.subtitle(languageCode),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isThai ? 'ฉบับมาตรฐาน' : 'Standard',
              style: GoogleFonts.notoSansThai(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(ColorScheme colorScheme) {
    return InputDecoration(
      filled: true,
      fillColor: colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _sectionTitle(ColorScheme colorScheme, String title) {
    return Text(
      title,
      style: GoogleFonts.notoSansThai(
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
    );
  }

  Widget _buildTranslationRow({
    required AppTranslationOption option,
    required SettingsProvider settings,
    required ColorScheme colorScheme,
    bool isDownloaded = true,
    bool isActiveList = false,
    bool isDownloadList = false,
    bool showSelector = true,
    double? progress,
    VoidCallback? onDownload,
    VoidCallback? onDelete,
  }) {
    final isPrimary = settings.primaryTranslationId == option.id;
    final isSecondary = settings.secondaryTranslationId == option.id;
    final isChecked = isPrimary || isSecondary;
    final canSelect = option.apiId == null || isDownloaded;

    final useTransparentBg = isDownloadList || isActiveList;

    return Container(
      margin: EdgeInsets.only(bottom: isDownloadList ? 2 : 0),
      padding: EdgeInsets.symmetric(
        horizontal: useTransparentBg ? 8 : 12,
        vertical: useTransparentBg ? 10 : 8,
      ),
      decoration: useTransparentBg
          ? null
          : BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
      child: Row(
        children: [
          if (isDownloadList) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getLanguageDisplayName(option.language, settings.languageCode),
                  style: GoogleFonts.notoSansThai(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  (() {
                    final status = isPrimary
                        ? context.tr('primary')
                        : isSecondary
                        ? context.tr('secondary')
                        : null;
                    final transName = option.displayName(settings.languageCode);
                    return status != null ? '$status • $transName' : transName;
                  })(),
                  style: GoogleFonts.notoSansThai(
                    color: isPrimary || isSecondary
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: isPrimary || isSecondary
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (progress != null) ...[
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: progress,
                color: colorScheme.primary,
                strokeWidth: 2,
              ),
            ),
          ] else if (canSelect && showSelector) ...[
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                color: colorScheme.error,
                onPressed: onDelete,
              ),
            Checkbox(
              value: isChecked,
              activeColor: colorScheme.primary,
              onChanged: (value) => _toggleTranslation(
                settings: settings,
                id: option.id,
                isPrimary: isPrimary,
                value: value,
              ),
            ),
          ] else if (isDownloaded && onDelete != null) ...[
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              color: colorScheme.error,
              onPressed: onDelete,
            ),
          ] else if (onDownload != null) ...[
            IconButton(
              tooltip: context.tr('download_more'),
              icon: const Icon(Icons.download_rounded),
              color: colorScheme.primary,
              onPressed: onDownload,
            ),
          ],
        ],
      ),
    );
  }

  void _toggleTranslation({
    required SettingsProvider settings,
    required String id,
    required bool isPrimary,
    required bool? value,
  }) {
    if (value == true) {
      settings.updateTranslationSlot('secondary', id);
      return;
    }

    if (isPrimary) {
      if (settings.secondaryTranslationId != null) {
        settings.updateTranslationSlot(
          'primary',
          settings.secondaryTranslationId,
        );
        settings.updateTranslationSlot('secondary', null);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('at_least_one_active'))),
        );
      }
      return;
    }

    settings.updateTranslationSlot('secondary', null);
  }

  Future<void> _downloadTranslation(AppTranslationOption option) async {
    final id = option.apiId;
    if (id == null) return;

    final overlayState = Overlay.of(context);
    final sectionContext = context;
    final transManager = context.read<TranslationManagerProvider>();

    // Request notification permission on Android/iOS
    await requestNotificationPermission();

    if (!mounted) return;

    _activeDownloadingId = id;

    // Clean up any existing download progress overlays
    _progressOverlayEntry?.remove();
    _progressOverlayEntry = null;
    _activeProgressNotifier?.dispose();

    final progressNotifier = ValueNotifier<double>(0);
    _activeProgressNotifier = progressNotifier;

    final entry = OverlayEntry(
      builder: (overlayContext) {
        return _DownloadProgressOverlay(
          option: option,
          progressNotifier: progressNotifier,
          sectionContext: sectionContext,
          onClose: () {
            _progressOverlayEntry?.remove();
            _progressOverlayEntry = null;
            _activeProgressNotifier?.dispose();
            _activeProgressNotifier = null;
            _activeDownloadingId = null;
          },
        );
      },
    );
    _progressOverlayEntry = entry;
    overlayState.insert(entry);

    await transManager.startBackgroundDownload(
      id: id,
      name: option.name,
      author: option.author,
      language: option.language,
    );
  }

  String get settingsLanguage {
    return context.read<SettingsProvider>().languageCode;
  }

  Future<void> _deleteTranslation(
    int id,
    TranslationManagerProvider transManager,
    SettingsProvider settings,
  ) async {
    final idStr = id.toString();
    if (settings.primaryTranslationId == idStr ||
        settings.secondaryTranslationId == idStr) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete active translation.')),
      );
      return;
    }
    await transManager.deleteTranslation(id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Translation deleted.')));
  }

  List<AppTranslationOption> _downloadedOptions(
    TranslationManagerProvider transManager,
  ) {
    return transManager.downloadedTranslations.map((item) {
      final id = item['id'].toString();
      final known = _availableTranslations
          .where((option) => option.id == id)
          .firstOrNull;
      if (known != null) return known;

      return AppTranslationOption(
        id: id,
        apiId: int.tryParse(id),
        name: item['name']?.toString() ?? 'Downloaded translation',
        author: item['author_name']?.toString() ?? '',
        language: item['language_name']?.toString() ?? '',
      );
    }).toList()..sort(TranslationConstants.compareOptions);
  }

  Map<String, List<AppTranslationOption>> _groupedAvailableTranslations() {
    final sorted = [
      ..._availableTranslations,
    ]..sort(TranslationConstants.compareOptions);
    final groups = <String, List<AppTranslationOption>>{};
    for (final option in sorted) {
      groups.putIfAbsent(option.language, () => []).add(option);
    }
    return groups;
  }

  String _languageLabel(String language, String appLanguage) {
    final normalized = language.toLowerCase();
    if (appLanguage == 'th') {
      return switch (normalized) {
        'thai' => 'ภาษาไทย',
        'english' => 'ภาษาอังกฤษ',
        'malay' => 'ภาษามลายู',
        _ => language,
      };
    }
    return switch (normalized) {
      'thai' => 'Thai',
      'english' => 'English',
      'malay' => 'Malay',
      _ => language,
    };
  }

  String _getLanguageDisplayName(String language, String appLanguage) {
    final normalized = language.toLowerCase();
    if (normalized == 'thai' || normalized == 'th') {
      return 'ภาษาไทย';
    }
    if (appLanguage == 'th') {
      return switch (normalized) {
        'english' => 'ภาษาอังกฤษ',
        'malay' => 'ภาษามลายู',
        _ => language,
      };
    }
    return switch (normalized) {
      'english' => 'English',
      'malay' => 'Malay',
      _ => language,
    };
  }
}

class _DownloadProgressOverlay extends StatefulWidget {
  final AppTranslationOption option;
  final ValueNotifier<double> progressNotifier;
  final BuildContext sectionContext;
  final VoidCallback onClose;

  const _DownloadProgressOverlay({
    required this.option,
    required this.progressNotifier,
    required this.sectionContext,
    required this.onClose,
  });

  @override
  State<_DownloadProgressOverlay> createState() => _DownloadProgressOverlayState();
}

class _DownloadProgressOverlayState extends State<_DownloadProgressOverlay> with SingleTickerProviderStateMixin {
  bool _isCollapsed = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String get settingsLanguage => context.read<SettingsProvider>().languageCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ValueListenableBuilder<double>(
      valueListenable: widget.progressNotifier,
      builder: (context, progress, child) {
        final isFinished = progress >= 1.0;
        final percent = (progress * 100).clamp(0, 100).round();

        if (_isCollapsed) {
          return Positioned(
            bottom: 80,
            right: 16,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => setState(() => _isCollapsed = false),
                child: Material(
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.3),
                  shape: const CircleBorder(),
                  color: isFinished ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!isFinished)
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 3,
                              color: colorScheme.primary,
                              backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
                            ),
                          ),
                        if (isFinished)
                          const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 28,
                          )
                        else
                          RotationTransition(
                            turns: _pulseController,
                            child: Icon(
                              Icons.hourglass_empty_rounded,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Positioned(
          bottom: 80,
          left: 16,
          right: 16,
          child: SafeArea(
            child: Material(
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isFinished
                                ? '${widget.option.displayName(settingsLanguage)} Downloaded'
                                : 'Downloading ${widget.option.displayName(settingsLanguage)}',
                            style: GoogleFonts.notoSansThai(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: isFinished ? colorScheme.primary : colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (!isFinished)
                          IconButton(
                            icon: const Icon(Icons.close_fullscreen_rounded),
                            tooltip: 'Collapse',
                            iconSize: 20,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            onPressed: () => setState(() => _isCollapsed = true),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Close',
                          iconSize: 20,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isFinished) ...[
                      Text(
                        'Translation is ready to read.',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: widget.onClose,
                            child: const Text('Dismiss'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () {
                              final settings = widget.sectionContext.read<SettingsProvider>();
                              settings.updateTranslationSlot('primary', widget.option.id);
                              widget.onClose();
                            },
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Activate Now'),
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                color: colorScheme.primary,
                                backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$percent%',
                            style: GoogleFonts.notoSansThai(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        settingsLanguage == 'th' ? 'กำลังดำเนินการในพื้นหลัง...' : 'Loading in the background...',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
