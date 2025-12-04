import 'package:shared_preferences/shared_preferences.dart';

class ThemeStorageService {
  static const String _themeKey = 'is_dark_mode';

  Future<void> saveThemeMode(bool isDarkMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, isDarkMode);
  }

  Future<bool?> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_themeKey);
  }
}
