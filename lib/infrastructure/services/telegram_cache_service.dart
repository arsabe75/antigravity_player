import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/storage_statistics.dart';
import 'telegram_service.dart';

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
/// - optimizeStorage() for cleanup with configurable TTL
/// - Manual cache clearing
class TelegramCacheService {
  static const String _keepMediaKey = 'telegram_keep_media_duration';

  final TelegramService _telegramService;

  TelegramCacheService({TelegramService? telegramService})
    : _telegramService = telegramService ?? TelegramService();

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
  Future<void> runOptimization() async {
    final keepDuration = await getKeepMediaDuration();

    if (keepDuration == KeepMediaDuration.forever) {
      debugPrint(
        'TelegramCacheService: Keep Media set to Forever, skipping optimization',
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
