import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:disk_space_2/disk_space_2.dart';
import '../../domain/entities/storage_statistics.dart';
import 'telegram_service.dart';
import 'cache_settings.dart';
import 'playback_storage_service.dart';

/// Duration options for "Keep Media" setting (auto-delete cache after period).
enum KeepMediaDuration {
  threeDays(Duration(days: 3), '3 days'),
  oneWeek(Duration(days: 7), '1 week'),
  oneMonth(Duration(days: 30), '1 month'),
  forever(null, 'Forever');

  final Duration? duration;
  final String label;

  const KeepMediaDuration(this.duration, this.label);

  /// Get TTL in seconds for TDLib (0 means no limit).
  int get ttlSeconds => duration?.inSeconds ?? 0;
}

/// Service for managing Telegram file cache using TDLib APIs.
///
/// Follows patterns from Telegram Android and Unigram:
/// - getStorageStatistics() for usage breakdown
/// - optimizeStorage() for cleanup with configurable TTL and size limits
/// - Manual cache clearing
/// - NVR-style video cache limit (delete oldest videos when limit reached)
class TelegramCacheService {
  static const String _keepMediaKey = 'telegram_keep_media_duration';
  static const String _cacheSizeLimitKey = 'telegram_video_cache_size_limit';

  final TelegramService _telegramService;

  TelegramCacheService({TelegramService? telegramService})
    : _telegramService = telegramService ?? TelegramService();

  // ============================================================
  // STORAGE STATISTICS
  // ============================================================

  /// Gets storage statistics from TDLib.
  ///
  /// Returns breakdown by file type (videos, photos, documents, etc.).
  Future<StorageStatistics> getStorageStatistics() async {
    try {
      final result = await _telegramService.sendWithResult({
        '@type': 'getStorageStatistics',
        'chat_limit': 100, // Include stats from up to 100 chats
      });

      if (result['@type'] == 'storageStatistics') {
        return StorageStatistics.fromTdLib(result);
      }

      if (result['@type'] == 'error') {
        debugPrint(
          'TelegramCacheService: getStorageStatistics error: ${result['message']}',
        );
      }

      return const StorageStatistics();
    } catch (e) {
      debugPrint('TelegramCacheService: Error getting storage stats: $e');
      return const StorageStatistics();
    }
  }

  /// Gets available disk space in bytes.
  ///
  /// Returns 0 if unable to determine.
  Future<int> getAvailableDiskSpace() async {
    try {
      // Get free disk space in MB, convert to bytes
      final freeMB = await DiskSpace.getFreeDiskSpace ?? 0;
      return (freeMB * 1024 * 1024).round();
    } catch (e) {
      debugPrint('TelegramCacheService: Error getting disk space: $e');
      return 0;
    }
  }

  /// Gets total disk space in bytes.
  ///
  /// Returns 0 if unable to determine.
  Future<int> getTotalDiskSpace() async {
    try {
      final totalMB = await DiskSpace.getTotalDiskSpace ?? 0;
      return (totalMB * 1024 * 1024).round();
    } catch (e) {
      debugPrint('TelegramCacheService: Error getting total disk space: $e');
      return 0;
    }
  }

  // ============================================================
  // CACHE SIZE LIMIT (VIDEO-ONLY)
  // ============================================================

