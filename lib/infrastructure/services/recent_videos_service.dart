import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Representa un video en el historial
class RecentVideo {
  final String path;
  final String? title;
  final bool isNetwork;
  final DateTime playedAt;
  final Duration? lastPosition;

  RecentVideo({
    required this.path,
    this.title,
    required this.isNetwork,
    required this.playedAt,
    this.lastPosition,
  });

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
  };

  factory RecentVideo.fromJson(Map<String, dynamic> json) => RecentVideo(
    path: json['path'] as String,
    title: json['title'] as String?,
    isNetwork: json['isNetwork'] as bool,
    playedAt: DateTime.parse(json['playedAt'] as String),
    lastPosition: json['lastPosition'] != null
        ? Duration(milliseconds: json['lastPosition'] as int)
        : null,
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
  Future<void> addVideo(
    String path, {
    String? title,
    bool isNetwork = false,
    Duration? position,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final videos = await getRecentVideos();

    // Remove if already exists to update it (move to top)
    // Preserve title if new title is null
    String? existingTitle;
    final existingIndex = videos.indexWhere((v) => v.path == path);
    if (existingIndex != -1) {
      existingTitle = videos[existingIndex].title;
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
        title: video.title, // Preserve title
        isNetwork: video.isNetwork,
        playedAt: video.playedAt,
        lastPosition: position,
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
}
