import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../models/mushaf_models.dart';

class TajweedService {
  static final Map<int, Map<String, dynamic>> _dataByMushaf = {};
  
  static Future<void> load({int mushafId = 11}) async {
    if (_dataByMushaf.containsKey(mushafId)) return;
    try {
      final assetPath = mushafId == 21
          ? 'assets/Tajweed/qul-hafs-tajweed.json'
          : 'assets/Tajweed/qpc-hafs-tajweed.json';
      final jsonString = await rootBundle.loadString(assetPath);
      _dataByMushaf[mushafId] = jsonDecode(jsonString);
    } catch (e) {
      debugPrint("Error loading Tajweed JSON for mushaf $mushafId: $e");
    }
  }

  static String? getVerse(int surah, int ayah, {int mushafId = 11}) {
    final data = _dataByMushaf[mushafId] ?? _dataByMushaf[11];
    final text = data?['$surah:$ayah']?['text'] as String?;
    if (text == null) return null;
    return _normalizeTajweedText(text);
  }

  static String _normalizeTajweedText(String text) {
    var result = text;
    if (result.contains('</rule>')) {
      final shiftPattern = RegExp(r'([^\s<>\u064B-\u065F\u0670\u06D6-\u06ED])<rule class=([^>]+)>([\u064B-\u0652])([^<]*)</rule>');
      while (shiftPattern.hasMatch(result)) {
        result = result.replaceAllMapped(
          shiftPattern,
          (m) => '${m[1]}${m[3]}<rule class=${m[2]}>${m[4]}</rule>',
        );
      }
      final markPattern = RegExp(r'(<rule class=[^>]+>[^<]+)</rule>([\u064B-\u065F\u0670\u06D6-\u06ED]+)');
      while (markPattern.hasMatch(result)) {
        result = result.replaceAllMapped(
          markPattern,
          (m) => '${m[1]}${m[2]}</rule>',
        );
      }
    }
    if (result.contains('لۡأَ') ||
        result.contains('لْأَ') ||
        result.contains('لِأَدَمَ') ||
        result.contains('لِأَيَ')) {
      result = result
          .replaceAll('لِأَدَمَ', 'لِـَٔادَمَ')
          .replaceAll('لِأَيَ', 'لِـَٔايَ')
          .replaceAll('لۡأَخِر', 'لۡـَٰٔخِر')
          .replaceAll('لْأَخِر', 'لْـَٰٔخِر')
          .replaceAll('لۡأَيَ', 'لۡـَٰٔيَ')
          .replaceAll('لْأَيَ', 'لْـَٰٔيَ')
          .replaceAll('لۡأَزِف', 'لۡـَٰٔزِف')
          .replaceAll('لْأَزِف', 'لْـَٰٔزِف')
          .replaceAll('لۡأَصَال', 'لۡـَٰٔصَال')
          .replaceAll('لْأَصَال', 'لْـَٰٔصَال')
          .replaceAll('لۡأَنَ', 'لۡـَٰٔنَ')
          .replaceAll('لْأَنَ', 'لْـَٰٔنَ');
    }
    if (result.contains('ـ<rule') || result.contains('ـ\u0640\u0654')) {
      result = result
          .replaceAllMapped(
            RegExp(r'ـ<rule class=([^>]+)>[ـ\s]*[ٔء]([ًۭٗ][^\s<]*)</rule>'),
            (m) => 'ـٔ<rule class=${m[1]}>ـ${m[2]}</rule>',
          )
          .replaceAll('ـ\u0640\u0654', 'ـ\u0654');
    }
    if (result.contains('custom-alef-maksora')) {
      result = result
          .replaceAll('<rule class=madda_normal><rule class=custom-alef-maksora>ٰ</rule></rule>', '<rule class=madda_normal>ٰ</rule>')
          .replaceAllMapped(
            RegExp(r'<rule class=custom-alef-maksora>([^<]*)</rule>'),
            (m) => m[1] ?? '',
          );
    }
    if (result.contains('madda_normal')) {
      result = result
          .replaceAll('<rule class=madda_normal>ـٰ</rule>', '<rule class=madda_normal>ٰ</rule>')
          .replaceAll('<rule class=madda_normal>ىٰ‍</rule>‍', '<rule class=madda_normal>ٰ</rule>')
          .replaceAll('<rule class=madda_normal>ىٰ</rule>‍', '<rule class=madda_normal>ٰ</rule>')
          .replaceAll('<rule class=madda_normal>ىٰ‍</rule>', '<rule class=madda_normal>ٰ</rule>')
          .replaceAll('<rule class=madda_normal>ىٰ</rule>', '<rule class=madda_normal>ٰ</rule>')
          .replaceAll('<rule class=madda_normal>ٮٰ</rule>', '<rule class=madda_normal>ٰ</rule>')
          .replaceAll('<rule class=madda_normal>ٮ</rule>', '');
    }
    if (result.contains('ٮٰ') || result.contains('ٮ')) {
      result = result.replaceAll('ٮٰ', '<rule class=madda_normal>ٰ</rule>').replaceAll('ٮ', '');
    }
    if (result.contains('ـٰ')) {
      result = result.replaceAll('ـٰ', '<rule class=madda_normal>ٰ</rule>');
    }
    if (result.contains('\u200D')) {
      result = result.replaceAll('\u200D', '');
    }
    return result;
  }

