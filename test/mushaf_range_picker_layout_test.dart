import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_space/data/quran_foundation_repository.dart';
import 'package:hifz_space/data/quran_repository.dart';
import 'package:hifz_space/providers/settings_provider.dart';
import 'package:hifz_space/screens/hifz_mushaf_range_picker_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HifzMushafRangePicker Layout & Structure Tests', () {
    test('HifzMushafRangePickerResult stores selected range correctly', () {
      const result = HifzMushafRangePickerResult(
        surah: 2,
        startVerse: 1,
        endVerse: 5,
        page: 2,
      );

      expect(result.surah, 2);
      expect(result.startVerse, 1);
      expect(result.endVerse, 5);
      expect(result.page, 2);
    });

    testWidgets('Screen renders PageView inside Expanded and BottomBar below it without overlap', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      final quranRepo = QuranRepository();
      final foundationRepo = QuranFoundationRepository();

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            home: HifzMushafRangePickerScreen(
              quranRepository: quranRepo,
              foundationRepository: foundationRepo,
              initialSurah: 1,
              initialStartVerse: 1,
              initialEndVerse: 7,
              initialPage: 1,
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify layout: Scaffold -> SafeArea -> Column -> [Expanded(PageView), BottomBar]
      final columnFinder = find.byType(Column);
      expect(columnFinder, findsWidgets);

      // Verify Expanded wraps PageView
      final expandedFinder = find.ancestor(
        of: find.byType(PageView),
        matching: find.byType(Expanded),
      );
      expect(expandedFinder, findsOneWidget);

      // Verify bottom bar exists and contains collapse chevron
      final collapseIconFinder = find.byIcon(Icons.keyboard_arrow_down_rounded);
      expect(collapseIconFinder, findsOneWidget);

      // Tap collapse button to minimize the bar
      await tester.tap(collapseIconFinder);
      await tester.pumpAndSettle();

      // Now expand chevron should be visible
      final expandIconFinder = find.byIcon(Icons.keyboard_arrow_up_rounded);
      expect(expandIconFinder, findsOneWidget);

      // Tap expand to restore
      await tester.tap(expandIconFinder);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });
  });
}
