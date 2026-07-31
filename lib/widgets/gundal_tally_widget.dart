import 'package:flutter/material.dart';

class GundalTallyPainter extends CustomPainter {
  final int count;
  final Color color;
  final double strokeWidth;

  GundalTallyPainter({
    required this.count,
    required this.color,
    this.strokeWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    int fullBundles = count ~/ 5;
    int remainder = count % 5;

    double bundleWidth = 32.0;
    double bundleSpacing = 12.0;

    for (int b = 0; b < fullBundles; b++) {
      double startX = b * (bundleWidth + bundleSpacing);
      _drawBundle(canvas, paint, size, startX, bundleWidth, 5);
    }

    if (remainder > 0) {
      double startX = fullBundles * (bundleWidth + bundleSpacing);
      _drawBundle(canvas, paint, size, startX, bundleWidth, remainder);
    }
  }

  void _drawBundle(Canvas canvas, Paint paint, Size size, double startX, double bundleWidth, int strokeCount) {
    double topY = 4.0;
    double bottomY = size.height - 4.0;
    double verticalSpacing = bundleWidth / 4;

    int verticalLines = strokeCount > 4 ? 4 : strokeCount;
    for (int i = 0; i < verticalLines; i++) {
      double x = startX + (i + 0.5) * verticalSpacing;
      canvas.drawLine(Offset(x, topY), Offset(x, bottomY), paint);
    }

    if (strokeCount >= 5) {
      // 5th diagonal line crossing through 4 vertical lines (| | | | /)
      double slashStartX = startX;
      double slashEndX = startX + bundleWidth;
      canvas.drawLine(Offset(slashStartX, bottomY), Offset(slashEndX, topY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GundalTallyPainter oldDelegate) {
    return oldDelegate.count != count ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class GundalTallyWidget extends StatelessWidget {
  final int count;
  final Color? color;
  final double strokeWidth;
  final double height;

  const GundalTallyWidget({
    super.key,
    required this.count,
    this.color,
    this.strokeWidth = 3.0,
    this.height = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    int fullBundles = count ~/ 5;
    int remainder = count % 5;
    int totalGroups = fullBundles + (remainder > 0 ? 1 : 0);

    double bundleWidth = 32.0;
    double bundleSpacing = 12.0;
    double calculatedWidth = totalGroups == 0
        ? bundleWidth
        : (totalGroups * bundleWidth) + ((totalGroups - 1) * bundleSpacing);

    return CustomPaint(
      size: Size(calculatedWidth, height),
      painter: GundalTallyPainter(
        count: count,
        color: effectiveColor,
        strokeWidth: strokeWidth,
      ),
    );
  }
}
