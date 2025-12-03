import 'dart:async';
import 'dart:io';

import 'package:video_player/video_player.dart';

import '../../domain/entities/video_entity.dart';
import '../../domain/repositories/video_repository.dart';

class VideoRepositoryImpl implements VideoRepository {
  VideoPlayerController? _controller;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _isBufferingController = StreamController<bool>.broadcast();

  Timer? _positionTimer;

  @override
  Future<void> initialize() async {
    // FVP registration is typically done at app startup, but we can ensure it here or in main.
    // For this repo, we assume main.dart calls registerWith() or we do it here if safe.
    // fvp.registerWith(); // Usually called in main.
  }

  @override
  Future<void> dispose() async {
    _positionTimer?.cancel();
    await _controller?.dispose();
    _controller = null;
    // Don't close stream controllers if this repo is singleton/long-lived,
    // but if it's scoped, we should. For now, we'll keep them open or close if we implement full dispose logic.
  }

  @override
  Future<void> play(VideoEntity video) async {
    _positionTimer?.cancel();
    await _controller?.dispose();

    if (video.isNetwork) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(video.path));
    } else {
      _controller = VideoPlayerController.file(File(video.path));
    }

    await _controller!.initialize();

    // FVP specific configuration if needed, usually automatic via video_player_mdk/fvp

    _controller!.addListener(_onControllerUpdate);
    await _controller!.play();
    _startPositionTimer();

    // Emit initial duration
    if (_controller!.value.duration != Duration.zero) {
      _durationController.add(_controller!.value.duration);
    }
  }

  void _onControllerUpdate() {
    if (_controller == null) return;
    final value = _controller!.value;

    _isPlayingController.add(value.isPlaying);
    _isBufferingController.add(value.isBuffering);

    if (value.duration != Duration.zero) {
      _durationController.add(value.duration);
    }
  }

  void _startPositionTimer() {
    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_controller != null && _controller!.value.isPlaying) {
        _positionController.add(_controller!.value.position);
      }
    });
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
  Duration get currentPosition => _controller?.value.position ?? Duration.zero;

  @override
  Duration get totalDuration => _controller?.value.duration ?? Duration.zero;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  // Helper to expose controller for VideoPlayer widget
  VideoPlayerController? get controller => _controller;
}
