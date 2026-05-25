import 'secure_storage_service.dart';

class LocaleStorageService {
  static const String _localeKey = 'app_locale';

  Future<void> saveLanguage(String languageCode) async {
    final prefs = SecureStorageService.instance;
    await prefs.setString(_localeKey, languageCode);
  }

  Future<String?> loadLanguage() async {
    final prefs = SecureStorageService.instance;
    return prefs.getString(_localeKey);
  }
}
