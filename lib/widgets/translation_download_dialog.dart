import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/translation_manager_provider.dart';
import '../services/translation_downloader.dart';
import '../shared/translation_constants.dart';
import '../theme/app_theme.dart';

class TranslationDownloadDialog extends StatefulWidget {
  final AppTranslationOption option;
  final bool isPrimary;
  final VoidCallback? onActivated;

  const TranslationDownloadDialog({
    super.key,
    required this.option,
    this.isPrimary = true,
    this.onActivated,
  });

  static Future<bool> show(
    BuildContext context, {
    required AppTranslationOption option,
    bool isPrimary = true,
    VoidCallback? onActivated,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TranslationDownloadDialog(
        option: option,
        isPrimary: isPrimary,
        onActivated: onActivated,
      ),
    );
    return result ?? false;
  }

  @override
  State<TranslationDownloadDialog> createState() =>
      _TranslationDownloadDialogState();
}

class _TranslationDownloadDialogState extends State<TranslationDownloadDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _errorMessage;
  bool _isSuccess = false;

  Future<void> _startDownload() async {
    final apiId = widget.option.apiId;
    if (apiId == null) return;

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _errorMessage = null;
    });

    final success = await TranslationDownloader.downloadTranslation(
      apiId,
      widget.option.name,
      widget.option.author,
      widget.option.language,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _progress = p;
          });
        }
      },
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _isDownloading = false;
        _isSuccess = true;
        _progress = 1.0;
      });

      final transManager = context.read<TranslationManagerProvider>();
      final settings = context.read<SettingsProvider>();

      await transManager.refreshDownloadedList();
      await transManager.loadTranslationIntoCache(widget.option.id);
      if (widget.option.apiId != null) {
        await transManager.loadTranslationIntoCache(widget.option.apiId);
      }

      settings.updateTranslationSlot(
        widget.isPrimary ? 'primary' : 'secondary',
        widget.option.id,
      );

      widget.onActivated?.call();

      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              settings.languageCode == 'th'
                  ? 'ดาวน์โหลดและเปิดใช้งานคำแปลสำเร็จแล้ว'
                  : 'Translation downloaded and activated successfully.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      setState(() {
        _isDownloading = false;
        _errorMessage = 'Download failed. Please check internet connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final isThai = settings.languageCode == 'th';
    final displayName = widget.option.displayName(settings.languageCode);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      backgroundColor: colorScheme.surface,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isSuccess
                  ? Icons.check_circle_rounded
                  : Icons.cloud_download_rounded,
              color: _isSuccess ? Colors.green : colorScheme.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _isSuccess
                  ? (isThai ? 'ดาวน์โหลดเสร็จสมบูรณ์' : 'Download Complete')
                  : (_isDownloading
                      ? (isThai ? 'กำลังดาวน์โหลด...' : 'Downloading...')
                      : (isThai ? 'ดาวน์โหลดคำแปล' : 'Download Translation')),
              style: GoogleFonts.notoSansThai(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayName,
            style: GoogleFonts.notoSansThai(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
          if (widget.option.author.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.option.author,
              style: GoogleFonts.notoSansThai(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isThai
                      ? 'ดาวน์โหลดครบ 114 ซูเราะฮฺ...'
                      : 'Downloading all 114 Surahs...',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ] else if (_isSuccess) ...[
            Text(
              isThai
                  ? 'ติดตั้งคำแปลและเปิดใช้งานทันทีเรียบร้อยแล้ว'
                  : 'Installed and activated for immediate reading.',
              style: GoogleFonts.notoSansThai(
                fontSize: 13,
                color: Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else ...[
            Text(
              isThai
                  ? 'คำแปลนี้ยังไม่ได้ดาวน์โหลดลงในเครื่อง ต้องการดาวน์โหลดทันทีเพื่อเปิดอ่านหรือไม่? (ขนาดไฟล์ประมาณ 2 MB)'
                  : 'This translation is not yet downloaded on your device. Would you like to download it now to read immediately? (~2 MB)',
              style: GoogleFonts.notoSansThai(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: GoogleFonts.notoSansThai(
                  fontSize: 12,
                  color: colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ],
      ),
      actions: _isDownloading
          ? []
          : [
              if (!_isSuccess)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    isThai ? 'ยกเลิก' : 'Cancel',
                    style: GoogleFonts.notoSansThai(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (!_isSuccess)
                FilledButton.icon(
                  onPressed: _startDownload,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    isThai ? 'ดาวน์โหลดและเปิดอ่าน' : 'Download & Read',
                    style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
    );
  }
}
