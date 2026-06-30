import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const _keyUseFahrenheit = 'use_fahrenheit';
  static const _keyUseGallons = 'use_gallons';
  static const _keyThemeMode = 'theme_mode';

  // US defaults
  static final ValueNotifier<bool> useFahrenheit = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> useGallons = ValueNotifier<bool>(true);
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.dark,
  );

  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final prefs = await SharedPreferences.getInstance();
    useFahrenheit.value = prefs.getBool(_keyUseFahrenheit) ?? true;
    useGallons.value = prefs.getBool(_keyUseGallons) ?? true;
    themeMode.value = _themeModeFromName(prefs.getString(_keyThemeMode));
  }

  static Future<void> setUseFahrenheit(bool value) async {
    useFahrenheit.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseFahrenheit, value);
  }

  static Future<void> setUseGallons(bool value) async {
    useGallons.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseGallons, value);
  }

  static Future<void> setThemeMode(ThemeMode value) async {
    themeMode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, value.name);
  }

  static ThemeMode _themeModeFromName(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }
}
