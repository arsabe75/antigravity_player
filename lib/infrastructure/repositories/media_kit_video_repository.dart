import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../domain/entities/video_entity.dart';
import '../../domain/repositories/video_repository.dart';
import '../services/local_streaming_proxy.dart';

class MediaKitVideoRepository implements VideoRepository {
  Player? _player;
  VideoController? _controller;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _isBufferingController = StreamController<bool>.broadcast();

  StreamSubscription? _playerSub;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  String? _videoUrl; // Track URL for cancellation

  @override
  Future<void> initialize() async {
    // MediaKit initialization is done in main.dart
  }

  @override
  Future<void> dispose() async {
    // If we were playing a proxy URL, extract file_id and abort proxy wait
    if (_videoUrl != null && _videoUrl!.contains('/stream?file_id=')) {
      try {
        final uri = Uri.parse(_videoUrl!);
        final idStr = uri.queryParameters['file_id'];
        if (idStr != null) {
          LocalStreamingProxy().abortRequest(int.parse(idStr));
        }
      } catch (e) {
        debugPrint('MediaKitVideoRepository: Error parsing abort URL: $e');
      }
    }

    _playerSub?.cancel();
    await _player?.dispose();
    _player = null;
    _controller = null;
    await _positionController.close();
    await _durationController.close();
    await _isPlayingController.close();
    await _isBufferingController.close();
  }

  @override
  Future<void> play(VideoEntity video) async {
    // Clean up previous instance partially if needed, or re-use
    // For now, let's create a new player per video for safety
    if (_player != null) {
      await _player!.dispose();
    }

    _player = Player(
      configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024),
    );

    String? hwdec;
    if (Platform.isWindows) {
      hwdec = 'd3d11';
    } else if (Platform.isLinux) {
      // Explictly use 'vaapi' to offload CPU for TDLib
      hwdec = 'vaapi';
    } else {
      hwdec = 'auto'; // Fallback
    }

    _controller = VideoController(
      _player!,
      configuration: VideoControllerConfiguration(hwdec: hwdec),
    );
    // Set properties directly on player for network caching
    await (_player!.platform as dynamic).setProperty('cache', 'yes');
    // Critical: Increase low-level stream buffer for TDLib proxy streaming
    await (_player!.platform as dynamic).setProperty(
      'stream-buffer-size',
      (16 * 1024 * 1024).toString(),
    ); // 16MB stream buffer
    // Increase demuxer buffer to handle high-bitrate hiccups
    await (_player!.platform as dynamic).setProperty(
      'demuxer-max-bytes',
      (64 * 1024 * 1024).toString(),
    ); // 64MB demuxer (reduced from 128 to save RAM)
    await (_player!.platform as dynamic).setProperty(
      'demuxer-max-back-bytes',
      (32 * 1024 * 1024).toString(),
    ); // 32MB back buffer
    await (_player!.platform as dynamic).setProperty(
      'network-timeout',
      '60',
    ); // 60s timeout for network reads
    await (_player!.platform as dynamic).setProperty(
      'cache-pause',
      'yes',
    ); // Allow pause for buffering
    await (_player!.platform as dynamic).setProperty(
      'cache-pause-initial',
      'yes',
    ); // Pre-buffer before start
    // Require 20 seconds of buffered content - prevents frame drops at start
    await (_player!.platform as dynamic).setProperty(
      'cache-secs',
      '20',
    ); // Listen to streams
    _playerSub = _player!.stream.position.listen((pos) {
      _currentPosition = pos;
      _positionController.add(pos);
    });

    _player!.stream.duration.listen((dur) {
      _totalDuration = dur;
      _durationController.add(dur);
    });

    _player!.stream.playing.listen((playing) {
      _isPlaying = playing;
      _isPlayingController.add(playing);
    });

    _player!.stream.buffering.listen((buffering) {
      _isBufferingController.add(buffering);
    });

    await _player!.open(Media(video.path));
    _videoUrl = video.path;

    // Force Unmute & Volume 100
    await _player!.setVolume(100);

    // Auto-select first audio track if "no" is selected or silent.
    // We listen to tracks changes
    _player!.stream.tracks.listen((tracks) {
      if (tracks.audio.isNotEmpty) {
        // If current is 'no', switch to first available
        if (_player!.state.track.audio.id == 'no' && tracks.audio.length > 2) {
          // tracks usually has [no, auto, track1...]
          // Try to find the first real track
          final realTrack = tracks.audio.firstWhere(
            (t) => t.id != 'no' && t.id != 'auto',
            orElse: () => tracks.audio.last,
          );
          if (realTrack.id != 'no') {
            debugPrint(
              'MediaKitVideoRepository: Auto-selecting audio track: ${realTrack.id}',
            );
            _player!.setAudioTrack(realTrack);
          }
        }
      }
    });
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
    await _player?.play();
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _player?.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _player?.setVolume(volume * 100); // media_kit wraps libmpv 0-100
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
    await _player?.setRate(speed);
  }

  @override
  Future<Map<int, String>> getAudioTracks() async {
    if (_player == null) return {};
    final tracks = _player!.state.tracks.audio;
    final Map<int, String> result = {};

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      if (track.id == 'no') {
        result[i] = 'Off';
        continue;
      }
      if (track.id == 'auto') {
        result[i] = 'Auto';
        continue;
      }

      var name = track.language ?? track.title ?? 'Audio ${i + 1}';
      // Append codec if useful and not redundant
      if (track.codec != null) name += ' (${track.codec})';

      // If we have both title and language, maybe show both?
      if (track.title != null && track.language != null) {
        name = '${track.title} - ${track.language}';
        if (track.codec != null) name += ' (${track.codec})';
      }

      result[i] = name;
    }
    return result;
  }

  // Helper to get actual track object
  // Since we don't return objects in interface, we need to fetch state again or cache.
  // Ideally, valid call is only when state is valid.

  @override
  Future<Map<int, String>> getSubtitleTracks() async {
    if (_player == null) return {};
    final tracks = _player!.state.tracks.subtitle;
    final Map<int, String> result = {};
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      if (track.id == 'no') {
        result[i] = 'Off';
        continue;
      }
      if (track.id == 'auto') {
        result[i] = 'Auto';
        continue;
      }

      var name = track.language ?? track.title ?? 'Subtitle ${i + 1}';

      if (track.title != null && track.language != null) {
        name = '${track.title} - ${track.language}';
      }

      if (track.codec != null) name += ' (${track.codec})';
      result[i] = name;
    }
    return result;
  }

  @override
  Future<void> setAudioTrack(int trackId) async {
    if (_player == null) return;
    final tracks = _player!.state.tracks.audio;
    if (trackId >= 0 && trackId < tracks.length) {
      await _player!.setAudioTrack(tracks[trackId]);
    }
  }

  @override
  Future<void> setSubtitleTrack(int trackId) async {
    if (_player == null) return;
    final tracks = _player!.state.tracks.subtitle;
    if (trackId >= 0 && trackId < tracks.length) {
      await _player!.setSubtitleTrack(tracks[trackId]);
    }
  }
}
