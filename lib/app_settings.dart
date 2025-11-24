import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const _keyUseFahrenheit = 'use_fahrenheit';
  static const _keyUseGallons = 'use_gallons';

  // US defaults
  static final ValueNotifier<bool> useFahrenheit = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> useGallons = ValueNotifier<bool>(true);

  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final prefs = await SharedPreferences.getInstance();
    useFahrenheit.value = prefs.getBool(_keyUseFahrenheit) ?? true;
    useGallons.value = prefs.getBool(_keyUseGallons) ?? true;
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
}
