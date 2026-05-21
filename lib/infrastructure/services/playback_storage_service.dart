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

  static const String _trackPrefPrefix = 'track_pref_';

  /// Saves the user's track preference (audio or subtitle) for a given video key.
  Future<void> saveTrackPreference(
    String videoKey,
    String trackType,
    String trackId,
  ) async {
    final prefs = SecureStorageService.instance;
    await prefs.setString('$_trackPrefPrefix${trackType}_$videoKey', trackId);
  }

  /// Retrieves the user's saved track preference (audio or subtitle) for a video key.
  /// Returns the track ID string, or null if no preference was saved.
  String? getTrackPreference(String videoKey, String trackType) {
    final prefs = SecureStorageService.instance;
    return prefs.getString('$_trackPrefPrefix${trackType}_$videoKey');
  }

  /// Clears saved track preferences for a given video key.
  Future<void> clearTrackPreferences(String videoKey) async {
    final prefs = SecureStorageService.instance;
    await prefs.remove('${_trackPrefPrefix}audio_$videoKey');
    await prefs.remove('${_trackPrefPrefix}subtitle_$videoKey');
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
