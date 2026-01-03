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
@Riverpod(
  dependencies: [
    videoRepository,
    playbackStorageService,
    streamingRepository,
    PlayerBackend,
  ],
)
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

  // Track the position when initial loading started to detect actual playback
  Duration? _initialLoadingStartPosition;

  // Note: isInitialLoading is now exposed in PlayerState for UI visibility

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

      // UX FIX: Only clear initial loading when position has ACTUALLY ADVANCED.
      // Compare against the starting position to detect real playback progress.
      if (state.isInitialLoading && state.isPlaying) {
        final startPos = _initialLoadingStartPosition ?? Duration.zero;
        // Position must have advanced by at least 100ms from start to confirm playback
        if (pos.inMilliseconds > startPos.inMilliseconds + 100) {
          debugPrint(
            'PlayerNotifier: Playback confirmed, clearing initial loading',
          );
          _initialLoadingStartPosition = null;
          state = state.copyWith(isInitialLoading: false, isBuffering: false);
        }
      }
    });
    _durationSub = _repository.durationStream.listen((dur) {
      state = state.copyWith(duration: dur);
    });
    _playingSub = _repository.isPlayingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
      // Don't clear isInitialLoading here - let position listener handle it
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

      // UX FIX: Ignore ALL buffering state changes during initial load
      // The player flickers buffering=true/false while loading metadata,
      // but we want to keep the spinner until real playback starts (position > 200ms).
      // The isInitialLoading flag is only cleared in the position listener.
      if (state.isInitialLoading) {
        // During initial load, only update moov optimization status, not buffering
        if (isNotOptimized && !state.isVideoNotOptimizedForStreaming) {
          state = state.copyWith(isVideoNotOptimizedForStreaming: true);
        }
        return;
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
      // Stop forced loading on error
      state = state.copyWith(error: error, isBuffering: false);
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
  Future<void> _savePosition() async {
    try {
      if (state.currentVideoPath != null) {
        final storageKey = _getStableStorageKey(state.currentVideoPath!);

        // Check if video has reached the end (within 500ms of duration)
        // If so, clear the progress instead of saving it
        final isAtEnd =
            state.duration > Duration.zero &&
            state.position >=
                state.duration - const Duration(milliseconds: 500);

        if (isAtEnd) {
          await _storageService.clearPosition(storageKey);
          debugPrint('PlayerNotifier: Video finished, cleared progress');
        } else {
          await _storageService.savePosition(
            storageKey,
            state.position.inMilliseconds,
          );
        }
      }
    } catch (e) {
      // Ignore errors during save, especially during dispose
    }
  }

  /// Load and play a video.
  Future<void> loadVideo(
    String path, {
    bool isNetwork = false,
    String? title,
    int? telegramChatId,
    int? telegramMessageId,
    int? telegramFileSize,
    int? telegramTopicId,
    String? telegramTopicName,
    bool startAtZero = false,
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
        // UX FIX: Force buffering state for network videos immediately
        isBuffering: isNetwork,
        isInitialLoading: isNetwork, // New: exposed to UI for loading indicator
      );

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

      // Use stable Telegram message ID for progress key (survives cache clears)
      // Falls back to file_id for legacy, then path for local files
      final storageKey = _getStableStorageKey(path);

      Duration startPosition = Duration.zero;

      if (!startAtZero) {
        final savedPositionMs = await _storageService.getPosition(storageKey);
        if (savedPositionMs != null && savedPositionMs > 0) {
          startPosition = Duration(milliseconds: savedPositionMs);
          debugPrint('PlayerNotifier: Will resume from $startPosition');
          // Optimistic update for UI to show correct time immediately
          state = state.copyWith(position: startPosition);
        }
      } else {
        debugPrint('PlayerNotifier: Forced start at zero');
      }

      // Track starting position for detecting actual playback (position must advance)
      if (isNetwork) {
        _initialLoadingStartPosition = startPosition;
      }
      final video = VideoEntity(path: path, isNetwork: isNetwork);

      // OPTIMIZATION: Pass startPosition to play()
      // This allows the player (MediaKit/libmpv) to start directly at this timestamp
      // avoiding the "start at 0 -> seek to X" pattern which causes double-loading and proxy crashes.
      await _repository.play(video, startPosition: startPosition);

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

      // CRITICAL: Ensure buffering state clears if not actually buffering
      // Sometimes MediaKit doesn't emit 'buffering=false' if we start with 'start' property
      if (state.isBuffering && !isNetwork) {
        state = state.copyWith(isBuffering: false, isInitialLoading: false);
      }

      _startSaveTimer();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Mutex lock for togglePlay() to prevent double-triggering.
  /// Some keyboards send multiple KeyDown events for a single physical press.
  /// This static flag ensures only one toggle operation runs at a time,
  /// with a 500ms cooldown after completion.
  static bool _isToggling = false;

  Future<void> togglePlay() async {
    // Mutex-style lock: reject if already toggling (prevents double-press hardware quirks)
    if (_isToggling) return;
    _isToggling = true;

    try {
      if (state.isPlaying) {
        await _repository.pause();
        await _savePosition();
      } else {
        await _repository.resume();
      }
    } finally {
      // Keep lock for 500ms after operation completes to prevent rapid re-triggering
      Future.delayed(const Duration(milliseconds: 500), () {
        _isToggling = false;
      });
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
