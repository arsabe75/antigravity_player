import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:window_manager/window_manager.dart';
import '../../domain/entities/video_entity.dart';
import '../../domain/repositories/video_repository.dart';
import 'video_repository_provider.dart';
import '../../domain/repositories/streaming_repository.dart';
import '../../domain/value_objects/streaming_error.dart';
import '../../infrastructure/services/playback_storage_service.dart';
import '../../infrastructure/services/recent_videos_service.dart';
import '../../application/use_cases/save_progress_use_case.dart';
import '../../application/use_cases/clear_finished_progress_use_case.dart';
import '../../application/services/storage_key_service.dart';
import 'player_state.dart';

part 'player_notifier.g.dart';

// =============================================================================
// PlayerNotifier - Core Video Playback Controller
// =============================================================================
//
// ARCHITECTURE OVERVIEW:
// ┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
// │  PlayerScreen   │────▶│  PlayerNotifier  │────▶│ VideoRepository │
// │  (UI Layer)     │     │  (State Layer)   │     │ (Domain Layer)  │
// └─────────────────┘     └──────────────────┘     └─────────────────┘
//                                │
//                                ▼
//                         ┌──────────────────┐
//                         │ StreamingRepo    │
//                         │ (Proxy Control)  │
//                         └──────────────────┘
//
// DATA FLOW:
// 1. UI calls loadVideo() → Notifier updates state → Repository plays video
// 2. Repository emits streams → Notifier updates state → UI rebuilds
// 3. User seeks/pauses → Notifier → Repository → Streams update state
//
// STREAM SUBSCRIPTIONS (6 total):
// - positionStream: Current playback position (updates ~200ms)
// - durationStream: Total video duration
// - isPlayingStream: Play/pause state
// - isBufferingStream: Network buffering state
// - tracksChangedStream: Audio/subtitle track availability
// - errorStream: Playback errors (codec, network, etc.)
//
// STABLE STORAGE KEYS (for progress persistence):
// Priority order for identifying videos across sessions:
// 1. Telegram message ID (telegram_{chatId}_{messageId}) - survives cache clears
// 2. Proxy file_id (file_{id}) - session-stable but changes after cache clear
// 3. File path - for local files only
//
// =============================================================================

/// Manages video playback state and coordinates between UI and video backends.
///
/// This notifier uses Riverpod 3's code generation pattern with `@Riverpod`.
/// The `build()` method initializes dependencies and returns initial state.
/// State updates are broadcast to all widgets watching [playerProvider].
///
/// ## Key Features:
/// - **Multi-backend support**: Works with both FVP (libmpv) and MediaKit
/// - **Progress persistence**: Saves playback position every 5 seconds
/// - **Telegram integration**: Uses stable message IDs for progress keys
/// - **Proxy port correction**: Fixes stale URLs after app restart
/// - **UX optimizations**: Buffering indicators, initial loading state
///
/// ## Usage:
/// ```dart
/// // In a widget
/// final state = ref.watch(playerProvider);
/// final notifier = ref.read(playerProvider.notifier);
///
/// // Load a video
/// notifier.loadVideo(
///   'http://example.com/video.mp4',
///   isNetwork: true,
///   title: 'My Video',
/// );
///
/// // Control playback
/// notifier.togglePlay();
/// notifier.seekTo(Duration(minutes: 5));
/// ```
@Riverpod(
  dependencies: [
    videoRepository,
    playbackStorageService,
    streamingRepository,
    PlayerBackend,
    saveProgressUseCase,
    clearFinishedProgressUseCase,
  ],
)
class PlayerNotifier extends _$PlayerNotifier {
  late final VideoRepository _repository;
  late final PlaybackStorageService _storageService;
  late final StreamingRepository _streamingRepository;
  late final SaveProgressUseCase _saveProgressUseCase;
  late final ClearFinishedProgressUseCase _clearFinishedProgressUseCase;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferingSub;
  StreamSubscription? _tracksSub;
  StreamSubscription? _errorSub;
  Timer? _saveTimer;
  Timer? _moovCheckTimer;
  Timer? _seekRecoveryTimer;
  Duration? _lastSeekTarget;
  DateTime? _lastSeekTime;
  static const int _maxSeekRetries = 2;
  static const Duration _seekRecoveryTimeout = Duration(seconds: 8);
  int _seekRecoveryExtensions = 0;
  int _seekRecoveryBytesSnapshot = 0;
  static const int _maxSeekRecoveryExtensions = 3;
  int? _currentProxyFileId;

