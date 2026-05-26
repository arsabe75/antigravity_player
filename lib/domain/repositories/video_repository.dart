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

  /// Returns the media_kit track ID string for a given audio track index.
  /// Returns null if the index is out of bounds or tracks are unavailable.
  String? getAudioTrackId(int index);

  /// Returns the media_kit track ID string for a given subtitle track index.
  /// Returns null if the index is out of bounds or tracks are unavailable.
  String? getSubtitleTrackId(int index);

  /// Finds the audio track index by its media_kit ID string.
  /// Returns null if no track with the given ID is found.
  int? findAudioTrackIndexById(String id);

  /// Finds the subtitle track index by its media_kit ID string.
  /// Returns null if no track with the given ID is found.
  int? findSubtitleTrackIndexById(String id);

  /// Stream that emits when available tracks change (for streaming videos)
  Stream<void> get tracksChangedStream;

  /// Stream that emits player errors (codec issues, network problems, etc.)
  Stream<String> get errorStream;

  /// Applies user-configured subtitle styling (font size, color, outline).
  /// No-op for backends that don't support subtitle rendering.
  Future<void> applySubtitleSettings();
}
