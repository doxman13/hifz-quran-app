import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_space/models/mushaf_models.dart';

void main() {
  test('Test Tajweed parsing on updated verse 16:122', () {
    final rawText = 'وَءَاتَيۡنَ<rule class=madda_normal>ٰ</rule>هُ فِى <rule class=ham_wasl>ٱ</rule><rule class=laam_shamsiyah>ل</rule>دُّنۡيَا حَسَنَ<rule class=idgham_ghunnah>ةً‌ۖ</rule> <rule class=idgham_ghunnah>و</rule>َإِ<rule class=ghunnah>نّ</rule>َهُ<rule class=madda_normal>ۥ</rule> فِى <rule class=ham_wasl>ٱ</rule>لۡـَٰٔخِرَةِ لَمِنَ <rule class=ham_wasl>ٱ</rule><rule class=laam_shamsiyah>ل</rule>صَّ<rule class=madda_normal>ٰ</rule>لِح<rule class=madda_permissible>ِي</rule>نَ ١٢٢';
    
    // Simulate words split
    List<String> splitTajweed(String tajText) {
      List<String> tajWords = [];
      StringBuffer currentWord = StringBuffer();
      bool insideTag = false;
      for (int i = 0; i < tajText.length; i++) {
        if (tajText[i] == '<') insideTag = true;
        if (tajText[i] == '>') insideTag = false;
        
        if (tajText[i] == ' ' && !insideTag) {
          if (currentWord.isNotEmpty) {
            tajWords.add(currentWord.toString());
            currentWord.clear();
          }
        } else {
          currentWord.write(tajText[i]);
        }
      }
      if (currentWord.isNotEmpty) tajWords.add(currentWord.toString());
      return tajWords;
    }

    String extractClass(String tag) {
      final match = RegExp(r'''class\s*=\s*["']?([^"'>\s]+)''').firstMatch(tag);
      if (match != null) {
        return match.group(1)?.replaceAll("'", "").replaceAll('"', '').trim() ?? '';
      }
      return '';
    }

    List<MushafTajweedPart> parseTajweedParts(String wordStr) {
      final parts = <MushafTajweedPart>[];
      final classStack = <String>[];
      var buffer = StringBuffer();
      var bufferClass = '';

      String activeClass() => classStack.isEmpty ? '' : classStack.last;

      void flushBuffer() {
        if (buffer.isEmpty) return;
        parts.add(MushafTajweedPart(
          text: buffer.toString(),
          className: bufferClass,
        ));
        buffer = StringBuffer();
      }

      var index = 0;
      while (index < wordStr.length) {
        final tagStart = wordStr.indexOf('<', index);
        if (tagStart == -1) {
          final text = wordStr.substring(index);
          final nextClass = activeClass();
          if (buffer.isNotEmpty && bufferClass != nextClass) {
            flushBuffer();
          }
          bufferClass = nextClass;
          buffer.write(text);
          break;
        }

        if (tagStart > index) {
          final text = wordStr.substring(index, tagStart);
          final nextClass = activeClass();
          if (buffer.isNotEmpty && bufferClass != nextClass) {
            flushBuffer();
          }
          bufferClass = nextClass;
          buffer.write(text);
        }

        final tagEnd = wordStr.indexOf('>', tagStart + 1);
        if (tagEnd == -1) {
          break;
        }

        final tag = wordStr.substring(tagStart + 1, tagEnd).trim();
        if (tag.startsWith('/')) {
          if (classStack.isNotEmpty) classStack.removeLast();
        } else if (!tag.startsWith('img') && !tag.endsWith('/')) {
          final className = extractClass(tag);
          classStack.add(className);
        }

        index = tagEnd + 1;
      }

      flushBuffer();
      return parts;
    }

    final words = splitTajweed(rawText);
    expect(words.length, 10);
    print('Words: $words');

    final alAkhirahWord = words[6]; // <rule class=ham_wasl>ٱ</rule>لۡـَٰٔخِرَةِ
    final parts = parseTajweedParts(alAkhirahWord);
    print('Parts for al-akhirah:');
    for (final p in parts) {
      print('  "${p.text}" (class: "${p.className}")');
    }

    expect(parts.length, 2);
    expect(parts[0].text, 'ٱ');
    expect(parts[0].className, 'ham_wasl');
    expect(parts[1].text, 'لۡـَٰٔخِرَةِ');
    expect(parts[1].className, '');
  });

  test('Test qul-hafs-tajweed.json file contains all 6236 verses', () {
    final file = File('assets/Tajweed/qul-hafs-tajweed.json');
    expect(file.existsSync(), true);
    final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(jsonMap.length, 6236);

    final v16_122 = jsonMap['16:122'];
    expect(v16_122 != null, true);
    final text16 = v16_122['text'] as String;
    expect(text16.contains('لۡـَٔاخِرَةِ') || text16.contains('لۡـَٰٔخِرَةِ'), true);

    final v18_74 = jsonMap['18:74'];
    expect(v18_74 != null, true);
    final text18 = v18_74['text'] as String;
    expect(text18.contains('شَيۡـٔ<rule') || text18.contains('شَيۡـًٔا'), true);
  });
}
