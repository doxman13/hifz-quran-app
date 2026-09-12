import "package:hifz_space/providers/hifz_session_provider.dart";
import "package:hifz_space/screens/hifz_new_verses_setup_screen.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hifz_space/services/waqf_chunker_service.dart";
import "package:hifz_space/models/hifz_task.dart";

void main() {
  group("WaqfChunkerService Tests", () {
    test("Gate 1: Verses < 14 words are kept intact (not chunked)", () {
      // Verse 2:2 has 8 words and contains waqf marks
      const v2_2 = "ذَٰلِكَ ٱلْكِتَٰبُ لَا رَيْبَ ۛ فِيهِ ۛ هُدًى لِّلْمُتَّقِينَ ٢";
      final chunks = WaqfChunkerService.chunkVerse(
        surah: 2,
        verse: 2,
        verseText: v2_2,
      );

      expect(chunks.length, 1);
      expect(chunks.first.isWholeVerse, true);
      expect(chunks.first.chunkIndex, 1);
      expect(chunks.first.totalChunks, 1);
      expect(chunks.first.startWordPos, 1);
      expect(chunks.first.wordCount, 7);
    });

    test("Gate 1: Verse 2:162 (9 words with waqf mark) stays intact", () {
      const v2_162 = "خَٰلِدِينَ فِيهَا ۖ لَا يُخَفَّفُ عَنْهُمُ ٱلْعَذَابُ وَلَا هُمْ يُنظَرُونَ ١٦٢";
      final chunks = WaqfChunkerService.chunkVerse(
        surah: 2,
        verse: 162,
        verseText: v2_162,
      );

      expect(chunks.length, 1);
      expect(chunks.first.isWholeVerse, true);
      expect(chunks.first.wordCount, 9);
    });

    test("Gate 2 & 4: Ayatul Kursi (2:255 - 50 words) splits into balanced chunks without micro-fragments", () {
      const v2_255 = "ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلۡحَىُّ ٱلۡقَيُّومُۚ لَا تَأۡخُذُهُۥ سِنَةٞ وَلَا نَوۡمٞۚ لَّهُۥ مَا فِى ٱلسَّمَٰوٰتِ وَمَا فِى ٱلۡأَرۡضِۗ مَن ذَا ٱلَّذِى يَشۡفَعُ عِندَهُۥٓ إِلَّا بِإِذۡنِهِۦۚ يَعۡلَمُ مَا بَيۡنَ أَيۡدِيهِمۡ وَمَا خَلۡفَهُمۡۖ وَلَا يُحِيطُونَ بِشَىۡءٖ مِّنۡ عِلۡمِهِۦٓ إِلَّا بِمَا شَآءَۚ وَسِعَ كُرۡسِيُّهُ ٱلسَّمَٰوٰتِ وَٱلۡأَرۡضَۖ وَلَا يَـُٔودُهُۥ حِفۡظُهُمَاۚ وَهُوَ ٱلۡعَلِىُّ ٱلۡعَظِيمُ ٢٥٥";
      final chunks = WaqfChunkerService.chunkVerse(
        surah: 2,
        verse: 255,
        verseText: v2_255,
      );

      expect(chunks.length, greaterThan(1));
      expect(chunks.length, lessThanOrEqualTo(9));

      // Check contiguous word positions
      int expectedStart = 1;
      for (int i = 0; i < chunks.length; i++) {
        final c = chunks[i];
        expect(c.chunkIndex, i + 1);
        expect(c.totalChunks, chunks.length);
        expect(c.startWordPos, expectedStart);
        expect(c.endWordPos, greaterThanOrEqualTo(c.startWordPos));
        expect(c.wordCount, greaterThanOrEqualTo(5), reason: "Chunk ${c.chunkIndex} is too short (< 5 words)");
        expectedStart = c.endWordPos + 1;
      }
      expect(chunks.last.endWordPos, 50);
    });

    test("Gate 3: Long verse with NO waqf marks (2:164 - 43 words) splits by conjunctions", () {
      const v2_164 = "إِنَّ فِى خَلۡقِ ٱلسَّمَٰوٰتِ وَٱلۡأَرۡضِ وَٱخۡتِلَٰفِ ٱلَّيۡلِ وَٱلنَّهَارِ وَٱلۡفُلۡكِ ٱلَّتِى تَجۡرِى فِى ٱلۡبَحۡرِ بِمَا يَنفَعُ ٱلنَّاسَ وَمَآ أَنزَلَ ٱللَّهُ مِنَ ٱلسَّمَآءِ مِن مَّآءٖ فَأَحۡيَا بِهِ ٱلۡأَرۡضَ بَعۡدَ مَوۡتِهَا وَبَثَّ فِيهَا مِن كُلِّ دَآبَّةٖ وَتَصۡرِيفِ ٱلرِّيَٰحِ وَٱلسَّحَابِ ٱلۡمُسَخَّرِ بَيۡنَ ٱلسَّمَآءِ وَٱلۡأَرۡضِ لَأٓيَٰتٖ لِّقَوۡمٖ يَعۡقِلُونَ ١٦٤";
      final chunks = WaqfChunkerService.chunkVerse(
        surah: 2,
        verse: 164,
        verseText: v2_164,
      );

      expect(chunks.length, greaterThanOrEqualTo(3));
      for (final c in chunks) {
        expect(c.wordCount, greaterThanOrEqualTo(5));
      }
      expect(chunks.first.startWordPos, 1);
      expect(chunks.last.endWordPos, 43);
    });

    test("generateHifzRoutine: generates chunked progression and intra-verse links for long verses", () {
      const v2_255 = "ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلۡحَىُّ ٱلۡقَيُّومُۚ لَا تَأۡخُذُهُۥ سِنَةٞ وَلَا نَوۡمٞۚ لَّهُۥ مَا فِى ٱلسَّمَٰوٰتِ وَمَا فِى ٱلۡأَرۡضِۗ مَن ذَا ٱلَّذِى يَشۡفَعُ عِندَهُۥٓ إِلَّا بِإِذۡنِهِۦۚ يَعۡلَمُ مَا بَيۡنَ أَيۡدِيهِمۡ وَمَا خَلۡفَهُمۡۖ وَلَا يُحِيطُونَ بِشَىۡءٖ مِّنۡ عِلۡمِهِۦٓ إِلَّا بِمَا شَآءَۚ وَسِعَ كُرۡسِيُّهُ ٱلسَّمَٰوٰتِ وَٱلۡأَرۡضَۖ وَلَا يَـُٔودُهُۥ حِفۡظُهُمَاۚ وَهُوَ ٱلۡعَلِىُّ ٱلۡعَظِيمُ ٢٥٥";
      final chunks = WaqfChunkerService.chunkVerse(
        surah: 2,
        verse: 255,
        verseText: v2_255,
      );

      final tasks = generateHifzRoutine(
        255,
        255,
        255,
        verseChunksMap: {255: chunks},
      );

      expect(tasks, isNotEmpty);
      // Verify first task is chunk 1 visible
      expect(tasks.first.isChunk, true);
      expect(tasks.first.chunkIndex, 1);
      expect(tasks.first.mode, TextVisibilityMode.visible);
      expect(tasks.first.targetRepetitions, 10);

      // Verify second task is chunk 1 hidden
      expect(tasks[1].isChunk, true);
      expect(tasks[1].chunkIndex, 1);
      expect(tasks[1].mode, TextVisibilityMode.hidden);
      expect(tasks[1].targetRepetitions, 5);

      // Verify chunk 2 exists and has intra-verse cumulative link
      final intraLinks = tasks.where((t) => t.type == TaskType.cumulativeLink && t.verseNumbers.length == 1).toList();
      expect(intraLinks, isNotEmpty);
      expect(intraLinks.first.startWordPosition, 1);
    });

    test("HifzSessionProvider initializes with chunks and supports toggle", () {
      const v2_255 = "ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلۡحَىُّ ٱلۡقَيُّومُۚ لَا تَأۡخُذُهُۥ سِنَةٞ وَلَا نَوۡمٞۚ لَّهُۥ مَا فِى ٱلسَّمَٰوٰتِ وَمَا فِى ٱلۡأَرۡضِۗ مَن ذَا ٱلَّذِى يَشۡفَعُ عِندَهُۥٓ إِلَّا بِإِذۡنِهِۦۚ يَعۡلَمُ مَا بَيۡنَ أَيۡدِيهِمۡ وَمَا خَلۡفَهُمۡۖ وَلَا يُحِيطُونَ بِشَىۡءٖ مِّنۡ عِلۡمِهِۦٓ إِلَّا بِمَا شَآءَۚ وَسِعَ كُرۡسِيُّهُ ٱلسَّمَٰوٰتِ وَٱلۡأَرۡضَۖ وَلَا يَـُٔودُهُۥ حِفۡظُهُمَاۚ وَهُوَ ٱلۡعَلِىُّ ٱلۡعَظِيمُ ٢٥٥";
      final chunks = WaqfChunkerService.chunkVerse(
        surah: 2,
        verse: 255,
        verseText: v2_255,
      );

      final provider = HifzSessionProvider(
        surahNumber: 2,
        repeatStart: 255,
        startVerse: 255,
        endVerse: 255,
        chunkLongVerses: true,
        verseChunksMap: {255: chunks},
      );

      expect(provider.chunkLongVerses, true);
      expect(provider.tasks.first.isChunk, true);
      expect(provider.tasks.first.chunkIndex, 1);

      // Toggle off chunking
      provider.toggleChunkLongVerses(false);
      expect(provider.chunkLongVerses, false);
      expect(provider.tasks.first.isChunk, false);

      // Toggle back on
      provider.toggleChunkLongVerses(true);
      expect(provider.chunkLongVerses, true);
      expect(provider.tasks.first.isChunk, true);
    });

    test("NewVersesSetupResult preserves chunkLongVerses flag", () {
      const resultWithChunk = NewVersesSetupResult(
        surah: 2,
        repeatStart: 1,
        startVerse: 1,
        endVerse: 3,
        page: 1,
        isSurahMode: true,
        chunkLongVerses: true,
      );
      expect(resultWithChunk.chunkLongVerses, true);

      const resultWithoutChunk = NewVersesSetupResult(
        surah: 2,
        repeatStart: 1,
        startVerse: 1,
        endVerse: 3,
        page: 1,
        isSurahMode: true,
        chunkLongVerses: false,
      );
      expect(resultWithoutChunk.chunkLongVerses, false);
    });
  });
}

