import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import 'flexcil_settings_widgets.dart';

/// Flexcil-styled quick settings modal sheet for Hifz (Memorization) mode.
class HifzQuickSettingsSheet extends StatefulWidget {
  final bool isMushafView;
  final bool isTajweedMushaf;
  final ValueChanged<bool> onToggleTajweed;
  final bool showWbw;
  final ValueChanged<bool> onToggleWbw;
  final bool chunkLongVerses;
  final ValueChanged<bool> onToggleChunking;
  final bool isReview;
  final VoidCallback onSwitchMode;
  final VoidCallback onOpenRangeSetup;
  final VoidCallback onOpenReport;
  final VoidCallback onOpenMastery;
  final VoidCallback onOpenGuide;
  final VoidCallback onOpenFullSettings;
  final String? currentSurahName;
  final int? startVerse;
  final int? endVerse;

  const HifzQuickSettingsSheet({
    super.key,
    required this.isMushafView,
    required this.isTajweedMushaf,
    required this.onToggleTajweed,
    required this.showWbw,
    required this.onToggleWbw,
    required this.chunkLongVerses,
    required this.onToggleChunking,
    required this.isReview,
    required this.onSwitchMode,
    required this.onOpenRangeSetup,
    required this.onOpenReport,
    required this.onOpenMastery,
    required this.onOpenGuide,
    required this.onOpenFullSettings,
    this.currentSurahName,
    this.startVerse,
    this.endVerse,
  });

  @override
  State<HifzQuickSettingsSheet> createState() => _HifzQuickSettingsSheetState();
}

