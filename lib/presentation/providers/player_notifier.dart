import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:window_manager/window_manager.dart';
import '../../domain/entities/video_entity.dart';
import '../../domain/repositories/video_repository.dart';
import 'video_repository_provider.dart';
import '../../domain/repositories/streaming_repository.dart';
import '../../infrastructure/services/playback_storage_service.dart';
import '../../infrastructure/services/recent_videos_service.dart';
import 'player_state.dart';

part 'player_notifier.g.dart';

// Player Notifier
// Riverpod 3: @riverpod sobre una clase genera un NotifierProvider (o AsyncNotifierProvider si build devuelve Future).
// La clase debe extender de _$NombreDeLaClase (generated mixin).
@riverpod
class PlayerNotifier extends _$PlayerNotifier {
  late final VideoRepository _repository;
  late final PlaybackStorageService _storageService;
  late final StreamingRepository _streamingRepository;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferingSub;
  StreamSubscription? _tracksSub;
  StreamSubscription? _errorSub;
  Timer? _saveTimer;
  Timer? _moovCheckTimer;
  int? _currentProxyFileId;
  bool _mounted = true;

  // Stable Telegram identifiers for progress persistence
  int? _telegramChatId;
  int? _telegramMessageId;
  int? _telegramFileSize;
  int? _telegramTopicId;
  String? _telegramTopicName;

  @override
  PlayerState build() {
    // Riverpod 3: El método build() reemplaza al constructor.
    // Aquí inicializamos el estado y las dependencias.
    // ref.watch lee el valor de otro provider y escucha sus cambios.
    // Si videoRepositoryProvider cambia, este provider se reconstruirá.
    _repository = ref.watch(videoRepositoryProvider);
    _storageService = ref.watch(playbackStorageServiceProvider);
    _streamingRepository = ref.watch(streamingRepositoryProvider);
    _initStreams();

    // Registramos la limpieza de recursos.
    // En Riverpod 3, esto reemplaza al método dispose() de los StateNotifier.
    ref.onDispose(() {
      _mounted = false;
      _positionSub?.cancel();
      _durationSub?.cancel();
      _playingSub?.cancel();
      _bufferingSub?.cancel();
      _tracksSub?.cancel();
      _errorSub?.cancel();
      _saveTimer?.cancel();
      _moovCheckTimer?.cancel();
      _savePosition();
      _abortCurrentProxyRequest();
    });

    // Retornamos el estado inicial.
    // Sync backend state
    final backend = ref.read(playerBackendProvider);
    return PlayerState(playerBackend: backend);
  }

