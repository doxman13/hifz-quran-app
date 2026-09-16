import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/ble_remote_provider.dart';
import '../providers/mushaf_audio_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/translation_manager_provider.dart';
import '../widgets/translation_download_dialog.dart';
import '../widgets/translation_manager_section.dart';
import '../shared/translation_constants.dart';

class HifzSettingsScreen extends StatelessWidget {
  final bool isEmbedded;

  const HifzSettingsScreen({
    super.key,
    this.isEmbedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final textTheme = Theme.of(context).textTheme;
    final isThai = settings.languageCode == 'th';
    final isBleSelected = settings.hifzInputMode == HifzInputMode.bleSmartRing;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isEmbedded,
        title: Text(
          isThai ? 'การตั้งค่า' : 'Settings',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // ── 1. Display & Language ──
          _SectionTitle(
            title: isThai ? 'การแสดงผลและภาษา' : 'Display & Language',
            subtitle: isThai
                ? 'โหมดมืด ภาษา และการเปิดหน้าจอ'
                : 'Theme mode, app language, and screen wake settings.',
          ),
          const SizedBox(height: 12),
          const _DisplayLanguageSettingCard(),
          const SizedBox(height: 28),

          // ── 2. Memorization Controls / Input Mode ──
          _SectionTitle(
            title: isThai ? 'อุปกรณ์และการควบคุม' : 'Input & Remote Mode',
            subtitle: isThai
                ? 'เลือกวิธีเลื่อนอายะห์ขณะท่องจำ (ปุ่มในแอป รีโมท หรือแหวนสมาร์ต)'
                : 'Choose how you advance through verses during memorization.',
          ),
          const SizedBox(height: 12),
          _InputModeOptionCard(
            title: isThai ? 'ปุ่มนับในแอป (หน้าจอ)' : 'In-App Tally Button',
            subtitle: isThai
                ? 'ใช้ปุ่มนับที่ด้านล่างของหน้าจอเพื่อบันทึกและเลื่อนอายะห์ ไม่จำเป็นต้องใช้อุปกรณ์ภายนอก'
                : 'Use the tally button at the bottom of the screen to manually advance each verse. No hardware needed.',
            icon: Icons.touch_app_rounded,
            value: HifzInputMode.inAppTally,
            groupValue: settings.hifzInputMode,
            onSelect: () => settings.setHifzInputMode(HifzInputMode.inAppTally),
          ),
          const SizedBox(height: 12),
          _InputModeOptionCard(
            title: isThai ? 'รีโมทบลูทูธ / ชัตเตอร์' : 'Bluetooth Remote / Shutter',
            subtitle: isThai
                ? 'ใช้ปุ่มชัตเตอร์หรือปุ่มปรับเสียงของรีโมทเลื่อนอายะห์ สะดวกเมื่อถือมือถือหรือวางไว้บนแท่น'
                : 'Use a Bluetooth shutter or remote to tap through verses. Volume keys are captured for navigation.',
            icon: Icons.bluetooth_searching_rounded,
            value: HifzInputMode.bluetoothShutter,
            groupValue: settings.hifzInputMode,
            onSelect: () => settings.setHifzInputMode(HifzInputMode.bluetoothShutter),
          ),
          const SizedBox(height: 12),
          _InputModeOptionCard(
            title: isThai ? 'แหวนบลูทูธอัจฉริยะ (BLE Smart Ring)' : 'BLE Smart Ring',
            subtitle: isThai
                ? 'เชื่อมต่อแหวน Smart Tasbih, Zikir Ring, iQibla เพื่อเลื่อนอายะห์แบบแฮนด์ฟรี'
                : 'Connect to a BLE smart ring for hands-free verse advancement (Smart Tasbih, Zikir Ring, iQibla, etc.).',
            icon: Icons.watch_rounded,
            value: HifzInputMode.bleSmartRing,
            groupValue: settings.hifzInputMode,
            onSelect: () => settings.setHifzInputMode(HifzInputMode.bleSmartRing),
          ),
          if (isBleSelected) ...[
            const SizedBox(height: 12),
            const BleDeviceManagementUI(),
          ],
          const SizedBox(height: 28),

          // ── 3. Voice Recitation Tracking ──
          _SectionTitle(
            title: isThai ? 'ตรวจจับเสียงอ่าน (AI Recitation)' : 'Voice Recitation Tracking',
            subtitle: isThai
                ? 'ระบบตรวจจับเสียงอ่านออฟไลน์บนเครื่อง ตรวจจับการอ่านข้ามอายะห์'
                : 'On-device speech recognition to auto-advance and detect skipped verses.',
          ),
          const SizedBox(height: 12),
          const _VoiceRecitationSettingCard(),
          const SizedBox(height: 28),

          // ── 4. Audio Playback & Volume ──
          _SectionTitle(
            title: isThai ? 'เสียงผู้อ่านและระดับเสียง' : 'Audio Playback',
            subtitle: isThai
                ? 'ปรับระดับเสียงของแอปโดยตรงเมื่อปุ่มเสียงของเครื่องถูกใช้เป็นชัตเตอร์'
                : 'Adjust recitation volume directly in-app when hardware keys are used as shutters.',
          ),
          const SizedBox(height: 12),
          const _InAppVolumeControlCard(),
          const SizedBox(height: 28),

          // ── 5. Quran Text & Font Sizes ──
          _SectionTitle(
            title: isThai ? 'ตัวอักษรและขนาด' : 'Quran Text & Font Sizes',
            subtitle: isThai
                ? 'ปรับขนาดตัวอักษรอาหรับ คำแปล และการแสดงคำต่อคำ'
                : 'Customize font sizes for Arabic, translation, and word-by-word display.',
          ),
          const SizedBox(height: 12),
          const _QuranTextFontSettingCard(),
          const SizedBox(height: 28),

          // ── 6. Translations ──
          _SectionTitle(
            title: isThai ? 'คำแปลอัลกุรอาน' : 'Translations',
            subtitle: isThai
                ? 'เลือกคำแปลหลักที่ใช้ในโหมดแอบดูและรายการอายะห์'
                : 'Select translation used during verse peek, reveal & list view.',
          ),
          const SizedBox(height: 12),
          const _TranslationSettingCard(),
          const SizedBox(height: 28),

          // ── 7. About App ──
          _SectionTitle(
            title: isThai ? 'เกี่ยวกับแอป' : 'About Hifz Quran',
            subtitle: isThai
                ? 'ข้อมูลแอปพลิเคชันสำหรับท่องจำอัลกุรอาน'
                : 'Application information and version.',
          ),
          const SizedBox(height: 12),
          const _AboutAppCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InputModeOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final HifzInputMode value;
  final HifzInputMode groupValue;
  final VoidCallback onSelect;

  const _InputModeOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.groupValue,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.18)
            : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.2),
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.12)
                        : colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BleDeviceManagementUI extends StatelessWidget {
  const BleDeviceManagementUI({super.key});

  @override
  Widget build(BuildContext context) {
    final bleProvider = Provider.of<BleRemoteProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    String statusText;
    Color statusColor;
    IconData statusIcon;

    final deviceName = (bleProvider.connectedDevice?.platformName.isNotEmpty == true)
        ? bleProvider.connectedDevice!.platformName
        : (bleProvider.savedDeviceName?.isNotEmpty == true
            ? bleProvider.savedDeviceName
            : null);

    final deviceId = bleProvider.connectedDevice?.remoteId.toString() ??
        bleProvider.savedDeviceId;

    switch (bleProvider.connectionState) {
      case BleConnectionState.disconnected:
        statusText = bleProvider.savedDeviceId != null ? 'Disconnected' : 'Not Connected';
        statusColor = colorScheme.onSurfaceVariant;
        statusIcon = Icons.bluetooth_disabled_rounded;
        break;
      case BleConnectionState.scanning:
        statusText = 'Scanning for rings...';
        statusColor = colorScheme.primary;
        statusIcon = Icons.bluetooth_searching_rounded;
        break;
      case BleConnectionState.connecting:
        statusText = 'Connecting...';
        statusColor = colorScheme.tertiary;
        statusIcon = Icons.bluetooth_connected_rounded;
        break;
      case BleConnectionState.connected:
        statusText = 'Connected to ${deviceName ?? 'Smart Ring'}';
        statusColor = colorScheme.primary;
        statusIcon = Icons.bluetooth_connected_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Smart Ring Management',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Supported devices: Smart Tasbih, Zikir Ring, Bluetooth Tasbih, iQibla Ring, etc.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusText,
                            style: textTheme.bodyMedium?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (deviceId != null && deviceId.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              deviceName != null && bleProvider.connectionState != BleConnectionState.connected
                                  ? 'Saved: $deviceName ($deviceId)'
                                  : 'Device ID: $deviceId',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (bleProvider.connectionState == BleConnectionState.connected)
                      OutlinedButton.icon(
                        onPressed: () => bleProvider.disconnect(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          side: BorderSide(color: colorScheme.error.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.link_off_rounded, size: 16),
                        label: const Text('Disconnect'),
                      )
                    else ...[
                      if (bleProvider.savedDeviceId != null &&
                          bleProvider.connectionState == BleConnectionState.disconnected) ...[
                        FilledButton.tonalIcon(
                          onPressed: () => bleProvider.connectToSavedDevice(),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          icon: const Icon(Icons.link_rounded, size: 16),
                          label: const Text('Connect Saved'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton.icon(
                        onPressed: bleProvider.connectionState == BleConnectionState.scanning
                            ? null
                            : () => bleProvider.startScan(),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: bleProvider.connectionState == BleConnectionState.scanning
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.search_rounded, size: 16),
                        label: Text(
                          bleProvider.connectionState == BleConnectionState.scanning
                              ? 'Scanning'
                              : 'Scan Devices',
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (bleProvider.scanResults.isNotEmpty && bleProvider.connectionState != BleConnectionState.connected) ...[
            const SizedBox(height: 12),
            Text(
              'Discovered Devices',
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...bleProvider.scanResults.map((result) {
              if (result.device.platformName.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    child: Icon(
                      Icons.watch_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    result.device.platformName,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    result.device.remoteId.toString(),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wifi_rounded,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${result.rssi} dBm',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => bleProvider.connectToDevice(result.device),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _InAppVolumeControlCard extends StatelessWidget {
  const _InAppVolumeControlCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = Provider.of<SettingsProvider>(context).languageCode == 'th';

    return Consumer<MushafAudioProvider>(
      builder: (context, audioProvider, _) {
        final volume = audioProvider.volume;
        final percentage = (volume * 100).round();

        IconData volumeIcon;
        if (volume == 0.0) {
          volumeIcon = Icons.volume_off_rounded;
        } else if (volume < 0.5) {
          volumeIcon = Icons.volume_down_rounded;
        } else {
          volumeIcon = Icons.volume_up_rounded;
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      volumeIcon,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isThai ? 'ระดับเสียงผู้อ่านอัลกุรอาน' : 'Reciter Playback Volume',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isThai
                              ? 'ปรับระดับเสียงของแอปโดยตรงเมื่อปุ่มเสียงของเครื่องถูกใช้เลื่อนอายะห์ในโหมดชัตเตอร์'
                              : 'Adjust app audio volume directly since hardware keys advance verses in shutter mode.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$percentage%',
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.volume_mute_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Slider(
                      value: volume,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) => audioProvider.setVolume(val),
                      activeColor: colorScheme.primary,
                    ),
                  ),
                  Icon(
                    Icons.volume_up_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DisplayLanguageSettingCard extends StatelessWidget {
  const _DisplayLanguageSettingCard();

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = settings.languageCode == 'th';

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          // Dark Mode
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                settings.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: colorScheme.primary,
                size: 20,
              ),
            ),
            title: Text(
              isThai ? 'โหมดมืด (Dark Mode)' : 'Dark Mode',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              isThai
                  ? 'ปรับธีมสีให้อ่านสบายตาในที่มืด'
                  : 'Use a darker color scheme for night recitation',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: settings.isDarkMode,
            activeThumbColor: colorScheme.primary,
            onChanged: (val) => settings.toggleDarkMode(val),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          // Keep Screen Awake
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.screen_lock_portrait_rounded,
                color: colorScheme.primary,
                size: 20,
              ),
            ),
            title: Text(
              isThai ? 'เปิดหน้าจอค้างไว้' : 'Keep Screen Awake',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              isThai
                  ? 'ป้องกันหน้าจอดับขณะท่องจำหรือทบทวน'
                  : 'Prevent screen from turning off during memorization',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: settings.keepAwake,
            activeThumbColor: colorScheme.primary,
            onChanged: (val) => settings.toggleKeepAwake(val),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          // App Language
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.language_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isThai ? 'ภาษาของแอป' : 'App Language',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isThai ? 'เลือกภาษาเมนูและข้อความ' : 'Choose interface language',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: settings.languageCode,
                  dropdownColor: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: 'en',
                      child: Text('English'),
                    ),
                    DropdownMenuItem(
                      value: 'th',
                      child: Text('ภาษาไทย'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) settings.setLanguageCode(val);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuranTextFontSettingCard extends StatelessWidget {
  const _QuranTextFontSettingCard();

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = settings.languageCode == 'th';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Arabic Font Size Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.format_size_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isThai ? 'ขนาดตัวอักษรอาหรับ' : 'Arabic Font Size',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${settings.arabicFontSize.round()} px',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.text_fields_rounded, size: 16, color: colorScheme.onSurfaceVariant),
              Expanded(
                child: Slider(
                  value: settings.arabicFontSize.clamp(20.0, 48.0),
                  min: 20.0,
                  max: 48.0,
                  onChanged: (val) => settings.setArabicFontSize(val),
                  activeColor: colorScheme.primary,
                ),
              ),
              Icon(Icons.text_fields_rounded, size: 24, color: colorScheme.onSurfaceVariant),
            ],
          ),
          // Arabic live preview box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: 'UthmanicHafs',
                fontSize: settings.arabicFontSize,
                color: colorScheme.onSurface,
                height: 1.8,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          // Translation Font Size Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.translate_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isThai ? 'ขนาดตัวอักษรคำแปล' : 'Translation Font Size',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${settings.translationFontSize.round()} px',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.text_fields_rounded, size: 16, color: colorScheme.onSurfaceVariant),
              Expanded(
                child: Slider(
                  value: settings.translationFontSize.clamp(12.0, 30.0),
                  min: 12.0,
                  max: 30.0,
                  onChanged: (val) => settings.setTranslationFontSize(val),
                  activeColor: colorScheme.primary,
                ),
              ),
              Icon(Icons.text_fields_rounded, size: 22, color: colorScheme.onSurfaceVariant),
            ],
          ),
          // Translation live preview box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              isThai
                  ? 'ด้วยพระนามของอัลลอฮ์ ผู้ทรงกรุณาปรานี ผู้ทรงเมตตาเสมอ'
                  : 'In the name of Allah, the Entirely Merciful, the Especially Merciful',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansThai(
                fontSize: settings.translationFontSize,
                color: colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 8),
          // Word-by-Word Switch
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              isThai ? 'คำต่อคำ (Word-by-Word) ในมุมมองรายการ' : 'Word-by-Word (WBW) in List View',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              isThai
                  ? 'แสดงคำแปลแยกทีละคำศัพท์ขณะเปิดดูรายการอายะห์'
                  : 'Show word-level breakdown and translations during memorization.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: settings.showWordByWord,
            activeThumbColor: colorScheme.primary,
            onChanged: (val) => settings.toggleShowWordByWord(val),
          ),
        ],
      ),
    );
  }
}

class _TranslationSettingCard extends StatelessWidget {
  const _TranslationSettingCard();

  void _openTranslationManagerModal(BuildContext context, SettingsProvider settings) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final isThai = settings.languageCode == 'th';
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (sheetCtx, scrollController) {
            return SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          isThai ? 'จัดการชุดคำแปล' : 'Manage Translations',
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: TranslationManagerSection(
                        colors: settings.getAppColors(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final transManager = Provider.of<TranslationManagerProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = settings.languageCode == 'th';

    final translationList = TranslationConstants.getAllOptions(
      downloadedTranslations: transManager.downloadedTranslations,
    );
    final currentPrimary = TranslationConstants.resolveTranslationId(settings.primaryTranslationId);
    final currentSelected = translationList.any((o) => o.id == settings.primaryTranslationId)
        ? settings.primaryTranslationId
        : (translationList.any((o) => o.id == currentPrimary) ? currentPrimary : 'thai_v3');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.translate_rounded,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isThai ? 'ภาษาของคำแปลหลัก' : 'Translation Language',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isThai
                          ? 'เลือกคำแปลที่ใช้ขณะแอบดูอายะห์และแสดงในรายการ'
                          : 'Select translation used during verse peek, reveal & list view.',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: currentSelected,
            decoration: InputDecoration(
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
            ),
            isExpanded: true,
            items: [
              ...translationList.map((opt) {
                final isDownloaded = transManager.isDownloaded(opt.id);
                return DropdownMenuItem<String>(
                  value: opt.id,
                  child: Row(
                    children: [
                      if (!isDownloaded) ...[
                        Icon(Icons.download_for_offline_outlined, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          isDownloaded
                              ? opt.displayName(settings.languageCode)
                              : '${opt.displayName(settings.languageCode)} (${settings.languageCode == 'th' ? 'แตะเพื่อโหลด' : 'Tap to download'})',
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: isDownloaded ? FontWeight.w500 : FontWeight.w600,
                            color: isDownloaded ? null : colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              DropdownMenuItem<String>(
                value: 'download_more',
                child: Text(
                  isThai ? '+ จัดการชุดคำแปลเพิ่มเติม...' : '+ Manage & Download More...',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
            onChanged: (val) async {
              if (val == null) return;
              if (val == 'download_more') {
                _openTranslationManagerModal(context, settings);
                return;
              }
              final opt = TranslationConstants.getKnownOption(val) ??
                  translationList.firstWhere(
                    (o) => o.id == val,
                    orElse: () => TranslationConstants.builtInThaiV3,
                  );
              if (transManager.isDownloaded(val)) {
                settings.updateTranslationSlot('primary', val);
                transManager.loadTranslationIntoCache(val);
              } else {
                await TranslationDownloadDialog.show(
                  context,
                  option: opt,
                  isPrimary: true,
                );
              }
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openTranslationManagerModal(context, settings),
              icon: const Icon(Icons.download_for_offline_outlined, size: 18),
              label: Text(
                isThai
                    ? 'จัดการและดาวน์โหลดชุดคำแปล'
                    : 'Manage & Download Translations',
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutAppCard extends StatelessWidget {
  const _AboutAppCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.psychology_rounded,
              color: colorScheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isThai ? 'ฮิฟซ์อัลกุรอาน (Hifz Quran)' : 'Hifz Quran App',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isThai
                      ? 'แอปเฉพาะทางสำหรับท่องจำและทบทวนอัลกุรอาน · เวอร์ชัน 1.0.0'
                      : 'Quran Memorization & Review · v1.0.0',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceRecitationSettingCard extends StatelessWidget {
  const _VoiceRecitationSettingCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        final isEnabled = settings.voiceRecitationEnabled;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isEnabled
                ? colorScheme.primaryContainer.withValues(alpha: 0.12)
                : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEnabled
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.2),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isEnabled
                          ? colorScheme.primary.withValues(alpha: 0.15)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.record_voice_over_rounded,
                      color: isEnabled
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Voice Recitation Tracking',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Offline AI',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Active during hidden stages (Review mode & cumulative repeat range in New Verses). Automatically reveals verses as you recite sequentially and alerts if a verse is skipped.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch.adaptive(
                    value: isEnabled,
                    onChanged: (val) => settings.setVoiceRecitationEnabled(val),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FeaturePill(
                    icon: Icons.offline_bolt_rounded,
                    label: '100% On-Device',
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                  _FeaturePill(
                    icon: Icons.warning_amber_rounded,
                    label: 'Skip Detection',
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                  _FeaturePill(
                    icon: Icons.mic_rounded,
                    label: 'In-Session Mic Toggle',
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                ],
              ),
              if (isEnabled) ...[
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: settings.voiceRecitationAdaptiveNoise
                            ? colorScheme.primary.withValues(alpha: 0.12)
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        color: settings.voiceRecitationAdaptiveNoise
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adaptive Noise Filter',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Auto-adapts breath detection in rooms with fans or air conditioning without distorting your recitation.',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch.adaptive(
                      value: settings.voiceRecitationAdaptiveNoise,
                      onChanged: (val) =>
                          settings.setVoiceRecitationAdaptiveNoise(val),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _FeaturePill({
    required this.icon,
    required this.label,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}