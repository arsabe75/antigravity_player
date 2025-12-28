import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Representa un video en el historial
class RecentVideo {
  final String path;
  final String? title;
  final bool isNetwork;
  final DateTime playedAt;
  final Duration? lastPosition;

  /// Telegram-specific stable identifiers (survive cache clears)
  /// These are used to reconstruct proxy URLs and persist progress.
  final int? telegramChatId;
  final int? telegramMessageId;
  final int? telegramFileSize;

  RecentVideo({
    required this.path,
    this.title,
    required this.isNetwork,
    required this.playedAt,
    this.lastPosition,
    this.telegramChatId,
    this.telegramMessageId,
    this.telegramFileSize,
  });

  /// Returns a stable key for progress storage.
  /// For Telegram videos, uses chatId:messageId which survives cache clears.
  /// For local files, uses the file path.
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
    if (isNetwork) {
      try {
        final uri = Uri.parse(path);
        return uri.host;
      } catch (_) {
        return path;
      }
    }
    return path.split('/').last;
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
  );
}

/// Servicio para guardar y obtener videos recientes
class RecentVideosService {
  static const _key = 'recent_videos';
  static const _maxVideos = 50;

  /// Obtiene los videos recientes
  Future<List<RecentVideo>> getRecentVideos() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_key) ?? [];

    return jsonList
        .map((json) {
          try {
            return RecentVideo.fromJson(jsonDecode(json));
          } catch (_) {
            return null;
          }
        })
        .whereType<RecentVideo>()
        .toList();
  }

  /// Añade o actualiza un video en el historial
  ///
  /// For Telegram videos, provide [telegramChatId], [telegramMessageId], and
  /// [telegramFileSize] for stable identification that survives cache clears.
  Future<void> addVideo(
    String path, {
    String? title,
    bool isNetwork = false,
    Duration? position,
    int? telegramChatId,
    int? telegramMessageId,
    int? telegramFileSize,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final videos = await getRecentVideos();

    // Remove if already exists to update it (move to top)
    // Match by stable Telegram ID when available, otherwise by path
    String? existingTitle;
    int? existingChatId;
    int? existingMessageId;
    int? existingFileSize;

    int existingIndex = -1;
    if (telegramChatId != null && telegramMessageId != null) {
      // Match by stable Telegram message ID (survives cache clears)
      existingIndex = videos.indexWhere(
        (v) =>
            v.telegramChatId == telegramChatId &&
            v.telegramMessageId == telegramMessageId,
      );
    }
    if (existingIndex == -1) {
      // Fallback to path match
      existingIndex = videos.indexWhere((v) => v.path == path);
    }

    if (existingIndex != -1) {
      final existing = videos[existingIndex];
      existingTitle = existing.title;
      existingChatId = existing.telegramChatId;
      existingMessageId = existing.telegramMessageId;
      existingFileSize = existing.telegramFileSize;
      videos.removeAt(existingIndex);
    }

    // Add to beginning
    videos.insert(
      0,
      RecentVideo(
        path: path,
        title: title ?? existingTitle,
        isNetwork: isNetwork,
        playedAt: DateTime.now(),
        lastPosition: position,
        telegramChatId: telegramChatId ?? existingChatId,
        telegramMessageId: telegramMessageId ?? existingMessageId,
        telegramFileSize: telegramFileSize ?? existingFileSize,
      ),
    );

    // Keep only max videos
    if (videos.length > _maxVideos) {
      videos.removeRange(_maxVideos, videos.length);
    }

    // Save
    final jsonList = videos.map((v) => jsonEncode(v.toJson())).toList();
    await prefs.setStringList(_key, jsonList);
  }

  /// Actualiza la posición de un video
  Future<void> updatePosition(String path, Duration position) async {
    final prefs = await SharedPreferences.getInstance();
    final videos = await getRecentVideos();

    final index = videos.indexWhere((v) => v.path == path);
    if (index != -1) {
      final video = videos[index];
      videos[index] = RecentVideo(
        path: video.path,
        title: video.title,
        isNetwork: video.isNetwork,
        playedAt: video.playedAt,
        lastPosition: position,
        telegramChatId: video.telegramChatId,
        telegramMessageId: video.telegramMessageId,
        telegramFileSize: video.telegramFileSize,
      );

      final jsonList = videos.map((v) => jsonEncode(v.toJson())).toList();
      await prefs.setStringList(_key, jsonList);
    }
  }

  /// Elimina un video del historial
  Future<void> removeVideo(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final videos = await getRecentVideos();
    videos.removeWhere((v) => v.path == path);

    final jsonList = videos.map((v) => jsonEncode(v.toJson())).toList();
    await prefs.setStringList(_key, jsonList);
  }

  /// Limpia todo el historial
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Limpia solo los videos de Telegram
  Future<void> clearTelegramVideos() async {
    final prefs = await SharedPreferences.getInstance();
    final videos = await getRecentVideos();
    // Keep only non-Telegram videos
    videos.removeWhere((v) => v.isTelegramVideo);

    final jsonList = videos.map((v) => jsonEncode(v.toJson())).toList();
    await prefs.setStringList(_key, jsonList);
  }

  /// Limpia solo los videos locales y de red (no Telegram)
  Future<void> clearLocalVideos() async {
    final prefs = await SharedPreferences.getInstance();
    final videos = await getRecentVideos();
    // Keep only Telegram videos
    videos.removeWhere((v) => !v.isTelegramVideo);

    final jsonList = videos.map((v) => jsonEncode(v.toJson())).toList();
    await prefs.setStringList(_key, jsonList);
  }
}
