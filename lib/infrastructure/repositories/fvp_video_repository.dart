import 'dart:async';
import 'dart:io';
import 'package:fvp/fvp.dart' as fvp;
import 'package:video_player/video_player.dart';
import '../../domain/entities/video_entity.dart';
import '../../domain/repositories/video_repository.dart';

/// FVP-based video repository using the video_player package with libmpv backend.
///
/// **WARNING: Streaming Limitation**
/// FVP/video_player has issues with seeking in streaming videos (e.g., Telegram proxy):
/// - Seeks create multiple parallel HTTP connections
/// - Buffer options in registerWith() don't fully control seek behavior
/// - Video may get stuck loading when seeking to unbuffered positions
///
/// **Recommendation:**
/// - Use FVP for local/completed files where all data is available
/// - Use MediaKitVideoRepository for streaming Telegram content
///
/// The buffer settings match media_kit for consistency when playback works correctly.
class FvpVideoRepository implements VideoRepository {
  VideoPlayerController? _controller;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _isBufferingController = StreamController<bool>.broadcast();

  Timer? _poller;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;

  @override
  Future<void> initialize() async {
    // Register FVP with HW acceleration and buffer settings
    // These match the media_kit configuration for consistent streaming
    fvp.registerWith(
      options: {
        // Hardware decoding
        'hwdec': 'auto',
        // Buffer settings for streaming
        'demuxer-max-bytes': '67108864', // 64MB demuxer buffer
        'demuxer-max-back-bytes': '33554432', // 32MB back buffer
        'cache': 'yes',
        'cache-secs': '20', // Require 20 seconds of buffer
        'cache-pause-initial': 'yes', // Pre-buffer before start
        'stream-buffer-size': '16777216', // 16MB stream buffer
      },
    );
  }

  @override
  Future<void> dispose() async {
    _stopPoller();
    await _controller?.dispose();
    _controller = null;
    await _positionController.close();
    await _durationController.close();
    await _isPlayingController.close();
    await _isBufferingController.close();
  }

  void _startPoller() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_controller == null || !_controller!.value.isInitialized) return;

      final value = _controller!.value;

      // Position
      if (value.position != _currentPosition) {
        _currentPosition = value.position;
        _positionController.add(_currentPosition);
      }

      // Duration
      if (value.duration != _totalDuration) {
        _totalDuration = value.duration;
        _durationController.add(_totalDuration);
      }

      // Playing
      if (value.isPlaying != _isPlaying) {
        _isPlaying = value.isPlaying;
        _isPlayingController.add(_isPlaying);
      }

      // Buffering
      if (value.isBuffering != _isBuffering) {
        _isBuffering = value.isBuffering;
        _isBufferingController.add(_isBuffering);
      }
    });
  }

  void _stopPoller() {
    _poller?.cancel();
    _poller = null;
  }

  @override
  Future<void> play(VideoEntity video) async {
    if (_controller != null) {
      await _controller!.dispose();
    }

    if (video.isNetwork) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(video.path));
    } else {
      _controller = VideoPlayerController.file(File(video.path));
    }

    await _controller!.initialize();
    _startPoller();
    await _controller!.play();
  }

  @override
  Future<void> pause() async {
    await _controller?.pause();
  }

  @override
  Future<void> resume() async {
    await _controller?.play();
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _controller?.seekTo(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _controller?.setVolume(volume);
  }

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<bool> get isPlayingStream => _isPlayingController.stream;

  @override
  Stream<bool> get isBufferingStream => _isBufferingController.stream;

  @override
  Duration get currentPosition => _currentPosition;

  @override
  Duration get totalDuration => _totalDuration;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Object? get platformController => _controller;

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    await _controller?.setPlaybackSpeed(speed);
  }

  @override
  Future<Map<int, String>> getAudioTracks() async {
    // Not supported in base video_player/FVP easily exposed yet
    return {};
  }

  @override
  Future<Map<int, String>> getSubtitleTracks() async {
    // Not supported in base video_player/FVP easily exposed yet
    return {};
  }

  @override
  Future<void> setAudioTrack(int trackId) async {
    // No-op
  }

  @override
  Future<void> setSubtitleTrack(int trackId) async {
    // No-op
  }

  // FVP doesn't support track detection - return empty stream
  @override
  Stream<void> get tracksChangedStream => const Stream.empty();

  // FVP doesn't have a built-in error stream mechanism
  @override
  Stream<String> get errorStream => const Stream.empty();
}
