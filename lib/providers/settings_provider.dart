// lib/providers/settings_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/translation_database.dart';
import '../data/quran_repository.dart';
import '../theme/app_theme.dart';

enum HifzInputMode {
  bluetoothShutter,
  bleSmartRing,
  inAppTally,
}

class SettingsProvider extends ChangeNotifier {
  static const quranOnlyMode = 'quran_only';
  static const translationOnlyMode = 'translation_only';
  static const quranTranslationMode = 'quran_translation';
  static const _validDisplayModes = {
    quranOnlyMode,
    translationOnlyMode,
    quranTranslationMode,
  };

  bool _isDarkMode = false;
  bool _keepAwake = true;
  String _readingDisplayMode = quranTranslationMode;
  double _arabicFontSize = 28.0;
  double _translationFontSize = 16.0;
  String _themeColor = 'teal';
  String _webHostUrl = 'http://10.0.2.2:3000'; // Default emulator localhost
  DateTime _settingsUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _languageCode = 'th'; // Default to Thai

  // New setting for Hifz input mode
  static const String _hifzInputModeKey = 'hifz_input_mode';
  HifzInputMode _hifzInputMode = HifzInputMode.bluetoothShutter;

  // Dual-slot translation model
  // Built-in ID: 'thai_v3'. Other active IDs should come from downloaded API translations.
  String _primaryTranslationId = 'thai_v3';
  String? _secondaryTranslationId;

  StreamSubscription<AuthState>? _authSubscription;

  bool get isDarkMode => _isDarkMode;
  bool get keepAwake => _keepAwake;
  String get readingDisplayMode => _readingDisplayMode;
  String get languageCode => _languageCode;
  bool get showArabicText =>
      _readingDisplayMode == quranOnlyMode ||
      _readingDisplayMode == quranTranslationMode;
  bool get showTranslationText =>
      _readingDisplayMode == translationOnlyMode ||
      _readingDisplayMode == quranTranslationMode;
  bool get alwaysShowArabic => showArabicText;
  bool get alwaysShowTranslation => showTranslationText;
  String get arabicFontFamily => 'UthmanicHafs';
  double get arabicFontSize => _arabicFontSize;
  double get translationFontSize => _translationFontSize;
  String get themeColor => _themeColor;
  String get webHostUrl => _webHostUrl;
  HifzInputMode get hifzInputMode => _hifzInputMode;

  // New dual-slot getters
  String get primaryTranslationId => _primaryTranslationId;
  String? get secondaryTranslationId => _secondaryTranslationId;

  // Derived boolean getters (computed from slots — backwards compat for verse_card.dart etc.)
  bool get showThaiV3 =>
      _primaryTranslationId == 'thai_v3' ||
      _secondaryTranslationId == 'thai_v3';
  bool get showThaiV2 =>
      _primaryTranslationId == 'thai_v2' ||
      _secondaryTranslationId == 'thai_v2';
  bool get showEnglish =>
      _primaryTranslationId == 'english' ||
      _secondaryTranslationId == 'english';

