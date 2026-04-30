import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';
import '../database/app_database.dart' as db;

/// Representa un video en el historial
class RecentVideo {
  final String path;
  final String? title;
  final bool isNetwork;
  final DateTime playedAt;
  final Duration? lastPosition;

  /// Telegram-specific stable identifiers (survive cache clears)
  final int? telegramChatId;
  final int? telegramMessageId;
  final int? telegramFileSize;

  /// Topic information for forum videos
  final int? telegramTopicId;
  final String? telegramTopicName;

  RecentVideo({
    required this.path,
    this.title,
    required this.isNetwork,
    required this.playedAt,
    this.lastPosition,
    this.telegramChatId,
    this.telegramMessageId,
    this.telegramFileSize,
    this.telegramTopicId,
    this.telegramTopicName,
  });

  /// Returns a stable key for progress storage.
  String get stableProgressKey {
    if (telegramChatId != null && telegramMessageId != null) {
      return 'telegram_${telegramChatId}_$telegramMessageId';
    }
    return path;
  }

  /// Returns true if this is a Telegram video with stable identifiers.
  bool get isTelegramVideo =>
      telegramChatId != null && telegramMessageId != null;

  /// Obtiene el nombre del archivo o dominio
  String get displayName {
    if (title != null && title!.isNotEmpty) {
      return title!;
    }
    if (isNetwork && !isTelegramVideo) {
      try {
        final uri = Uri.parse(path);
        return uri.host;
      } catch (_) {
        return path;
      }
    }
    return p.basename(path);
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'isNetwork': isNetwork,
    'playedAt': playedAt.toIso8601String(),
    'lastPosition': lastPosition?.inMilliseconds,
    'telegramChatId': telegramChatId,
    'telegramMessageId': telegramMessageId,
    'telegramFileSize': telegramFileSize,
    'telegramTopicId': telegramTopicId,
    'telegramTopicName': telegramTopicName,
  };

  factory RecentVideo.fromJson(Map<String, dynamic> json) => RecentVideo(
    path: json['path'] as String,
    title: json['title'] as String?,
    isNetwork: json['isNetwork'] as bool,
    playedAt: DateTime.parse(json['playedAt'] as String),
    lastPosition: json['lastPosition'] != null
        ? Duration(milliseconds: json['lastPosition'] as int)
        : null,
    telegramChatId: json['telegramChatId'] as int?,
    telegramMessageId: json['telegramMessageId'] as int?,
    telegramFileSize: json['telegramFileSize'] as int?,
    telegramTopicId: json['telegramTopicId'] as int?,
    telegramTopicName: json['telegramTopicName'] as String?,
  );

  factory RecentVideo.fromDb(db.RecentVideo dbVideo) {
    return RecentVideo(
      path: dbVideo.path,
      title: dbVideo.title,
      isNetwork: dbVideo.isNetwork,
      playedAt: dbVideo.playedAt,
      lastPosition: dbVideo.lastPosition != null
          ? Duration(milliseconds: dbVideo.lastPosition!)
          : null,
      telegramChatId: dbVideo.telegramChatId,
      telegramMessageId: dbVideo.telegramMessageId,
      telegramFileSize: dbVideo.telegramFileSize,
      telegramTopicId: dbVideo.telegramTopicId,
      telegramTopicName: dbVideo.telegramTopicName,
    );
  }
}

/// Servicio para guardar y obtener videos recientes
class RecentVideosService {
  static const _maxVideos = 50;
  static bool _migrated = false;

  db.AppDatabase get _db => SecureStorageService.instance.database;

  Future<void> _migrateIfNeeded() async {
    if (_migrated) return;
    try {
      final prefs = SecureStorageService.instance;
      final oldList = prefs.getStringList('recent_videos');
      if (oldList != null && oldList.isNotEmpty) {
        debugPrint('Migrating ${oldList.length} recent videos to Drift...');
        for (final jsonStr in oldList.reversed) {
          try {
            final Map<String, dynamic> map = jsonDecode(jsonStr);
            final video = RecentVideo.fromJson(map);
            await _db.into(_db.recentVideos).insertOnConflictUpdate(
              db.RecentVideosCompanion.insert(
                path: video.path,
                title: Value(video.title),
                isNetwork: Value(video.isNetwork),
                isTelegram: Value(video.isTelegramVideo),
                playedAt: video.playedAt,
                lastPosition: Value(video.lastPosition?.inMilliseconds),
                telegramChatId: Value(video.telegramChatId),
                telegramMessageId: Value(video.telegramMessageId),
                telegramFileSize: Value(video.telegramFileSize),
                telegramTopicId: Value(video.telegramTopicId),
                telegramTopicName: Value(video.telegramTopicName),
              ),
            );
          } catch (e) {
            debugPrint('Error migrating single video: $e');
          }
        }
        await prefs.remove('recent_videos');
        debugPrint('Migration complete.');
      }
      _migrated = true;
    } catch (e) {
      debugPrint('Error migrating recent videos: $e');
    }
  }

