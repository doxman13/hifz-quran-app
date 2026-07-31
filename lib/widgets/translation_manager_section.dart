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
  static const _builtInThaiV3 = _TranslationOption(
    id: 'thai_v3',
    apiId: null,
    name: 'Society of Institutes and Universities (Language revised edition)',
    nameTh: 'Society of Institutes and Universities (ฉบับปรับปรุงภาษา)',
    author: 'Society of Institutes and Universities',
    language: 'thai',
  );

  static const List<_TranslationOption> _availableTranslations = [
    _TranslationOption(
      id: '51',
      apiId: 51,
      name: 'Thai Translation (King Fahad Quran Complex)',
      nameTh: 'ศูนย์กษัตริย์ฟะฮัดเพื่อการพิมพ์อัลกุรอาน',
      author: 'King Fahad Quran Complex',
      language: 'thai',
    ),
    _TranslationOption(
      id: '230',
      apiId: 230,
      name: 'Society of Institutes and Universities',
      nameTh: 'Society of Institutes and Universities (Original)',
      author: 'Society of Institutes and Universities',
      language: 'thai',
    ),
    _TranslationOption(
      id: '85',
      apiId: 85,
      name: 'M.A.S. Abdel Haleem',
      author: 'Abdul Haleem',
      language: 'english',
    ),
    _TranslationOption(
      id: '20',
      apiId: 20,
      name: 'Saheeh International',
      author: 'Saheeh International',
      language: 'english',
    ),
    _TranslationOption(
      id: '84',
      apiId: 84,
      name: 'T. Usmani',
      author: 'Mufti Taqi Usmani',
      language: 'english',
    ),
    _TranslationOption(
      id: '39',
      apiId: 39,
      name: 'Abdullah Muhammad Basmeih',
      author: 'Abdullah Muhammad Basmeih',
      language: 'malay',
    ),
  ];

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
    final availableOptions = _allAvailableOptions(transManager);

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

    return Card(
      color: colorScheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(colorScheme, context.tr('active_translations')),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('primary'),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: settings.primaryTranslationId,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colorScheme.outline, width: 1),
                    ),
                  ),
                  items: availableOptions.map((opt) {
                    return DropdownMenuItem<String>(
                      value: opt.id,
                      child: Text(opt.displayName(settings.languageCode)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      settings.updateTranslationSlot('primary', val);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('secondary'),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: settings.secondaryTranslationId ?? '',
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colorScheme.outline, width: 1),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('None / ไม่เลือก')),
                    ...availableOptions.map((opt) {
                      return DropdownMenuItem<String>(
                        value: opt.id,
                        child: Text(opt.displayName(settings.languageCode)),
                      );
                    }).toList(),
                  ],
                  onChanged: (val) {
                    if (val == null || val.isEmpty) {
                      settings.updateTranslationSlot('secondary', null);
                    } else if (val != settings.primaryTranslationId) {
                      settings.updateTranslationSlot('secondary', val);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            _sectionTitle(colorScheme, context.tr('download_more')),
            const SizedBox(height: 16),
            Divider(height: 1, color: colorScheme.outlineVariant),
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
    required _TranslationOption option,
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

  Future<void> _downloadTranslation(_TranslationOption option) async {
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

  List<_TranslationOption> _downloadedOptions(
    TranslationManagerProvider transManager,
  ) {
    return transManager.downloadedTranslations.map((item) {
      final id = item['id'].toString();
      final known = _availableTranslations
          .where((option) => option.id == id)
          .firstOrNull;
      if (known != null) return known;

      return _TranslationOption(
        id: id,
        apiId: int.tryParse(id),
        name: item['name']?.toString() ?? 'Downloaded translation',
        author: item['author_name']?.toString() ?? '',
        language: item['language_name']?.toString() ?? '',
      );
    }).toList()..sort(_compareTranslationOptions);
  }

  List<_TranslationOption> _allAvailableOptions(TranslationManagerProvider transManager) {
    final downloaded = _downloadedOptions(transManager);

    final builtIns = <_TranslationOption>[];
    builtIns.add(_builtInThaiV3);

    final all = <String, _TranslationOption>{};
    for (final opt in builtIns) {
      all[opt.id] = opt;
    }
    for (final opt in downloaded) {
      all[opt.id] = opt;
    }

    final result = all.values.toList();
    result.sort(_compareTranslationOptions);
    return result;
  }

  Map<String, List<_TranslationOption>> _groupedAvailableTranslations() {
    final sorted = [..._availableTranslations]
      ..sort(_compareTranslationOptions);
    final groups = <String, List<_TranslationOption>>{};
    for (final option in sorted) {
      groups.putIfAbsent(option.language, () => []).add(option);
    }
    return groups;
  }

  int _compareTranslationOptions(_TranslationOption a, _TranslationOption b) {
    final languageCompare = _languageSortOrder(
      a.language,
    ).compareTo(_languageSortOrder(b.language));
    if (languageCompare != 0) return languageCompare;
    return a.name.compareTo(b.name);
  }

  int _languageSortOrder(String language) {
    return switch (language.toLowerCase()) {
      'thai' => 0,
      'english' => 1,
      'malay' => 2,
      _ => 99,
    };
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

class _TranslationOption {
  final String id;
  final int? apiId;
  final String name;
  final String? nameTh;
  final String author;
  final String language;

  const _TranslationOption({
    required this.id,
    required this.apiId,
    required this.name,
    this.nameTh,
    required this.author,
    required this.language,
  });

  String displayName(String appLanguage) {
    if (appLanguage == 'th' && nameTh != null && nameTh!.isNotEmpty) {
      return nameTh!;
    }
    return name;
  }
}

class _DownloadProgressOverlay extends StatefulWidget {
  final _TranslationOption option;
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
                        'Translation is ready. Open Settings to activate it.',
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
                              Scrollable.ensureVisible(
                                widget.sectionContext,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                              );
                              widget.onClose();
                            },
                            icon: const Icon(Icons.settings_rounded, size: 16),
                            label: const Text('Open Settings'),
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
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Loading in the background...',
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