  void _initStreams() {
    _positionSub = _repository.positionStream.listen((pos) {
      // Riverpod 3: 'state' es la propiedad que mantiene el estado actual.
      // Es inmutable (en este caso), por lo que usamos copyWith para actualizarlo.
      // Al asignar un nuevo valor a 'state', se notifica a los listeners.
      state = state.copyWith(position: pos);
    });
    _durationSub = _repository.durationStream.listen((dur) {
      state = state.copyWith(duration: dur);
    });
    _playingSub = _repository.isPlayingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });
    _bufferingSub = _repository.isBufferingStream.listen((buffering) {
      // Check if current video is not optimized for streaming (moov atom at end)
      bool isNotOptimized = false;
      if (buffering && _currentProxyFileId != null) {
        isNotOptimized = _streamingRepository.isVideoNotOptimizedForStreaming(
          _currentProxyFileId!,
        );

        // Start periodic check if buffering and not yet detected as not-optimized
        // This catches cases where moov detection happens after buffering starts
        if (!isNotOptimized) {
          _startMoovCheckTimer();
        }
      } else {
        // Stop timer when not buffering
        _stopMoovCheckTimer();
      }

      state = state.copyWith(
        isBuffering: buffering,
        isVideoNotOptimizedForStreaming: isNotOptimized,
      );
    });
    // Listen for track changes (for streaming videos where tracks arrive late)
    _tracksSub = _repository.tracksChangedStream.listen((_) {
      _loadTracks();
    });
    // Listen for player errors and update state
    _errorSub = _repository.errorStream.listen((error) {
      debugPrint('PlayerNotifier: Player error received: $error');
      state = state.copyWith(error: error);
    });
  }

  /// Start a timer to periodically check if video is not optimized for streaming
  /// This catches late detection of moov-at-end during initial buffering
  void _startMoovCheckTimer() {
    _stopMoovCheckTimer();
    _moovCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!state.isBuffering || _currentProxyFileId == null) {
        _stopMoovCheckTimer();
        return;
      }

      final isNotOptimized = _streamingRepository
          .isVideoNotOptimizedForStreaming(_currentProxyFileId!);

      if (isNotOptimized && !state.isVideoNotOptimizedForStreaming) {
        state = state.copyWith(isVideoNotOptimizedForStreaming: true);
        _stopMoovCheckTimer(); // Stop once we've detected it
      }
    });
  }

  /// Stop the moov check timer
  void _stopMoovCheckTimer() {
    _moovCheckTimer?.cancel();
    _moovCheckTimer = null;
  }

  /// Load and play a video.
  ///
  /// For Telegram videos, provide [telegramChatId], [telegramMessageId], and
  /// [telegramFileSize] for stable progress persistence that survives cache clears.
  /// For forum topics, provide [telegramTopicId] and [telegramTopicName].
  Future<void> loadVideo(
    String path, {
    bool isNetwork = false,
    String? title,
    int? telegramChatId,
    int? telegramMessageId,
    int? telegramFileSize,
    int? telegramTopicId,
    String? telegramTopicName,
  }) async {
    _abortCurrentProxyRequest();

    try {
      state = state.copyWith(
        currentVideoPath: path,
        currentVideoTitle: title,
        error: null,
        position: Duration.zero,
        duration: Duration.zero,
        isPlaying: false,
      );

      // ... (existing code for proxy fix) ...
      // I will use replace_file_content so I don't need to copy 80 lines.
      // Wait, replacement content must match target content exactly.
      // I will use multi_replace.

      // Store Telegram context for stable progress persistence
      _telegramChatId = telegramChatId;
      _telegramMessageId = telegramMessageId;
      _telegramFileSize = telegramFileSize;
      _telegramTopicId = telegramTopicId;
      _telegramTopicName = telegramTopicName;

      // Extract and store proxy file ID safely for disposal
      _currentProxyFileId = null;
      if (path.contains('/stream?file_id=')) {
        try {
          final uri = Uri.parse(path);
          final fileIdStr = uri.queryParameters['file_id'];
          if (fileIdStr != null) {
            _currentProxyFileId = int.tryParse(fileIdStr);
          }

          // FIX: Correct the port if this is a local proxy URL to ensure we use the active port
          // This fixes "Recent Videos" failing after restart because they point to dead ports
          if (uri.authority.contains('127.0.0.1') ||
              uri.authority.contains('localhost')) {
            final activePort = _streamingRepository.port;
            if (activePort > 0 && uri.port != activePort) {
              final newPath = path.replaceFirst(
                ':${uri.port}/',
                ':$activePort/',
              );
              debugPrint(
                'PlayerNotifier: Corrected port from ${uri.port} to $activePort',
              );
              path = newPath;
              // Update current video path in state immediately so UI/Logic uses the working URL
              state = state.copyWith(currentVideoPath: path);
            }
          }
        } catch (_) {}
      }

      if (!isNetwork) {
        final file = File(path);
        if (!await file.exists()) {
          throw const FileSystemException('File not found');
        }
      }

      final video = VideoEntity(path: path, isNetwork: isNetwork);
      await _repository.play(video);

      // Give player a moment to load initial tracks (for local files)
      await Future.delayed(const Duration(milliseconds: 300));
      await _loadTracks();

      // Save to recent videos history with stable Telegram identifiers
      final recentVideosService = RecentVideosService();
      await recentVideosService.addVideo(
        path,
        isNetwork: isNetwork,
        title: title,
        telegramChatId: _telegramChatId,
        telegramMessageId: _telegramMessageId,
        telegramFileSize: _telegramFileSize,
        telegramTopicId: _telegramTopicId,
        telegramTopicName: _telegramTopicName,
      );

      // Use stable Telegram message ID for progress key (survives cache clears)
      // Falls back to file_id for legacy, then path for local files
      final storageKey = _getStableStorageKey(path);
      final savedPositionMs = await _storageService.getPosition(storageKey);
      if (savedPositionMs != null && savedPositionMs > 0) {
        final position = Duration(milliseconds: savedPositionMs);

        // Wait for duration to be known (metadata loaded) before seeking
        // This prevents seeking to a valid position while duration is 0 (which often fails or resets)
        int waitAttempts = 0;
        const maxWaitAttempts = 100; // 10 seconds (100 * 100ms)

        // Modified loop to check _mounted to avoid crash on dispose
        while (_mounted &&
            state.duration == Duration.zero &&
            waitAttempts < maxWaitAttempts) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!_mounted) return; // Exit if disposed
          waitAttempts++;
        }

        if (!_mounted) return; // Safety check

        // Only seek if we have a valid duration or just try your best if timed out
        if (state.duration > Duration.zero) {
          debugPrint(
            'PlayerNotifier: Resuming to $position (Duration: ${state.duration})',
          );
          await seekTo(position);
        } else {
          debugPrint(
            'PlayerNotifier: Resume timed out waiting for duration. Attempting seek anyway...',
          );
          await seekTo(position);
        }
      }

      _startSaveTimer();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await _repository.pause();
      await _savePosition();
      _saveTimer?.cancel();
    } else {
      await _repository.resume();
      _startSaveTimer();
    }
  }

  Future<void> seekTo(Duration position) async {
    // Optimistic update
    state = state.copyWith(position: position);
    await _savePosition();
    await _repository.seekTo(position);
  }

  double _lastVolume = 1.0;

  Future<void> setVolume(double volume) async {
    await _repository.setVolume(volume);
    state = state.copyWith(volume: volume);
  }

  Future<void> toggleMute() async {
    if (state.volume > 0) {
      _lastVolume = state.volume;
      await setVolume(0);
    } else {
      await setVolume(_lastVolume > 0 ? _lastVolume : 1.0);
    }
  }

  void toggleFullscreen() {
    state = state.copyWith(isFullscreen: !state.isFullscreen);
  }

  Future<void> toggleAlwaysOnTop() async {
    final newState = !state.isAlwaysOnTop;
    await windowManager.setAlwaysOnTop(newState);
    state = state.copyWith(isAlwaysOnTop: newState);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _repository.setPlaybackSpeed(speed);
    state = state.copyWith(playbackSpeed: speed);
  }

  void setControlsVisibility(bool visible) {
    state = state.copyWith(areControlsVisible: visible);
  }

  /// Returns a stable storage key for progress persistence.
  /// Priority: Telegram message ID > file_id > path
  String _getStableStorageKey(String path) {
    // Best: Use stable Telegram message ID (survives cache clears)
    if (_telegramChatId != null && _telegramMessageId != null) {
      return 'telegram_${_telegramChatId}_$_telegramMessageId';
    }
    // Fallback: Use file_id (may change after cache clear, but works for session)
    if (_currentProxyFileId != null) {
      return 'file_$_currentProxyFileId';
    }
    // Default: Use path for local files
    return path;
  }

  Future<void> _savePosition() async {
    try {
      if (state.currentVideoPath != null) {
        final storageKey = _getStableStorageKey(state.currentVideoPath!);
        await _storageService.savePosition(
          storageKey,
          state.position.inMilliseconds,
        );
      }
    } catch (e) {
      // Ignore errors during save, especially during dispose
    }
  }

  Future<void> _loadTracks() async {
    final audioTracks = await _repository.getAudioTracks();
    final subtitleTracks = await _repository.getSubtitleTracks();
    state = state.copyWith(
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      // Reset current selection or set default if needed
      currentAudioTrack: 0,
      currentSubtitleTrack: 0,
    );
  }

  Future<void> setAudioTrack(int trackId) async {
    await _repository.setAudioTrack(trackId);
    state = state.copyWith(currentAudioTrack: trackId);
  }

  Future<void> setSubtitleTrack(int trackId) async {
    await _repository.setSubtitleTrack(trackId);
    state = state.copyWith(currentSubtitleTrack: trackId);
  }

  /// Manually refresh available tracks (useful for streaming videos)
  Future<void> refreshTracks() async {
    await _loadTracks();
  }

  Future<void> stop() async {
    _abortCurrentProxyRequest();
    _saveTimer?.cancel();
    await _savePosition();
    // We manually dispose the repo here to ensure resources are freed before window close
    await _repository.dispose();
  }

  void _startSaveTimer() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (state.isPlaying) {
        _savePosition();
      }
    });
  }

  void _abortCurrentProxyRequest() {
    if (_currentProxyFileId != null) {
      debugPrint('PlayerNotifier: Aborting proxy file $_currentProxyFileId');
      _streamingRepository.abortRequest(_currentProxyFileId!);
      _currentProxyFileId = null;
    } else {
      debugPrint('PlayerNotifier: No proxy file to abort');
    }
  }
}
