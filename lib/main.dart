// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';
import 'providers/ble_remote_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/notes_provider.dart';
import 'providers/stats_provider.dart';
import 'providers/local_reading_provider.dart';
import 'providers/mushaf_reading_provider.dart';
import 'providers/supabase_provider.dart';
import 'providers/thai_text_protection_provider.dart';
import 'providers/translation_manager_provider.dart';
import 'providers/mushaf_audio_provider.dart';
import 'providers/recitation_tracker_provider.dart';
import 'data/quran_repository.dart';
import 'screens/hifz_landing_screen.dart';
import 'screens/welcome_screen.dart';
import 'data/quran_foundation_repository.dart';
import 'theme/app_theme.dart';
import 'services/background_download_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = QuranRepository();
  final foundationRepository = QuranFoundationRepository();

  runApp(
    HifzAppBootstrap(
      repository: repository,
      foundationRepository: foundationRepository,
      initialization: _initializeAppServices(),
    ),
  );
}



Future<void> _initializeAppServices() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  await AppTheme.prewarmFonts();

  await Supabase.initialize(
    url: 'https://qeciqdjidugdipgqxysm.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlY2lxZGppZHVnZGlwZ3F4eXNtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE5MzQxMzcsImV4cCI6MjA5NzUxMDEzN30.HtEVA3me06ShjtTRe6KdjV6qd3hPkiJTC9GAW0xDGuY',
  );

  await _initializeAudioBackground();
  await initializeDownloadService();
}

Future<void> _initializeAudioBackground() async {
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
    );
  } catch (error) {
    debugPrint('Unable to initialize audio background service: $error');
  }
}

class HifzAppBootstrap extends StatelessWidget {
  final QuranRepository repository;
  final QuranFoundationRepository foundationRepository;
  final Future<void> initialization;

  const HifzAppBootstrap({
    super.key,
    required this.repository,
    required this.foundationRepository,
    required this.initialization,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupScreen();
        }

        if (snapshot.hasError) {
          return _StartupErrorScreen(error: snapshot.error);
        }

        return MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => BleRemoteProvider()),
            ChangeNotifierProvider(create: (_) => SupabaseProvider()),
            ChangeNotifierProvider(create: (_) => ProgressProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => TranslationManagerProvider()),
            ChangeNotifierProvider(create: (_) => LocalReadingProvider()),
            ChangeNotifierProvider(create: (_) => MushafReadingProvider()),
            ChangeNotifierProvider(create: (_) => NotesProvider()),
            ChangeNotifierProvider(create: (_) => StatsProvider()),
            ChangeNotifierProvider(create: (_) => ThaiTextProtectionProvider()),
            ChangeNotifierProvider(create: (_) => MushafAudioProvider()),
            ChangeNotifierProvider(create: (_) => RecitationTrackerProvider()),
          ],
          child: HifzApp(
            repository: repository,
            foundationRepository: foundationRepository,
          ),
        );
      },
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.toThemeData(isDark: false);
    final colorScheme = theme.colorScheme;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(
          child: CircularProgressIndicator(color: colorScheme.primary),
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final Object? error;

  const _StartupErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.toThemeData(isDark: false);
    final colorScheme = theme.colorScheme;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 48,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Unable to start HifzSpace',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HifzApp extends StatelessWidget {
  final QuranRepository repository;
  final QuranFoundationRepository foundationRepository;

  const HifzApp({
    Key? key,
    required this.repository,
    required this.foundationRepository,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return MaterialApp(
          title: 'HifzSpace',
          debugShowCheckedModeBanner: false,

          // Connects your live app settings state directly into the theme engine
          themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,

          // Natively builds your beautiful Material 3 styles using your custom palette options
          theme: AppTheme.toThemeData(
            isDark: false,
            palette: settings.themeColor,
            languageCode: settings.languageCode,
          ),
          darkTheme: AppTheme.toThemeData(
            isDark: true,
            palette: settings.themeColor,
            languageCode: settings.languageCode,
          ),

          home: WelcomeScreen(
            repository: repository,
            foundationRepository: foundationRepository,
          ),
        );
      },
    );
  }
}
