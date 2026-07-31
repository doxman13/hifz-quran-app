import 'dart:convert';
import 'dart:io';

void main() {
  final tajweedFile = File('assets/Tajweed/qpc-hafs-tajweed.json');
  final tajweedData = jsonDecode(tajweedFile.readAsStringSync());
  
  int mismatchCount = 0;
  
  for (int page = 1; page <= 604; page++) {
    final qcfFile = File('assets/qcf_v1_pages/page_$page.json');
    if (!qcfFile.existsSync()) continue;
    
    final qcfData = jsonDecode(qcfFile.readAsStringSync());
    final verses = qcfData['verses'] as List;
    
    for (final v in verses) {
      final verseKey = v['verse_key'];
      final qcfWords = (v['words'] as List).where((w) => w['char_type_name'] == 'word' || w['char_type_name'] == 'end').toList();
      
      final tajweedVerse = tajweedData[verseKey];
      if (tajweedVerse == null) {
        print('Missing Tajweed verse for $verseKey');
        mismatchCount++;
        continue;
      }
      
      final tajText = tajweedVerse['text'] as String;
      
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
      
      if (qcfWords.length != tajWords.length) {
        if (verseKey == '2:181' || verseKey == '8:6' || verseKey == '13:37') {
          for (int i = 0; i < tajWords.length - 1; i++) {
            if (tajWords[i].contains('عۡدَ') && tajWords[i+1].contains('مَا')) {
              tajWords[i] = tajWords[i] + ' ' + tajWords[i+1];
              tajWords.removeAt(i + 1);
              break;
            }
          }
        }
        
        if (tajWords.length > qcfWords.length && tajWords.contains('۩')) {
          final idx = tajWords.indexOf('۩');
          if (idx > 0) {
            tajWords[idx - 1] = tajWords[idx - 1] + ' ' + tajWords[idx];
            tajWords.removeAt(idx);
          }
        }
        
        if (qcfWords.length != tajWords.length) {
          print('STILL Mismatch in $verseKey: QCF=${qcfWords.length}, Taj=${tajWords.length}');
          mismatchCount++;
        }
      }
    }
  }
  print('Total mismatches: $mismatchCount');
}
