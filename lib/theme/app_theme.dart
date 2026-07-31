import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Clean, modern Material 3 design system tokens matching thai-quran-web (iQra Foundation).
class AppThemeColors {
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color borderSoft;
  final Color foreground;
  final Color textStrong;
  final Color textInverse;
  final Color primary;
  final Color primaryHover;
  final Color primaryLight;
  final Color primaryLightBorder;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;

  const AppThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.borderSoft,
    required this.foreground,
    required this.textStrong,
    required this.textInverse,
    required this.primary,
    required this.primaryHover,
    required this.primaryLight,
    required this.primaryLightBorder,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
  });

  /// Official Teal palette (iQra foundation: warm paper, deep teal, and quiet gold).
  factory AppThemeColors.teal({required bool isDark}) {
    if (isDark) {
      return const AppThemeColors(
        background: Color(0xFF0D0D0D),
        surface: Color(0xFF161616),
        surfaceMuted: Color(0xFF1C1C1C),
        borderSoft: Color(0xFF2C2C2C),
        foreground: Color(0xFFD1D5DB),
        textStrong: Color(0xFFFFFFFF),
        textInverse: Color(0xFF0D0D0D),
        primary: Color(0xFF529665),
        primaryHover: Color(0xFF407D51),
        primaryLight: Color(0xFF122016),
        primaryLightBorder: Color(0xFF1E3625),
        accent: Color(0xFF78BD8C),
        success: Color(0xFF78BD8C),
        warning: Color(0xFFE2A65C),
        danger: Color(0xFFE68585),
      );
    }
    return const AppThemeColors(
      background: Color(0xFFF5F4EE),
      surface: Color(0xFFFFFDF9),
      surfaceMuted: Color(0xFFEEEEEE),
      borderSoft: Color(0xFFD9DDD4),
      foreground: Color(0xFF3F4F4A),
      textStrong: Color(0xFF123B3C),
      textInverse: Color(0xFFFFFDF9),
      primary: Color(0xFF0E5B59),
      primaryHover: Color(0xFF084645),
      primaryLight: Color(0xFFE3EFEB),
      primaryLightBorder: Color(0xFFC3D9D1),
      accent: Color(0xFFC59A52),
      success: Color(0xFF2F8877),
      warning: Color(0xFFB77C32),
      danger: Color(0xFFB55454),
    );
  }
}

class AppTheme {
  /// Standard geometry radius for soft modern M3 containers (16.0px)
  static const radius = 16.0;

  static Future<void> prewarmFonts() async {
    try {
      final fontLoader = FontLoader('UthmanicHafs');
      fontLoader.addFont(rootBundle.load('assets/fonts/UthmanicHafs.ttf'));
      await fontLoader.load();
    } catch (e) {
      debugPrint('Error pre-warming UthmanicHafs font: $e');
    }
  }

  /// Returns the theme color tokens. Forced to Teal (the web app active theme).
  static AppThemeColors colors({
    required bool isDark,
    String palette = 'teal',
  }) {
    return AppThemeColors.teal(isDark: isDark);
  }

  /// Builds Material 3 ThemeData bridge using web theme tokens.
  static ThemeData toThemeData({
    required bool isDark,
    String palette = 'teal',
  }) {
    final c = colors(isDark: isDark, palette: palette);
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );
    final textTheme = GoogleFonts.notoSansThaiTextTheme(
      baseTheme.textTheme,
    ).apply(bodyColor: c.textStrong, displayColor: c.textStrong);

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: c.background,
      fontFamily: GoogleFonts.notoSansThai().fontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,

      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: c.primary,
        onPrimary: c.textInverse,
        secondary: c.accent,
        onSecondary: c.textStrong,
        surface: c.surface,
        onSurface: c.textStrong,
        surfaceContainerLow: c.surfaceMuted,
        onSurfaceVariant: c.foreground,
        outline: c.borderSoft,
        error: c.danger,
        onError: Colors.white,
      ),

      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: c.borderSoft, width: 1),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: c.textStrong),
        titleTextStyle: GoogleFonts.notoSansThai(
          color: c.textStrong,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

extension BuildContextThemeExt on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  AppThemeColors get appColors => AppTheme.colors(
    isDark: Theme.of(this).brightness == Brightness.dark,
    palette: 'teal',
  );
}
