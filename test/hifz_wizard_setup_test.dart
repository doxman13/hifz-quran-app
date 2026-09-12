import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_space/data/quran_foundation_repository.dart';
import 'package:hifz_space/data/quran_repository.dart';
import 'package:hifz_space/models/hifz_session_config.dart';
import 'package:hifz_space/screens/hifz_wizard_setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HifzWizardSetupScreen Initialization', () {
    test('Constructor sets default parameters correctly', () {
      final quranRepo = QuranRepository();
      final foundationRepo = QuranFoundationRepository();

      final screen = HifzWizardSetupScreen(
        quranRepository: quranRepo,
        foundationRepository: foundationRepo,
      );

      expect(screen.initialStep, 0);
      expect(screen.initialMode, isNull);
      expect(screen.initialSurah, isNull);
    });

    test('Constructor accepts pre-configured parameters', () {
      final quranRepo = QuranRepository();
      final foundationRepo = QuranFoundationRepository();

      final screen = HifzWizardSetupScreen(
        quranRepository: quranRepo,
        foundationRepository: foundationRepo,
        initialMode: HifzSessionType.review,
        initialSurah: 67,
        initialStartVerse: 1,
        initialEndVerse: 10,
        initialRepeatStart: 1,
        initialStep: 1,
      );

      expect(screen.initialMode, HifzSessionType.review);
      expect(screen.initialSurah, 67);
      expect(screen.initialStartVerse, 1);
      expect(screen.initialEndVerse, 10);
      expect(screen.initialRepeatStart, 1);
      expect(screen.initialStep, 1);
    });

    test('Constructor accepts multi-surah review range parameters', () {
      final quranRepo = QuranRepository();
      final foundationRepo = QuranFoundationRepository();

      final screen = HifzWizardSetupScreen(
        quranRepository: quranRepo,
        foundationRepository: foundationRepo,
        initialMode: HifzSessionType.review,
        initialStartSurah: 78,
        initialEndSurah: 114,
        initialStep: 1,
      );

      expect(screen.initialMode, HifzSessionType.review);
      expect(screen.initialStartSurah, 78);
      expect(screen.initialEndSurah, 114);
      expect(screen.initialStep, 1);
    });

    test('Constructor accepts page range review parameters', () {
      final quranRepo = QuranRepository();
      final foundationRepo = QuranFoundationRepository();

      final screen = HifzWizardSetupScreen(
        quranRepository: quranRepo,
        foundationRepository: foundationRepo,
        initialMode: HifzSessionType.review,
        initialStartPage: 582,
        initialEndPage: 604,
        initialStep: 1,
      );

      expect(screen.initialMode, HifzSessionType.review);
      expect(screen.initialStartPage, 582);
      expect(screen.initialEndPage, 604);
      expect(screen.initialStep, 1);
    });
  });
}