  // Track the position when initial loading started to detect actual playback
  Duration? _initialLoadingStartPosition;

  // Track the position when ANY error occurred (MediaKit or streaming) to detect recovery
  Duration? _errorOccurredAtPosition;

  // THROTTLE: Reduce position UI updates to prevent Windows message queue overflow
  // Position updates come at ~10/sec from mpv, but UI only needs 4/sec
  DateTime _lastPositionUpdate = DateTime.now();
  static const Duration _positionUpdateThrottle = Duration(milliseconds: 250);

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
    _saveProgressUseCase = ref.watch(saveProgressUseCaseProvider);
    _clearFinishedProgressUseCase = ref.watch(
      clearFinishedProgressUseCaseProvider,
    );
    _initStreams();

    // Subscribe to proxy streaming errors (max retries, timeouts, etc.)
    _streamingRepository.onStreamingError = _handleStreamingError;

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
      _seekRecoveryTimer?.cancel();
      _savePosition();
      _abortCurrentProxyRequest();
      // Clear streaming error callback
      _streamingRepository.onStreamingError = null;
    });

    // Retornamos el estado inicial.
    // Sync backend state
    final backend = ref.read(playerBackendProvider);
    return PlayerState(playerBackend: backend);
  }

  void _initStreams() {
    _positionSub = _repository.positionStream.listen((pos) {
      // Guard against disposed provider
      if (!ref.mounted) return;

      // THROTTLE: Only update UI position every 250ms to reduce Windows message queue load
      // This prevents "Failed to post message to main thread" errors
      final now = DateTime.now();
      final shouldUpdateState =
          now.difference(_lastPositionUpdate) >= _positionUpdateThrottle;

      if (shouldUpdateState) {
        // Ignorar posiciones "viejas" o reseteos a 0 emitidos por el reproductor 
        // mientras procesa un seek asincrónicamente (por buffering de red).
        if (_lastSeekTarget != null && _lastSeekTime != null) {
          final timeSinceSeek = now.difference(_lastSeekTime!);
          // Durante una ventana de 4 segundos posterior al inicio de un seek
          if (timeSinceSeek < const Duration(seconds: 4)) {
            final delta = (pos - _lastSeekTarget!).abs();
            // Si la posición enviada difiere en más de 2 segundos del target, 
            // asumimos que es vieja (el salto aún no ocurre). La ignoramos.
            if (delta > const Duration(seconds: 2)) {
               debugPrint(
                 'PlayerNotifier: Ignoring stale position ${pos.inSeconds}s '
                 '(target: ${_lastSeekTarget!.inSeconds}s, delta: ${delta.inSeconds}s) during seek cooldown.',
               );
               return;
            } else {
               // El reproductor ya llegó o está muy cerca del target.
               // Podemos dar por superado el salto.
               _lastSeekTarget = null;
               _lastSeekTime = null;
            }
          } else {
            // Ya expiró el cooldown
            _lastSeekTarget = null;
            _lastSeekTime = null;
          }
        }

        _lastPositionUpdate = now;
        state = state.copyWith(position: pos);
      }

      // NOTE: Detection logic below runs on EVERY position event (not throttled)
      // This ensures accurate playback detection and error recovery

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
          // Also clear any streaming error since playback resumed successfully
          state = state.copyWith(
            isInitialLoading: false,
            isBuffering: false,
            streamingError: null,
          );
        }
      }

      // UX FIX: Auto-dismiss error overlay when playback continues successfully
      // This handles the case where an error occurs mid-playback but video recovers
      // Works for BOTH MediaKit errors (state.error) and streaming errors (state.streamingError)
      if (_errorOccurredAtPosition != null &&
          (state.error != null || state.streamingError != null)) {
        // If position has advanced 500ms from when error occurred, playback recovered
        final errorPos = _errorOccurredAtPosition!;
        if (pos.inMilliseconds > errorPos.inMilliseconds + 500 ||
            pos.inMilliseconds < errorPos.inMilliseconds - 500) {
          debugPrint(
            'PlayerNotifier: Playback recovered (pos: ${pos.inMilliseconds}ms, error was at: ${errorPos.inMilliseconds}ms), clearing errors',
          );
          _errorOccurredAtPosition = null;
          state = state.copyWith(error: null, streamingError: null);

          // FIX: Reset proxy retry counter so future stalls don't immediately hit MAX_RETRIES
          // This prevents cascading MAX_RETRIES_EXCEEDED errors after recovery
          if (_currentProxyFileId != null) {
            _streamingRepository.resetRetryCount(_currentProxyFileId!);
          }
        }
      }
    });
    _durationSub = _repository.durationStream.listen((dur) {
      if (!ref.mounted) return;
      state = state.copyWith(duration: dur);
    });
    _playingSub = _repository.isPlayingStream.listen((playing) {
      if (!ref.mounted) return;
      // DIAG: Log playing state changes for debugging video stops
      if (playing != state.isPlaying) {
        debugPrint(
          'PlayerNotifier: isPlaying changed: ${state.isPlaying} -> $playing '
          '(pos: ${state.position.inSeconds}s)',
        );
      }
      state = state.copyWith(isPlaying: playing);
      // Don't clear isInitialLoading here - let position listener handle it
    });
    _bufferingSub = _repository.isBufferingStream.listen((buffering) {
      if (!ref.mounted) return;
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
        // Cancelar recuperación de seek: el buffering terminó normalmente
        _seekRecoveryTimer?.cancel();
        _seekRecoveryTimer = null;
      }

      // UX FIX: Ignore buffering TRUE flickers during initial load.
      // The player flickers buffering=true/false while loading metadata,
      // but we want to keep the spinner until real playback starts.
      //
      // FIX 3: However, when buffering transitions to FALSE and the player
      // is actively playing, this is the strongest signal that playback has
      // genuinely started (mpv has data and is decoding). Clear isInitialLoading
      // here to prevent the loading spinner from persisting over active video.
      // The position-based check in the position listener remains as a fallback.
      if (state.isInitialLoading) {
        if (!buffering && state.isPlaying) {
          // Player is playing and not buffering — real playback has started
          debugPrint(
            'PlayerNotifier: FIX 3 - Clearing isInitialLoading '
            '(buffering=false, isPlaying=true)',
          );
          state = state.copyWith(
            isInitialLoading: false,
            isBuffering: false,
            isVideoNotOptimizedForStreaming: isNotOptimized,
          );
        } else if (isNotOptimized && !state.isVideoNotOptimizedForStreaming) {
          // During initial load, only update moov optimization status
          state = state.copyWith(isVideoNotOptimizedForStreaming: true);
        }
        return;
      }

      // DIAG: Log buffering state changes for debugging video stops
      if (buffering != state.isBuffering) {
        debugPrint(
          'PlayerNotifier: isBuffering changed: ${state.isBuffering} -> $buffering '
          '(pos: ${state.position.inSeconds}s)',
        );
      }
      state = state.copyWith(
        isBuffering: buffering,
        isVideoNotOptimizedForStreaming: isNotOptimized,
      );
    });
    // Listen for track changes (for streaming videos where tracks arrive late)
    _tracksSub = _repository.tracksChangedStream.listen((_) {
      if (!ref.mounted) return;
      _loadTracks();
    });
    // Listen for player errors and update state
    _errorSub = _repository.errorStream.listen((error) {
      if (!ref.mounted) return;
      debugPrint('PlayerNotifier: Player error received: $error');
      // Store position when error occurred to detect recovery later
      _errorOccurredAtPosition = state.position;
      // Stop forced loading on error
      state = state.copyWith(error: error, isBuffering: false);

      // Classify player errors for proxy/streaming videos (codec, corrupt file)
      if (_currentProxyFileId != null) {
        final streamingError = _classifyPlayerError(
          error,
          _currentProxyFileId!,
        );
        if (streamingError != null) {
          _streamingRepository.reportPlayerError(streamingError);
        }
      }
    });
  }

  /// Classifies MediaKit/player error strings into StreamingError (codec/corrupt).
  /// Returns null if the error cannot be classified.
  StreamingError? _classifyPlayerError(String errorMessage, int fileId) {
    final lower = errorMessage.toLowerCase();
    // Unsupported codec / format patterns (mpv, libmpv, MediaKit)
    if (lower.contains('unsupported codec') ||
        lower.contains('codec not found') ||
        lower.contains('no decoder') ||
        lower.contains('decoder not found') ||
        lower.contains('format not supported') ||
        lower.contains('unknown format') ||
        lower.contains('no suitable stream')) {
      return StreamingError.unsupportedCodec(fileId);
    }
    // Corrupt / invalid data patterns
    if (lower.contains('invalid data') ||
        lower.contains('corrupt') ||
        lower.contains('damaged') ||
        lower.contains('failed to open') ||
        lower.contains('could not open') ||
        lower.contains('error reading') ||
        lower.contains('invalid stream') ||
        lower.contains('spurious_eof') ||
        lower.contains('premature end')) {
      return StreamingError.corruptFile(fileId);
    }
    return null;
  }

  /// Handle streaming proxy errors (max retries, timeout, etc.)
  void _handleStreamingError(StreamingError error) {
    if (!ref.mounted) return;
    debugPrint(
      'PlayerNotifier: Streaming error for file ${error.fileId}: ${error.message}',
    );
    // Only update if this error is for the current video
    if (_currentProxyFileId == error.fileId) {
      // Store the position when error occurred to detect recovery later
      _errorOccurredAtPosition = state.position;
      state = state.copyWith(
        streamingError: error,
        isBuffering: false,
        isInitialLoading: false,
      );

      // AUTO-PAUSE: For unrecoverable errors (max retries, timeout, corrupt),
      // pause the player to stop it from requesting more data via HTTP.
      // This breaks the feedback loop: player requests → proxy 503 → player
      // retries → more events → overflow. The user can still manually retry
      // or navigate away.
      if (!error.isRecoverable && state.isPlaying) {
        debugPrint(
          'PlayerNotifier: Auto-pausing due to unrecoverable error: ${error.type}',
        );
        _repository.pause();
      }
    }
  }

  /// Clear any streaming error (e.g., when user retries)
  void clearStreamingError() {
    if (_currentProxyFileId != null) {
      _streamingRepository.clearError(_currentProxyFileId!);
    }
    state = state.copyWith(streamingError: null);
  }

  /// Start a timer to periodically check if video is not optimized for streaming
  /// This catches late detection of moov-at-end during initial buffering
  void _startMoovCheckTimer() {
    _stopMoovCheckTimer();
    // FIX: Run every 100ms (not 500ms) to catch MOOV detection before playback confirms
    _moovCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!ref.mounted) {
        _stopMoovCheckTimer();
        return;
      }
      if (_currentProxyFileId == null) {
        _stopMoovCheckTimer();
        return;
      }

      // FIX: Keep checking during initial loading OR buffering
      // Don't stop just because buffering is false - we need to detect during initial load
      if (!state.isBuffering && !state.isInitialLoading) {
        _stopMoovCheckTimer();
        return;
      }

      final isNotOptimized = _streamingRepository
          .isVideoNotOptimizedForStreaming(_currentProxyFileId!);

      if (isNotOptimized && !state.isVideoNotOptimizedForStreaming) {
        debugPrint('PlayerNotifier: Detected MOOV-at-end, updating state');
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

  /// Clears progress for a finished video using captured values.
  ///
  /// This is called BEFORE state is reset to ensure we use the correct
  /// position/duration values from the completed video, not from the next video.
  /// Delegates to ClearFinishedProgressUseCase for business logic.
  Future<void> _clearProgressForFinishedVideo({
    required String storageKey,
    required Duration position,
    required Duration duration,
  }) async {
    try {
      final wasCleared = await _clearFinishedProgressUseCase.call(
        ClearFinishedProgressParams(
          storageKey: storageKey,
          position: position,
          duration: duration,
        ),
      );
      if (wasCleared) {
        debugPrint(
          'PlayerNotifier: Cleared progress for finished video: $storageKey',
        );
      }
    } catch (e) {
      debugPrint('PlayerNotifier: Error clearing progress: $e');
    }
  }

  /// Saves playback progress using SaveProgressUseCase.
  ///
  /// Delegates to use case which handles:
  /// - Generating stable storage key
  /// - Saving or clearing progress based on video completion
  /// - Updating recent videos list
  Future<void> _savePosition() async {
    try {
      if (state.currentVideoPath != null) {
        await _saveProgressUseCase.call(
          SaveProgressParams(
            videoPath: state.currentVideoPath!,
            position: state.position,
            duration: state.duration,
            telegramChatId: _telegramChatId,
            telegramMessageId: _telegramMessageId,
            proxyFileId: _currentProxyFileId,
          ),
        );
      }
    } catch (e) {
      // Ignore errors during save, especially during dispose
    }
  }

  /// Loads and plays a video file or network stream.
  ///
  /// ## Flow Diagram:
  /// ```
  /// loadVideo()
  ///     │
  ///     ├── 1. Abort previous proxy request (if any)
  ///     ├── 2. Reset state (path, title, buffering indicators)
  ///     ├── 3. Store Telegram context for stable progress keys
  ///     ├── 4. Extract proxy file_id and correct port if stale
  ///     ├── 5. Validate local file exists (if not network)
  ///     ├── 6. Restore saved position (unless startAtZero)
  ///     ├── 7. Start playback via VideoRepository
  ///     ├── 8. Load audio/subtitle tracks
  ///     ├── 9. Save to recent videos history
  ///     └── 10. Start auto-save timer (every 5 seconds)
  /// ```
  ///
  /// ## Parameters:
  /// - [path]: Video URL or local file path
  /// - [isNetwork]: Set true for http/https URLs
  /// - [title]: Display title (falls back to filename)
  /// - [telegramChatId]: For stable progress persistence across cache clears
  /// - [telegramMessageId]: Combined with chatId to create unique key
  /// - [telegramFileSize]: Stored for history display
  /// - [telegramTopicId]: Forum topic identifier
  /// - [telegramTopicName]: Forum topic display name
  /// - [startAtZero]: Force start from beginning (used by playlist restart)
  ///
  /// ## Proxy Port Correction:
  /// When loading a stored URL (e.g., from "Recent Videos"), the proxy port
  /// may have changed since app restart. This method detects stale ports
  /// and corrects them using the active [StreamingRepository.port].
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
      // CRITICAL FIX: Capture previous video data BEFORE resetting state.
      // This ensures we can clear progress for finished videos using the correct
      // position/duration values, not the reset values from the new video.
      final previousPath = state.currentVideoPath;
      final previousPosition = state.position;
      final previousDuration = state.duration;

      // Get storage key for previous video using current Telegram context
      // (before it gets overwritten by new video's context)
      final previousStorageKey = previousPath != null
          ? _getStableStorageKey(previousPath)
          : null;

      // Clear progress for the previous video if it finished
      if (previousStorageKey != null) {
        await _clearProgressForFinishedVideo(
          storageKey: previousStorageKey,
          position: previousPosition,
          duration: previousDuration,
        );
      }

      state = state.copyWith(
        currentVideoPath: path,
        currentVideoTitle: title,
        error: null,
        streamingError: null, // Clear any previous streaming error
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
      if (path.contains('file_id=')) {
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
      
      // FIX: Set seek target variables to prevent the position listener from flashing
      // the UI back to 0% when MediaKit emits its initial 0-position events.
      if (startPosition > Duration.zero) {
        _lastSeekTarget = startPosition;
        _lastSeekTime = DateTime.now();
        // Clear any previous recovery extensions to avoid confusion
        _seekRecoveryExtensions = 0;
      }
      
      await _repository.play(video, startPosition: startPosition);

      // FIX: Start MOOV check timer immediately for network videos
      // This ensures we detect MOOV-at-end before playback confirms,
      // so the "not optimized for streaming" message appears during loading.
      if (isNetwork && _currentProxyFileId != null) {
        _startMoovCheckTimer();
      }

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
    // Cancelar recuperación de seek anterior
    _seekRecoveryTimer?.cancel();
    _seekRecoveryTimer = null;
    _lastSeekTarget = position;
    _lastSeekTime = DateTime.now();
    _seekRecoveryExtensions = 0;

    // CRITICAL: Si hay un error de streaming activo, limpiar ANTES del seek.
    // Sin esto, el proxy rechaza la request con 503 (circuit breaker) y el
    // seek falla silenciosamente sin que el player entre en buffering.
    if (state.streamingError != null && _currentProxyFileId != null) {
      debugPrint(
        'PlayerNotifier: Limpiando error de streaming antes de seek',
      );
      clearStreamingError();
    }

    // Capturar bytes descargados para detectar progreso en recovery
    _seekRecoveryBytesSnapshot = _currentProxyFileId != null
        ? _streamingRepository
                .getLoadingProgress(_currentProxyFileId!)
                ?.bytesLoaded ??
            0
        : 0;

    // Optimistic update
    state = state.copyWith(position: position, seekRetryCount: 0);
    await _savePosition();
    await _repository.seekTo(position);

    // Iniciar recuperación automática solo para videos de Telegram
    if (_currentProxyFileId != null) {
      _startSeekRecovery(position);
    }
  }

  /// Inicia un timer de recuperación que reintenta el seek si el buffering
  /// se queda atascado por más de [_seekRecoveryTimeout].
  ///
  /// FIX I: Antes de re-seek destructivo, verifica si el proxy está
  /// descargando activamente. Si hay progreso, extiende el timeout en vez
  /// de cancelar la descarga de TDLib con un re-seek innecesario.
  void _startSeekRecovery(Duration seekTarget) {
    _seekRecoveryTimer?.cancel();
    _seekRecoveryTimer = Timer(_seekRecoveryTimeout, () {
      if (!ref.mounted) return;

      // Recuperar si: buffering atascado O hay error de streaming activo
      // (el proxy puede rechazar con 503 sin que el player entre en buffering)
      final needsRecovery = _lastSeekTarget == seekTarget &&
          (state.isBuffering || state.streamingError != null);

      if (needsRecovery) {
        // FIX I: Si solo es buffering (sin error), verificar si la descarga
        // está progresando antes de hacer un re-seek destructivo.
        if (state.streamingError == null && _currentProxyFileId != null) {
          final progress = _streamingRepository.getLoadingProgress(
            _currentProxyFileId!,
          );
          final currentBytes = progress?.bytesLoaded ?? 0;
          final bytesGrew = currentBytes >
              _seekRecoveryBytesSnapshot + 100 * 1024; // >100KB de progreso

          if (bytesGrew &&
              _seekRecoveryExtensions < _maxSeekRecoveryExtensions) {
            _seekRecoveryExtensions++;
            final progressMB =
                (currentBytes - _seekRecoveryBytesSnapshot) / 1024 / 1024;
            debugPrint(
              'PlayerNotifier: Seek recovery - buffering pero descarga activa '
              '(${progressMB.toStringAsFixed(1)}MB progreso), '
              'extendiendo timeout '
              '($_seekRecoveryExtensions/$_maxSeekRecoveryExtensions)',
            );
            // Actualizar snapshot para la siguiente comparación
            _seekRecoveryBytesSnapshot = currentBytes;
            // Re-programar sin re-seek destructivo
            _startSeekRecovery(seekTarget);
            return;
          }
        }

        final retryCount = state.seekRetryCount;

        if (retryCount < _maxSeekRetries) {
          debugPrint(
            'PlayerNotifier: Seek recovery - '
            '${state.isBuffering ? "buffering atascado" : "error de streaming"} '
            'por ${_seekRecoveryTimeout.inSeconds}s, reintentando seek '
            '(intento ${retryCount + 1}/$_maxSeekRetries)',
          );
          state = state.copyWith(seekRetryCount: retryCount + 1);

          // Limpiar error completo del proxy (resetea loadState, retries, etc.)
          if (_currentProxyFileId != null) {
            _streamingRepository.clearError(_currentProxyFileId!);
          }
          state = state.copyWith(streamingError: null);

          // Reintentar el seek
          _repository.seekTo(seekTarget);

          // Programar siguiente chequeo de recuperación
          _startSeekRecovery(seekTarget);
        } else {
          debugPrint(
            'PlayerNotifier: Seek recovery agotada después de $_maxSeekRetries '
            'intentos. Recargando video completo.',
          );
          _reloadVideoAtPosition(seekTarget);
        }
      }
    });
  }

  /// Último recurso: recargar el video completo desde la posición del seek.
  Future<void> _reloadVideoAtPosition(Duration position) async {
    final path = state.currentVideoPath;
    if (path == null) return;

    // Limpiar error completo del proxy
    if (_currentProxyFileId != null) {
      _streamingRepository.clearError(_currentProxyFileId!);
    }
    state = state.copyWith(streamingError: null);

    await loadVideo(
      path,
      isNetwork: true,
      title: state.currentVideoTitle,
      telegramChatId: _telegramChatId,
      telegramMessageId: _telegramMessageId,
      telegramFileSize: _telegramFileSize,
      telegramTopicId: _telegramTopicId,
      telegramTopicName: _telegramTopicName,
    );
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

  void toggleMirror() {
    state = state.copyWith(isMirrored: !state.isMirrored);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _repository.setPlaybackSpeed(speed);
    state = state.copyWith(playbackSpeed: speed);
  }

  void setControlsVisibility(bool visible) {
    state = state.copyWith(areControlsVisible: visible);
  }

  /// Returns a stable storage key for progress persistence.
  /// Delegates to StorageKeyService for centralized logic.
  String _getStableStorageKey(String path) {
    return StorageKeyService.getStableKey(
      telegramChatId: _telegramChatId,
      telegramMessageId: _telegramMessageId,
      proxyFileId: _currentProxyFileId,
      fallbackPath: path,
    );
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
      if (!ref.mounted) {
        _saveTimer?.cancel();
        return;
      }
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