class _HifzQuickSettingsSheetState extends State<HifzQuickSettingsSheet> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isThai = settings.languageCode == 'th';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surface : const Color(0xFFFCFBF9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isThai ? 'การตั้งค่าการท่องจำด่วน' : 'Quick Hifz Settings',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        isThai ? 'ฉบับมุศหัฟ ตัวช่วยจำ และสถิติ' : 'Script, aids, range & analytics',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Flexcil Top Segmented Pills
          FlexcilSegmentedPills<int>(
            items: [
              FlexcilPillItem<int>(
                value: 0,
                label: isThai ? 'การแสดงผล' : 'Display',
                icon: Icons.auto_stories_rounded,
              ),
              FlexcilPillItem<int>(
                value: 1,
                label: isThai ? 'ช่วง & สถิติ' : 'Range & Stats',
                icon: Icons.analytics_outlined,
              ),
              FlexcilPillItem<int>(
                value: 2,
                label: isThai ? 'อุปกรณ์ & ระบบ' : 'Hardware',
                icon: Icons.bluetooth_rounded,
              ),
            ],
            selectedValue: _selectedTabIndex,
            onSelected: (idx) {
              setState(() => _selectedTabIndex = idx);
            },
          ),
          const SizedBox(height: 14),

          // Tab Content
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.52,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selectedTabIndex == 0) ..._buildDisplayTab(settings, colorScheme, isThai),
                  if (_selectedTabIndex == 1) ..._buildRangeStatsTab(colorScheme, isThai),
                  if (_selectedTabIndex == 2) ..._buildHardwareTab(settings, colorScheme, isThai),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 📖 TAB 0: DISPLAY & SCRIPT
  // ─────────────────────────────────────────────────────────────
  List<Widget> _buildDisplayTab(SettingsProvider settings, ColorScheme colorScheme, bool isThai) {
    return [
      // Mushaf Script Type (if in mushaf view)
      if (widget.isMushafView) ...[
        FlexcilSectionHeader(
          title: isThai ? 'ฉบับคัมภีร์มุศหัฟ' : 'Mushaf Script Style',
          subtitle: isThai ? 'เลือกลายเส้นมาตรฐานหรือแบบมีสีแยกกฎ' : 'Authentic Madinah or color-coded tajweed',
        ),
        FlexcilCard(
          padding: const EdgeInsets.all(10),
          child: FlexcilSegmentedPills<bool>(
            items: [
              FlexcilPillItem<bool>(
                value: false,
                label: isThai ? 'มะดีนะฮฺ (มาตรฐาน)' : 'Standard (1405H)',
                icon: Icons.menu_book_rounded,
              ),
              FlexcilPillItem<bool>(
                value: true,
                label: isThai ? 'ตัจญ์วีด (มีสีแยกกฎ)' : 'Tajweed Colors',
                icon: Icons.palette_outlined,
              ),
            ],
            selectedValue: widget.isTajweedMushaf,
            onSelected: widget.onToggleTajweed,
          ),
        ),
        const SizedBox(height: 14),
      ],

      // Reading Aids
      FlexcilSectionHeader(
        title: isThai ? 'ตัวช่วยท่องจำ' : 'Memorization Aids',
        subtitle: isThai ? 'ตัวช่วยแสดงคำต่อคำและแบ่งย่อยอายะฮ์' : 'Word-by-word meanings and chunking',
      ),
      FlexcilCard(
        child: Column(
          children: [
            // Word-by-Word
            if (!widget.isMushafView) ...[
              FlexcilToggleTile(
                icon: Icons.translate_rounded,
                title: isThai ? 'แสดงคำต่อคำ (Word-by-Word)' : 'Word-by-Word (WBW)',
                subtitle: isThai ? 'แสดงคำแปลแยกรายคำศัพท์ใต้ตัวบท' : 'Show translation below each word',
                value: widget.showWbw,
                onChanged: widget.onToggleWbw,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
            ],

            // Chunk Long Verses
            if (!widget.isReview) ...[
              FlexcilToggleTile(
                icon: Icons.format_list_numbered_rounded,
                title: isThai ? 'แบ่งย่อยอายะฮ์ยาว (Chunking)' : 'Chunk Long Verses',
                subtitle: isThai
                    ? 'แบ่งวรรคตอนอายะฮ์ยาวเพื่อจำทีละส่วนก่อนเชื่อมโยง'
                    : 'Break long verses into smaller segments for easier memorization',
                value: widget.chunkLongVerses,
                onChanged: widget.onToggleChunking,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
            ],

            // Dark Mode
            FlexcilToggleTile(
              icon: settings.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              title: isThai ? 'โหมดมืด (Dark Mode)' : 'Dark Theme',
              subtitle: isThai ? 'ปรับความสว่างสบายตาสำหรับการอ่านกลางคืน' : 'Comfortable high-contrast night reading',
              value: settings.isDarkMode,
              onChanged: settings.toggleDarkMode,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // Switch Mode Action Card
      FlexcilCard(
        padding: const EdgeInsets.all(12),
        child: InkWell(
          onTap: widget.onSwitchMode,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.swap_horiz_rounded, color: colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isThai ? 'สลับโหมดการแสดงผล (Switch Mode)' : 'Switch View Mode',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        isThai ? 'สลับระหว่างหน้ามุศหัฟกับมุมมองรายการ' : 'Switch between Mushaf page and List view',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  // ─────────────────────────────────────────────────────────────
  // 🎯 TAB 1: RANGE & STATS
  // ─────────────────────────────────────────────────────────────
  List<Widget> _buildRangeStatsTab(ColorScheme colorScheme, bool isThai) {
    return [
      // Active Memorization Range Card
      if (widget.currentSurahName != null && widget.startVerse != null && widget.endVerse != null) ...[
        FlexcilSectionHeader(
          title: isThai ? 'ช่วงอายะห์ที่กำลังท่องจำ' : 'Active Memorization Range',
        ),
        FlexcilCard(
          child: Row(
            mainAxisAlignment: deliberateSpaceBetween(),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.currentSurahName!,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isThai
                        ? 'อายะห์ที่ ${widget.startVerse} ถึง ${widget.endVerse}'
                        : 'Verses ${widget.startVerse} – ${widget.endVerse}',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              if (!widget.isReview)
                FilledButton.tonalIcon(
                  onPressed: widget.onOpenRangeSetup,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: Text(
                    isThai ? 'เปลี่ยนช่วง' : 'Change',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],

      // Memorization Analytics & Tools
      FlexcilSectionHeader(
        title: isThai ? 'สถิติและเครื่องมือ' : 'Analytics & Guidance',
        subtitle: isThai ? 'รายงานสถิติการทวนซ้ำและความแม่นยำ' : 'Repetition stats, mastery, and how-to guide',
      ),
      FlexcilCard(
        child: Column(
          children: [
            // Repetition Report
            _buildActionRow(
              icon: Icons.analytics_outlined,
              title: isThai ? 'รายงานสถิติการทวนซ้ำ (Report)' : 'Repetition Report',
              subtitle: isThai ? 'ดูจำนวนครั้งการทวนซ้ำและระยะเวลาในเซสชันนี้' : 'Review session tally and duration',
              onTap: widget.onOpenReport,
              colorScheme: colorScheme,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            // Mastery List
            _buildActionRow(
              icon: Icons.workspace_premium_outlined,
              title: isThai ? 'บันทึกระดับความแม่นยำ (Mastery List)' : 'Mastery List',
              subtitle: isThai ? 'ดูและจัดการอายะห์ที่ท่องจำผ่านระดับต่างๆ' : 'Check memorized verses by mastery level',
              onTap: widget.onOpenMastery,
              colorScheme: colorScheme,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            // How to Hifz Guide
            _buildActionRow(
              icon: Icons.menu_book_outlined,
              title: isThai ? 'คู่มือเทคนิคการท่องจำ (How to Hifz)' : 'How to Hifz Guide',
              subtitle: isThai ? 'หลักการท่องจำแบบทวนซ้ำที่มีประสิทธิภาพ' : 'Effective repetition and retention techniques',
              onTap: widget.onOpenGuide,
              colorScheme: colorScheme,
            ),
          ],
        ),
      ),
    ];
  }

  // ─────────────────────────────────────────────────────────────
  // ⚙️ TAB 2: HARDWARE & FULL SETTINGS
  // ─────────────────────────────────────────────────────────────
  List<Widget> _buildHardwareTab(SettingsProvider settings, ColorScheme colorScheme, bool isThai) {
    String inputModeLabel;
    IconData inputModeIcon;

    switch (settings.hifzInputMode) {
      case HifzInputMode.inAppTally:
        inputModeLabel = isThai ? 'ปุ่มนับในแอป (หน้าจอ)' : 'In-App Tally Button';
        inputModeIcon = Icons.touch_app_rounded;
        break;
      case HifzInputMode.bluetoothShutter:
        inputModeLabel = isThai ? 'รีโมทบลูทูธ / ชัตเตอร์' : 'Bluetooth Remote / Shutter';
        inputModeIcon = Icons.bluetooth_searching_rounded;
        break;
      case HifzInputMode.bleSmartRing:
        inputModeLabel = isThai ? 'แหวนบลูทูธอัจฉริยะ (BLE Ring)' : 'BLE Smart Ring';
        inputModeIcon = Icons.watch_rounded;
        break;
    }

    return [
      FlexcilSectionHeader(
        title: isThai ? 'อุปกรณ์และการควบคุม' : 'Input & Remote Method',
        subtitle: isThai ? 'วิธีเลื่อนและนับรอบอายะห์ขณะท่องจำ' : 'How verses advance during your memorization session',
      ),
      FlexcilCard(
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(inputModeIcon, color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isThai ? 'โหมดควบคุมปัจจุบัน' : 'Active Input Mode',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        inputModeLabel,
                        style: GoogleFonts.notoSansThai(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: widget.onOpenFullSettings,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
                label: Text(
                  isThai ? 'จัดการแหวนและอุปกรณ์บลูทูธ' : 'Manage BLE Devices & Ring',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),

      // Shortcut to Full Hifz Settings
      FlexcilCard(
        padding: const EdgeInsets.all(12),
        child: InkWell(
          onTap: widget.onOpenFullSettings,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.settings_outlined, color: colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isThai ? 'การตั้งค่าท่องจำทั้งหมด' : 'All Hifz Settings',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        isThai ? 'ปรับแต่งเสียงอ่าน AI การจับเวลา และคำแปล' : 'Configure AI voice tracking, timers, audio & translations',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  MainAxisAlignment deliberateSpaceBetween() => MainAxisAlignment.spaceBetween;

  Widget _buildActionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: colorScheme.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant, size: 18),
          ],
        ),
      ),
    );
  }
}
