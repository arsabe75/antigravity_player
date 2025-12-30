import '../entities/video_entity.dart';

abstract class VideoRepository {
  Future<void> initialize();
  Future<void> dispose();
  Future<void> play(VideoEntity video, {Duration? startPosition});
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

  /// Exposes the underlying VideoController for the Video widget
  /// Return type is dynamic/Object to support both MediaKit and VideoPlayer controllers
  Object? get platformController;

  /// Sets the playback speed
  Future<void> setPlaybackSpeed(double speed);

  /// Gets available audio tracks (ID: Name)
  Future<Map<int, String>> getAudioTracks();

  /// Gets available subtitle tracks (ID: Name)
  Future<Map<int, String>> getSubtitleTracks();

  /// Sets the audio track by ID
  Future<void> setAudioTrack(int trackId);

  /// Sets the subtitle track by ID
  Future<void> setSubtitleTrack(int trackId);

  /// Stream that emits when available tracks change (for streaming videos)
  Stream<void> get tracksChangedStream;

  /// Stream that emits player errors (codec issues, network problems, etc.)
  Stream<String> get errorStream;
}
