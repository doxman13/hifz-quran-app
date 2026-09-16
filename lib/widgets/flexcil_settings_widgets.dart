import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Flexcil-style warm golden-amber category section header.
class FlexcilSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final AppThemeColors? colors;

  const FlexcilSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amberColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFF8A6530);

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.notoSansThai(
              color: amberColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: GoogleFonts.notoSansThai(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Flexcil-style grouped card container with rounded corners and subtle border.
class FlexcilCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  const FlexcilCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? (isDark ? colorScheme.surface : colorScheme.surface),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.45),
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Segmented Pill Item data class.
class FlexcilPillItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const FlexcilPillItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// Flexcil-style segmented pill selector.
class FlexcilSegmentedPills<T> extends StatelessWidget {
  final List<FlexcilPillItem<T>> items;
  final T selectedValue;
  final ValueChanged<T> onSelected;

  const FlexcilSegmentedPills({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerHigh : const Color(0xFFF0EFE9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: items.map((item) {
          final isSelected = item.value == selectedValue;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(item.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? colorScheme.surfaceContainerHighest : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.icon != null) ...[
                      Icon(
                        item.icon,
                        size: 15,
                        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansThai(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected
                              ? (isDark ? colorScheme.primary : const Color(0xFF0E5B59))
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Flexcil-style font stepper with A- button, slider, A+ button, and px badge.
class FlexcilStepper extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  final String unit;

  const FlexcilStepper({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1.0,
    required this.onChanged,
    this.unit = 'px',
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: GoogleFonts.notoSansThai(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${value.toInt()} $unit',
                style: GoogleFonts.notoSansThai(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // A- button
            InkWell(
              onTap: () {
                final next = (value - step).clamp(min, max);
                onChanged(next);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 36,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  'A-',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            // Slider
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: colorScheme.primary,
                  inactiveTrackColor: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  thumbColor: colorScheme.primary,
                  overlayColor: colorScheme.primary.withValues(alpha: 0.12),
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: ((max - min) / step).round(),
                  onChanged: onChanged,
                ),
              ),
            ),
            // A+ button
            InkWell(
              onTap: () {
                final next = (value + step).clamp(min, max);
                onChanged(next);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 36,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  'A+',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Interactive live typography preview card.
class FlexcilLivePreview extends StatelessWidget {
  final double arabicFontSize;
  final double translationFontSize;
  final String readingDisplayMode;
  final bool isThai;

  const FlexcilLivePreview({
    super.key,
    required this.arabicFontSize,
    required this.translationFontSize,
    required this.readingDisplayMode,
    required this.isThai,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final showArabic = readingDisplayMode != 'translation_only';
    final showTranslation = readingDisplayMode != 'quran_only';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFFBF9F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.4),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isThai ? 'ตัวอย่างการอ่านจริง (LIVE PREVIEW)' : 'LIVE TYPOGRAPHY PREVIEW',
                style: GoogleFonts.notoSansThai(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF8A6530),
                ),
              ),
              Text(
                '1:1 Al-Fatihah',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (showArabic) ...[
            Text(
              'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: 'UthmanicHafs',
                fontSize: arabicFontSize,
                height: 1.9,
                color: colorScheme.onSurface,
              ),
            ),
          ],
          if (showArabic && showTranslation) const SizedBox(height: 8),
          if (showTranslation) ...[
            Text(
              isThai
                  ? 'ด้วยพระนามแห่งอัลลอฮฺ ผู้ทรงกรุณาปรานี ผู้ทรงเมตตาเสมอ'
                  : 'In the name of Allah, the Entirely Merciful, the Especially Merciful.',
              style: GoogleFonts.notoSansThai(
                fontSize: translationFontSize,
                height: 1.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Flexcil-style clean toggle tile.
class FlexcilToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const FlexcilToggleTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansThai(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: GoogleFonts.notoSansThai(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
