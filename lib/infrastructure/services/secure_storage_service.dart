import 'package:encrypt_shared_preferences/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Centralized wrapper for encrypted SharedPreferences.
/// Provides a singleton pattern for consistent access across the app.
class SecureStorageService {
  static EncryptedSharedPreferences? _instance;
  static bool _legacyCleanupDone = false;

  // Encryption key - must be exactly 16 characters for AES-128
  static const String _encryptionKey = 'AnT1gR4v1ty_2026';

  // Keys used by the app that need cleanup from legacy unencrypted storage
  static const List<String> _legacyKeys = [
    'recent_videos',
    'recent_urls',
    'playback_position_',
    'is_dark_mode',
    'player_engine',
    'telegram_favorites',
    'telegram_keep_media_duration',
    'telegram_video_cache_size_limit',
  ];

  /// Initialize and get the encrypted preferences instance.
  /// Must be called once at app startup before any storage operations.
  static Future<void> initialize() async {
    if (_instance != null) return;

    // Clean up legacy unencrypted data (one-time)
    await _cleanupLegacyData();

    await EncryptedSharedPreferences.initialize(_encryptionKey);
    _instance = EncryptedSharedPreferences.getInstance();
  }

  /// Clean up old unencrypted SharedPreferences data.
  /// This runs once to remove data that was stored before encryption was enabled.
  static Future<void> _cleanupLegacyData() async {
    if (_legacyCleanupDone) return;
    _legacyCleanupDone = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      int cleanedCount = 0;

      for (final key in allKeys) {
        // Check if this key matches any of our legacy keys
        final shouldClean = _legacyKeys.any(
          (legacyKey) => key == legacyKey || key.startsWith(legacyKey),
        );

        if (shouldClean) {
          await prefs.remove(key);
          cleanedCount++;
        }
      }

      if (cleanedCount > 0) {
        debugPrint(
          'SecureStorageService: Cleaned up $cleanedCount legacy unencrypted keys',
        );
      }
    } catch (e) {
      debugPrint('SecureStorageService: Legacy cleanup error: $e');
    }
  }

  /// Get the singleton instance. Throws if not initialized.
  static EncryptedSharedPreferences get instance {
    if (_instance == null) {
      throw StateError(
        'SecureStorageService not initialized. Call initialize() first.',
      );
    }
    return _instance!;
  }

  /// Check if the service is initialized.
  static bool get isInitialized => _instance != null;
}
