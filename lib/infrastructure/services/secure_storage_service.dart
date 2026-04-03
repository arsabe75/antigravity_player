import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';

/// Facade to maintain the synchronous read / async write interface 
/// for the app's key-value configurations, now backed by Drift.
class StorageFacade {
  final AppDatabase _db;
  final Map<String, String> _cache;

  StorageFacade(this._db, this._cache);

  Future<bool> _save(String key, String value) async {
    _cache[key] = value;
    try {
      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSetting(key: key, value: value),
          );
      return true;
    } catch (e) {
      debugPrint('StorageFacade error: $e');
      return false;
    }
  }

  String? getString(String key) => _cache[key];

  Future<bool> setString(String key, String value) => _save(key, value);

  int? getInt(String key) {
    var val = _cache[key];
    return val == null ? null : int.tryParse(val);
  }

  Future<bool> setInt(String key, int value) => _save(key, value.toString());

  bool? getBool(String key) {
    var val = _cache[key];
    if (val == 'true') return true;
    if (val == 'false') return false;
    return null;
  }

  Future<bool> setBool(String key, bool value) => _save(key, value.toString());

  List<String>? getStringList(String key) {
    var val = _cache[key];
    if (val == null) return null;
    try {
      final List<dynamic> decoded = jsonDecode(val);
      return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return null;
    }
  }

  Future<bool> setStringList(String key, List<String> value) =>
      _save(key, jsonEncode(value));

  Iterable<String> getKeys() => _cache.keys;

  Future<bool> remove(String key) async {
    _cache.remove(key);
    try {
      await (_db.delete(_db.appSettings)..where((tbl) => tbl.key.equals(key)))
          .go();
      return true;
    } catch (e) {
      debugPrint('StorageFacade error deleting $key: $e');
      return false;
    }
  }

  Future<bool> clear() async {
    _cache.clear();
    try {
      await _db.delete(_db.appSettings).go();
      return true;
    } catch (e) {
      debugPrint('StorageFacade error clearing: $e');
      return false;
    }
  }
}

/// Centralized wrapper for app settings, previously encrypted SharedPreferences.
/// Now using Drift for ACID-compliant, robust local storage that prevents corruption.
class SecureStorageService {
  static StorageFacade? _instance;

  /// Initialize and get the database backed preferences instance.
  /// Must be called once at app startup before any storage operations.
  static Future<void> initialize() async {
    if (_instance != null) return;

    final db = AppDatabase();
    final allSettings = await db.select(db.appSettings).get();

    final cache = <String, String>{};
    for (var setting in allSettings) {
      cache[setting.key] = setting.value;
    }

    _instance = StorageFacade(db, cache);
  }

  @visibleForTesting
  static Future<void> initializeForTest(AppDatabase testDb) async {
    _instance = StorageFacade(testDb, {});
  }

  /// Get the singleton instance. Throws if not initialized.
  static StorageFacade get instance {
    if (_instance == null) {
      throw StateError(
        'SecureStorageService not initialized. Call initialize() first.',
      );
    }
    return _instance!;
  }

  /// Check if the service is initialized.
  static bool get isInitialized => _instance != null;

    @visibleForTesting
  static void reset() {
    _instance = null;
  }
}
