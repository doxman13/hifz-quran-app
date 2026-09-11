// lib/screens/main_app_shell.dart
//
// Root navigation shell for HifzSpace.
// Houses the modern Material 3 NavigationBar with 4 primary tabs:
// 1. Memorize (Hifz Dashboard)
// 2. Mushaf (Browse & Read)
// 3. Mastery (Retention & Surah Progress)
// 4. Settings (Preferences, Theme, Voice Engine, Account)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/quran_foundation_repository.dart';
import '../data/quran_repository.dart';
import '../providers/settings_provider.dart';
import 'browse_screen.dart';
import 'hifz_landing_screen.dart';
import 'hifz_mastery_list_screen.dart';
import 'mushaf_reader_screen.dart';
import 'settings_screen.dart';

class MainAppShell extends StatefulWidget {
  final QuranRepository repository;
  final QuranFoundationRepository foundationRepository;
  final int initialTabIndex;

  const MainAppShell({
    super.key,
    required this.repository,
    required this.foundationRepository,
    this.initialTabIndex = 0,
  });

  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
  }

  void _onOpenMushafPage(int page, {String? highlightVerseKey}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MushafReaderScreen(
          quranRepository: widget.repository,
          foundationRepository: widget.foundationRepository,
          initialPage: page,
          initialHighlightVerseKey: highlightVerseKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isThai = context.watch<SettingsProvider>().languageCode == 'th';

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HifzLandingScreen(
            quranRepository: widget.repository,
            foundationRepository: widget.foundationRepository,
            isEmbedded: true,
          ),
          BrowseScreen(
            repository: widget.repository,
            foundationRepository: widget.foundationRepository,
            onOpenMushafPage: _onOpenMushafPage,
          ),
          HifzMasteryListScreen(
            quranRepository: widget.repository,
          ),
          SettingsScreen(
            repository: widget.repository,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.psychology_outlined),
            selectedIcon: Icon(
              Icons.psychology_rounded,
              color: colorScheme.onPrimaryContainer,
            ),
            label: isThai ? 'ท่องจำ' : 'Memorize',
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(
              Icons.menu_book_rounded,
              color: colorScheme.onPrimaryContainer,
            ),
            label: isThai ? 'มุศฮัฟ' : 'Mushaf',
          ),
          NavigationDestination(
            icon: const Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(
              Icons.workspace_premium_rounded,
              color: colorScheme.onPrimaryContainer,
            ),
            label: isThai ? 'ความแม่นยำ' : 'Mastery',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: Icon(
              Icons.settings_rounded,
              color: colorScheme.onPrimaryContainer,
            ),
            label: isThai ? 'ตั้งค่า' : 'Settings',
          ),
        ],
      ),
    );
  }
}
