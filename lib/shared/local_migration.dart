import 'quran_contract.dart';

List<ReadingProfileInput> migrateLegacyProgress(
  Map<String, Map<String, Object?>> legacyProgress,
  String userId,
) {
  final rows = <String, ReadingProfileInput>{};

  for (final entry in legacyProgress.entries) {
    if (entry.key == 'Last Read' || entry.key == 'Audit Check') continue;

    final slug =
        normalizeLegacyProfileSlug(entry.key) ??
        slugifyReadingProfileName(entry.key);
    final surahId = entry.value['surahId']?.toString();
    final verseId = entry.value['verseId']?.toString();
    if (surahId == null || verseId == null) continue;

    final verseRef = toVerseRef(surahId, verseId);
    rows[slug] = ReadingProfileInput(
      userId: userId,
      name: slug == 'free_read' ? 'Free Read' : entry.key,
      slug: slug,
      start: toVerseRef(1, 1),
      current: verseRef,
    );
  }

  return rows.values.toList();
}

RecentReadingInput? migrateLegacyLastRead(
  Map<String, Map<String, Object?>> legacyProgress,
  String userId,
) {
  final lastRead = legacyProgress['Last Read'];
  final surahId = lastRead?['surahId']?.toString();
  final verseId = lastRead?['verseId']?.toString();
  if (surahId == null || verseId == null) return null;

  final verseRef = toVerseRef(surahId, verseId);
  return RecentReadingInput(
    userId: userId,
    surahId: verseRef.surahId,
    verseId: verseRef.verseId,
    verseKey: verseRef.verseKey,
  );
}

List<TadabburNoteInput> migrateLegacyPersonalNotes(
  Map<String, String> legacyNotes,
  String userId,
) {
  final notes = <TadabburNoteInput>[];

  for (final entry in legacyNotes.entries) {
    final verseRef = parseVerseKey(entry.key);
    final noteText = entry.value.trim();
    if (verseRef == null || noteText.isEmpty) continue;

    notes.add(
      TadabburNoteInput(
        userId: userId,
        surahId: verseRef.surahId,
        verseId: verseRef.verseId,
        verseKey: verseRef.verseKey,
        noteText: noteText,
        visibility: 'private',
        language: 'th',
      ),
    );
  }

  return notes;
}

String verseKeyFromMaybeIndex(String surahId, int verseIndex) {
  return createVerseKey(surahId, verseIndex + 1);
}
