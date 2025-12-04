import 'package:shared_preferences/shared_preferences.dart';

class PlaybackStorageService {
  static const String _prefix = 'playback_position_';

  Future<void> savePosition(String videoPath, int positionMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix$videoPath', positionMs);
  }

  Future<int?> getPosition(String videoPath) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_prefix$videoPath');
  }
}
