import 'package:flutter/foundation.dart';
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

  /// Clears all saved playback positions.
  /// Called when cache is cleared to avoid resume-after-cache-clear issues.
  Future<void> clearAllPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    if (keys.isNotEmpty) {
      debugPrint(
        'PlaybackStorageService: Cleared ${keys.length} saved positions',
      );
    }
  }
}
