import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../models/mushaf_models.dart';

class TajweedService {
  static Map<String, dynamic>? _data;
  
  static Future<void> load() async {
    if (_data != null) return;
    try {
      final jsonString = await rootBundle.loadString('assets/Tajweed/qpc-hafs-tajweed.json');
      _data = jsonDecode(jsonString);
    } catch (e) {
      debugPrint("Error loading Tajweed JSON: $e");
    }
  }

  static String? getVerse(int surah, int ayah) {
    return _data?['$surah:$ayah']?['text'];
  }

  static MushafPage augmentMushafPage(MushafPage page) {
    if (_data == null) return page;

    final newLines = <List<MushafWord>>[];
    final newVerses = <MushafVerse>[];
    final verseWordsMap = <String, List<MushafWord>>{};

    for (final verse in page.verses) {
      final tajText = getVerse(int.parse(verse.surahId), int.parse(verse.verseId));
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
      mushafId: 11, // Fake mushafId 11 to trigger Tajweed rendering in MushafLine
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
          result[i] = result[i] + ' ' + result[i+1];
          result.removeAt(i + 1);
          break;
        }
      }
    }
    
    if (result.length > qcfLength && result.contains('۩')) {
      final idx = result.indexOf('۩');
      if (idx > 0) {
        result[idx - 1] = result[idx - 1] + ' ' + result[idx];
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
    final regex = RegExp(r'<rule class=([^>]+)>([^<]+)</rule>|([^<]+)');
    final matches = regex.allMatches(wordStr);
    for (final match in matches) {
      if (match.group(1) != null) {
        final className = match.group(1)!.replaceAll("'", "").replaceAll('"', '').trim();
        parts.add(MushafTajweedPart(text: match.group(2)!, className: className));
      } else {
        parts.add(MushafTajweedPart(text: match.group(3)!, className: ''));
      }
    }
    return parts;
  }
}
