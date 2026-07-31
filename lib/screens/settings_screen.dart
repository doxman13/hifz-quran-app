import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/quran_repository.dart';
import '../providers/settings_provider.dart';
import '../services/remote_content_service.dart';
import '../theme/app_theme.dart';
import '../widgets/translation_manager_section.dart';
import '../shared/shared.dart';

class SettingsScreen extends StatefulWidget {
  final QuranRepository? repository;

  const SettingsScreen({Key? key, this.repository}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isCheckingContentUpdates = false;

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final colors = settings.getAppColors();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          context.tr('settings'),
          style: GoogleFonts.notoSansThai(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        backgroundColor: colorScheme.surfaceContainerLow,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: colorScheme.outline, width: 1)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          _buildSectionHeader(colorScheme, context.tr('display')),
          const SizedBox(height: 8),
          _SettingsCard(
            colorScheme: colorScheme,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: Text(
                    context.tr('dark_mode'),
                    style: GoogleFonts.notoSansThai(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  value: settings.isDarkMode,
                  onChanged: (val) => settings.toggleDarkMode(val),
                  activeColor: colorScheme.primary,
                ),
                Divider(height: 1, color: colorScheme.outline, thickness: 1),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: Text(
                    context.tr('keep_screen_awake'),
                    style: GoogleFonts.notoSansThai(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    context.tr('keep_screen_awake_desc'),
                    style: GoogleFonts.notoSansThai(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: settings.keepAwake,
                  onChanged: settings.toggleKeepAwake,
                  activeColor: colorScheme.primary,
                ),
                Divider(height: 1, color: colorScheme.outline, thickness: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: DropdownButtonFormField<String>(
                    value: settings.languageCode,
                    dropdownColor: colorScheme.surfaceContainerLow,
                    decoration: InputDecoration(
                      labelText: context.tr('language'),
                      labelStyle: GoogleFonts.notoSansThai(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        borderSide: BorderSide(
                          color: colorScheme.outline,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        borderSide: BorderSide(
                          color: colorScheme.outline,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        borderSide: BorderSide(
                          color: colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'th',
                        child: Text('ภาษาไทย (Thai)'),
                      ),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (val) {
                      if (val != null) settings.setLanguageCode(val);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(colorScheme, context.tr('reading_experience')),
          const SizedBox(height: 8),
          _SettingsCard(
            colorScheme: colorScheme,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.tr('arabic_font_size'),
                        style: GoogleFonts.notoSansThai(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${settings.arabicFontSize.toInt()} px',
                        style: GoogleFonts.notoSansThai(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: colorScheme.primary,
                      inactiveTrackColor: colorScheme.outline,
                      thumbColor: colorScheme.primary,
                      overlayColor: colorScheme.primary.withOpacity(0.1),
                    ),
                    child: Slider(
                      value: settings.arabicFontSize,
                      min: 18.0,
                      max: 48.0,
                      onChanged: (val) => settings.setArabicFontSize(val),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.tr('translation_font_size'),
                        style: GoogleFonts.notoSansThai(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${settings.translationFontSize.toInt()} px',
                        style: GoogleFonts.notoSansThai(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: colorScheme.primary,
                      inactiveTrackColor: colorScheme.outline,
                      thumbColor: colorScheme.primary,
                      overlayColor: colorScheme.primary.withOpacity(0.1),
                    ),
                    child: Slider(
                      value: settings.translationFontSize,
                      min: 12.0,
                      max: 32.0,
                      onChanged: (val) => settings.setTranslationFontSize(val),
                    ),
                  ),
                ],
              ),
            ),
          ),
          TranslationManagerSection(colors: colors),
          const SizedBox(height: 24),
          _buildContentUpdateSection(colorScheme),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ColorScheme colorScheme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.notoSansThai(
          color: colorScheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Future<void> _checkContentUpdates() async {
    setState(() => _isCheckingContentUpdates = true);
    try {
      final result = await RemoteContentService.instance.updateAll();
      if (result.updated > 0) {
        await widget.repository?.reloadRemoteContent();
      }
      if (!mounted) return;

      final message = result.hasFailures
          ? 'Updated ${result.updated}/${result.checked}. Failed: ${result.failedKeys.join(', ')}'
          : result.updated > 0
          ? 'Updated ${result.updated} content pack(s).'
          : 'All content is already up to date.';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not check content updates.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isCheckingContentUpdates = false);
      }
    }
  }

  Widget _buildContentUpdateSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(colorScheme, context.tr('content_updates')),
        const SizedBox(height: 8),
        _SettingsCard(
          colorScheme: colorScheme,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('remote_quran_content'),
                  style: GoogleFonts.notoSansThai(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('content_updates_desc'),
                  style: GoogleFonts.notoSansThai(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isCheckingContentUpdates
                        ? null
                        : _checkContentUpdates,
                    icon: _isCheckingContentUpdates
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.system_update_alt_rounded),
                    label: Text(
                      _isCheckingContentUpdates
                          ? context.tr('checking_updates')
                          : context.tr('check_now'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A flat M3-styled settings group container.
class _SettingsCard extends StatelessWidget {
  final ColorScheme colorScheme;
  final Widget child;
  const _SettingsCard({required this.colorScheme, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: colorScheme.outline, width: 1),
      ),
      child: child,
    );
  }
}