  SettingsProvider() {
    _loadSettings();
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      final user = data.session?.user;
      if (user != null) {
        await loadAndApplySyncedSettings(user.id);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _syncToSupabase({String? userIdOverride}) async {
    final client = Supabase.instance.client;
    final userId = userIdOverride ?? client.auth.currentUser?.id;
    if (userId != null) {
      try {
        final updatedAt =
            _settingsUpdatedAt.isAfter(DateTime.fromMillisecondsSinceEpoch(0))
            ? _settingsUpdatedAt
            : DateTime.now();
        // Derive legacy booleans from slots for backward compat with old Supabase rows
        await client.from('user_settings').upsert({
          'user_id': userId,
          'theme_color': _themeColor,
          'is_dark_mode': _isDarkMode,
          'keep_awake': _keepAwake,
          'reading_display_mode': _readingDisplayMode,
          'always_show_arabic': showArabicText,
          'arabic_font_family': 'UthmanicHafs',
          'arabic_font_size': _arabicFontSize,
          'thai_font_family': 'sans-serif',
          'thai_font_size': _translationFontSize,
          'translation_font_size': _translationFontSize,
          // Legacy boolean columns kept for web backwards compat
          'show_thai_v3': showThaiV3,
          'show_thai_v2': showThaiV2,
          'show_english': showEnglish,
          // New dual-slot columns
          'primary_translation_id': _primaryTranslationId,
          'secondary_translation_id': _secondaryTranslationId,
          'language_code': _languageCode,
          'web_host_url': _webHostUrl,
          'updated_at': updatedAt.toIso8601String(),
        }, onConflict: 'user_id');
      } catch (e) {
        debugPrint('Error syncing settings to Supabase: $e');
        rethrow;
      }
    }
  }

  Future<void> syncWithSupabase(String userId) async {
    await loadAndApplySyncedSettings(userId);
  }

  Future<void> loadAndApplySyncedSettings(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('user_settings')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();

      final prefs = await SharedPreferences.getInstance();
      if (response == null) {
        await _syncToSupabase(userIdOverride: userId);
        return;
      }

      final hasLocalDisplayMode = prefs.containsKey('readingDisplayMode');
      final localUpdatedAt =
          DateTime.tryParse(prefs.getString('settingsUpdatedAt') ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final remoteUpdatedAt =
          DateTime.tryParse(response['updated_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);

      if (localUpdatedAt.isAfter(remoteUpdatedAt)) {
        _settingsUpdatedAt = localUpdatedAt;
        await _syncToSupabase();
        return;
      }

      _themeColor = _normalizeThemeColor(
        response['theme_color']?.toString() ?? _themeColor,
      );
      _isDarkMode = response['is_dark_mode'] == true;
      _keepAwake = response['keep_awake'] ?? true;
      final remoteDisplayMode = response['reading_display_mode']?.toString();
      _readingDisplayMode =
          remoteDisplayMode != null && remoteDisplayMode.isNotEmpty
          ? _normalizeReadingDisplayMode(remoteDisplayMode)
          : hasLocalDisplayMode
          ? _readingDisplayMode
          : _modeFromLegacyFlags(
              showArabic: response['always_show_arabic'] == true,
              showTranslation: _readingDisplayMode != quranOnlyMode,
            );
      _arabicFontSize =
          double.tryParse(response['arabic_font_size']?.toString() ?? '') ??
          _arabicFontSize;
      _translationFontSize =
          double.tryParse(
            (response['translation_font_size'] ?? response['thai_font_size'])
                    ?.toString() ??
                '',
          ) ??
          _translationFontSize;
      _languageCode = response['language_code']?.toString() == 'en'
          ? 'en'
          : 'th';
      _webHostUrl = response['web_host_url']?.toString() ?? _webHostUrl;

      // Prefer new dual-slot columns; fall back to legacy booleans for old rows
      final rawPrimary = response['primary_translation_id']?.toString();
      if (rawPrimary != null && rawPrimary.isNotEmpty) {
        _primaryTranslationId = rawPrimary;
        _secondaryTranslationId = response['secondary_translation_id']
            ?.toString();
      } else {
        // Migrate from legacy boolean columns
        final v3 = response['show_thai_v3'] == true;
        final v2 = response['show_thai_v2'] == true;
        final en = response['show_english'] == true;
        final ids = _deriveSlotIds(v3: v3, v2: v2, en: en);
        _primaryTranslationId = ids.$1;
        _secondaryTranslationId = ids.$2;
      }
      final sanitizedIds = await _sanitizeTranslationSlots(
        primary: _primaryTranslationId,
        secondary: _secondaryTranslationId,
      );
      _primaryTranslationId = sanitizedIds.$1;
      _secondaryTranslationId = sanitizedIds.$2;
      _syncGlobalState();

      // Save to local SharedPreferences
      await prefs.setString('themeColor', _themeColor);
      await prefs.setBool('isDarkMode', _isDarkMode);
      await prefs.setBool('keepAwake', _keepAwake);
      await prefs.setString('readingDisplayMode', _readingDisplayMode);
      await prefs.setBool('alwaysShowArabic', showArabicText);
      await prefs.setBool('alwaysShowTranslation', showTranslationText);
      await prefs.setString('arabicFontFamily', 'UthmanicHafs');
      await prefs.setDouble('arabicFontSize', _arabicFontSize);
      await prefs.setDouble('translationFontSize', _translationFontSize);
      await prefs.setString('languageCode', _languageCode);
      await prefs.setString('webHostUrl', _webHostUrl);
      await prefs.setString('primaryTranslationId', _primaryTranslationId);
      _settingsUpdatedAt = remoteUpdatedAt;
      await prefs.setString(
        'settingsUpdatedAt',
        remoteUpdatedAt.toIso8601String(),
      );
      if (_secondaryTranslationId != null) {
        await prefs.setString(
          'secondaryTranslationId',
          _secondaryTranslationId!,
        );
      } else {
        await prefs.remove('secondaryTranslationId');
      }

      // Load Hifz input mode
      final savedHifzMode = prefs.getString(_hifzInputModeKey);
      if (savedHifzMode == HifzInputMode.bleSmartRing.toString()) {
        _hifzInputMode = HifzInputMode.bleSmartRing;
      } else if (savedHifzMode == HifzInputMode.inAppTally.toString()) {
        _hifzInputMode = HifzInputMode.inAppTally;
      } else {
        _hifzInputMode = HifzInputMode.bluetoothShutter;
      }
    } catch (e) {
      debugPrint('Error loading/applying user settings: $e');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _languageCode = prefs.getString('languageCode') ?? 'th';
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _keepAwake = prefs.getBool('keepAwake') ?? true;
    final storedDisplayMode = prefs.getString('readingDisplayMode');
    if (storedDisplayMode != null && storedDisplayMode.isNotEmpty) {
      _readingDisplayMode = _normalizeReadingDisplayMode(storedDisplayMode);
    } else {
      final hasLegacyArabic = prefs.containsKey('alwaysShowArabic');
      final hasLegacyTranslation = prefs.containsKey('alwaysShowTranslation');
      _readingDisplayMode = hasLegacyArabic || hasLegacyTranslation
          ? _modeFromLegacyFlags(
              showArabic: prefs.getBool('alwaysShowArabic') ?? true,
              showTranslation: prefs.getBool('alwaysShowTranslation') ?? true,
            )
          : quranTranslationMode;
      await prefs.setString('readingDisplayMode', _readingDisplayMode);
    }
    await prefs.setString('arabicFontFamily', 'UthmanicHafs');
    _arabicFontSize = prefs.getDouble('arabicFontSize') ?? 28.0;
    _translationFontSize = prefs.getDouble('translationFontSize') ?? 16.0;
    _themeColor = _normalizeThemeColor(prefs.getString('themeColor') ?? 'teal');
    _webHostUrl = prefs.getString('webHostUrl') ?? 'http://10.0.2.2:3000';
    _settingsUpdatedAt =
        DateTime.tryParse(prefs.getString('settingsUpdatedAt') ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);

    // Load dual-slot translation state — migrate from legacy booleans if absent
    final storedPrimary = prefs.getString('primaryTranslationId');
    if (storedPrimary != null && storedPrimary.isNotEmpty) {
      _primaryTranslationId = storedPrimary;
      _secondaryTranslationId = prefs.getString('secondaryTranslationId');
      final sanitizedIds = await _sanitizeTranslationSlots(
        primary: _primaryTranslationId,
        secondary: _secondaryTranslationId,
      );
      _primaryTranslationId = sanitizedIds.$1;
      _secondaryTranslationId = sanitizedIds.$2;
      await prefs.setString('primaryTranslationId', _primaryTranslationId);
      if (_secondaryTranslationId != null) {
        await prefs.setString(
          'secondaryTranslationId',
          _secondaryTranslationId!,
        );
      } else {
        await prefs.remove('secondaryTranslationId');
      }
    } else {
      // First-run locale detection with migration from old boolean prefs
      final bool hasShowThaiV3 = prefs.containsKey('showThaiV3');
      bool v3, v2, en;
      if (!hasShowThaiV3) {
        v3 = true;
        v2 = false;
        en = false;
      } else {
        v3 = prefs.getBool('showThaiV3') ?? true;
        v2 = prefs.getBool('showThaiV2') ?? false;
        en = prefs.getBool('showEnglish') ?? false;
      }
      final ids = _deriveSlotIds(v3: v3, v2: v2, en: en);
      _primaryTranslationId = ids.$1;
      _secondaryTranslationId = ids.$2;
      // Persist migrated values
      await prefs.setString('primaryTranslationId', _primaryTranslationId);
      if (_secondaryTranslationId != null) {
        await prefs.setString(
          'secondaryTranslationId',
          _secondaryTranslationId!,
        );
      }
    }
    _syncGlobalState();
    notifyListeners();
  }

  /// Derive dual-slot IDs from legacy boolean flags.
  /// Priority: thai_v3 only. Thai 2 and English should come from API downloads.
  (String, String?) _deriveSlotIds({
    required bool v3,
    required bool v2,
    required bool en,
  }) {
    final enabled = [if (v3 || v2 || en) 'thai_v3'];
    if (enabled.isEmpty) return ('thai_v3', null);
    return (enabled[0], enabled.length > 1 ? enabled[1] : null);
  }

  String _normalizeReadingDisplayMode(String value) {
    return _validDisplayModes.contains(value) ? value : quranTranslationMode;
  }

  bool _isBundledTranslationId(String id) {
    return id == 'thai_v3' || id == 'thai_v2' || id == 'english';
  }

  Future<bool> _isTranslationAvailableOnDevice(String? id) async {
    if (id == null || id.isEmpty) return false;
    if (_isBundledTranslationId(id)) return true;
    final customId = int.tryParse(id);
    if (customId == null) return false;
    return TranslationDatabase.instance.isDownloaded(customId);
  }

  Future<(String, String?)> _sanitizeTranslationSlots({
    required String primary,
    required String? secondary,
  }) async {
    final primaryAvailable = await _isTranslationAvailableOnDevice(primary);
    final secondaryAvailable = await _isTranslationAvailableOnDevice(secondary);

    String resolvedPrimary = primaryAvailable ? primary : 'thai_v3';
    String? resolvedSecondary =
        secondaryAvailable && secondary != resolvedPrimary ? secondary : null;

    if (!primaryAvailable && secondaryAvailable && secondary != null) {
      resolvedPrimary = secondary;
      resolvedSecondary = null;
    }

    if (resolvedPrimary.isEmpty) {
      resolvedPrimary = 'thai_v3';
    }

    return (resolvedPrimary, resolvedSecondary);
  }

  String _modeFromLegacyFlags({
    required bool showArabic,
    required bool showTranslation,
  }) {
    if (showArabic && !showTranslation) return quranOnlyMode;
    if (!showArabic && showTranslation) return translationOnlyMode;
    if (showArabic && showTranslation) return quranTranslationMode;
    return quranTranslationMode;
  }

  void _syncGlobalState() {
    QuranRepository.globalIsThaiName = _languageCode == 'th' || _primaryTranslationId.startsWith('thai');
  }

  Future<void> _markSettingsChanged(SharedPreferences prefs) async {
    _settingsUpdatedAt = DateTime.now();
    await prefs.setString(
      'settingsUpdatedAt',
      _settingsUpdatedAt.toIso8601String(),
    );
  }

  void toggleDarkMode(bool value) async {
    _isDarkMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
    await _markSettingsChanged(prefs);
    await _syncToSupabase();
  }

  void toggleKeepAwake(bool value) async {
    _keepAwake = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keepAwake', value);
    await _markSettingsChanged(prefs);
    await _syncToSupabase();
  }

  void toggleAlwaysShowArabic(bool value) async {
    setReadingDisplayMode(
      value
          ? (showTranslationText ? quranTranslationMode : quranOnlyMode)
          : translationOnlyMode,
    );
  }

  void toggleAlwaysShowTranslation(bool value) async {
    setReadingDisplayMode(
      value
          ? (showArabicText ? quranTranslationMode : translationOnlyMode)
          : quranOnlyMode,
    );
  }

  void setArabicFontFamily(String value) async {
    if (value != 'UthmanicHafs') return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('arabicFontFamily', 'UthmanicHafs');
    await _markSettingsChanged(prefs);
    await _syncToSupabase();
  }

  void setReadingDisplayMode(String value) async {
    final normalized = _normalizeReadingDisplayMode(value);
    if (_readingDisplayMode == normalized) return;
    _readingDisplayMode = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('readingDisplayMode', normalized);
    await prefs.setBool('alwaysShowArabic', showArabicText);
    await prefs.setBool('alwaysShowTranslation', showTranslationText);
    await _markSettingsChanged(prefs);
    await _syncToSupabase();
  }

  void setArabicFontSize(double value) async {
    _arabicFontSize = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('arabicFontSize', value);
    await _markSettingsChanged(prefs);
    await _syncToSupabase();
  }

  void setTranslationFontSize(double value) async {
    _translationFontSize = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('translationFontSize', value);
    await _markSettingsChanged(prefs);
    await _syncToSupabase();
  }

  void setThemeColor(String value) async {
    _themeColor = _normalizeThemeColor(value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeColor', _themeColor);
    await _markSettingsChanged(prefs);
    await _syncToSupabase();
  }

  void setWebHostUrl(String value) async {
    _webHostUrl = value.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webHostUrl', _webHostUrl);
    await _markSettingsChanged(prefs);
    await _syncToSupabase();
  }

  void setLanguageCode(String value) async {
    if (value != 'th' && value != 'en') return;
    _languageCode = value;
    _syncGlobalState();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', _languageCode);
    await _markSettingsChanged(prefs);
    await _syncToSupabase();
  }

  /// Core dual-slot mutation with Auto-Eviction collision logic.
  ///
  /// [slot] must be `'primary'` or `'secondary'`.
  /// [id] must be `'thai_v3'`, a downloaded API translation ID, or `null` (secondary only).
  ///
  /// Rules:
  /// - `primary` cannot be null.
  /// - If new primary == current secondary → secondary is evicted to null.
  /// - If new secondary == current primary → silently rejected (no-op).
  void updateTranslationSlot(String slot, String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (slot == 'primary') {
      if (id == null) return; // primary must always have a value
      final newSecondary = _secondaryTranslationId == id
          ? null
          : _secondaryTranslationId;
      _primaryTranslationId = id;
      _secondaryTranslationId = newSecondary;
    } else {
      if (id == _primaryTranslationId) return; // collision — reject
      _secondaryTranslationId = id;
    }
    _syncGlobalState();
    notifyListeners();
    await prefs.setString('primaryTranslationId', _primaryTranslationId);
    if (_secondaryTranslationId != null) {
      await prefs.setString('secondaryTranslationId', _secondaryTranslationId!);
    } else {
      await prefs.remove('secondaryTranslationId');
    }
    await _markSettingsChanged(prefs);
    await _syncToSupabase();
  }

  Future<void> setHifzInputMode(HifzInputMode mode) async {
    if (_hifzInputMode == mode) return;

    _hifzInputMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hifzInputModeKey, mode.toString());
  }

  // Legacy adaptor setters — delegate to updateTranslationSlot for backwards compat
  void setShowThaiV3(bool value) {
    if (value) {
      updateTranslationSlot('primary', 'thai_v3');
    } else if (_primaryTranslationId == 'thai_v3') {
      final fallback = _secondaryTranslationId ?? 'thai_v3';
      updateTranslationSlot('primary', fallback);
    } else {
      updateTranslationSlot('secondary', null);
    }
  }

  void setShowThaiV2(bool value) {
    if (_primaryTranslationId == 'thai_v2') {
      updateTranslationSlot('primary', _secondaryTranslationId ?? 'thai_v3');
    }
    if (_secondaryTranslationId == 'thai_v2') {
      updateTranslationSlot('secondary', null);
    }
  }

  void setShowEnglish(bool value) {
    if (_primaryTranslationId == 'english') {
      updateTranslationSlot('primary', _secondaryTranslationId ?? 'thai_v3');
    }
    if (_secondaryTranslationId == 'english') {
      updateTranslationSlot('secondary', null);
    }
  }

  // Helper method to get theme colors
  MaterialColor getThemeSwatch() {
    return Colors.teal;
  }

  AppThemeColors getAppColors() {
    return AppTheme.colors(isDark: _isDarkMode, palette: 'teal');
  }

  Color getPrimaryColor() {
    return getAppColors().primary;
  }

  Color getHighlightColor() {
    return getAppColors().accent;
  }

  String _normalizeThemeColor(String value) {
    return 'teal';
  }
}
