// lib/providers/settings_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/translation_database.dart';
import '../data/quran_repository.dart';
import '../models/recitation_event.dart';
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
  String _languageCode = 'en'; // Default to English for global launch

  // Setting for Hifz input mode (default: inAppTally)
  static const String _hifzInputModeKey = 'hifz_input_mode';
  HifzInputMode _hifzInputMode = HifzInputMode.inAppTally;

  // Setting for on-device voice recitation tracking
  static const String _voiceRecitationEnabledKey = 'voice_recitation_enabled';
  bool _voiceRecitationEnabled = true;
  bool get voiceRecitationEnabled => _voiceRecitationEnabled;

  static const String _voiceRecitationSensitivityKey = 'voice_recitation_sensitivity';
  RecitationSensitivity _voiceRecitationSensitivity = RecitationSensitivity.balanced;
  RecitationSensitivity get voiceRecitationSensitivity => _voiceRecitationSensitivity;

  static const String _voiceRecitationAdaptiveNoiseKey = 'voice_recitation_adaptive_noise';
  bool _voiceRecitationAdaptiveNoise = true;
  bool get voiceRecitationAdaptiveNoise => _voiceRecitationAdaptiveNoise;

  // Dual-slot translation model
  // Built-in ID: 'en_usmani' (English offline) or 'thai_v3' (Thai offline)
  String _primaryTranslationId = 'en_usmani';
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
  // Word by word display setting
  bool _showWordByWord = false;
  bool get showWordByWord => _showWordByWord;
  String _wordByWordLanguage = 'en'; // 'en', 'th', 'ms'
  String get wordByWordLanguage => _wordByWordLanguage;

  // Footnotes display setting (default: true)
  bool _showFootnotes = true;
  bool get showFootnotes => _showFootnotes;

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

  /// Effective UI and theme language code ('th' or 'en') chosen by the user.
  String get effectiveLanguageCode => _languageCode;

  SettingsProvider() {
    _loadSettings();
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
        data,
      ) async {
        final user = data.session?.user;
        if (user != null) {
          await loadAndApplySyncedSettings(user.id);
        }
      });
    } catch (e) {
      debugPrint('Supabase auth listener not initialized: $e');
    }
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
      // Note: Mobile font sizes are kept Device-Local in SharedPreferences to prevent conflict with desktop screen sizes.
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

      // Load Hifz input mode and voice recitation setting
      _voiceRecitationEnabled = prefs.getBool(_voiceRecitationEnabledKey) ?? true;
      _voiceRecitationAdaptiveNoise = prefs.getBool(_voiceRecitationAdaptiveNoiseKey) ?? true;
      final remoteSensitivity = prefs.getString(_voiceRecitationSensitivityKey);
      if (remoteSensitivity != null) {
        _voiceRecitationSensitivity = RecitationSensitivity.values.firstWhere(
          (e) => e.name == remoteSensitivity,
          orElse: () => RecitationSensitivity.balanced,
        );
      }
      final savedHifzMode = prefs.getString(_hifzInputModeKey);
      if (savedHifzMode == HifzInputMode.bleSmartRing.toString()) {
        _hifzInputMode = HifzInputMode.bleSmartRing;
      } else if (savedHifzMode == HifzInputMode.bluetoothShutter.toString()) {
        _hifzInputMode = HifzInputMode.bluetoothShutter;
      } else {
        _hifzInputMode = HifzInputMode.inAppTally;
      }
    } catch (e) {
      debugPrint('Error loading/applying user settings: $e');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _languageCode = prefs.getString('languageCode') ?? 'en';
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _keepAwake = prefs.getBool('keepAwake') ?? true;
    _showWordByWord = prefs.getBool('showWordByWord') ?? false;
    _wordByWordLanguage = prefs.getString('wordByWordLanguage') ?? 'en';
    _showFootnotes = prefs.getBool('showFootnotes') ?? true;
    _voiceRecitationEnabled = prefs.getBool(_voiceRecitationEnabledKey) ?? true;
    _voiceRecitationAdaptiveNoise = prefs.getBool(_voiceRecitationAdaptiveNoiseKey) ?? true;
    final savedSensitivity = prefs.getString(_voiceRecitationSensitivityKey);
    if (savedSensitivity != null) {
      _voiceRecitationSensitivity = RecitationSensitivity.values.firstWhere(
        (e) => e.name == savedSensitivity,
        orElse: () => RecitationSensitivity.balanced,
      );
    }

    final savedHifzMode = prefs.getString(_hifzInputModeKey);
    if (savedHifzMode == HifzInputMode.bleSmartRing.toString()) {
      _hifzInputMode = HifzInputMode.bleSmartRing;
    } else if (savedHifzMode == HifzInputMode.bluetoothShutter.toString()) {
      _hifzInputMode = HifzInputMode.bluetoothShutter;
    } else {
      _hifzInputMode = HifzInputMode.inAppTally;
    }
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
        v3 = _languageCode == 'th';
        v2 = false;
        en = _languageCode != 'th';
      } else {
        v3 = prefs.getBool('showThaiV3') ?? (_languageCode == 'th');
        v2 = prefs.getBool('showThaiV2') ?? false;
        en = prefs.getBool('showEnglish') ?? (_languageCode != 'th');
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
  (String, String?) _deriveSlotIds({
    required bool v3,
    required bool v2,
    required bool en,
  }) {
    if (v3) return ('thai_v3', en ? 'en_usmani' : null);
    return ('en_usmani', null);
  }

  String _normalizeReadingDisplayMode(String value) {
    return _validDisplayModes.contains(value) ? value : quranTranslationMode;
  }

  bool _isBundledTranslationId(String id) {
    return id == 'thai_v3' ||
        id == 'thai_v2' ||
        id == 'english' ||
        id == 'en_usmani' ||
        id == 'ms_basmeih';
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

    final defaultId = _languageCode == 'th' ? 'thai_v3' : 'en_usmani';
    String resolvedPrimary = primaryAvailable ? primary : defaultId;
    String? resolvedSecondary =
        secondaryAvailable && secondary != resolvedPrimary ? secondary : null;

    if (!primaryAvailable && secondaryAvailable && secondary != null) {
      resolvedPrimary = secondary;
      resolvedSecondary = null;
    }

    if (resolvedPrimary.isEmpty) {
      resolvedPrimary = defaultId;
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
    QuranRepository.globalIsThaiName = _languageCode == 'th';
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

  void toggleShowWordByWord(bool value) async {
    _showWordByWord = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showWordByWord', value);
    await _markSettingsChanged(prefs);
  }

  void setWordByWordLanguage(String lang) async {
    if (_wordByWordLanguage == lang) return;
    _wordByWordLanguage = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wordByWordLanguage', lang);
    await _markSettingsChanged(prefs);
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
    // Device-local setting: keep in SharedPreferences, do not override desktop web font size
  }

  void setTranslationFontSize(double value) async {
    _translationFontSize = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('translationFontSize', value);
    // Device-local setting: keep in SharedPreferences, do not override desktop web font size
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
    if (value == 'th' && (_primaryTranslationId == 'en_usmani' || _primaryTranslationId == 'english')) {
      _primaryTranslationId = 'thai_v3';
    } else if (value == 'en' && (_primaryTranslationId == 'thai_v3' || _primaryTranslationId == 'thai_v2')) {
      _primaryTranslationId = 'en_usmani';
    }
    _syncGlobalState();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', _languageCode);
    await prefs.setString('primaryTranslationId', _primaryTranslationId);
    await _markSettingsChanged(prefs);
    await _syncToSupabase();
  }

  void setShowFootnotes(bool value) async {
    if (_showFootnotes == value) return;
    _showFootnotes = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showFootnotes', value);
    await _markSettingsChanged(prefs);
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

      final lowerId = id.trim().toLowerCase();
      if (lowerId.startsWith('thai') || lowerId.startsWith('th')) {
        _languageCode = 'th';
      } else if (lowerId == 'english' || lowerId.startsWith('en') || lowerId == 'malay' || lowerId.startsWith('ms')) {
        _languageCode = 'en';
      }
      await prefs.setString('languageCode', _languageCode);
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

  Future<void> setVoiceRecitationEnabled(bool value) async {
    if (_voiceRecitationEnabled == value) return;

    _voiceRecitationEnabled = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voiceRecitationEnabledKey, value);
  }

  Future<void> setVoiceRecitationSensitivity(RecitationSensitivity sensitivity) async {
    if (_voiceRecitationSensitivity == sensitivity) return;

    _voiceRecitationSensitivity = sensitivity;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_voiceRecitationSensitivityKey, sensitivity.name);
  }

  Future<void> setVoiceRecitationAdaptiveNoise(bool value) async {
    if (_voiceRecitationAdaptiveNoise == value) return;

    _voiceRecitationAdaptiveNoise = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voiceRecitationAdaptiveNoiseKey, value);
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
