import 'package:video_player/video_player.dart';

import '../entities/video_entity.dart';

abstract class VideoRepository {
  Future<void> initialize();
  Future<void> dispose();
  Future<void> play(VideoEntity video);
  Future<void> pause();
  Future<void> resume();
  Future<void> seekTo(Duration position);
  Future<void> setVolume(double volume);
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get isPlayingStream;
  Stream<bool> get isBufferingStream;
  Duration get currentPosition;
  Duration get totalDuration;
  bool get isPlaying;

  /// Exposes the underlying VideoPlayerController for the VideoPlayer widget
  VideoPlayerController? get controller;
}
