import 'package:flutter/material.dart';

import '../data/quran_repository.dart';
import 'hifz_settings_screen.dart';

/// Standardized settings screen alias for backward compatibility.
/// Forwards directly to [HifzSettingsScreen].
class SettingsScreen extends StatelessWidget {
  final QuranRepository? repository;

  const SettingsScreen({
    super.key,
    this.repository,
  });

  @override
  Widget build(BuildContext context) {
    return const HifzSettingsScreen();
  }
}
