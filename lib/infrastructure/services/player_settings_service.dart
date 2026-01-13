import 'secure_storage_service.dart';

class PlayerSettingsService {
  static const String _playerEngineKey = 'player_engine';
  static const String engineMediaKit = 'media_kit';
  static const String engineFvp = 'fvp';

  Future<void> savePlayerEngine(String engine) async {
    final prefs = SecureStorageService.instance;
    await prefs.setString(_playerEngineKey, engine);
  }

  Future<String> getPlayerEngine() async {
    final prefs = SecureStorageService.instance;
    return prefs.getString(_playerEngineKey) ?? engineMediaKit;
  }
}
