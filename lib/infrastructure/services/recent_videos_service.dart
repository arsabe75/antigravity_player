import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Representa un video en el historial
class RecentVideo {
  final String path;
  final bool isNetwork;
  final DateTime playedAt;
  final Duration? lastPosition;

  RecentVideo({
    required this.path,
    required this.isNetwork,
    required this.playedAt,
    this.lastPosition,
  });

  /// Obtiene el nombre del archivo o dominio
  String get displayName {
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
    'isNetwork': isNetwork,
    'playedAt': playedAt.toIso8601String(),
    'lastPosition': lastPosition?.inMilliseconds,
  };

  factory RecentVideo.fromJson(Map<String, dynamic> json) => RecentVideo(
    path: json['path'] as String,
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
    bool isNetwork = false,
    Duration? position,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final videos = await getRecentVideos();

    // Remove if already exists
    videos.removeWhere((v) => v.path == path);

    // Add to beginning
    videos.insert(
      0,
      RecentVideo(
        path: path,
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