  static MushafPage augmentMushafPage(MushafPage page, {int targetMushafId = 11}) {
    final data = _dataByMushaf[targetMushafId] ?? _dataByMushaf[11];
    if (data == null) return page;

    final newLines = <List<MushafWord>>[];
    final newVerses = <MushafVerse>[];
    final verseWordsMap = <String, List<MushafWord>>{};

    for (final verse in page.verses) {
      final tajText = getVerse(int.parse(verse.surahId), int.parse(verse.verseId), mushafId: targetMushafId);
      if (tajText == null) {
        verseWordsMap[verse.verseKey] = verse.words;
        continue;
      }
      
      final tajWords = _splitTajweed(tajText);
      final alignedTajWords = _alignTajweed(verse.verseKey, tajWords, verse.words.length);
      
      final newWords = <MushafWord>[];
      for (int i = 0; i < verse.words.length; i++) {
        final oldWord = verse.words[i];
        if (i < alignedTajWords.length) {
          final tajStr = alignedTajWords[i];
          final isLastWord = (i == verse.words.length - 1);
          final parts = isLastWord ? <MushafTajweedPart>[] : _parseTajweedParts(tajStr);
          newWords.add(MushafWord(
            text: isLastWord ? oldWord.text : _stripTags(tajStr),
            verseKey: oldWord.verseKey,
            lineNumber: oldWord.lineNumber,
            position: oldWord.position,
            tajweedParts: parts,
          ));
        } else {
          newWords.add(oldWord);
        }
      }
      verseWordsMap[verse.verseKey] = newWords;
      newVerses.add(MushafVerse(
        verseKey: verse.verseKey,
        surahId: verse.surahId,
        verseId: verse.verseId,
        words: newWords,
      ));
    }

    for (final line in page.lines) {
      final newLine = <MushafWord>[];
      for (final word in line) {
        final newVerseWords = verseWordsMap[word.verseKey];
        if (newVerseWords != null) {
          final newWord = newVerseWords.firstWhere((w) => w.position == word.position, orElse: () => word);
          newLine.add(newWord);
        } else {
          newLine.add(word);
        }
      }
      newLines.add(newLine);
    }

    return MushafPage(
      mushafId: targetMushafId, // Trigger Tajweed rendering in MushafLine
      pageNumber: page.pageNumber,
      verses: newVerses,
      lines: newLines,
    );
  }

  static List<String> _splitTajweed(String tajText) {
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

  static List<String> _alignTajweed(String verseKey, List<String> tajWords, int qcfLength) {
    if (tajWords.length == qcfLength) return tajWords;
    
    final List<String> result = List.from(tajWords);
    
    if (verseKey == '2:181' || verseKey == '8:6' || verseKey == '13:37') {
      for (int i = 0; i < result.length - 1; i++) {
        if (result[i].contains('عۡدَ') && result[i+1].contains('مَا')) {
          result[i] = '${result[i]} ${result[i+1]}';
          result.removeAt(i + 1);
          break;
        }
      }
    }
    
    if (result.length > qcfLength && result.contains('۩')) {
      final idx = result.indexOf('۩');
      if (idx > 0) {
        result[idx - 1] = '${result[idx - 1]} ${result[idx]}';
        result.removeAt(idx);
      }
    }
    
    return result;
  }

  static String _stripTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  static List<MushafTajweedPart> _parseTajweedParts(String wordStr) {
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
        final className = _extractClass(tag);
        classStack.add(className);
      }

      index = tagEnd + 1;
    }

    flushBuffer();
    return parts;
  }

  static String _extractClass(String tag) {
    final match = RegExp(r'''class\s*=\s*["']?([^"'>\s]+)''').firstMatch(tag);
    if (match != null) {
      return match.group(1)?.replaceAll("'", "").replaceAll('"', '').trim() ?? '';
    }
    return '';
  }
}
