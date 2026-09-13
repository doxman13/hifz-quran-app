import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Render exact comparison of shayan bug vs fix', () async {
    final fontData = File('assets/Tajweed/DigitalKhattQuranicV1.otf').readAsBytesSync();
    final fontLoader = FontLoader('Tajweed');
    fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
    await fontLoader.load();

    final testCases = <String, TextSpan>{
      'A. Current Bug in App (Hamza drowned on baseline):\n   شَيۡـ + ـًٔا': const TextSpan(
        children: [
          TextSpan(text: 'شَيۡـ', style: TextStyle(fontFamily: 'Tajweed', fontSize: 44, color: Colors.black)),
          TextSpan(text: 'ـًٔا', style: TextStyle(fontFamily: 'Tajweed', fontSize: 44, color: Color(0xFF169200))),
        ],
      ),
      'B. The Clean Fix (Hamza on tooth, Tanween colored):\n   شَيۡـٔ + ـًا': const TextSpan(
        children: [
          TextSpan(text: 'شَيۡـٔ', style: TextStyle(fontFamily: 'Tajweed', fontSize: 44, color: Colors.black)),
          TextSpan(text: 'ـًا', style: TextStyle(fontFamily: 'Tajweed', fontSize: 44, color: Color(0xFF169200))),
        ],
      ),
      'C. Full phrase: جِئۡتَ شَيۡـًٔا نُّكۡرًا (with fix)': const TextSpan(
        children: [
          TextSpan(text: 'جِئۡتَ شَيۡـٔ', style: TextStyle(fontFamily: 'Tajweed', fontSize: 38, color: Colors.black)),
          TextSpan(text: 'ـًا', style: TextStyle(fontFamily: 'Tajweed', fontSize: 38, color: Color(0xFF169200))),
          TextSpan(text: ' ', style: TextStyle(fontFamily: 'Tajweed', fontSize: 38, color: Colors.black)),
          TextSpan(text: 'ن', style: TextStyle(fontFamily: 'Tajweed', fontSize: 38, color: Color(0xFF169200))),
          TextSpan(text: 'ُّكۡرًا', style: TextStyle(fontFamily: 'Tajweed', fontSize: 38, color: Colors.black)),
        ],
      ),
    };

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 950, 600));
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 950, 600), bgPaint);

    double y = 40.0;
    for (final entry in testCases.entries) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: entry.key,
          style: const TextStyle(color: Colors.black87, fontSize: 16, fontFamily: 'Arial', height: 1.4),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(canvas, Offset(30, y));

      final arabicPainter = TextPainter(
        text: entry.value,
        textDirection: TextDirection.rtl,
      )..layout();
      arabicPainter.paint(canvas, Offset(560, y + 10));

      y += 180.0;
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(950, 600);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final outFile = File('C:/Users/E/.gemini/antigravity-cli/brain/c09a8df2-682b-4ce3-ba34-f609d8b6ae49/scratch/rendered_shayan_fix_clear.png');
    outFile.writeAsBytesSync(pngBytes);
    print("Rendered clear comparison successfully!");
  });
}
