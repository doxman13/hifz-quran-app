import 'quran_contract.dart';

String formatVerseShareText(
  SharePayload payload,
  String option, {
  String language = 'th',
}) {
  final lines = <String>[
    '${payload.surahName} ${payload.surahId}:${payload.verseId}',
    '',
  ];
  final includeArabic =
      option == 'arabic_and_translation' ||
      option == 'arabic_translation_with_quick_note';
  final includeQuickNote =
      option == 'translation_with_quick_note' ||
      option == 'arabic_translation_with_quick_note';

  final arabic = payload.arabic?.trim();
  if (includeArabic && arabic != null && arabic.isNotEmpty) {
    lines
      ..add(arabic)
      ..add('');
  }

  lines.add(payload.translation.trim());

  final quickNote = payload.quickNote?.trim();
  if (includeQuickNote && quickNote != null && quickNote.isNotEmpty) {
    lines
      ..add('')
      ..add(language == 'th' ? 'บันทึกของฉัน:' : 'My note:')
      ..add(quickNote);
  }

  lines
    ..add('')
    ..add(language == 'th' ? 'อ่านต่อ:' : 'Read:')
    ..add(payload.url);

  return lines.join('\n');
}
