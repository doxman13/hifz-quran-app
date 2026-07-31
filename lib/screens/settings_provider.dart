import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HifzInputMode {
  bluetoothShutter,
  bleSmartRing,
  inAppTally,
}

class SettingsProvider extends ChangeNotifier {
  static const String _hifzInputModeKey = 'hifz_input_mode';

  // Assume other settings properties exist here...
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  // New setting for Hifz input mode
  HifzInputMode _hifzInputMode = HifzInputMode.bluetoothShutter;
  HifzInputMode get hifzInputMode => _hifzInputMode;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load existing settings...
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;

    // Load new setting
    final savedMode = prefs.getString(_hifzInputModeKey);
    if (savedMode == HifzInputMode.bleSmartRing.toString()) {
      _hifzInputMode = HifzInputMode.bleSmartRing;
    } else {
      _hifzInputMode = HifzInputMode.bluetoothShutter;
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setHifzInputMode(HifzInputMode mode) async {
    if (_hifzInputMode == mode) return;

    _hifzInputMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hifzInputModeKey, mode.toString());
  }

  // Assume other methods like setDarkMode exist here...
  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }
}