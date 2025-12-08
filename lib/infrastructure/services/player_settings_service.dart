import 'package:shared_preferences/shared_preferences.dart';

class PlayerSettingsService {
  static const String _playerEngineKey = 'player_engine';
  static const String engineMediaKit = 'media_kit';
  static const String engineFvp = 'fvp';

  Future<void> savePlayerEngine(String engine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playerEngineKey, engine);
  }

  Future<String> getPlayerEngine() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_playerEngineKey) ?? engineMediaKit;
  }
}
