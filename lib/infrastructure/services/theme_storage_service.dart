import 'secure_storage_service.dart';

class ThemeStorageService {
  static const String _themeKey = 'is_dark_mode';

  Future<void> saveThemeMode(bool isDarkMode) async {
    final prefs = SecureStorageService.instance;
    await prefs.setBool(_themeKey, isDarkMode);
  }

  Future<bool?> loadThemeMode() async {
    final prefs = SecureStorageService.instance;
    return prefs.getBool(_themeKey);
  }
}