  /// Gets the user's video cache size limit preference.
  Future<CacheSizeLimit> getCacheSizeLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_cacheSizeLimitKey);

    if (index == null || index < 0 || index >= CacheSizeLimit.values.length) {
      return CacheSizeLimit.unlimited; // Default
    }

    return CacheSizeLimit.values[index];
  }

  /// Sets the user's video cache size limit preference.
  Future<void> setCacheSizeLimit(CacheSizeLimit limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cacheSizeLimitKey, limit.index);
    debugPrint('TelegramCacheService: Video cache limit set to ${limit.label}');
  }

  /// Enforces the video cache size limit using NVR-style cleanup.
  ///
  /// Deletes oldest video files until cache is within the limit.
  /// Also enforces a "Safety Buffer" - ensures at least 500MB of disk space remains free.
  Future<bool> enforceVideoSizeLimit() async {
    try {
      final userLimit = await getCacheSizeLimit();
      final stats = await getStorageStatistics();
      final availableDisk = await getAvailableDiskSpace();

      // Safety Buffer: Always keep at least 500MB free on disk
      const safetyBuffer = 500 * 1024 * 1024; // 500 MB

      // Calculate the maximum cache size allowed by physical disk space
      // MaxPossible = CurrentVideoSize + AvailableSpace - Buffer
      // We use CurrentVideoSize because 'AvailableSpace' doesn't count space currently used by cache
      final maxPhysicalLimit = stats.videoSize + availableDisk - safetyBuffer;

      // Determine effective limit (min of User Preference AND Physical Limit)
      int effectiveLimitBytes;

      if (userLimit.isUnlimited) {
        effectiveLimitBytes = maxPhysicalLimit;
      } else {
        effectiveLimitBytes = userLimit.sizeInBytes;
        // If physical space is tight, lower the limit
        if (maxPhysicalLimit < effectiveLimitBytes) {
          debugPrint(
            'TelegramCacheService: Disk space tight! Lowering limit from ${_formatBytes(effectiveLimitBytes)} to ${_formatBytes(maxPhysicalLimit)}',
          );
          effectiveLimitBytes = maxPhysicalLimit;
        }
      }

      // Ensure limit is not negative
      if (effectiveLimitBytes < 0) effectiveLimitBytes = 0;

      // Check if video size exceeds effective limit
      if (stats.videoSize <= effectiveLimitBytes) {
        debugPrint(
          'TelegramCacheService: Video cache (${_formatBytes(stats.videoSize)}) within effective limit (${_formatBytes(effectiveLimitBytes)})',
        );
        return true;
      }

      debugPrint(
        'TelegramCacheService: Video cache (${_formatBytes(stats.videoSize)}) exceeds effective limit (${_formatBytes(effectiveLimitBytes)}), cleaning up ${_formatBytes(stats.videoSize - effectiveLimitBytes)}...',
      );

      // Use optimizeStorage with size parameter for videos only
      // TDLib will delete least-recently-accessed videos to reach target size
      final result = await _telegramService.sendWithResult({
        '@type': 'optimizeStorage',
        'size': effectiveLimitBytes, // Target size for video cache
        'ttl': -1, // Use default TTL
        'count': -1, // No file count limit
        'immunity_delay': 0, // Allow deletion of all files (oldest first)
        'file_types': [
          {'@type': 'fileTypeVideo'},
          {'@type': 'fileTypeVideoNote'},
        ],
        'chat_ids': null, // All chats
        'exclude_chat_ids': null, // No exclusions
        'return_deleted_file_statistics': true,
        'chat_limit': 100,
      });

      if (result['@type'] == 'storageStatistics') {
        final deletedStats = StorageStatistics.fromTdLib(result);
        debugPrint(
          'TelegramCacheService: Cleaned up ${_formatBytes(deletedStats.videoSize)} of video cache '
          '(total deleted: ${_formatBytes(deletedStats.totalSize)})',
        );
        return true;
      }

      if (result['@type'] == 'error') {
        debugPrint(
          'TelegramCacheService: enforceVideoSizeLimit error: ${result['message']}',
        );
        return false;
      }

      return false;
    } catch (e) {
      debugPrint('TelegramCacheService: Error enforcing video size limit: $e');
      return false;
    }
  }

  // ADDED: Static stream for global disk safety state
  static final _diskCriticalController = StreamController<bool>.broadcast();
  Stream<bool> get onDiskCriticalState => _diskCriticalController.stream;

  static DateTime _lastSafetyCheck = DateTime.fromMillisecondsSinceEpoch(0);

  /// Checks if disk space is safe for writing.
  ///
  /// Returns `false` if disk space is CRITICALLY low (< 50MB) and writing should stop immediately.
  /// Triggers [enforceVideoSizeLimit] if space is in the warning zone (< 500MB).
  Future<bool> checkDiskSafety() async {
    // Throttle checks to avoid overhead
    final now = DateTime.now();
    if (now.difference(_lastSafetyCheck).inMilliseconds < 1000) {
      // Return true conservatively (assume safe if checked recently) or cache result?
      // For now, allow proceed to avoid blocking high-speed loops too often.
      return true;
    }
    _lastSafetyCheck = now;

    final available = await getAvailableDiskSpace();

    // CRITICAL: Stop everything if < 50MB free
    // This allows Binlog to breathe and prevents OS crash
    if (available < 50 * 1024 * 1024) {
      debugPrint(
        'TelegramCacheService: CRITICAL DISK SPACE ($available bytes). Blocking write.',
      );
      _diskCriticalController.add(true); // Emit critical state
      return false;
    }

    _diskCriticalController.add(false); // Emit safe state

    // WARNING: If < 500MB, trigger cleanup but allow writing
    if (available < 500 * 1024 * 1024) {
      // Don't await this, let it run in background
      enforceVideoSizeLimit();
    }

    return true;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ============================================================
  // KEEP MEDIA (TTL-based cleanup)
  // ============================================================

  /// Clears cached files based on the "Keep Media" TTL setting.
  ///
  /// If [forceAll] is true, clears ALL cached files regardless of TTL.
  /// Otherwise, respects the user's "Keep Media" preference.
  Future<bool> clearCache({bool forceAll = false}) async {
    try {
      final keepDuration = await getKeepMediaDuration();

      final result = await _telegramService.sendWithResult({
        '@type': 'optimizeStorage',
        'size': forceAll ? 0 : -1, // 0 = delete as much as possible
        'ttl': forceAll ? 0 : keepDuration.ttlSeconds, // 0 = delete everything
        'count': -1, // No file count limit
        'immunity_delay': 60, // Don't delete files accessed in last minute
        'file_types': null, // All file types
        'chat_ids': null, // All chats
        'exclude_chat_ids': null, // No exclusions
        'return_deleted_file_statistics': true,
        'chat_limit': 100,
      });

      if (result['@type'] == 'storageStatistics') {
        debugPrint('TelegramCacheService: Cache cleared successfully');

        // Also clear saved playback progress when clearing all cache
        // This avoids resume-after-cache-clear issues
        if (forceAll) {
          await PlaybackStorageService().clearAllPositions();
        }

        return true;
      }

      if (result['@type'] == 'error') {
        debugPrint(
          'TelegramCacheService: clearCache error: ${result['message']}',
        );
        return false;
      }

      return false;
    } catch (e) {
      debugPrint('TelegramCacheService: Error clearing cache: $e');
      return false;
    }
  }

  /// Runs storage optimization with the current "Keep Media" setting.
  ///
  /// This is called periodically or on app startup to clean old files.
  /// Also enforces video size limit if set.
  Future<void> runOptimization() async {
    // First enforce video size limit (NVR-style)
    await enforceVideoSizeLimit();

    // Then apply TTL-based cleanup if not "Forever"
    final keepDuration = await getKeepMediaDuration();

    if (keepDuration == KeepMediaDuration.forever) {
      debugPrint(
        'TelegramCacheService: Keep Media set to Forever, skipping TTL cleanup',
      );
      return;
    }

    debugPrint(
      'TelegramCacheService: Running optimization with TTL ${keepDuration.label}',
    );

    await clearCache(forceAll: false);
  }

  /// Gets the user's "Keep Media" duration preference.
  Future<KeepMediaDuration> getKeepMediaDuration() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_keepMediaKey);

    if (index == null ||
        index < 0 ||
        index >= KeepMediaDuration.values.length) {
      return KeepMediaDuration.forever; // Default
    }

    return KeepMediaDuration.values[index];
  }

  /// Sets the user's "Keep Media" duration preference.
  Future<void> setKeepMediaDuration(KeepMediaDuration duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keepMediaKey, duration.index);
    debugPrint('TelegramCacheService: Keep Media set to ${duration.label}');
  }

  /// Deletes a specific file from the cache by its file_id.
  Future<bool> deleteFile(int fileId) async {
    try {
      final result = await _telegramService.sendWithResult({
        '@type': 'deleteFile',
        'file_id': fileId,
      });

      return result['@type'] == 'ok';
    } catch (e) {
      debugPrint('TelegramCacheService: Error deleting file $fileId: $e');
      return false;
    }
  }
}
