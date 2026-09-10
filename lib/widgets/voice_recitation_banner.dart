import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recitation_event.dart';
import '../providers/recitation_tracker_provider.dart';
import '../providers/settings_provider.dart';

class VoiceRecitationBanner extends StatelessWidget {
  final RecitationTrackerProvider tracker;
  final VoidCallback onToggleMic;
  final VoidCallback onDismissAlert;
  final void Function(int ayah)? onRetryVerse;
  final void Function(int fromAyah, int toAyah)? onAcceptSkip;
  final VoidCallback? onSkipOrRevealNextVerse;
  final bool isCurrentVerseHinted;

  const VoiceRecitationBanner({
    super.key,
    required this.tracker,
    required this.onToggleMic,
    required this.onDismissAlert,
    this.onRetryVerse,
    this.onAcceptSkip,
    this.onSkipOrRevealNextVerse,
    this.isCurrentVerseHinted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // 1. If a verse skip was detected, show the high-priority Alert Banner
    if (tracker.skippedFromAyah != null && tracker.skippedToAyah != null) {
      final fromAyah = tracker.skippedFromAyah!;
      final toAyah = tracker.skippedToAyah!;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.error.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.error.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: colorScheme.error,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ayah Skipped?',
                        style: textTheme.titleSmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Expected Verse $fromAyah, but heard Verse $toAyah.',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onErrorContainer.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: colorScheme.onErrorContainer, size: 20),
                  onPressed: onDismissAlert,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Stay on Verse $fromAyah',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Primary Action: Stay / Retry the expected verse
                FilledButton.tonalIcon(
                  onPressed: () {
                    if (onRetryVerse != null) {
                      onRetryVerse!(fromAyah);
                    } else {
                      onDismissAlert();
                    }
                  },
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: Text('Stay on Verse $fromAyah'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.surface,
                    foregroundColor: colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                if (onAcceptSkip != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => onAcceptSkip!(fromAyah, toAyah),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: Text('Jump to V$toAyah'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    // 2. Engine Error Banner
    if (tracker.errorMessage != null) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.error.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Voice Tracking Error',
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tracker.errorMessage!,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: colorScheme.onErrorContainer, size: 20),
              onPressed: onDismissAlert,
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
            ),
          ],
        ),
      );
    }

    // 3. Normal Status / Audio Level Visualizer Bar
    final isListening = tracker.isListening;
    final isProcessing = tracker.status == RecitationStatus.processing;
    final isMatched = tracker.status == RecitationStatus.matched;

    final Color statusColor;
    final IconData statusIcon;
    final String statusText;
    final String statusSubtext;

    if (!isListening) {
      statusColor = colorScheme.onSurfaceVariant;
      statusIcon = Icons.mic_off_rounded;
      statusText = 'Voice Tracking Paused';
      statusSubtext = 'Tap mic to resume on-device listening';
    } else if (isProcessing) {
      statusColor = colorScheme.secondary;
      statusIcon = Icons.sync_rounded;
      statusText = 'Analyzing Recitation...';
      statusSubtext = 'FastConformer CTC neural engine running';
    } else if (isMatched) {
      statusColor = Colors.teal;
      statusIcon = Icons.check_circle_rounded;
      statusText = 'Verse ${tracker.lastMatchedAyah} Matched!';
      statusSubtext = tracker.lastRecognizedText != null
          ? tracker.lastRecognizedText!
          : 'Revealing verse on screen...';
    } else {
      statusColor = colorScheme.primary;
      statusIcon = Icons.mic_rounded;
      statusText = 'Listening for Verse ${tracker.currentExpectedAyah}';
      statusSubtext = 'Recite the verse to reveal it automatically';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isListening
              ? statusColor.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.25),
          width: 1.0,
        ),
        boxShadow: [
          if (isListening && tracker.audioLevel > 0.1)
            BoxShadow(
              color: statusColor.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(
        children: [
          // Audio level pulsing mic indicator
          _AudioLevelIndicator(
            audioLevel: tracker.audioLevel,
            color: statusColor,
            icon: statusIcon,
            isProcessing: isProcessing,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        statusText,
                        style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _SensitivityPill(
                      sensitivity: tracker.sensitivity,
                      onTap: () => showSensitivitySheet(context, tracker),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  statusSubtext,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isListening && onSkipOrRevealNextVerse != null) ...[
            FilledButton.tonalIcon(
              onPressed: onSkipOrRevealNextVerse,
              icon: Icon(
                isCurrentVerseHinted ? Icons.arrow_forward_rounded : Icons.lightbulb_outline_rounded,
                size: 14,
              ),
              label: Text(
                isCurrentVerseHinted
                    ? 'V${tracker.currentExpectedAyah} Skip >'
                    : 'V${tracker.currentExpectedAyah} Hint',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: isCurrentVerseHinted
                    ? colorScheme.errorContainer.withValues(alpha: 0.8)
                    : colorScheme.primaryContainer.withValues(alpha: 0.85),
                foregroundColor: isCurrentVerseHinted
                    ? colorScheme.onErrorContainer
                    : colorScheme.onPrimaryContainer,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isCurrentVerseHinted
                        ? colorScheme.error.withValues(alpha: 0.35)
                        : colorScheme.primary.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onToggleMic,
              onLongPress: () => showSensitivitySheet(context, tracker),
              child: Tooltip(
                message: isListening
                    ? 'Tap to pause, hold for sensitivity'
                    : 'Tap to resume, hold for sensitivity',
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    isListening ? Icons.mic_rounded : Icons.mic_off_rounded,
                    color: isListening ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Displays an M3 bottom sheet allowing the user to switch detection sensitivity modes on the fly.
  static void showSensitivitySheet(
    BuildContext context,
    RecitationTrackerProvider tracker, {
    void Function(RecitationSensitivity)? onSensitivityChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.tune_rounded, color: colorScheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Voice Tracking Precision',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Select the detection sensitivity that matches your recitation pace and style.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _SensitivityOptionTile(
                  title: 'Quick Recap',
                  arabicTitle: 'Hadr · حدر',
                  description: 'Forgiving match for rapid review & whispered recitation.',
                  icon: Icons.bolt_rounded,
                  iconColor: Colors.amber.shade700,
                  isSelected: tracker.sensitivity == RecitationSensitivity.quickRecap,
                  onTap: () {
                    _selectSensitivity(
                      sheetContext,
                      tracker,
                      RecitationSensitivity.quickRecap,
                      onSensitivityChanged,
                    );
                  },
                ),
                const SizedBox(height: 8),
                _SensitivityOptionTile(
                  title: 'Balanced',
                  arabicTitle: 'Tadweer · تدوير',
                  description: 'Smart adaptive tracking for regular memorization (recommended).',
                  icon: Icons.balance_rounded,
                  iconColor: colorScheme.primary,
                  isSelected: tracker.sensitivity == RecitationSensitivity.balanced,
                  onTap: () {
                    _selectSensitivity(
                      sheetContext,
                      tracker,
                      RecitationSensitivity.balanced,
                      onSensitivityChanged,
                    );
                  },
                ),
                const SizedBox(height: 8),
                _SensitivityOptionTile(
                  title: 'Strict Exam',
                  arabicTitle: 'Tahqeeq · تحقيق',
                  description: 'High precision testing, requires clear articulation and verse endings.',
                  icon: Icons.verified_rounded,
                  iconColor: Colors.teal,
                  isSelected: tracker.sensitivity == RecitationSensitivity.strict,
                  onTap: () {
                    _selectSensitivity(
                      sheetContext,
                      tracker,
                      RecitationSensitivity.strict,
                      onSensitivityChanged,
                    );
                  },
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                ),
                const SizedBox(height: 12),
                StatefulBuilder(
                  builder: (ctx, setLocalState) {
                    final isAdaptive = tracker.adaptiveNoise;
                    return Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isAdaptive
                                ? colorScheme.primary.withValues(alpha: 0.35)
                                : colorScheme.outlineVariant.withValues(alpha: 0.25),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: (isAdaptive ? colorScheme.primary : colorScheme.onSurfaceVariant)
                                    .withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.graphic_eq_rounded,
                                color: isAdaptive ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Adaptive Noise Filter',
                                    style: textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Adapts pause detection to fans & AC without clipping voice or Madd.',
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
                              value: isAdaptive,
                              onChanged: (val) {
                                setLocalState(() {
                                  tracker.setAdaptiveNoise(val);
                                  try {
                                    final settings = Provider.of<SettingsProvider>(context, listen: false);
                                    settings.setVoiceRecitationAdaptiveNoise(val);
                                  } catch (_) {}
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void _selectSensitivity(
    BuildContext context,
    RecitationTrackerProvider tracker,
    RecitationSensitivity sensitivity,
    void Function(RecitationSensitivity)? onSensitivityChanged,
  ) {
    tracker.setSensitivity(sensitivity);
    try {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      settings.setVoiceRecitationSensitivity(sensitivity);
    } catch (_) {}
    onSensitivityChanged?.call(sensitivity);
    Navigator.of(context).pop();
  }
}

class _AudioLevelIndicator extends StatelessWidget {
  final double audioLevel;
  final Color color;
  final IconData icon;
  final bool isProcessing;

  const _AudioLevelIndicator({
    required this.audioLevel,
    required this.color,
    required this.icon,
    required this.isProcessing,
  });

  @override
  Widget build(BuildContext context) {
    // Dynamic scale based on mic audio input energy
    final scale = 1.0 + (audioLevel * 0.35).clamp(0.0, 0.35);

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 100),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: 0.3 + (audioLevel * 0.5)),
            width: 1.5,
          ),
        ),
        child: isProcessing
            ? Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                ),
              )
            : Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: color,
                ),
              ),
      ),
    );
  }
}

class _SensitivityPill extends StatelessWidget {
  final RecitationSensitivity sensitivity;
  final VoidCallback onTap;

  const _SensitivityPill({
    required this.sensitivity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final IconData icon;
    final String label;
    final Color badgeColor;

    switch (sensitivity) {
      case RecitationSensitivity.quickRecap:
        icon = Icons.bolt_rounded;
        label = 'Quick';
        badgeColor = Colors.amber.shade700;
        break;
      case RecitationSensitivity.strict:
        icon = Icons.verified_rounded;
        label = 'Strict';
        badgeColor = Colors.teal;
        break;
      case RecitationSensitivity.balanced:
        icon = Icons.balance_rounded;
        label = 'Balanced';
        badgeColor = colorScheme.primary;
        break;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: badgeColor.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: badgeColor),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 1),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SensitivityOptionTile extends StatelessWidget {
  final String title;
  final String arabicTitle;
  final String description;
  final IconData icon;
  final Color iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _SensitivityOptionTile({
    required this.title,
    required this.arabicTitle,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.6)
                  : colorScheme.outlineVariant.withValues(alpha: 0.25),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '($arabicTitle)',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'UthmanicHafs',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 20)
              else
                Icon(Icons.radio_button_unchecked_rounded,
                    color: colorScheme.outlineVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
