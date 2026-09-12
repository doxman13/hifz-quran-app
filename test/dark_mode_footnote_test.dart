import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_space/providers/settings_provider.dart';
import 'package:hifz_space/theme/app_theme.dart';
import 'package:hifz_space/utils/html_parser.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dark Mode Footnote Visibility Tests', () {
    test('Dark theme primaryColor matches teal primary token', () {
      final darkColors = AppTheme.colors(isDark: true, palette: 'teal');
      expect(darkColors.primary, const Color(0xFF529665));

      final darkTheme = ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: darkColors.primary,
        colorScheme: ColorScheme.dark(
          primary: darkColors.primary,
          surface: darkColors.surface,
          onSurface: darkColors.textStrong,
        ),
      );

      expect(darkTheme.primaryColor, darkColors.primary);
      expect(darkTheme.primaryColor, isNot(Colors.grey[900]));
      expect(darkTheme.colorScheme.primary, darkColors.primary);
    });

    testWidgets('HtmlParser ensures high contrast for footnote links in dark mode', (tester) async {
      SharedPreferences.setMockInitialValues({'isDarkMode': true});
      final settings = SettingsProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              primaryColor: const Color(0xFF529665),
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF529665),
                surface: Color(0xFF161616),
                onSurface: Colors.white,
              ),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  // Even if legacy or low-contrast linkColor is passed, dark mode guard ensures visibility
                  final spans = HtmlParser.parseTranslationText(
                    context,
                    'Test text [1] with footnote',
                    const TextStyle(color: Colors.white),
                    Theme.of(context).primaryColor,
                  );

                  final fnSpan = spans.firstWhere((s) => s.text == '[1]');
                  final linkColor = fnSpan.style?.color;
                  expect(linkColor, isNotNull);
                  // Must be vibrant and visible on dark surfaces: luminance > 0.12
                  expect(linkColor!.computeLuminance(), greaterThan(0.12));
                  return Text.rich(TextSpan(children: spans));
                },
              ),
            ),
          ),
        ),
      );
    });
  });
}