  /// Obtiene los videos recientes (todos combinados)
  Future<List<RecentVideo>> getRecentVideos() async {
    await _migrateIfNeeded();
    final query = _db.select(_db.recentVideos)
      ..orderBy([(t) => OrderingTerm(expression: t.playedAt, mode: OrderingMode.desc)]);
    
    final dbVideos = await query.get();
    return dbVideos.map((v) => RecentVideo.fromDb(v)).toList();
  }

  /// Añade o actualiza un video en el historial
  Future<void> addVideo(
    String path, {
    String? title,
    bool isNetwork = false,
    Duration? position,
    int? telegramChatId,
    int? telegramMessageId,
    int? telegramFileSize,
    int? telegramTopicId,
    String? telegramTopicName,
  }) async {
    await _migrateIfNeeded();
    final isTelegram = telegramChatId != null && telegramMessageId != null;

    // First delete old entries with same telegram stable id if telegram
    if (isTelegram) {
      await (_db.delete(_db.recentVideos)
            ..where((t) => t.telegramChatId.equals(telegramChatId) &
                           t.telegramMessageId.equals(telegramMessageId)))
          .go();
    }

    // Insert new entry (conflict update by path)
    await _db.into(_db.recentVideos).insertOnConflictUpdate(
      db.RecentVideosCompanion.insert(
        path: path,
        title: Value(title),
        isNetwork: Value(isNetwork),
        isTelegram: Value(isTelegram),
        playedAt: DateTime.now(),
        lastPosition: Value(position?.inMilliseconds),
        telegramChatId: Value(telegramChatId),
        telegramMessageId: Value(telegramMessageId),
        telegramFileSize: Value(telegramFileSize),
        telegramTopicId: Value(telegramTopicId),
        telegramTopicName: Value(telegramTopicName),
      ),
    );

    // Enforce limits per category
    await _enforceLimits(isTelegram: isTelegram);
  }

  Future<void> _enforceLimits({required bool isTelegram}) async {
    final query = _db.select(_db.recentVideos)
      ..where((t) => t.isTelegram.equals(isTelegram))
      ..orderBy([(t) => OrderingTerm(expression: t.playedAt, mode: OrderingMode.desc)]);
    
    final videos = await query.get();
    if (videos.length > _maxVideos) {
      final videosToDelete = videos.sublist(_maxVideos);
      for (final v in videosToDelete) {
        await (_db.delete(_db.recentVideos)..where((t) => t.path.equals(v.path))).go();
      }
    }
  }

  /// Actualiza la posición de un video
  Future<void> updatePosition(String path, Duration position) async {
    await _migrateIfNeeded();
    await (_db.update(_db.recentVideos)..where((t) => t.path.equals(path)))
        .write(db.RecentVideosCompanion(lastPosition: Value(position.inMilliseconds)));
  }

  /// Elimina un video del historial
  Future<void> removeVideo(String path) async {
    await _migrateIfNeeded();
    await (_db.delete(_db.recentVideos)..where((t) => t.path.equals(path))).go();
  }

  /// Limpia todo el historial
  Future<void> clearAll() async {
    await _migrateIfNeeded();
    await _db.delete(_db.recentVideos).go();
  }

  /// Limpia solo los videos de Telegram
  Future<void> clearTelegramVideos() async {
    await _migrateIfNeeded();
    await (_db.delete(_db.recentVideos)..where((t) => t.isTelegram.equals(true))).go();
  }

  /// Limpia solo los videos locales y de red (no Telegram)
  Future<void> clearLocalVideos() async {
    await _migrateIfNeeded();
    await (_db.delete(_db.recentVideos)..where((t) => t.isTelegram.equals(false))).go();
  }
}
