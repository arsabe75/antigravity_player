import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage service for TDLib database encryption key.
///
/// Uses platform-specific secure storage:
/// - Windows: Windows Credential Manager
/// - Linux: libsecret
/// - macOS: Keychain
///
/// The encryption key is generated once and stored securely.
/// This key is used to encrypt the TDLib SQLite database.
class TDLibEncryptionService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    wOptions: WindowsOptions(),
    lOptions: LinuxOptions(),
  );

  static const _keyName = 'tdlib_database_encryption_key';

  /// Gets or creates a secure encryption key for TDLib database.
  ///
  /// The key is stored in the platform's secure storage and is
  /// generated only once. Subsequent calls return the same key.
  ///
  /// Returns a Base64-encoded 256-bit key suitable for TDLib's
  /// database_encryption_key parameter.
  static Future<String> getOrCreateEncryptionKey() async {
    try {
      // Try to read existing key
      var key = await _storage.read(key: _keyName);

      if (key == null || key.isEmpty) {
        // Generate new 256-bit (32 bytes) random key
        final random = Random.secure();
        final bytes = List<int>.generate(32, (_) => random.nextInt(256));
        key = base64Encode(bytes);

        // Store securely
        await _storage.write(key: _keyName, value: key);

        if (kDebugMode) {
          debugPrint('TDLibEncryption: Generated new database encryption key');
        }
      } else {
        if (kDebugMode) {
          debugPrint('TDLibEncryption: Using existing database encryption key');
        }
      }

      return key;
    } catch (e) {
      // If secure storage fails (e.g., on unsupported platform),
      // return empty string to maintain backwards compatibility
      debugPrint('TDLibEncryption: Failed to access secure storage: $e');
      return '';
    }
  }

  /// Deletes the encryption key from secure storage.
  ///
  /// WARNING: This will make existing TDLib databases unreadable!
  /// Only call this when the user explicitly logs out and you want
  /// to clear all local data.
  static Future<void> deleteEncryptionKey() async {
    try {
      await _storage.delete(key: _keyName);
      if (kDebugMode) {
        debugPrint('TDLibEncryption: Deleted database encryption key');
      }
    } catch (e) {
      debugPrint('TDLibEncryption: Failed to delete encryption key: $e');
    }
  }
}
