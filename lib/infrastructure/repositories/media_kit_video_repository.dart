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
  final _tracksChangedController = StreamController<void>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  StreamSubscription? _playerSub;
  StreamSubscription? _tracksSub;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  String? _videoUrl; // Track URL for cancellation

  int _initId = 0; // Token to track active initialization

  @override
  Future<void> initialize() async {
    // MediaKit initialization is done in main.dart
  }

  @override
  Future<void> dispose() async {
    _initId++; // Cancel pending ops

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

    // Cancel subscriptions first
    await _playerSub?.cancel();
    _playerSub = null;
    await _tracksSub?.cancel();
    _tracksSub = null;

    // Dispose player with error handling (may already be disposed)
    if (_player != null) {
      try {
        await _player!.dispose();
      } catch (e) {
        debugPrint(
          'MediaKitVideoRepository: Player dispose error (ignored): $e',
        );
      }
      _player = null;
    }
    _controller = null;
    _videoUrl = null;

    // Close StreamControllers safely (check if not already closed)
    if (!_positionController.isClosed) {
      await _positionController.close();
    }
    if (!_durationController.isClosed) {
      await _durationController.close();
    }
    if (!_isPlayingController.isClosed) {
      await _isPlayingController.close();
    }
    if (!_isBufferingController.isClosed) {
      await _isBufferingController.close();
    }
    if (!_tracksChangedController.isClosed) {
      await _tracksChangedController.close();
    }
    if (!_errorController.isClosed) {
      await _errorController.close();
    }
  }

  /// Helper to initialize player once and reuse it
  Future<void> _ensurePlayerInitialized(int currentId) async {
    if (_player != null) return;

    final player = Player(
      configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024),
    );
    _player = player;

    String? hwdec;
    if (Platform.isWindows) {
      hwdec = 'd3d11';
    } else if (Platform.isLinux) {
      hwdec = 'vaapi';
    } else {
      hwdec = 'auto';
    }

    _controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(hwdec: hwdec),
    );

    // One-time property setup
    // Exception checks not strictly needed here as we just created it, but good practice
    Future<void> setProp(String key, String value) async {
      if (_initId != currentId) return;
      try {
        await (player.platform as dynamic).setProperty(key, value);
      } catch (e) {
        debugPrint(
          'MediaKit: Error setting $key in _ensurePlayerInitialized: $e',
        );
      }
    }

    await setProp('cache', 'yes');
    if (_initId != currentId) return;
    await setProp('stream-buffer-size', (16 * 1024 * 1024).toString());
    if (_initId != currentId) return;
    await setProp('demuxer-max-bytes', (64 * 1024 * 1024).toString());
    if (_initId != currentId) return;
    await setProp('demuxer-max-back-bytes', (32 * 1024 * 1024).toString());
    if (_initId != currentId) return;
    await setProp('network-timeout', '60');
    if (_initId != currentId) return;
    await setProp('cache-pause', 'yes');
    if (_initId != currentId) return;
    await setProp('cache-pause-initial', 'yes');
    if (_initId != currentId) return;
    await setProp('cache-secs', '20');
    if (_initId != currentId) return;

    // One-time listener setup
    _playerSub = player.stream.position.listen((pos) {
      _currentPosition = pos;
      _positionController.add(pos);
    });

    player.stream.duration.listen((dur) {
      _totalDuration = dur;
      _durationController.add(dur);
    });

    player.stream.playing.listen((playing) {
      _isPlaying = playing;
      _isPlayingController.add(playing);
    });

    player.stream.buffering.listen((buffering) {
      _isBufferingController.add(buffering);
    });

    player.stream.error.listen((error) {
      debugPrint('MediaKit Error: $error');
      _errorController.add(error);
    });

    // Track selection logic
    _tracksSub = player.stream.tracks.listen((tracks) {
      _tracksChangedController.add(null);

      // Auto-select first audio track if "no" is selected
      if (tracks.audio.isNotEmpty) {
        if (player.state.track.audio.id == 'no' && tracks.audio.length > 2) {
          final realTrack = tracks.audio.firstWhere(
            (t) => t.id != 'no' && t.id != 'auto',
            orElse: () => tracks.audio.last,
          );
          if (realTrack.id != 'no') {
            debugPrint('MediaKit: Auto-selecting audio: ${realTrack.id}');
            player.setAudioTrack(realTrack);
          }
        }
      }
    });
  }

  @override
  Future<void> play(VideoEntity video, {Duration? startPosition}) async {
    // 1. Generate new Initialization ID
    _initId++;
    final int currentId = _initId;

    // 2. Ensure Player exists (create if null)
    await _ensurePlayerInitialized(currentId);
    if (_initId != currentId) return;
    final player = _player!;

    // 3. Set Per-Video Properties
    // 'start' property must be set before open to take effect
    if (startPosition != null && startPosition > Duration.zero) {
      final startSeconds = startPosition.inMilliseconds / 1000.0;
      try {
        await (player.platform as dynamic).setProperty(
          'start',
          startSeconds.toString(),
        );
        debugPrint('MediaKit: Starting playback at ${startSeconds}s');
      } catch (e) {
        debugPrint('MediaKit: Error setting start property: $e');
      }

      // Update UI immediately
      _currentPosition = startPosition;
      _positionController.add(startPosition);
    } else {
      // Reset start pos to 0 for next video if not specified
      try {
        await (player.platform as dynamic).setProperty('start', '0');
      } catch (e) {
        debugPrint('MediaKit: Error resetting start property: $e');
      }
    }

    if (_initId != currentId) return;

    // 4. Open Media
    try {
      await player.open(Media(video.path));
    } catch (e) {
      if (_initId == currentId) {
        debugPrint('MediaKit: Open failed: $e');
        _errorController.add(e.toString());
      }
      return;
    }

    if (_initId != currentId) return;

    // RESUME FIX: Explicitly seek if start position was requested.
    // The 'start' property (mpv --start) is sometimes ignored when reusing the player instance.
    // This semantic seek ensures we definitely start at the right place.
    if (startPosition != null && startPosition > Duration.zero) {
      // Allow mpv to initialize media info (helps with some formats)
      if (_initId == currentId) {
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Check cancellation again after delay
      if (_initId == currentId) {
        debugPrint(
          'MediaKit: Explicitly seeking to $startPosition (resume fallback)',
        );
        await player.seek(startPosition);
      }
    }

    _videoUrl = video.path;

    if (_initId != currentId) return;

    // Force Unmute & Volume 100
    await player.setVolume(100);
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
    if (_player == null) return;

    // P1 FIX: Signal explicit user seek to proxy BEFORE player seeks
    // This helps proxy prioritize the first offset request after seek
    if (_videoUrl != null && _videoUrl!.contains('/stream?file_id=')) {
      try {
        final uri = Uri.parse(_videoUrl!);
        final idStr = uri.queryParameters['file_id'];
        if (idStr != null) {
          LocalStreamingProxy().signalUserSeek(
            int.parse(idStr),
            position.inMilliseconds,
          );
        }
      } catch (e) {
        debugPrint('MediaKit: Error signaling seek to proxy: $e');
      }
    }

    // TELEGRAM ANDROID-INSPIRED: Temporarily reduce buffer requirement for faster seek
    // Similar to ExoPlayer's bufferForPlaybackMs being lower than minBufferMs
    try {
      // Reduce cache-secs to 3 seconds for immediate playback after seek
      await (_player!.platform as dynamic).setProperty('cache-secs', '3');
      debugPrint(
        'MediaKit: Seek to ${position.inSeconds}s - reduced buffer for fast resume',
      );
    } catch (e) {
      debugPrint('MediaKit: Could not reduce cache-secs: $e');
    }

    await _player!.seek(position);

    // Restore normal buffer after 5 seconds
    Future.delayed(const Duration(seconds: 5), () async {
      if (_player != null) {
        try {
          await (_player!.platform as dynamic).setProperty('cache-secs', '20');
          debugPrint('MediaKit: Restored normal buffer (20s)');
        } catch (e) {
          // Player may have been disposed
        }
      }
    });
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

  @override
  Stream<void> get tracksChangedStream => _tracksChangedController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;
}
