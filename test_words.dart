import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/Tajweed/qpc-hafs-tajweed.json');
  final jsonStr = file.readAsStringSync();
  final data = jsonDecode(jsonStr);
  
  final text = data['1:1']['text'] as String;
  // Replace space in rule tags to avoid splitting
  final safeText = text.replaceAll('<rule class=', '<rule_class=');
  final words = safeText.split(' ').map((w) => w.replaceAll('<rule_class=', '<rule class=')).toList();
  print('1:1 Tajweed words: ${words.length}');
  print(words);
}
