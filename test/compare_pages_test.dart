import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_space/data/medina_mushaf_pages.dart';
import 'package:qcf_quran/qcf_quran.dart' as qcf;

void main() {
  test('Compare assets with qcf package', () {
    int mismatches = 0;
    for (int p = 1; p <= 604; p++) {
      final file = File('assets/qcf_v1_pages/page_$p.json');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final verses = (json['verses'] as List)
          .map((v) => v['verse_key'] as String)
          .toList();

      final firstKey = verses.first;
      final lastKey = verses.last;

      final qcfItems = qcf.getPageData(p);
      final qcfFirstSurah = qcfItems.first['surah'];
      final qcfFirstStart = qcfItems.first['start'];
      final qcfLastSurah = qcfItems.last['surah'];
      final qcfLastEnd = qcfItems.last['end'];

      final expectedFirstKey = '$qcfFirstSurah:$qcfFirstStart';
      final expectedLastKey = '$qcfLastSurah:$qcfLastEnd';

      if (firstKey != expectedFirstKey || lastKey != expectedLastKey) {
        mismatches++;
      }
    }
    expect(mismatches, 36);
  });

  test('Verify medinaMushafPages matches assets 100% across all 604 pages', () {
    for (int p = 1; p <= 604; p++) {
      final file = File('assets/qcf_v1_pages/page_$p.json');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final verses = (json['verses'] as List)
          .map((v) => v['verse_key'] as String)
          .toList();

      final firstKey = verses.first;
      final lastKey = verses.last;

      final medinaItems = getMedinaMushafPageData(p);
      expect(medinaItems.isNotEmpty, true, reason: 'Page $p data empty');

      final medinaFirstSurah = medinaItems.first['surah'];
      final medinaFirstStart = medinaItems.first['start'];
      final medinaLastSurah = medinaItems.last['surah'];
      final medinaLastEnd = medinaItems.last['end'];

      expect('$medinaFirstSurah:$medinaFirstStart', firstKey,
          reason: 'Page $p first verse mismatch');
      expect('$medinaLastSurah:$medinaLastEnd', lastKey,
          reason: 'Page $p last verse mismatch');

      for (final key in verses) {
        final parts = key.split(':');
        final s = int.parse(parts[0]);
        final v = int.parse(parts[1]);
        expect(getMedinaMushafPageNumber(s, v), p,
            reason: 'Verse $s:$v page lookup mismatch');
      }
    }
  });
}

