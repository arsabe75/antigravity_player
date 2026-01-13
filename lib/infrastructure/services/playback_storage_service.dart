import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

class PlaybackStorageService {
  static const String _prefix = 'playback_position_';

  Future<void> savePosition(String videoPath, int positionMs) async {
    final prefs = SecureStorageService.instance;
    await prefs.setInt('$_prefix$videoPath', positionMs);
  }

  Future<int?> getPosition(String videoPath) async {
    final prefs = SecureStorageService.instance;
    return prefs.getInt('$_prefix$videoPath');
  }

  /// Clears the saved position for a specific video.
  /// Called when video playback reaches the end.
  Future<void> clearPosition(String videoPath) async {
    final prefs = SecureStorageService.instance;
    await prefs.remove('$_prefix$videoPath');
  }

  /// Clears all saved playback positions.
  /// Called when cache is cleared to avoid resume-after-cache-clear issues.
  Future<void> clearAllPositions() async {
    final prefs = SecureStorageService.instance;
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
