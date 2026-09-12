import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_space/data/quran_repository.dart';
import 'package:hifz_space/screens/hifz_review_setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HifzReviewSetupScreen Parameters', () {
    test('Constructor accepts initial parameters correctly', () {
      final repo = QuranRepository();
      final screen = HifzReviewSetupScreen(
        quranRepository: repo,
        initialStartSurah: 18,
        initialEndSurah: 18,
        initialVersesSurah: 18,
        initialVersesStart: 1,
        initialVersesEnd: 10,
        initialStartPage: 293,
        initialEndPage: 304,
        initialTabIndex: 0,
      );

      expect(screen.initialStartSurah, 18);
      expect(screen.initialEndSurah, 18);
      expect(screen.initialVersesSurah, 18);
      expect(screen.initialVersesStart, 1);
      expect(screen.initialVersesEnd, 10);
      expect(screen.initialStartPage, 293);
      expect(screen.initialEndPage, 304);
      expect(screen.initialTabIndex, 0);
    });

    test('Constructor accepts page-targeted parameters correctly', () {
      final repo = QuranRepository();
      final screen = HifzReviewSetupScreen(
        quranRepository: repo,
        initialStartPage: 50,
        initialEndPage: 50,
        initialTabIndex: 2,
      );

      expect(screen.initialStartPage, 50);
      expect(screen.initialEndPage, 50);
      expect(screen.initialTabIndex, 2);
    });
  });
}
