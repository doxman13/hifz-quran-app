// lib/widgets/mushaf_page_skeleton.dart
//
// Modern Material 3 Shimmer Skeleton for Mushaf Pages.
// Prevents harsh flashes and layout popping during page fetching and buffering
// by mimicking the authentic 15-line Quran page geometry.

import 'package:flutter/material.dart';

class MushafPageSkeleton extends StatefulWidget {
  final bool showHeader;
  final double? width;

  const MushafPageSkeleton({
    super.key,
    this.showHeader = true,
    this.width,
  });

  @override
  State<MushafPageSkeleton> createState() => _MushafPageSkeletonState();
}

class _MushafPageSkeletonState extends State<MushafPageSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Realistic relative line widths mimicking a standard Madani 15-line Mushaf page
  static const List<double> _lineWidthFractions = [
    0.85, // Line 1 (Often surah start / bismillah)
    0.98, // Line 2
    0.95, // Line 3
    0.97, // Line 4
    0.92, // Line 5
    0.96, // Line 6
    0.94, // Line 7
    0.97, // Line 8
    0.95, // Line 9
    0.93, // Line 10
    0.98, // Line 11
    0.94, // Line 12
    0.96, // Line 13
    0.92, // Line 14
    0.70, // Line 15 (Page ending verse)
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final highlightColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.75);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final shimmerValue = _controller.value;
        return Center(
          child: Container(
            width: widget.width ?? 380,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Top Header Placeholder (Surah name / Juz)
                if (widget.showHeader) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildShimmerBlock(64, 12, shimmerValue, baseColor, highlightColor),
                      _buildShimmerBlock(48, 12, shimmerValue, baseColor, highlightColor),
                      _buildShimmerBlock(64, 12, shimmerValue, baseColor, highlightColor),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Surah Decorative Frame placeholder
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: _buildShimmerBlock(
                          120, 14, shimmerValue, baseColor, highlightColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 15 Classic Mushaf Lines
                for (int i = 0; i < _lineWidthFractions.length; i++) ...[
                  Align(
                    alignment: Alignment.center,
                    child: _buildShimmerLine(
                      _lineWidthFractions[i],
                      shimmerValue,
                      baseColor,
                      highlightColor,
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Bottom Page Number Placeholder
                _buildShimmerBlock(28, 12, shimmerValue, baseColor, highlightColor),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerBlock(
    double width,
    double height,
    double progress,
    Color baseColor,
    Color highlightColor,
  ) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [baseColor, highlightColor, baseColor],
          stops: [
            (progress - 0.3).clamp(0.0, 1.0),
            progress.clamp(0.0, 1.0),
            (progress + 0.3).clamp(0.0, 1.0),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerLine(
    double widthFraction,
    double progress,
    Color baseColor,
    Color highlightColor,
  ) {
    return FractionallySizedBox(
      widthFactor: widthFraction,
      child: Container(
        height: 16,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [baseColor, highlightColor, baseColor],
            stops: [
              (progress - 0.3).clamp(0.0, 1.0),
              progress.clamp(0.0, 1.0),
              (progress + 0.3).clamp(0.0, 1.0),
            ],
          ),
        ),
      ),
    );
  }
}
