import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'telegram_service.dart';
import 'mp4_sample_table.dart';
import 'telegram_cache_service.dart';
import 'retry_tracker.dart';
import 'download_priority.dart';
import 'proxy_logger.dart';
import 'proxy_file_state.dart';
import 'proxy_config.dart';
import 'download_metrics.dart';
import 'streaming_lru_cache.dart';
import '../../domain/value_objects/loading_progress.dart';
import '../../domain/value_objects/streaming_error.dart';

class ProxyFileInfo {
  final String path;
  final int totalSize;
  final int downloadOffset;
  final int downloadedPrefixSize;
  final bool isDownloadingActive;
  final bool isCompleted;

  ProxyFileInfo({
    required this.path,
    required this.totalSize,
    this.downloadOffset = 0,
    this.downloadedPrefixSize = 0,
    this.isDownloadingActive = false,
    this.isCompleted = false,
  });

  /// Check if data is available at the given offset
  /// Returns the number of available bytes from offset, or 0 if not available
  int availableBytesFrom(int offset) {
    if (isCompleted) {
      return totalSize > offset ? totalSize - offset : 0;
    }

    final begin = downloadOffset;
    final end = downloadOffset + downloadedPrefixSize;

    // Check if offset is within the downloaded range
    if (offset >= begin && offset < end) {
      return end - offset;
    }

    return 0;
  }
}

// DownloadMetrics and StreamingLRUCache are imported from their own files
// See: download_metrics.dart and streaming_lru_cache.dart

// =============================================================================
// LocalStreamingProxy - HTTP Proxy for Telegram Video Streaming
// =============================================================================
//
// PURPOSE:
// Bridges HTTP video players (VLC, MediaKit, FVP) with TDLib's file download API.
// Converts HTTP Range requests into TDLib downloadFile() calls.
//
// ARCHITECTURE:
// ┌─────────────────┐     HTTP/1.1     ┌──────────────────┐     TDLib FFI     ┌─────────────┐
// │  Video Player   │────Range Req────▶│ LocalStreamingProxy│───downloadFile──▶│  Telegram   │
// │  (MediaKit)     │◀───206 Partial───│  (HTTP Server)   │◀──updateFile────│   Servers   │
// └─────────────────┘                  └──────────────────┘                 └─────────────┘
//
// KEY MECHANISMS:
//
// 1. MOOV ATOM DETECTION:
//    MP4 files have a "moov" atom containing video metadata (duration, keyframes).
//    - moov-at-START: Optimized for streaming, player gets metadata immediately
//    - moov-at-END: NOT optimized, player must download end of file first
//    The proxy detects this via player behavior (request for end of file early).
//
// 2. MOOV-FIRST STATE MACHINE (FileLoadState):
//    For files with saved playback position after cache clear:
//    idle → loadingMoov → moovReady → seeking → playing
//    This prevents "stale seek" where player seeks before metadata is loaded.
//
// 3. PRIORITY SYSTEM:
//    - Priority 32: User-initiated seeks (highest, protected from cancellation)
//    - Priority 16: Active playback (normal viewing)
//    - Priority 5: Visible videos in list view (preload)
//    - Priority 1: Background preload
//
// 4. LRU STREAMING CACHE:
//    32MB per-file cache with 512KB chunks for instant backward seeks.
//    Eliminates network round-trip for small backward seeks (<32MB).
//
// 5. ZOMBIE PROTECTION:
//    "Zombie" requests are HTTP connections that remain open after seek.
//    The proxy blacklists old offsets to prevent them from hijacking downloads.
//
// 6. STALL DETECTION:
//    Tracks download speed and detects stalls (<50KB/s for >2s).
//    Triggers adaptive buffer escalation when stalls are detected.
//
// =============================================================================

/// HTTP proxy server that streams Telegram videos to local video players.
///
/// Singleton pattern ensures single port allocation and consistent state.
///
/// ## URL Format:
/// ```
/// http://127.0.0.1:{port}/stream?file_id={id}&size={bytes}
/// ```
///
/// ## Key Methods:
/// - [start]: Initialize HTTP server on random port
/// - [getUrl]: Generate streaming URL for a file
/// - [abortRequest]: Cancel streaming for a file (e.g., on video change)
/// - [invalidateAllFiles]: Clear all state after cache clear
/// - [signalUserSeek]: Tell proxy a user-initiated seek is coming
///
/// ## Integration:
/// Works with [StreamingRepository] interface for clean architecture.
/// PlayerNotifier uses this via [StreamingRepository.port].
class LocalStreamingProxy {
  static final LocalStreamingProxy _instance = LocalStreamingProxy._internal();
  factory LocalStreamingProxy() => _instance;
  LocalStreamingProxy._internal();

  // ============================================================
  // STRUCTURED LOGGING with ProxyLogger
  // ============================================================
  /// Access to the centralized logger with levels and buffering.
  final ProxyLogger _logger = ProxyLogger.instance;

  /// Convenience method for trace-level logging (most verbose).
  void _logTrace(String message, {int? fileId, Map<String, dynamic>? data}) {
    _logger.trace(message, fileId: fileId, data: data);
  }

  /// Convenience method for debug-level logging.
  void _log(String message, {int? fileId, Map<String, dynamic>? data}) {
    _logger.debug(message, fileId: fileId, data: data);
  }

  /// Convenience method for info-level logging.
  void _logInfo(String message, {int? fileId, Map<String, dynamic>? data}) {
    _logger.info(message, fileId: fileId, data: data);
  }

  /// Convenience method for warning-level logging.
  void _logWarning(String message, {int? fileId, Map<String, dynamic>? data}) {
    _logger.warning(message, fileId: fileId, data: data);
  }

  /// Convenience method for error-level logging.
  void _logError(
    String message, {
    int? fileId,
    Map<String, dynamic>? data,
    Object? exception,
  }) {
    _logger.error(message, fileId: fileId, data: data, exception: exception);
  }

  /// Set the log level at runtime.
  void setLogLevel(ProxyLogLevel level) {
    _logger.setLevel(level);
  }

  /// Debug-only print that's completely eliminated in release builds.
  /// The compiler removes this entirely when kDebugMode is false,
  /// so there's zero overhead in production.
  ///
  /// Use [_debugLog] for very verbose debug output that should NOT be
  /// captured in the ring buffer (console-only, frequent messages).
  /// Use [_log] for structured logging that should be captured for debugging.
  void _debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      debugPrint(message);
    }
  }

  /// Get buffered logs for debugging.
  List<ProxyLogEntry> getBufferedLogs({int? fileId, ProxyLogLevel? minLevel}) {
    if (fileId != null) {
      return _logger.getLogsForFile(fileId);
    } else if (minLevel != null) {
      return _logger.getLogsAtLevel(minLevel);
    }
    return _logger.getBufferedLogs();
  }

  // ============================================================
  // OPTIMIZATION: Update Throttling
  // ============================================================
  // Process TDLib updateFile events at most every 50ms to reduce main thread load
  // See ProxyConfig.updateThrottleMs for configuration
  static int get _updateThrottleMs => ProxyConfig.updateThrottleMs;
  DateTime? _lastUpdateProcessedTime;
  final Map<int, ProxyFileInfo> _pendingFileUpdates = {};
  Timer? _throttleTimer;

  // ============================================================
  // CACHE LIMIT ENFORCEMENT
  // ============================================================
  // Trigger cache limit enforcement based on downloaded bytes (streaming mode)
  // Since videos stream partially and never "complete", we trigger enforcement
  // every _enforcementThresholdBytes of downloaded data.
  // See ProxyConfig for configuration
  static int get _enforcementThresholdBytes =>
      ProxyConfig.enforcementThresholdBytes;
  static int get _enforcementDebounceMs => ProxyConfig.enforcementDebounceMs;
  Timer? _enforcementTimer;
  DateTime? _lastEnforcementTime;
  int _totalBytesDownloadedSinceEnforcement = 0;

  // ============================================================
  // OPTIMIZATION: Disk Safety Check Caching
  // ============================================================
  // Cache disk safety check result for 5 seconds to avoid redundant disk queries
  // See ProxyConfig.diskCheckCacheMs for configuration
  static int get _diskCheckCacheMs => ProxyConfig.diskCheckCacheMs;
  DateTime? _lastDiskCheckTime;
  bool? _lastDiskCheckResult;

  /// Cached disk safety check to reduce disk queries during rapid download requests
  Future<bool> _checkDiskSafetyCached() async {
    final now = DateTime.now();
    if (_lastDiskCheckResult != null &&
        _lastDiskCheckTime != null &&
        now.difference(_lastDiskCheckTime!).inMilliseconds <
            _diskCheckCacheMs) {
      return _lastDiskCheckResult!;
    }

    _lastDiskCheckResult = await TelegramCacheService().checkDiskSafety();
    _lastDiskCheckTime = now;
    return _lastDiskCheckResult!;
  }

  HttpServer? _server;
  int _port = 0;

  // Security: Session token to prevent unauthorized local access
  // Generated on each start() call, required in all streaming URLs
  String _sessionToken = '';

  // Cache of file_id -> ProxyFileInfo
  final Map<int, ProxyFileInfo> _filePaths = {};

  // Consolidated per-file state for better maintainability
  final Map<int, ProxyFileState> _fileStates = {};

  /// Get or create consolidated state for a file.
  /// Use this instead of accessing individual Maps.
  ProxyFileState _getOrCreateState(int fileId) {
    return _fileStates.putIfAbsent(fileId, () => ProxyFileState(fileId));
  }

  // Active download requests
  final Set<int> _activeDownloadRequests = {};

  // File update notifiers for blocking waits
  final Map<int, StreamController<void>> _fileUpdateNotifiers = {};

  // EVENT-DRIVEN WAITS: Completers that wait for specific byte offsets
  // Key: fileId, Value: List of (requiredOffset, Completer) pairs
  // When updateFile arrives with data at an offset, matching Completers are completed
  final Map<int, List<MapEntry<int, Completer<void>>>>
  _byteAvailabilityWaiters = {};

  // Track aborted requests to cancel waiting loops
  final Set<int> _abortedRequests = {};

  // ============================================================
  // TELEGRAM ANDROID-INSPIRED IMPROVEMENTS
  // ============================================================

  // PRELOAD ADAPTATIVO: Bytes mínimos antes de servir datos al player
  // Inspired by ExoPlayer's bufferForPlaybackMs
  // See ProxyConfig for configuration
  static int get _minPreloadBytes => ProxyConfig.minPreloadBytes;
  static int get _fastNetworkPreload => ProxyConfig.fastNetworkPreload;
  static int get _slowNetworkPreload => ProxyConfig.slowNetworkPreload;

  // MÉTRICAS DE VELOCIDAD: Track download speed for adaptive decisions
  final Map<int, DownloadMetrics> _downloadMetrics = {};

  // IN-MEMORY LRU CACHE: Cache recently read data for instant backward seeks
  final Map<int, StreamingLRUCache> _streamingCaches = {};
  // Track all active HTTP request offsets per file for cleanup on close
  final Map<int, Set<int>> _activeHttpRequestOffsets = {};

  // INITIALIZATION GRACE PERIOD: Track when video was first opened
  // Used to prevent false stalls during MOOV-at-end video initialization
  // See ProxyConfig.initializationGracePeriod for configuration
  static Duration get _initializationGracePeriod =>
      ProxyConfig.initializationGracePeriod;

  // ============================================================
  // SEEK OPTIMIZATION (Telegram/drklo-inspired)
  // ============================================================

  // SEEK DEBOUNCE: Prevent flooding TDLib with rapid seek cancellations
  final Map<int, Timer?> _seekDebounceTimers = {};
  final Map<int, int> _pendingSeekOffsets = {};
  // See ProxyConfig.seekDebounceMs for configuration
  static int get _seekDebounceMs => ProxyConfig.seekDebounceMs;

  // STALL DETECTION: Track last download progress
  final Map<int, int> _lastDownloadProgress = {};

  // LOG THROTTLING: Prevent excessive debug logs from consuming CPU
  // Maps fileId -> last time "Waiting for data" was logged
  final Map<int, DateTime> _lastWaitingLogTime = {};
  // Maps fileId -> last time "PROTECTED" was logged
  final Map<int, DateTime> _lastProtectedLogTime = {};
  // See ProxyConfig for throttle durations
  static Duration get _waitingLogThrottle => ProxyConfig.waitingLogThrottle;
  static Duration get _protectedLogThrottle => ProxyConfig.protectedLogThrottle;

  /// Check if a file has moov atom at the end (not optimized for streaming)
  bool isVideoNotOptimizedForStreaming(int fileId) =>
      _getOrCreateState(fileId).isMoovAtEnd;

  // ============================================================
  // P0 FIX: MOOV-FIRST STATE MACHINE
  // ============================================================

  /// Track files with stale playback positions (after cache clear)
  /// These files need MOOV verification before seeking to saved position
  final Set<int> _stalePlaybackPositions = {};

  /// Track the saved position to seek to after MOOV is loaded
  /// Key: fileId, Value: byte offset to seek to
  final Map<int, int> _pendingSeekAfterMoov = {};

  // ============================================================
  // RETRY TRACKING AND ERROR HANDLING
  // ============================================================

  /// Tracks retry attempts per file to prevent infinite loops
  final RetryTracker _retryTracker = RetryTracker();

  /// Callback for unrecoverable errors - UI should subscribe to this
  void Function(StreamingError error)? onStreamingError;

  /// Get the last error for a file, or null if no error
  StreamingError? getLastError(int fileId) =>
      _getOrCreateState(fileId).lastError;

  /// Clear error state for a file (e.g., when retrying manually)
  void clearError(int fileId) {
    _getOrCreateState(fileId).lastError = null;
    _retryTracker.reset(fileId);
    // Reset load state back to idle if it was in error
    final state = _getOrCreateState(fileId);
    if (state.loadState == FileLoadState.error ||
        state.loadState == FileLoadState.timeout ||
        state.loadState == FileLoadState.unsupported) {
      state.loadState = FileLoadState.idle;
    }
  }

  /// Reset retry counter only (e.g., when playback recovers successfully).
  /// This prevents cascading MAX_RETRIES_EXCEEDED errors after recovery.
  void resetRetryCount(int fileId) {
    _retryTracker.reset(fileId);
    // Also reset stall count in metrics to prevent accumulated stall counts
    // from affecting buffer sizing after recovery
    _downloadMetrics[fileId]?.resetStallCount();
    _debugLog('Proxy: Retry count reset for $fileId (playback recovered)');
  }

  /// Report a player-detected error (e.g. unsupported codec, corrupt file).
  /// Marks the file as unrecoverable so the proxy stops retrying for this fileId.
  void reportPlayerError(StreamingError error) {
    final fileId = error.fileId;
    final state = _getOrCreateState(fileId);
    state.lastError = error;
    state.loadState = FileLoadState.unsupported;
    onStreamingError?.call(error);
    _logError(
      'Player reported error for file - ${error.type}: ${error.message}',
      fileId: fileId,
    );
  }

  /// Internal method to notify error and update state.
  /// Returns true if error was notified (new), false if it was a duplicate.
  bool _notifyErrorIfNew(int fileId, StreamingError error) {
    final state = _getOrCreateState(fileId);

    // Guard: Prevent duplicate error notifications for the same error type
    // This prevents multiple concurrent stall timers from spamming MAX_RETRIES_EXCEEDED
    if (state.lastError != null && state.lastError!.type == error.type) {
      return false; // Already notified for this error type
    }

    state.lastError = error;

    // Transition to appropriate error state
    if (error.isRecoverable) {
      state.loadState = FileLoadState.error;
    } else {
      switch (error.type) {
        case StreamingErrorType.timeout:
          state.loadState = FileLoadState.timeout;
          break;
        case StreamingErrorType.unsupportedCodec:
        case StreamingErrorType.corruptFile:
          state.loadState = FileLoadState.unsupported;
          break;
        default:
          state.loadState = FileLoadState.error;
      }
    }

    // Notify callback
    onStreamingError?.call(error);
    _logError(
      'ERROR for file - ${error.type}: ${error.message}',
      fileId: fileId,
    );
    return true;
  }

  /// Get the current load state for a file
  FileLoadState getFileLoadState(int fileId) =>
      _getOrCreateState(fileId).loadState;

  /// Check if a file has a stale playback position (needs MOOV first)
  bool hasStalePlaybackPosition(int fileId) =>
      _stalePlaybackPositions.contains(fileId);

  /// Get the pending seek position for a file (set when MOOV-first redirect happened)
  /// Returns null if no pending seek.
  /// UI should call this after MOOV loads to know where to seek.
  int? getPendingSeekPosition(int fileId) => _pendingSeekAfterMoov[fileId];

  /// Acknowledge that a pending seek has been processed.
  /// Call this after the player has successfully seeked to the pending position.
  void acknowledgePendingSeek(int fileId) {
    _pendingSeekAfterMoov.remove(fileId);
    _stalePlaybackPositions.remove(fileId);
    _getOrCreateState(fileId).loadState = FileLoadState.playing;
    _debugLog('Proxy: P0 FIX - Pending seek acknowledged for $fileId');
  }

  int get port => _port;

  /// Get current loading progress for a file.
  /// Returns null if file is not being tracked.
  /// UI can use this to show loading indicators and progress bars.
  LoadingProgress? getLoadingProgress(int fileId) {
    final cached = _filePaths[fileId];
    if (cached == null) return null;

    final metrics = _downloadMetrics[fileId];
    final loadState = _getOrCreateState(fileId).loadState;
    final isFetchingMoov =
        _getOrCreateState(fileId).forcedMoovOffset != null ||
        loadState == FileLoadState.loadingMoov;

    return LoadingProgress(
      fileId: fileId,
      totalBytes: cached.totalSize,
      bytesLoaded: cached.downloadedPrefixSize,
      isFetchingMoov: isFetchingMoov,
      isComplete: cached.isCompleted,
      bytesPerSecond: metrics?.bytesPerSecond ?? 0,
      loadState: loadState,
    );
  }

  /// Preload video start - no-op stub maintained for API compatibility.
  /// Actual preloading was disabled as it interfered with TDLib download management.
  @Deprecated(
    'Preloading disabled due to TDLib limitations. Remove calls to this method.',
  )
  void preloadVideoStart(int fileId, int? totalSize, {bool isVisible = false}) {
    // No-op: preloading disabled
  }

  void abortRequest(int fileId) {
    // Prevent duplicate abort calls
    if (_abortedRequests.contains(fileId)) {
      _log('Already aborted fileId $fileId, skipping');
      return;
    }

    _log('===== ABORTING REQUEST for fileId $fileId =====');
    _abortedRequests.add(fileId);

    // Clean up retry and error tracking
    _retryTracker.reset(fileId);

    // Clean up early MOOV detection tracking
    _earlyMoovDetectionTriggered.remove(fileId);

    // Clean up byte availability waiters to prevent memory leak
    final waiters = _byteAvailabilityWaiters.remove(fileId);
    if (waiters != null) {
      for (final entry in waiters) {
        if (!entry.value.isCompleted) {
          entry.value.complete(); // Wake up any waiting futures
        }
      }
      _log(
        'Cleaned up ${waiters.length} byte availability waiters for $fileId',
      );
    }

    // Notify any waiting loops to wake up and check abort status, then close notifier
    final notifier = _fileUpdateNotifiers.remove(fileId);
    if (notifier != null) {
      notifier.add(null);
      notifier.close();
    }

    // Cancel seek debounce timer
    _seekDebounceTimers[fileId]?.cancel();
    _seekDebounceTimers.remove(fileId);
    _pendingSeekOffsets.remove(fileId);

    // Clear LRU streaming cache for this file (releases up to 32MB)
    _streamingCaches[fileId]?.clear();
    _streamingCaches.remove(fileId);

    // Remove all per-file state to prevent memory growth
    _filePaths.remove(fileId);
    _fileStates.remove(fileId);
    _downloadMetrics.remove(fileId);
    _activeHttpRequestOffsets.remove(fileId);
    _lastDownloadProgress.remove(fileId);
    _lastWaitingLogTime.remove(fileId);
    _lastProtectedLogTime.remove(fileId);
    _pendingFileUpdates.remove(fileId);
  }

  /// Invalidates all cached file information.
  /// Call this when Telegram cache is cleared to ensure fresh file info is fetched.
  void invalidateAllFiles() {
    _log('Invalidating all cached file info');
    _filePaths.clear();
    _activeHttpRequestOffsets.clear();

    _downloadMetrics.clear();
    _sampleTableCache.clear();

    // Clear consolidated file states
    _fileStates.clear();

    // Clear LRU streaming caches
    for (final cache in _streamingCaches.values) {
      cache.clear();
    }
    _streamingCaches.clear();

    // Clear file load states (handled by _fileStates.clear())
    _pendingSeekAfterMoov.clear();
    _stalePlaybackPositions.clear();

    // Clear retry tracking and error state
    _retryTracker.resetAll();

    // Clear early MOOV detection tracking
    _earlyMoovDetectionTriggered.clear();

    _log('All cached file info invalidated');
  }

  /// Invalidates cached info for a specific file.
  void invalidateFile(int fileId) {
    _log('Invalidating cached info for file $fileId');
    _filePaths.remove(fileId);
    _activeHttpRequestOffsets.remove(fileId);

    // Clear LRU streaming cache for this file
    _streamingCaches[fileId]?.clear();
    _streamingCaches.remove(fileId);
  }

  /// Signal that user explicitly initiated a seek.
  /// Call this from MediaKitVideoRepository.seekTo() BEFORE the player seeks.
  void signalUserSeek(int fileId, int targetTimeMs) {
    _log('USER SEEK SIGNALED for $fileId to ${targetTimeMs}ms');
    // Simplified - just update primary offset tracking
    // The actual seek handling is done when the new offset request arrives
  }

  Future<void> start() async {
    if (_server != null) return;

    // Security: Generate random session token (32 hex characters)
    final random = Random.secure();
    final tokenBytes = List<int>.generate(16, (_) => random.nextInt(256));
    _sessionToken = tokenBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _logInfo('Running on port $_port');

    _server!.listen(_handleRequest);

    TelegramService().updates.listen(_onUpdate);
  }

  void _onUpdate(Map<String, dynamic> update) {
    if (update['@type'] != 'updateFile') return;

    final file = update['file'];
    final id = file['id'] as int?;
    if (id == null) return;

    final local = file['local'] as Map<String, dynamic>?;
    final info = ProxyFileInfo(
      path: local?['path'] as String? ?? '',
      totalSize: file['size'] as int? ?? 0,
      downloadOffset: local?['download_offset'] as int? ?? 0,
      downloadedPrefixSize: local?['downloaded_prefix_size'] as int? ?? 0,
      isDownloadingActive: local?['is_downloading_active'] as bool? ?? false,
      isCompleted: local?['is_downloading_completed'] as bool? ?? false,
    );

    // CACHE LIMIT ENFORCEMENT (STREAMING MODE):
    // Since videos stream partially and never "complete", we track cumulative
    // downloaded bytes and trigger enforcement every _enforcementThresholdBytes.
    final previousInfo = _filePaths[id];
    if (previousInfo != null) {
      final previousBytes = previousInfo.downloadedPrefixSize;
      final currentBytes = info.downloadedPrefixSize;
      if (currentBytes > previousBytes) {
        final delta = currentBytes - previousBytes;
        _totalBytesDownloadedSinceEnforcement += delta;

        // Check if we've crossed the threshold
        if (_totalBytesDownloadedSinceEnforcement >=
            _enforcementThresholdBytes) {
          _debugLog(
            'Proxy: Downloaded ${_totalBytesDownloadedSinceEnforcement ~/ (1024 * 1024)} MB since last enforcement, scheduling cleanup',
          );
          _scheduleEnforcement();
        }
      }
    }

    // Also trigger on download complete (for fully cached videos)
    final wasCompleted = previousInfo?.isCompleted ?? false;
    if (info.isCompleted && !wasCompleted) {
      _debugLog(
        'Proxy: Video $id download completed, scheduling cache enforcement',
      );
      _scheduleEnforcement();
    }

    // CRITICAL FIX: Always process immediately if there are active waiters
    // for this file. This ensures MOOV-at-end videos don't stall.
    final hasActiveWaiter = _fileUpdateNotifiers.containsKey(id);
    final hasActiveByteWaiter = _byteAvailabilityWaiters.containsKey(id);
    if (hasActiveWaiter || hasActiveByteWaiter) {
      // Process this update immediately - someone is waiting for it
      _filePaths[id] = info;
      _fileUpdateNotifiers[id]?.add(null);

      // EVENT-DRIVEN: Wake up byte availability waiters whose offsets are now satisfied
      if (hasActiveByteWaiter) {
        final waiters = _byteAvailabilityWaiters[id]!;
        waiters.removeWhere((entry) {
          final requiredOffset = entry.key;
          final completer = entry.value;

          // Check if data is now available at the required offset
          if (info.availableBytesFrom(requiredOffset) > 0) {
            if (!completer.isCompleted) {
              completer.complete();
            }
            return true; // Remove from list
          }
          return false;
        });

        // Clean up empty waiter lists
        if (waiters.isEmpty) {
          _byteAvailabilityWaiters.remove(id);
        }
      }

      // EARLY MOOV DETECTION: Trigger as soon as we have enough bytes
      // This allows us to detect moov-at-start immediately and prepare
      // for moov-at-end videos before the player even requests data.
      _triggerEarlyMoovDetection(id, info);

      return;
    }

    // OPTIMIZATION: Buffer non-critical updates and process with throttling
    _pendingFileUpdates[id] = info;

    // Throttle: process at most every 50ms
    final now = DateTime.now();
    if (_lastUpdateProcessedTime != null &&
        now.difference(_lastUpdateProcessedTime!).inMilliseconds <
            _updateThrottleMs) {
      // Schedule delayed processing if not already scheduled
      _scheduleThrottledUpdate();
      return;
    }

    // Process immediately if throttle window passed
    _processPendingUpdates();
  }

  /// Schedule a delayed update processing if one isn't already pending
  void _scheduleThrottledUpdate() {
    if (_throttleTimer != null) return; // Already scheduled

    _throttleTimer = Timer(Duration(milliseconds: _updateThrottleMs), () {
      _throttleTimer = null;
      _processPendingUpdates();
    });
  }

  /// Process all buffered file updates at once
  void _processPendingUpdates() {
    if (_pendingFileUpdates.isEmpty) return;

    _lastUpdateProcessedTime = DateTime.now();

    for (final entry in _pendingFileUpdates.entries) {
      final id = entry.key;
      final info = entry.value;

      _filePaths[id] = info;

      // Notify anyone waiting for updates on this file
      _fileUpdateNotifiers[id]?.add(null);
    }
    _pendingFileUpdates.clear();
  }

  /// Schedule cache limit enforcement with debounce.
  /// Called when a video download completes to ensure cache stays within limit.
  void _scheduleEnforcement() {
    if (_enforcementTimer != null) return; // Already scheduled

    final now = DateTime.now();
    if (_lastEnforcementTime != null &&
        now.difference(_lastEnforcementTime!).inMilliseconds <
            _enforcementDebounceMs) {
      // Recently enforced - schedule for later
      final delay =
          _enforcementDebounceMs -
          now.difference(_lastEnforcementTime!).inMilliseconds;
      _enforcementTimer = Timer(Duration(milliseconds: delay), () {
        _enforcementTimer = null;
        _runEnforcement();
      });
      return;
    }

    // Run immediately (first time or after debounce window)
    _runEnforcement();
  }

  /// Execute the cache limit enforcement
  Future<void> _runEnforcement() async {
    _lastEnforcementTime = DateTime.now();
    _totalBytesDownloadedSinceEnforcement = 0; // Reset counter
    _logTrace('Running cache limit enforcement');
    await TelegramCacheService().enforceVideoSizeLimit();
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;

    for (var c in _fileUpdateNotifiers.values) {
      await c.close();
    }
    _fileUpdateNotifiers.clear();
    _activeDownloadRequests.clear();
    _filePaths.clear();
    _abortedRequests.clear();
  }

  String getUrl(int fileId, int size) {
    return 'http://127.0.0.1:$_port/stream?token=$_sessionToken&file_id=$fileId&size=$size';
  }

  // Helper to get available bytes from the given offset
  // Uses local cache first (like Unigram), then queries TDLib if needed
  Future<int> _getDownloadedPrefixSize(int fileId, int offset) async {
    // 1. Check local cache first (Unigram pattern)
    final cached = _filePaths[fileId];
    if (cached != null && cached.path.isNotEmpty) {
      final available = cached.availableBytesFrom(offset);
      if (available > 0) {
        return available;
      }
    }

    // 2. If no cached data available, query TDLib
    try {
      final result = await TelegramService().sendWithResult({
        '@type': 'getFileDownloadedPrefixSize',
        'file_id': fileId,
        'offset': offset,
      });

      if (result['@type'] == 'error') {
        _debugLog(
          'Proxy: getFileDownloadedPrefixSize error: ${result['message']}',
        );
        return 0;
      }

      if (result['@type'] == 'fileDownloadedPrefixSize') {
        // TDLib returns 'size' not 'count' in this response
        final size = result['size'];
        if (size is int) {
          return size;
        }
        // Fallback: some versions might use 'count'
        final count = result['count'];
        if (count is int) {
          return count;
        }
        return 0;
      }
    } catch (e) {
      _debugLog('Proxy: Error getting prefix size: $e');
    }
    return 0;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    String? fileIdStr;
    int? fileId;
    int start = 0;
    try {
      _debugLog('Proxy: Received request for ${request.uri}');

      // Security: Validate session token
      final tokenParam = request.uri.queryParameters['token'];
      if (tokenParam != _sessionToken) {
        _debugLog('Proxy: Invalid or missing token - rejecting request');
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }

      fileIdStr = request.uri.queryParameters['file_id'];
      final sizeStr = request.uri.queryParameters['size'];

      if (fileIdStr == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      fileId = int.parse(fileIdStr);
      final totalSize = int.tryParse(sizeStr ?? '') ?? 0;

      // Track when video was first opened for initialization grace period
      final state = _getOrCreateState(fileId);
      state.openTime ??= DateTime.now();

      // Reject requests for files marked unsupported (codec/corrupt) - stop retrying
      if (state.loadState == FileLoadState.unsupported) {
        _debugLog('Proxy: Rejecting request for unsupported file $fileId');
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }

      // Wait for TDLib client to be ready (max 10 seconds)
      // This is crucial on app start when TDLib might still be initializing
      if (!TelegramService().isClientReady) {
        _debugLog('Proxy: Waiting for TDLib client to initialize...');
        int attempts = 0;
        while (!TelegramService().isClientReady && attempts < 100) {
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
        }
        if (!TelegramService().isClientReady) {
          _debugLog(
            'Proxy: TDLib client failed to initialize after 10 seconds',
          );
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        _debugLog('Proxy: TDLib client ready after ${attempts * 100}ms');
      }

      // If ANY files were recently aborted, give TDLib time to clean up
      // This is crucial - TDLib can crash if we start new downloads while
      // it's still processing cancellations internally
      if (_abortedRequests.isNotEmpty) {
        // Check if THIS file was aborted - needs longer wait
        final thisFileWasAborted = _abortedRequests.contains(fileId);

        _debugLog(
          'Proxy: Waiting for TDLib to stabilize (${_abortedRequests.length} aborted files, current file aborted: $thisFileWasAborted)...',
        );
        // Clear our abort tracking - we're about to start fresh
        _abortedRequests.clear();

        // Use shorter wait for unrelated files, longer if this file was aborted
        final waitMs = thisFileWasAborted ? 500 : 200;
        await Future.delayed(Duration(milliseconds: waitMs));
        _debugLog('Proxy: TDLib stabilization wait complete (${waitMs}ms)');
      }

      // Also clear stale cache for this specific file if it exists
      if (_filePaths.containsKey(fileId)) {
        final cached = _filePaths[fileId]!;
        // If the cached file was actively downloading but we're re-requesting,
        // clear it to get fresh state
        if (cached.isDownloadingActive) {
          _filePaths.remove(fileId);
        }
      }

      // 1. Parse Range Header
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      int? end;

      if (rangeHeader != null) {
        final parts = rangeHeader.replaceFirst('bytes=', '').split('-');
        start = int.parse(parts[0]);
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.parse(parts[1]);
        }
      }

      // Register this HTTP request offset for cleanup on close
      _activeHttpRequestOffsets.putIfAbsent(fileId, () => {});
      _activeHttpRequestOffsets[fileId]!.add(start);

      // ============================================================
      // P0/P1 FIX: MOOV-FIRST STATE MACHINE LOGIC
      // ============================================================
      // After cache clear, saved playback positions are stale.
      // If player requests a seek position > 1MB, we MUST load MOOV first.
      // This prevents TDLib crashes when jumping to far offsets without metadata.
      //
      // P1 FIX: Handle both MOOV-at-start AND MOOV-at-end files correctly.
      // For MOOV-at-end, we let the moov detection logic handle it normally.
      bool moovFirstRedirect = false;

      if (_stalePlaybackPositions.contains(fileId) && start > 1024 * 1024) {
        // File has stale position from cache clear, and player wants to seek far
        // Check current load state
        final currentState = _getOrCreateState(fileId).loadState;

        if (currentState == FileLoadState.idle ||
            currentState == FileLoadState.loadingMoov) {
          // Store the desired seek position for after MOOV loads
          _pendingSeekAfterMoov[fileId] = start;
          _getOrCreateState(fileId).loadState = FileLoadState.loadingMoov;

          // P1: Check if we know MOOV location for this file
          final isMoovAtEnd = _getOrCreateState(fileId).isMoovAtEnd;

          if (isMoovAtEnd) {
            // MOOV is at end - don't redirect to 0, let the existing
            // moov-at-end handling logic fetch from the correct offset.
            // We just mark the state and store pending seek.
            _debugLog(
              'Proxy: P1 FIX - Stale position for $fileId (MOOV at END). '
              'Requested: ${start ~/ 1024}KB. Pending seek stored. '
              'Letting moov-at-end logic handle MOOV fetch.',
            );
            // Don't redirect - moov will be fetched when player requests end of file
          } else {
            // MOOV is at start (or unknown) - redirect to 0
            _debugLog(
              'Proxy: P1 FIX - Stale position for $fileId (MOOV at START). '
              'Requested: ${start ~/ 1024}KB, forcing start from 0.',
            );
            moovFirstRedirect = true;
            start = 0;
          }
        } else if (currentState == FileLoadState.moovReady) {
          // MOOV is loaded, we can now process the stale seek
          _debugLog(
            'Proxy: P1 FIX - MOOV ready for $fileId. Processing pending seek to ${start ~/ 1024}KB',
          );
          _getOrCreateState(fileId).loadState = FileLoadState.seeking;
          _stalePlaybackPositions.remove(fileId);
          _pendingSeekAfterMoov.remove(fileId);
        }
      } else if (_stalePlaybackPositions.contains(fileId) &&
          start <= 1024 * 1024) {
        // Stale file but requesting near start - this is fine, likely loading MOOV
        // Mark as loading MOOV and clear stale status once we get some data
        _getOrCreateState(fileId).loadState = FileLoadState.loadingMoov;
      }

      // SEEK DETECTION: Mark if this is a seek (jump > 1MB from last served offset)
      // IMPORTANT: Do this BEFORE primary tracking so we can reset primary on seek
      // Skip seek detection if we did MOOV-first redirect (start was changed to 0)
      bool isSeekRequest = false;
      final lastOffset = moovFirstRedirect
          ? null
          : _getOrCreateState(fileId).lastServedOffset;
      if (lastOffset != null) {
        final jump = (start - lastOffset).abs();
        if (jump > 1024 * 1024) {
          isSeekRequest = true;

          // Don't set _lastSeekTime for moov requests (near end of file) OR
          // for seeks TO the beginning (initial playback).
          // _lastSeekTime should only be set for TRUE SCRUBBING: user dragging
          // the seek bar while video is playing (both positions > 10MB).
          final isMoovRequest =
              totalSize > 0 &&
              (totalSize - start) <
                  (totalSize * 0.05).round().clamp(
                    10 * 1024 * 1024,
                    100 * 1024 * 1024,
                  );
          final isSeekToBeginning = start < 10 * 1024 * 1024;
          final isTrueScrubbing =
              !isMoovRequest &&
              !isSeekToBeginning &&
              lastOffset > 10 * 1024 * 1024;

          if (isTrueScrubbing) {
            _getOrCreateState(fileId).lastSeekTime = DateTime.now();
          }

          // CRITICAL FIX: When a seek is detected, reset the primary offset to the seek target
          // This prevents the primary from getting stuck at 0 when seeking forward
          // _primaryPlaybackOffset[fileId] = start; // MOVED BELOW for centralized logic
          _debugLog(
            'Proxy: Detected seek for $fileId: $lastOffset -> $start (jump: ${jump ~/ 1024}KB)',
          );
        }
      }

      // PRIMARY PLAYBACK TRACKING (STABILIZED):
      // The player often fires multiple "Seek" requests (video, audio, etc.) to different offsets.
      // We must lock onto the FIRST one (user's intent) and ignore subsequent divergent "seeks".
      final playbackState = _getOrCreateState(fileId);
      final existingPrimary = playbackState.primaryPlaybackOffset;
      final lastPrimaryUpdate = playbackState.lastPrimaryUpdateTime;

      bool shouldUpdatePrimary = false;

      if (existingPrimary == null) {
        shouldUpdatePrimary = true;
      } else if (playbackState.userSeekInProgress) {
        // P1: User explicitly seeked via MediaKit - force Primary update
        // Don't require isSeekRequest because lastServedOffset may not be set yet
        // Accept any offset significantly different from current Primary (>50MB)
        final distFromPrimary = (start - existingPrimary).abs();
        if (distFromPrimary > 50 * 1024 * 1024) {
          _debugLog(
            'Proxy: EXPLICIT USER SEEK for $fileId. Primary $existingPrimary -> $start.',
          );
          shouldUpdatePrimary = true;
          playbackState.userSeekInProgress = false;
          // P1 FIX: Track this seek to protect from stagnant adoption
          playbackState.lastExplicitSeekOffset = start;
          playbackState.lastExplicitSeekTime = DateTime.now();
        } else {
          _debugLog(
            'Proxy: USER SEEK SIGNAL active but offset $start too close to Primary $existingPrimary (${distFromPrimary ~/ 1024}KB)',
          );
        }
      } else if (isSeekRequest) {
        // Check for Rapid Divergence
        if (lastPrimaryUpdate != null &&
            DateTime.now().difference(lastPrimaryUpdate).inMilliseconds <
                1000) {
          // Rapid update! distinct from previous primary?
          if ((start - existingPrimary).abs() > 10 * 1024 * 1024) {
            // RECOVERY ADOPTION (Seek variant):
            // If the player is "Thrashing" between two streams (e.g. 80MB and 180MB), both appear as
            // "Seeks" because lastServedOffset jumps. This blocks Sequential Recovery.
            // Force adoption if Primary has been stagnant for > 2000ms.
            //
            // RESUME-FROM-START FIX:
            // If the existing Primary is currently near the start (< 50MB) and the new seek is
            // significantly further (> 50MB), it's almost certainly a "Resume" or "User Seek".
            // The initial "Primary at 0" was just the player probing metadata/start.
            // We should ALWAYS adopt this new seek.
            //
            // MOOV FIX: Ensure we don't accidentally adopt the "Moov Atom" request (End of File)
            // as the Primary, because that will block the actual playback request at the middle.
            final isMoovRequestForCheck =
                totalSize > 0 && (totalSize - start) < 100 * 1024 * 1024;

            final isResumeFromStart =
                !isMoovRequestForCheck &&
                existingPrimary < 50 * 1024 * 1024 &&
                start > 50 * 1024 * 1024;

            if (isResumeFromStart) {
              _debugLog(
                'Proxy: RESUME DETECTED ($existingPrimary -> $start). Forcing Primary update.',
              );
              shouldUpdatePrimary = true;
            } else if (DateTime.now()
                    .difference(lastPrimaryUpdate)
                    .inMilliseconds >
                2000) {
              _debugLog(
                'Proxy: Recovering Primary Offset (Stagnant 2s in Seek) -> Adopting $start',
              );
              shouldUpdatePrimary = true;
            } else {
              _debugLog(
                'Proxy: IGNORING rapid divergent seek to $start (kept primary at $existingPrimary)',
              );
              shouldUpdatePrimary = false;
              // Reset isSeekRequest to false so this request doesn't bypass debounce!
              isSeekRequest = false;
            }
          } else {
            shouldUpdatePrimary = true; // Close enough, update it
          }
        } else {
          shouldUpdatePrimary = true; // Stable seek
        }
      } else if (start < existingPrimary) {
        // Only track lower offsets if they are reasonable (not huge jumps back which are likely zombie streams)
        final jumpBack = existingPrimary - start;
        if (jumpBack < 50 * 1024 * 1024) {
          shouldUpdatePrimary = true;
        } else {
          _debugLog(
            'Proxy: Ignoring primary offset reset $existingPrimary -> $start (diff: ${jumpBack ~/ (1024 * 1024)}MB) - likely zombie stream',
          );
        }
      } else {
        // SEQUENTIAL TRACKING:
        // If legitimate playback progresses forward, we must advance the Primary Offset so the
        // "Blocking Guard" (50MB radius) moves with the user.
        final jumpForward = start - existingPrimary;
        if (jumpForward > 0) {
          // 1. Standard Sequential: within 50MB
          if (jumpForward < 50 * 1024 * 1024) {
            shouldUpdatePrimary = true;
          }
          // 2. READ-AHEAD DETECTION:
          // If jump is > 50MB, it might be a Buffer Request (Parallel Read-Ahead).
          // We should NOT update Primary immediately, because the player is likely still
          // playing at 'existingPrimary'.
          // However, if Primary is STAGNANT ( hasn't moved for > 2000ms),
          // it might be a legitimate Seek that we misidentified.
          else if (lastPrimaryUpdate != null &&
              DateTime.now().difference(lastPrimaryUpdate).inMilliseconds >
                  2000) {
            _debugLog(
              'Proxy: Recovering Primary Offset (Stagnant 2s on Forward Jump) -> Adopting $start',
            );
            shouldUpdatePrimary = true;
          } else {
            _debugLog(
              'Proxy: Ignoring likely Read-Ahead Buffer Request at $start (Primary at $existingPrimary)',
            );
            shouldUpdatePrimary = false;
            // Treat as background/buffer request, don't debounce as seek
            isSeekRequest = false;
          }
        }
      }

      if (shouldUpdatePrimary) {
        playbackState.primaryPlaybackOffset = start;
        playbackState.lastPrimaryUpdateTime = DateTime.now();
        if (isSeekRequest) {
          // Only log if it was a seek
          _debugLog('Proxy: Primary Target UPDATED to $start');
        }
      }

      // 2. Ensure File Info is available
      if (!_filePaths.containsKey(fileId) || _filePaths[fileId]!.path.isEmpty) {
        await _fetchFileInfo(fileId);
      }

      var fileInfo = _filePaths[fileId];
      if (fileInfo == null || fileInfo.path.isEmpty) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      var file = File(fileInfo.path);

      // CRITICAL: Verify the file actually exists on disk
      // TDLib may report a path for a file that was deleted by cache cleanup
      if (!await file.exists()) {
        _debugLog(
          'Proxy: File does not exist on disk: ${fileInfo.path}, re-fetching...',
        );

        // Clear stale cache entry
        _filePaths.remove(fileId);

        // Tell TDLib to delete its reference to the missing file
        await TelegramService().sendWithResult({
          '@type': 'deleteFile',
          'file_id': fileId,
        });

        // Wait for TDLib to process
        await Future.delayed(const Duration(milliseconds: 300));

        // Re-fetch file info (this will trigger a new download)
        await _fetchFileInfo(fileId);

        fileInfo = _filePaths[fileId];
        if (fileInfo == null || fileInfo.path.isEmpty) {
          _debugLog('Proxy: Failed to re-allocate file $fileId');
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        file = File(fileInfo.path);

        // Verify the new file exists
        if (!await file.exists()) {
          _debugLog('Proxy: New file still does not exist: ${fileInfo.path}');
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
      }

      final effectiveTotalSize = totalSize > 0
          ? totalSize
          : (await file.length());
      var effectiveEnd =
          end ?? (effectiveTotalSize > 0 ? effectiveTotalSize - 1 : 0);

      // CRITICAL FIX: Clamp end to actual file size to prevent reading past EOF
      if (effectiveTotalSize > 0 && effectiveEnd >= effectiveTotalSize) {
        effectiveEnd = effectiveTotalSize - 1;
      }

      // Validate Range
      // Must start strictly before EOF (offset < size)
      if (start > effectiveEnd ||
          (effectiveTotalSize > 0 && start >= effectiveTotalSize)) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$effectiveTotalSize',
        );
        await request.response.close();
        return;
      }

      final contentLength = effectiveEnd - start + 1;

      // 3. Send Headers
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$effectiveEnd/$effectiveTotalSize',
      );
      request.response.headers.set(
        HttpHeaders.contentLengthHeader,
        contentLength,
      );
      request.response.headers.contentType = ContentType.parse('video/mp4');
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      // 4. Stream Data Loop
      RandomAccessFile? raf;
      try {
        // FILE LOCKING FIX (Windows): TDLib may have the file locked while writing.
        // Retry with exponential backoff to handle temporary file access issues.
        const maxRetries = 5;
        FileSystemException? lastError;
        for (var attempt = 0; attempt < maxRetries; attempt++) {
          try {
            raf = await file.open(mode: FileMode.read);
            break; // Success
          } on FileSystemException catch (e) {
            lastError = e;
            if (attempt < maxRetries - 1) {
              final delayMs = 50 * (1 << attempt); // 50, 100, 200, 400, 800ms
              _debugLog(
                'Proxy: File locked, retrying in ${delayMs}ms (attempt ${attempt + 1}/$maxRetries): ${e.message}',
              );
              await Future.delayed(Duration(milliseconds: delayMs));
            }
          }
        }

        // If still null after retries, throw the last error
        if (raf == null) {
          _debugLog('Proxy: Failed to open file after $maxRetries attempts');
          throw lastError ?? FileSystemException('Failed to open file');
        }

        int currentReadOffset = start;
        int remainingToSend = contentLength;

        // Ensure notifier exists
        if (!_fileUpdateNotifiers.containsKey(fileId)) {
          _fileUpdateNotifiers[fileId] = StreamController.broadcast();
        }

        while (remainingToSend > 0) {
          if (_abortedRequests.contains(fileId)) {
            _debugLog('Proxy: Request aborted for $fileId');
            break;
          }

          // Check direct availability on disk via TDLib
          final available = await _getDownloadedPrefixSize(
            fileId,
            currentReadOffset,
          );

          if (available > 0) {
            // Data is available!
            final chunkToRead = min(
              available,
              min(remainingToSend, 512 * 1024),
            );

            // LRU Cache: Try cache first, fall back to disk read
            _streamingCaches.putIfAbsent(fileId, () => StreamingLRUCache());
            final cache = _streamingCaches[fileId]!;
            var cachedData = cache.get(currentReadOffset, chunkToRead);

            Uint8List data;
            if (cachedData != null) {
              // Cache hit!
              data = cachedData;
            } else {
              // Cache miss - read from disk
              await raf.setPosition(currentReadOffset);
              data = await raf.read(chunkToRead);

              // Store in cache for future use
              if (data.isNotEmpty) {
                cache.put(currentReadOffset, data);
              }
            }

            if (data.isEmpty) {
              await Future.delayed(const Duration(milliseconds: 50));
              continue;
            }

            request.response.add(data);
            await request.response.flush();

            currentReadOffset += data.length;
            remainingToSend -= data.length;

            // Track download metrics for adaptive decisions
            _downloadMetrics.putIfAbsent(fileId, () => DownloadMetrics());
            _downloadMetrics[fileId]!.recordBytes(data.length);

            // Update last served offset for seek detection
            _getOrCreateState(fileId).lastServedOffset = currentReadOffset;

            // P0 FIX: MOOV state transition
            // If we were in loadingMoov state and have now loaded enough data (2MB),
            // transition to moovReady so pending seeks can proceed
            final fileState = _getOrCreateState(fileId);
            if (fileState.loadState == FileLoadState.loadingMoov &&
                currentReadOffset >= 2 * 1024 * 1024) {
              fileState.loadState = FileLoadState.moovReady;
              final pendingSeek = _pendingSeekAfterMoov[fileId];
              if (pendingSeek != null) {
                _debugLog(
                  'Proxy: P0 FIX - MOOV ready for $fileId. '
                  'Player should now seek to ${pendingSeek ~/ 1024}KB',
                );
              } else {
                // No pending seek means this was a fresh start, clear stale status
                _stalePlaybackPositions.remove(fileId);
                fileState.loadState = FileLoadState.playing;
              }
            }

            // Ensure download is started at the exact offset the player needs
            // FIX: Only start download if we still have data to send.
            // If we just finished the file (remainingToSend == 0), currentReadOffset == totalSize,
            // which causes TDLib crash if we request it.
            if (remainingToSend > 0) {
              _startDownloadAtOffset(fileId, currentReadOffset);

              // POST-SEEK PRELOAD: Trigger proactive preload if we recently seeked
              final lastSeek = _getOrCreateState(fileId).lastSeekTime;
              if (lastSeek != null &&
                  DateTime.now().difference(lastSeek).inMilliseconds < 2000) {
                _triggerPostSeekPreload(fileId, currentReadOffset);
              }
            }

            // PRIMARY TRACKING FIX:
            // Continuously update the Primary Offset as we serve data.
            // This ensures the "Protection Bubble" moves with the playback head.
            // FIX: We must THROTTLE this update to prevent "Buffering" from dragging the Primary
            // Offset far ahead of the actual Playback (Time).
            // If the player buffers 300MB in 1 second, we should NOT update Primary to +300MB,
            // because if the player then requests data at +10MB (Playback), it would look like
            // a "Distant Zombie" relative to the Buffer Head.
            //
            // Logic:
            // 1. Only allow Primary to advance by MAX_SPEED (e.g. 5MB/s) relative to elapsed time.
            // 2. Seeks (handled in _handleRequest) break this limit instantly.
            if (data.isNotEmpty) {
              final streamState = _getOrCreateState(fileId);
              final lastPrimary = streamState.primaryPlaybackOffset ?? 0;
              final lastUpdateTime = streamState.lastPrimaryUpdateTime;

              // If this is sequential (close to last known primary)
              if (currentReadOffset > lastPrimary &&
                  (currentReadOffset - lastPrimary) < 50 * 1024 * 1024) {
                final now = DateTime.now();
                // Determine allowed progress based on time elapsed
                // Base 2MB allowed instantly
                int allowedProgress = 2 * 1024 * 1024;
                if (lastUpdateTime != null) {
                  final elapsedMs = now
                      .difference(lastUpdateTime)
                      .inMilliseconds;
                  // Allow up to 3MB per second of additional progress (approx 3x realtime 1080p)
                  // Total max rate ~ 5MB/s roughly.
                  // (elapsedMs / 1000 * 3MB)
                  final timeBasedAllowance =
                      (elapsedMs / 1000 * 3 * 1024 * 1024).round();
                  allowedProgress += timeBasedAllowance;
                }

                // If the new offset is within the allowed progress window, update it.
                // Otherwise, hold the Primary back (it lags behind buffer).
                // If the new offset is within the allowed progress window, update it.
                // Otherwise, hold the Primary back (it lags behind buffer).
                if ((currentReadOffset - lastPrimary) <= allowedProgress) {
                  // Throttle the actual map update to avoid spamming debug logs/maps
                  // Update at most every 200ms
                  if (lastUpdateTime == null ||
                      now.difference(lastUpdateTime).inMilliseconds > 200) {
                    streamState.primaryPlaybackOffset = currentReadOffset;
                    streamState.lastPrimaryUpdateTime = now;
                  }
                }
              } else if (currentReadOffset > lastPrimary &&
                  (currentReadOffset - lastPrimary) > 50 * 1024 * 1024) {
                // STAGNANT ADOPTION (Stream Loop):
                // We are streaming far ahead of Primary (>50MB).
                // If the Primary hasn't moved for > 2000ms, assume the user seeked here
                // and the initial Seek Logic rejected it (or we missed it).
                //
                // P1 FIX: BACKWARD SEEK PROTECTION (POSITION-BASED)
                // If there was an explicit user seek and the proposed adoption offset
                // is significantly FORWARD of that seek, DON'T adopt.
                // Protection stays active until Primary moves >100MB from seek position.
                final lastExplicitSeek = streamState.lastExplicitSeekOffset;

                // Block adoption if:
                // - There was an explicit seek AND
                // - Current Primary is still near the seek position (within 100MB) AND
                // - The proposed offset is significantly forward of seek (>50MB)
                final primaryNearSeek =
                    lastExplicitSeek != null &&
                    (lastPrimary - lastExplicitSeek).abs() < 100 * 1024 * 1024;
                final proposedIsFarForward =
                    lastExplicitSeek != null &&
                    currentReadOffset > lastExplicitSeek &&
                    (currentReadOffset - lastExplicitSeek) > 50 * 1024 * 1024;
                final isOverridingBackwardSeek =
                    primaryNearSeek && proposedIsFarForward;

                if (isOverridingBackwardSeek) {
                  _debugLog(
                    'Proxy: BLOCKED Stagnant Adoption for $fileId. Would override recent backward seek '
                    '(seekTarget: ${lastExplicitSeek ~/ (1024 * 1024)}MB, primary: ${lastPrimary ~/ (1024 * 1024)}MB, proposed: ${currentReadOffset ~/ (1024 * 1024)}MB)',
                  );
                  // Don't adopt - keep the user's seek position
                  // Reset stagnant timer to prevent repeated adoption attempts
                  streamState.lastPrimaryUpdateTime = DateTime.now();
                } else if (lastUpdateTime != null &&
                    DateTime.now().difference(lastUpdateTime).inMilliseconds >
                        2000) {
                  _debugLog(
                    'Proxy: Recovering Primary Offset (Stagnant 2s in StreamLoop) -> Adopting $currentReadOffset',
                  );
                  streamState.primaryPlaybackOffset = currentReadOffset;
                  streamState.lastPrimaryUpdateTime = DateTime.now();
                }
              }
            } else {
              // NO DATA AVAILABLE -> BLOCKING WAIT (EVENT-DRIVEN)
              // Throttled log: only print every 2 seconds per file to reduce CPU overhead
              final now = DateTime.now();
              final lastLog = _lastWaitingLogTime[fileId];
              if (lastLog == null ||
                  now.difference(lastLog) >= _waitingLogThrottle) {
                _lastWaitingLogTime[fileId] = now;
                final cached = _filePaths[fileId];
                _debugLog(
                  'Proxy: Waiting for data at $currentReadOffset for $fileId '
                  '(CachedOffset: ${cached?.downloadOffset}, CachedPrefix: ${cached?.downloadedPrefixSize})...',
                );
              }

              // Ensure download is started at the exact offset the player needs
              _startDownloadAtOffset(
                fileId,
                currentReadOffset,
                isBlocking: true,
              );

              // EXTENDED TIMEOUT FOR MOOV ATOM: Requests near end of file need more time
              // because TDLib must start a new download from a distant offset
              final fileInfo = _filePaths[fileId];
              final totalFileSize = fileInfo?.totalSize ?? 0;
              final distanceFromEnd = totalFileSize > 0
                  ? totalFileSize - currentReadOffset
                  : 0;
              final isMoovRequest =
                  distanceFromEnd > 0 && distanceFromEnd < 10 * 1024 * 1024;

              // Use 15 seconds for moov requests, 5 seconds for normal data
              final timeout = isMoovRequest
                  ? const Duration(seconds: 15)
                  : const Duration(seconds: 5);

              // EVENT-DRIVEN WAIT: Register a Completer and wait for _onUpdate to wake us
              final completer = Completer<void>();
              _byteAvailabilityWaiters.putIfAbsent(fileId, () => []);
              _byteAvailabilityWaiters[fileId]!.add(
                MapEntry(currentReadOffset, completer),
              );

              try {
                // Wait for data to become available (or timeout)
                await completer.future.timeout(
                  timeout,
                  onTimeout: () {
                    // Timeout - remove our waiter and check manually
                    _byteAvailabilityWaiters[fileId]?.removeWhere(
                      (e) => e.value == completer,
                    );
                    if (_byteAvailabilityWaiters[fileId]?.isEmpty ?? false) {
                      _byteAvailabilityWaiters.remove(fileId);
                    }
                  },
                );

                // Check if aborted during wait
                if (_abortedRequests.contains(fileId)) {
                  _debugLog('Proxy: Wait aborted for $fileId');
                  return;
                }
              } catch (_) {
                // Timeout or error - check data availability manually on next loop
              }
            }

            // Read-ahead DISABLED due to TDLib limitation
            // TDLib cancels any ongoing download when a new downloadFile is called
            // for the same file_id with a different offset. This causes more harm
            // than benefit, so read-ahead is disabled until TDLib supports parallel
            // range requests for the same file.
            // _scheduleReadAhead(fileId, currentReadOffset);
          } else {
            // NO DATA AVAILABLE -> BLOCKING WAIT (EVENT-DRIVEN)
            // Throttled log: only print every 2 seconds per file to reduce CPU overhead
            final now = DateTime.now();
            final lastLog = _lastWaitingLogTime[fileId];
            if (lastLog == null ||
                now.difference(lastLog) >= _waitingLogThrottle) {
              _lastWaitingLogTime[fileId] = now;
              final cached = _filePaths[fileId];
              _debugLog(
                'Proxy: Waiting for data at $currentReadOffset for $fileId '
                '(CachedOffset: ${cached?.downloadOffset}, CachedPrefix: ${cached?.downloadedPrefixSize})...',
              );
            }

            // Ensure download is started at the exact offset the player needs
            _startDownloadAtOffset(fileId, currentReadOffset, isBlocking: true);

            // EXTENDED TIMEOUT FOR MOOV ATOM: Requests near end of file need more time
            final fileInfo = _filePaths[fileId];
            final totalFileSize = fileInfo?.totalSize ?? 0;
            final distanceFromEnd = totalFileSize > 0
                ? totalFileSize - currentReadOffset
                : 0;
            final isMoovRequest =
                distanceFromEnd > 0 && distanceFromEnd < 10 * 1024 * 1024;

            // Use 15 seconds for moov requests, 5 seconds for normal data
            final timeout = isMoovRequest
                ? const Duration(seconds: 15)
                : const Duration(seconds: 5);

            // EVENT-DRIVEN WAIT: Register a Completer and wait for _onUpdate to wake us
            final completer = Completer<void>();
            _byteAvailabilityWaiters.putIfAbsent(fileId, () => []);
            _byteAvailabilityWaiters[fileId]!.add(
              MapEntry(currentReadOffset, completer),
            );

            // STALL DETECTION: Check for stalls every 2 seconds while waiting
            // Capture values in local finals to avoid nullable issues in closure
            final capturedFileId = fileId;
            final capturedOffset = currentReadOffset;
            Timer? stallTimer;
            stallTimer = Timer.periodic(const Duration(seconds: 2), (_) {
              if (completer.isCompleted) {
                stallTimer?.cancel();
                return;
              }

              // MOOV PROTECTION: Don't restart download if MOOV download is in progress
              // This prevents the cycle of cancellations seen with MOOV-at-end videos
              if (_getOrCreateState(capturedFileId).forcedMoovOffset != null) {
                _debugLog(
                  'Proxy: Stall timer - MOOV download in progress for $capturedFileId, skipping restart',
                );
                return;
              }

              // INITIALIZATION GRACE PERIOD: Don't count stalls during first 30 seconds
              // This prevents false stalls for MOOV-at-end videos where multiple offsets
              // are being served simultaneously and TDLib is downloading the MOOV first
              final fileState = _getOrCreateState(capturedFileId);
              if (fileState.isWithinGracePeriod(_initializationGracePeriod)) {
                // During grace period, don't count as stall - just keep waiting
                return;
              }

              final updatedCache = _filePaths[capturedFileId];
              if (updatedCache != null) {
                // DOWNLOAD COOLDOWN PROTECTION:
                // TDLib may briefly report isDownloadingActive=false between download chunks.
                // If we recently started a download (within 5 seconds), don't count as stall.
                if (fileState.isRecentDownload(const Duration(seconds: 5))) {
                  // Download started very recently - still initializing
                  return;
                }

                // ACTIVE DOWNLOAD PROTECTION (IMPROVED):
                // Don't count as stall if download is actively running, even at a different offset.
                // This fixes false stalls for MOOV-at-end videos where TDLib prioritizes
                // downloading the MOOV atom at the end of the file before serving start data.
                if (updatedCache.isDownloadingActive) {
                  // Check if download is at a different offset than what we're waiting for
                  final activeOffset = _getOrCreateState(
                    capturedFileId,
                  ).activeDownloadOffset;
                  if (activeOffset != null && activeOffset != capturedOffset) {
                    // Download is active at a different offset - this is normal for MOOV-at-end
                    // Don't count as stall, just wait for the data
                    _logTrace(
                      'Stall timer - download active at different offset '
                      '($activeOffset vs waiting for $capturedOffset), not a stall',
                      fileId: capturedFileId,
                    );
                  }
                  return;
                }

                final currentPrefix = updatedCache.downloadedPrefixSize;
                final lastPrefix = _lastDownloadProgress[capturedFileId] ?? 0;

                if (currentPrefix <= lastPrefix) {
                  // No progress and download not active - check retry limit
                  if (!_retryTracker.canRetry(capturedFileId)) {
                    // Max retries exceeded - transition to error state
                    final attempts = _retryTracker.totalAttempts(
                      capturedFileId,
                    );
                    final error = StreamingError.maxRetries(
                      capturedFileId,
                      attempts,
                    );
                    // Only print if this is a NEW error (not duplicate)
                    final wasNotified = _notifyErrorIfNew(
                      capturedFileId,
                      error,
                    );
                    stallTimer?.cancel();
                    if (wasNotified) {
                      _debugLog(
                        'Proxy: MAX RETRIES EXCEEDED for $capturedFileId after $attempts attempts',
                      );
                    }
                    return;
                  }

                  // Record retry attempt
                  _retryTracker.recordRetry(capturedFileId);
                  final remaining = _retryTracker.remainingRetries(
                    capturedFileId,
                  );

                  final metrics = _downloadMetrics[capturedFileId];
                  if (metrics != null) {
                    metrics.recordStall();
                    _debugLog(
                      'Proxy: P2 STALL RECORDED for $capturedFileId '
                      '(stalls: ${metrics.recentStallCount}, retries remaining: $remaining)',
                    );
                  }
                  _startDownloadAtOffset(capturedFileId, capturedOffset);
                }
                _lastDownloadProgress[capturedFileId] = currentPrefix;
              }
            });

            try {
              // Wait for data to become available (or timeout)
              await completer.future.timeout(
                timeout,
                onTimeout: () {
                  // Timeout - clean up and fall through
                  _byteAvailabilityWaiters[fileId]?.removeWhere(
                    (e) => e.value == completer,
                  );
                  if (_byteAvailabilityWaiters[fileId]?.isEmpty ?? false) {
                    _byteAvailabilityWaiters.remove(fileId);
                  }
                },
              );

              // Check if aborted during wait
              if (_abortedRequests.contains(fileId)) {
                _debugLog('Proxy: Wait aborted for $fileId');
                stallTimer.cancel();
                break;
              }
            } catch (_) {
              // Timeout or error - continue loop to retry
            } finally {
              stallTimer.cancel();
            }
          }
        }
      } catch (e) {
        if (e is! SocketException && e is! HttpException) {
          _debugLog('Proxy: Error streaming: $e');
        }
      } finally {
        await raf?.close();
        // Clean up this request's offset tracking
        _activeHttpRequestOffsets[fileId]?.remove(start);
        if (_activeHttpRequestOffsets[fileId]?.isEmpty ?? false) {
          _activeHttpRequestOffsets.remove(fileId);
        }
      }

      // Close response, handling aborts logic
      if (_abortedRequests.contains(fileId)) {
        // Destroy to act as forced close
        // request.response.destroy(); // Not exposed/safe?
        // Just let it close or fail.
        // Note: Dart HttpServer responses don't have destroy() easily.
        // We can just exit without close(), or try close and ignore error.
        try {
          await request.response.close();
        } catch (_) {}
      } else {
        await request.response.close();
      }
    } catch (e) {
      if (e is HttpException) {
        // Ignore expected HttpExceptions on abort/close
      } else {
        _debugLog('Proxy: Top-level error: $e');
      }
      // Clean up on error too
      if (fileId != null) {
        _activeHttpRequestOffsets[fileId]?.remove(start);
        if (_activeHttpRequestOffsets[fileId]?.isEmpty ?? false) {
          _activeHttpRequestOffsets.remove(fileId);
        }
      }
      try {
        if (!_abortedRequests.contains(
          fileIdStr != null ? int.tryParse(fileIdStr) : -1,
        )) {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchFileInfo(int fileId) async {
    try {
      final fileJson = await TelegramService().sendWithResult({
        '@type': 'getFile',
        'file_id': fileId,
      });

      if (fileJson['@type'] == 'file') {
        final local = fileJson['local'] as Map<String, dynamic>?;
        final path = local?['path'] as String? ?? '';
        final isCompleted =
            local?['is_downloading_completed'] as bool? ?? false;
        final totalSize = fileJson['size'] as int? ?? 0;
        final downloadOffset = local?['download_offset'] as int? ?? 0;
        final downloadedPrefixSize =
            local?['downloaded_prefix_size'] as int? ?? 0;
        final isDownloadingActive =
            local?['is_downloading_active'] as bool? ?? false;
        final canBeDownloaded = local?['can_be_downloaded'] as bool? ?? true;

        _debugLog(
          'Proxy: File $fileId - path: ${path.isNotEmpty}, completed: $isCompleted, '
          'downloading: $isDownloadingActive, prefix: $downloadedPrefixSize, canDownload: $canBeDownloaded',
        );

        // OPTIMIZATION: Only delete partial downloads if very little data exists
        // Keep files with significant downloaded data to avoid re-downloading
        final minUsableData = 5 * 1024 * 1024; // 5MB threshold
        final isStaleWithLittleData =
            path.isNotEmpty &&
            !isCompleted &&
            !isDownloadingActive &&
            downloadedPrefixSize > 0 &&
            downloadedPrefixSize < minUsableData;

        if (isStaleWithLittleData) {
          _debugLog(
            'Proxy: Detected stale partial download for $fileId (only ${downloadedPrefixSize ~/ 1024}KB), cleaning up...',
          );

          // Delete the local file to reset TDLib's state
          final deleteResult = await TelegramService().sendWithResult({
            '@type': 'deleteFile',
            'file_id': fileId,
          });

          if (deleteResult['@type'] == 'ok') {
            _debugLog('Proxy: Successfully deleted partial file $fileId');
          } else {
            _debugLog('Proxy: Delete file result: ${deleteResult['@type']}');
          }

          // Clear our cache
          _filePaths.remove(fileId);

          // Wait a bit for TDLib to process
          await Future.delayed(const Duration(milliseconds: 200));

          // Re-fetch file info after deletion
          final newFileJson = await TelegramService().sendWithResult({
            '@type': 'getFile',
            'file_id': fileId,
          });

          if (newFileJson['@type'] == 'file') {
            final newLocal = newFileJson['local'] as Map<String, dynamic>?;
            _filePaths[fileId] = ProxyFileInfo(
              path: newLocal?['path'] as String? ?? '',
              totalSize: newFileJson['size'] as int? ?? 0,
              downloadOffset: newLocal?['download_offset'] as int? ?? 0,
              downloadedPrefixSize:
                  newLocal?['downloaded_prefix_size'] as int? ?? 0,
              isDownloadingActive:
                  newLocal?['is_downloading_active'] as bool? ?? false,
              isCompleted:
                  newLocal?['is_downloading_completed'] as bool? ?? false,
            );
          }
        } else {
          _filePaths[fileId] = ProxyFileInfo(
            path: path,
            totalSize: totalSize,
            downloadOffset: downloadOffset,
            downloadedPrefixSize: downloadedPrefixSize,
            isDownloadingActive: isDownloadingActive,
            isCompleted: isCompleted,
          );
        }

        // PRE-DETECT MOOV POSITION for large files
        // Schedule detection after some data is available
        if (totalSize > 10 * 1024 * 1024 && !isCompleted) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!_abortedRequests.contains(fileId)) {
              _detectMoovPosition(fileId, totalSize);
            }
          });
        }

        // If path is empty, trigger download to allocate the file
        final currentInfo = _filePaths[fileId];
        if (currentInfo == null ||
            (currentInfo.path.isEmpty && !currentInfo.isCompleted)) {
          _debugLog(
            'Proxy: File path empty, triggering initial download for $fileId',
          );

          // Ensure notifier exists for waiting
          if (!_fileUpdateNotifiers.containsKey(fileId)) {
            _fileUpdateNotifiers[fileId] = StreamController.broadcast();
          }

          // Trigger download to allocate the file - use synchronous mode
          // to download sequentially and avoid PartsManager issues
          _getOrCreateState(fileId).downloadStartTime =
              DateTime.now(); // Track when download started
          TelegramService().send({
            '@type': 'downloadFile',
            'file_id': fileId,
            'priority': DownloadPriority.critical,
            'offset': 0,
            'limit': 0, // Download entire file
            'synchronous': true, // Sequential download, no file parts
          });

          // Wait for updateFile with a valid path (max 10 seconds)
          final updateStream = _fileUpdateNotifiers[fileId]!.stream;
          int attempts = 0;
          const maxAttempts = 50; // 50 * 200ms = 10 seconds

          while (attempts < maxAttempts) {
            if (_abortedRequests.contains(fileId)) {
              _debugLog('Proxy: Fetch aborted for $fileId');
              return;
            }

            final cached = _filePaths[fileId];
            if (cached != null && cached.path.isNotEmpty) {
              _debugLog('Proxy: File path obtained: ${cached.path}');
              return;
            }

            try {
              await updateStream.first.timeout(
                const Duration(milliseconds: 200),
              );
            } catch (_) {
              // Timeout, continue loop
            }
            attempts++;
          }

          _debugLog('Proxy: Timed out waiting for file allocation for $fileId');
        }
      }
    } catch (e) {
      _debugLog('Proxy: Error fetching file info: $e');
    }
  }

  /// Direct 1:1 mapping: player's Range request → TDLib downloadFile offset
  /// Following Telegram Android's FileStreamLoadOperation pattern.
  /// IMPROVED: Dynamic priority based on distance to playback position.
  /// STABILIZED: Longer cooldown post-seek to prevent ping-pong downloads.
  Future<void> _startDownloadAtOffset(
    int fileId,
    int requestedOffset, {
    bool isBlocking = false,
  }) async {
    // DISK SAFETY CHECK: Prevent crash if disk is full (<50MB)
    // Uses cached result for 5 seconds to avoid redundant disk queries
    if (!await _checkDiskSafetyCached()) {
      _debugLog(
        'Proxy: CRITICAL DISK SPACE - Aborting new download request for $fileId',
      );
      return;
    }

    // Check if file is already complete - no download needed
    final cached = _filePaths[fileId];
    if (cached != null && cached.isCompleted) {
      return;
    }

    // CRITICAL FIX: Prevent requests beyond EOF which crash TDLib
    // This happens if currentReadOffset reaches totalSize in the streaming loop
    final totalSize = cached?.totalSize ?? 0;
    if (totalSize > 0 && requestedOffset >= totalSize) {
      _debugLog(
        'Proxy: Ignoring request at EOF ($requestedOffset >= $totalSize) for $fileId',
      );
      return;
    }

    // CHECK FORCED MOOV: If we are forcing a moov download, ignore requests for other offsets
    // This allows the moov download to complete without being intercepted by start-of-file requests
    final forcedOffset = _getOrCreateState(fileId).forcedMoovOffset;
    if (forcedOffset != null) {
      // Check if we have enough data at the forced offset now
      final availableAtForced = cached?.availableBytesFrom(forcedOffset) ?? 0;
      // MOOV FIX: Wait for the ENTIRE moov atom to be downloaded (or a reasonable cap)
      // The previous 512KB threshold was too small (moov often > 2MB), causing early release
      // of the lock and subsequent cancellation of the incomplete moov download.
      final totalSize = cached?.totalSize ?? 0;
      final neededSize = totalSize > forcedOffset
          ? totalSize - forcedOffset
          : 0;

      // Use the exact needed size if known, capped at 20MB to prevent blocking forever on weird files
      final targetSize = neededSize > 0
          ? min(neededSize, 20 * 1024 * 1024)
          : 5 * 1024 * 1024; // Default to 5MB if total size unknown

      if (availableAtForced >= targetSize) {
        // Got enough moov data - clear MOOV lock AND reset active priority
        // This allows normal priority calculation for subsequent requests
        _debugLog(
          'Proxy: Forced moov download satisfied ($availableAtForced bytes >= $targetSize), releasing lock for $fileId',
        );
        _getOrCreateState(fileId).forcedMoovOffset = null;
        _getOrCreateState(fileId).activePriority =
            0; // CRITICAL: Reset priority to avoid deadlock
      } else if (requestedOffset != forcedOffset) {
        _debugLog(
          'Proxy: Ignoring request for $requestedOffset while forcing moov download at $forcedOffset for $fileId (have $availableAtForced/$targetSize)',
        );
        return;
      }
    }

    // SCRUBBING DETECTION: If multiple seeks detected within 500ms, use debounce
    // to reduce TDLib download cancellations during rapid scrubbing.
    // IMPORTANT: Only debounce during ACTIVE PLAYBACK, not during initial load.
    // We detect active playback by checking if we've served at least 10MB of data.
    final lastServed = _getOrCreateState(fileId).lastServedOffset ?? 0;
    final isActivePlayback =
        lastServed > 10 * 1024 * 1024; // At least 10MB served

    final debounceLastSeek = _getOrCreateState(fileId).lastSeekTime;
    final debounceNow = DateTime.now();
    final isRapidSeek =
        isActivePlayback &&
        debounceLastSeek != null &&
        debounceNow.difference(debounceLastSeek).inMilliseconds < 500;

    // Check if there's already a pending debounced seek - if so, let it handle this
    if (isActivePlayback && _pendingSeekOffsets.containsKey(fileId)) {
      // Update the pending offset to the latest request
      _handleDebouncedSeek(fileId, requestedOffset);
      return;
    }

    // If this is a rapid seek (second+ seek within 500ms), use debounce
    if (isRapidSeek) {
      _debugLog(
        'Proxy: Rapid seek detected for $fileId, debouncing to ${requestedOffset ~/ 1024}KB',
      );
      _handleDebouncedSeek(fileId, requestedOffset);
      return;
    }

    // Check if we're already downloading from this offset (or very close)
    final currentActiveOffset = _getOrCreateState(fileId).activeDownloadOffset;
    final currentDownloadOffset = cached?.downloadOffset ?? 0;
    final currentPrefix = cached?.downloadedPrefixSize ?? 0;

    // If data is available at requested offset, no need to re-trigger
    if (cached != null && cached.availableBytesFrom(requestedOffset) > 0) {
      return;
    }

    // RESUME FIX: Cache-gap detection
    // When resuming far ahead, we need to fill the gap from cache edge first.
    // Otherwise the player stalls waiting for data that never comes.
    // Detect: requestedOffset is way ahead of cached data (>50MB gap)
    final cacheEnd = currentDownloadOffset + currentPrefix;
    final gapFromCache = requestedOffset - cacheEnd;
    if (gapFromCache > 50 * 1024 * 1024 && cacheEnd > 0 && !isBlocking) {
      // Large gap detected - this is likely a resume scenario
      // Start downloading from cache edge instead of creating a gap
      _debugLog(
        'Proxy: RESUME GAP DETECTED for $fileId. '
        'Requested: ${requestedOffset ~/ 1024}KB, CacheEnd: ${cacheEnd ~/ 1024}KB, '
        'Gap: ${gapFromCache ~/ 1024}KB. Redirecting to cache edge.',
      );
      // Note: We don't redirect here, but when isBlocking is true,
      // we'll allow the cache-edge request through instead of denying it.
    }

    // Check if current download will soon provide the data we need
    // (within 5MB of the download frontier - reduced from 10MB for stability)
    // CRITICAL: Only wait if download is ACTUALLY ACTIVE, otherwise we'd wait forever!
    final downloadFrontier = currentDownloadOffset + currentPrefix;
    final distanceFromFrontier = requestedOffset - downloadFrontier;
    final isDownloading = cached?.isDownloadingActive ?? false;
    if (isDownloading &&
        distanceFromFrontier >= 0 &&
        distanceFromFrontier < 5 * 1024 * 1024) {
      // Current download will reach our offset soon, don't restart
      return;
    }

    // Check if already targeting this offset
    if (currentActiveOffset == requestedOffset) {
      return;
    }

    // SMART MOOV ATOM DETECTION
    // Instead of blocking all requests near end of file, distinguish:
    // 1. Actual moov atom requests (metadata, no sample table entry)
    // 2. Legitimate seeks to end of video (has sample table entry)
    // variable 'totalSize' is already defined above, reuse it or use cached?.totalSize
    final fileSize = cached?.totalSize ?? 0;
    if (fileSize > 0) {
      final distanceFromEnd = fileSize - requestedOffset;

      // Use percentage-based threshold for large files
      // For 2GB file: 0.5% = 10MB, for 500MB file: 0.5% = 2.5MB
      final moovThresholdBytes = fileSize > 500 * 1024 * 1024
          ? (fileSize * 0.005)
                .round() // 0.5% for large files
          : 10 * 1024 * 1024; // 10MB for smaller files

      final mightBeMoovRequest = distanceFromEnd < moovThresholdBytes;

      // PHASE 4: If we have sample table, check if this offset is video data
      // If it's valid video data, it's NOT a moov request
      final sampleTable = _sampleTableCache[fileId];
      bool isConfirmedVideoData = false;
      if (sampleTable != null && sampleTable.samples.isNotEmpty) {
        // Check if requestedOffset falls within known sample ranges
        final lastSample = sampleTable.samples.last;
        final lastVideoByteOffset = lastSample.byteOffset + lastSample.size;
        isConfirmedVideoData = requestedOffset < lastVideoByteOffset;

        if (mightBeMoovRequest && isConfirmedVideoData) {
          // This looks like moov position but sample table says it's video data
          // This is a legitimate seek to end of video, allow it!
          _debugLog(
            'Proxy: Offset $requestedOffset is near end but confirmed as video data '
            '(last sample ends at $lastVideoByteOffset)',
          );
        }
      }

      // PHASE2: SIMPLIFIED MOOV DETECTION
      // Only mark file as moov-at-end for informational purposes
      // No blocking or stabilization - let TDLib and player handle naturally
      final isMoovAtomRequest = mightBeMoovRequest && !isConfirmedVideoData;

      if (isMoovAtomRequest && !_getOrCreateState(fileId).isMoovAtEnd) {
        _getOrCreateState(fileId).isMoovAtEnd = true;
        _debugLog(
          'Proxy: File $fileId has moov atom at end (not optimized for streaming)',
        );
      }
    }

    final now = DateTime.now();

    // Calculate distance to CURRENT download offset
    final activeDownloadTarget =
        _getOrCreateState(fileId).activeDownloadOffset ?? 0;
    final distanceFromCurrent = (requestedOffset - activeDownloadTarget).abs();

    // Calculate distance to primary offset for priority calculation
    final primaryOffset = _getOrCreateState(fileId).primaryPlaybackOffset ?? 0;
    final distanceToPlayback = (requestedOffset - primaryOffset).abs();

    // Check if this is a recent seek (used for preload calculation)
    final lastSeek = _getOrCreateState(fileId).lastSeekTime;
    final seekWindowMs = 2000;
    final isRecentSeek =
        lastSeek != null &&
        now.difference(lastSeek).inMilliseconds < seekWindowMs;

    // NOTE: POST-SEEK BLOCK has been DISABLED after testing showed it was
    // blocking legitimate resume requests and causing videos to not start.
    // The general cooldown (500-1000ms) and distance threshold (2-5MB) provide
    // sufficient protection against rapid offset changes.

    // Determine if this is a Seek Request (jump > 1MB from last served offset)
    bool isSeekRequest = false;
    final lastServedForCheck = _getOrCreateState(fileId).lastServedOffset;
    if (lastServedForCheck != null) {
      final jump = (requestedOffset - lastServedForCheck).abs();
      if (jump > 1024 * 1024) {
        isSeekRequest = true;
      }
    }

    // PARTSMANAGER FIX: Increased cooldown to prevent TDLib crashes
    // TDLib's PartsManager can crash if offset changes happen too rapidly
    final lastChange = _getOrCreateState(fileId).lastOffsetChangeTime;
    final isSequentialRead =
        requestedOffset > activeDownloadTarget &&
        distanceFromCurrent < 2 * 1024 * 1024; // Within 2MB ahead

    // PHASE1 OPTIMIZATION: Reduced cooldown for faster seek response
    // TDLib handles rapid changes better than previously assumed
    final cooldownMs = isSequentialRead ? 50 : 100;

    if (lastChange != null) {
      final timeSinceLastChange = now.difference(lastChange).inMilliseconds;
      // PHASE1 OPTIMIZATION: Reduced distance threshold for more responsive seeks
      final minDistance = isSequentialRead ? 256 * 1024 : 512 * 1024;

      // DEADLOCK PREVENTION:
      // If we think we are downloading at offset X, but cache says we are inactive
      // or at a totally different offset (e.g. Moov), then our "active" status is phantom.
      // We should not let this phantom status block new requests.
      bool isEffectiveActive = true;
      if (timeSinceLastChange > 1000) {
        // Only check after 1s to allow initial setup
        if (cached == null ||
            (!cached.isDownloadingActive && !cached.isCompleted)) {
          // Not active according to TDLib (and not complete) triggers reset
          isEffectiveActive = false;
        } else if ((cached.downloadOffset - activeDownloadTarget).abs() >
            2 * 1024 * 1024) {
          // TDLib is downloading something completely different (>2MB away)
          isEffectiveActive = false;
        }
      }

      // Only apply blocking logic if the active download is effectively real
      // EXCEPTION: If isBlocking is true (player starving), we MUST recover immediately
      if (!isBlocking &&
          isEffectiveActive &&
          (timeSinceLastChange < cooldownMs ||
              distanceFromCurrent < minDistance)) {
        return; // Too soon or too close
      }
    }

    // PHASE2: MOOV DOWNLOAD LOCK REMOVED
    // The lock was blocking video data requests and causing stalls.
    // TDLib handles priority naturally - let it manage MOOV vs video data.
    final isMoovDownload =
        _getOrCreateState(fileId).isMoovAtEnd &&
        totalSize > 0 &&
        (totalSize - requestedOffset) <
            (totalSize * 0.01).round().clamp(5 * 1024 * 1024, 50 * 1024 * 1024);

    // TELEGRAM ANDROID-INSPIRED: Calculate dynamic priority based on distance
    // to primary playback position. Closer = higher priority.
    // FORCE PRIORITY 32 for Moov downloads AND Blocking waits.
    // EXCEPTION: If "Blocking" request is extremely far (>50MB) from Primary Playback,
    // it's likely a stalled zombie stream. IGNORE the blocking flag to prevent hijacking.
    bool shouldForcePriority = isMoovDownload;
    if (isBlocking) {
      final primary = _getOrCreateState(fileId).primaryPlaybackOffset;
      // Trust blocking if:
      // 1. No primary set yet (start of playback)
      // 2. Explicit Moov request (End of File)
      // 3. We are close to primary (<50MB)
      // 4. We are sequentially ahead of primary (normal playback)
      // 5. NEW: Request is at cache edge (resume scenarios)
      if (primary == null || isMoovDownload) {
        shouldForcePriority = true;
      } else {
        final dist = requestedOffset - primary;
        // RELAXED LIMIT: Allow buffering up to 500MB ahead (Deep Buffering)
        // Modern players/network can easily buffer hundreds of MBs.
        // Blocking requests within this range are critical.
        if (dist >= 0 && dist < 500 * 1024 * 1024) {
          shouldForcePriority = true; // Normal forward playback buffer
        } else if (dist < 0 && dist.abs() < 100 * 1024 * 1024) {
          // INCREASED FROM 10MB TO 100MB:
          // Resume playback scenarios need to load data from cached position
          // to resume position, which can be quite far behind Primary.
          shouldForcePriority = true; // Allow reasonable overlap behind
        } else {
          // CACHE EDGE DETECTION:
          // If the request is near the edge of what's already downloaded,
          // this is likely a legitimate request to continue buffering
          // in a resume scenario. Allow it.
          final cached = _filePaths[fileId];
          if (cached != null) {
            final cacheEnd =
                cached.downloadOffset + cached.downloadedPrefixSize;
            final distToCacheEnd = (requestedOffset - cacheEnd).abs();
            if (distToCacheEnd < 5 * 1024 * 1024) {
              // Request is within 5MB of cache edge - this is buffering continuation
              _debugLog(
                'Proxy: CACHE EDGE ALLOWED for $requestedOffset (CacheEnd: $cacheEnd, Dist: ${distToCacheEnd ~/ 1024}KB)',
              );
              shouldForcePriority = true;
            } else if (requestedOffset < 300 * 1024 * 1024) {
              // If request is for early part of file (<300MB), it's likely trying
              // to buffer contiguous data from the start. Allow it.
              _debugLog(
                'Proxy: LOW OFFSET ALLOWED for $requestedOffset (early file data)',
              );
              shouldForcePriority = true;
            } else {
              _debugLog(
                'Proxy: DENIED Blocking Priority for $requestedOffset (Primary: $primary, Dist: ${dist ~/ 1024}KB). Treated as background.',
              );
              shouldForcePriority = false;
            }
          } else {
            _debugLog(
              'Proxy: DENIED Blocking Priority for $requestedOffset (Primary: $primary, Dist: ${dist ~/ 1024}KB). Treated as background.',
            );
            shouldForcePriority = false;
          }
        }
      }
    }

    // PRIORITY HIERARCHY FIX:
    // Split Blocking Priority into "Critical" and "Deep Buffering".
    // This prevents a "Deep Buffer" request (e.g. 500MB ahead) from displacing an
    // "Immediate Playback" request (e.g. 1MB ahead), which is also Critical.
    // They used to fight and cancel each other. Now Critical wins.
    //
    // EXCEPTION: Low-offset requests (<150MB) always get critical priority because
    // they represent contiguous cache data needed for playback.
    int blockingPriority = DownloadPriority.critical;
    if (shouldForcePriority) {
      final distToPrimary = (requestedOffset - primaryOffset).abs();
      final isLowOffsetRequest =
          requestedOffset < DownloadPriority.lowOffsetThresholdBytes;
      if (distToPrimary > DownloadPriority.closestToPrimaryBytes &&
          !isMoovDownload &&
          !isLowOffsetRequest) {
        blockingPriority = DownloadPriority
            .deepBuffer; // Urgent, but interruptible by Critical
      }
    }

    final calculatedPriority = shouldForcePriority
        ? blockingPriority
        : _calculateDynamicPriority(fileId, distanceToPlayback);

    // LOW OFFSET PRIORITY FLOOR:
    // Ensure requests for early file data (<300MB) get at least highFloor priority.
    // BUT: To prevent ping-pong, only give CRITICAL priority to the request
    // that is closest to the primary playback offset. Other low-offset requests
    // get highFloor (high enough to interrupt background, but can be superseded
    // by the truly critical request).
    final isLowOffsetRequest =
        requestedOffset < DownloadPriority.lowOffsetThresholdBytes;
    final distToPrimaryForFloor = (requestedOffset - primaryOffset).abs();
    final isClosestToPrimary =
        distToPrimaryForFloor < DownloadPriority.closestToPrimaryBytes;

    int priority;
    if (isLowOffsetRequest) {
      // Simplified LOW OFFSET priority logic
      // Use active download priority instead of removed lock mechanism
      final hasActiveHighPriority =
          _getOrCreateState(fileId).activePriority >=
          DownloadPriority.deepBuffer;

      if (hasActiveHighPriority) {
        // When there's an active high-priority download, cap LOW OFFSET at highFloor
        priority = (calculatedPriority > DownloadPriority.highFloor)
            ? DownloadPriority.highFloor
            : calculatedPriority;
      } else if (calculatedPriority < DownloadPriority.highFloor) {
        // Apply floor, but differentiate between closest-to-primary and others
        priority = isClosestToPrimary
            ? DownloadPriority.critical
            : DownloadPriority.highFloor;
      } else {
        priority = calculatedPriority;
      }
    } else {
      priority = calculatedPriority;
    }

    // SAME-FILE DISPLACEMENT PROTECTION:
    // TDLib cancels the current download for File X if a new request comes for File X.
    // We must prevent a Low Priority request (e.g. background preload) from killing
    // a High Priority Active Download (e.g. user watching video).
    final activePriority = _getOrCreateState(fileId).activePriority;
    final isHighPriorityActive = activePriority >= DownloadPriority.highFloor;

    // PHASE3: Removed STICKY PRIORITY PROTECTION - was too conservative\n    // The simplified distance-based protection below is sufficient
    // VIRTUAL ACTIVE STATE LOGIC REMOVED:
    // Previously tracked _lastActiveDownloadEndTime and _lastActiveDownloadOffset
    // but those maps were never written to, making this dead code.
    // The simplified cooldown system provides sufficient protection.
    // Original zombie blacklist code and related variables removed.

    // SIMPLIFIED SEEK DEBOUNCE
    // Always allow seek requests through immediately - the player knows best where it needs data
    final lastStart = _getOrCreateState(fileId).lastOffsetChangeTime;
    if (lastStart != null &&
        now.difference(lastStart).inMilliseconds < 100 &&
        !isBlocking &&
        !isSeekRequest) {
      final activeOffset = _getOrCreateState(fileId).activeDownloadOffset ?? -1;
      // Allow if sequential (reading forward within 2MB)
      if (requestedOffset >= activeOffset &&
          requestedOffset < activeOffset + 2 * 1024 * 1024) {
        // Sequential: Allowed
      } else {
        _debugLog(
          'Proxy: DEBOUNCED rapid switch from $activeOffset to $requestedOffset. Ignoring.',
        );
        return;
      }
    }

    // PHASE4: Zombie blacklist checking removed\n    // Was already disabled in Phase 1 and state variables removed

    // PHASE3: HIGH-PRIORITY DOWNLOAD LOCK REMOVED
    // The lock was causing stalls by blocking requests after seeks.
    // Simple distance-based protection is sufficient.

    // PHASE3: Simplified priority protection
    // Only block if priority is significantly lower AND not blocking
    // CRITICAL FIX: Never block low-offset requests (needed for MOOV/playback start)
    final isLowOffsetRequestForProtection =
        requestedOffset < DownloadPriority.lowOffsetThresholdBytes;
    if (!isBlocking &&
        !isLowOffsetRequestForProtection && // NEVER block initial file data
        isHighPriorityActive &&
        priority < activePriority - DownloadPriority.priorityProtectionGap &&
        (requestedOffset - activeDownloadTarget).abs() >
            DownloadPriority.cacheEdgeDistanceBytes) {
      // Throttled log: only print every 5 seconds per file to reduce CPU overhead
      final now = DateTime.now();
      final lastLog = _lastProtectedLogTime[fileId];
      if (lastLog == null || now.difference(lastLog) >= _protectedLogThrottle) {
        _lastProtectedLogTime[fileId] = now;
        _logWarning(
          'PROTECTED active download from lower-priority request',
          fileId: fileId,
          data: {
            'activePriority': activePriority,
            'requestPriority': priority,
            'requestOffset': requestedOffset,
          },
        );
      }
      return;
    }

    // ADAPTIVE PRELOAD: Determine minimum bytes before we start serving
    // Based on network speed, recent stalls, and whether we just seeked
    // PHASE 1 IMPROVEMENT: Dynamic buffer calculation with safety margin
    final metrics = _downloadMetrics[fileId];

    int preloadBytes = _calculateSmartPreload(fileId, isRecentSeek, metrics);

    // Start download at exactly the offset the player requested
    _debugLog(
      'Proxy: Downloading from offset $requestedOffset for $fileId '
      '(priority: $priority, preload: ${preloadBytes ~/ 1024}KB)',
    );

    final state = _getOrCreateState(fileId);
    state.activeDownloadOffset = requestedOffset;
    state.activePriority = priority; // Track priority
    state.lastOffsetChangeTime = now;
    state.downloadStartTime = now; // Track for stall cooldown protection

    // PHASE3: HIGH-PRIORITY LOCK ACQUISITION REMOVED
    // No longer tracking locks - TDLib handles priority naturally

    // PARTSMANAGER FIX: Use synchronous mode for moov atom downloads
    // This prevents parallel range conflicts that cause PartsManager crashes

    // MOOV FIX: Use dynamic preload for moov downloads based on actual moov size
    // Moov atoms can be 5-15MB+ for large videos (4GB+ files have 10-15MB moov)
    // Calculate the actual bytes remaining from request to end of file
    int actualPreload = preloadBytes;
    if (isMoovDownload) {
      final moovSize = totalSize - requestedOffset;
      // Use the actual moov size, clamped between 8MB min and 20MB max
      final moovPreload = moovSize.clamp(8 * 1024 * 1024, 20 * 1024 * 1024);
      actualPreload = (preloadBytes < moovPreload) ? moovPreload : preloadBytes;

      if (actualPreload != preloadBytes) {
        _debugLog(
          'Proxy: Using larger preload for moov: ${actualPreload ~/ 1024}KB (actual moov size: ${moovSize ~/ 1024}KB)',
        );
      }
    }

    TelegramService().send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': priority,
      'offset': requestedOffset,
      'limit': actualPreload,
      // Use synchronous mode for moov downloads to prevent PartsManager crashes
      'synchronous': isMoovDownload,
    });
  }

  /// Calculate dynamic priority based on distance from playback position.
  /// Delegates to [DownloadPriority.fromDistance] for centralized calculation.
  ///
  /// Priority ranges:
  /// - 32: Critical (0-1MB ahead)
  /// - 20-31: High (1-10MB ahead)
  /// - 1-10: Low (>10MB ahead)
  int _calculateDynamicPriority(int fileId, int distanceBytes) {
    return DownloadPriority.fromDistance(distanceBytes);
  }

  /// Smart adaptive preload calculation
  /// Calculates buffer size based on:
  /// - Network speed (with 3x safety margin)
  /// - Recent stall history (increases buffer if stalls detected)
  /// - Post-seek mode (faster initial response, then builds up)
  int _calculateSmartPreload(
    int fileId,
    bool isRecentSeek,
    DownloadMetrics? metrics,
  ) {
    // Base calculation: 3 seconds of buffer at current network speed
    // with 3x safety margin for variable bitrate videos
    const safetyMultiplier = 3.0;
    const targetBufferSeconds = 3.0;

    // Default: 2MB if no metrics available
    int basePreload = _minPreloadBytes;

    if (metrics != null && metrics.bytesPerSecond > 0) {
      // Calculate based on network speed
      basePreload =
          (metrics.bytesPerSecond * targetBufferSeconds * safetyMultiplier)
              .round();

      // Clamp to reasonable range: 1MB - 8MB
      basePreload = basePreload.clamp(
        _fastNetworkPreload, // 1MB min
        _slowNetworkPreload * 2, // 8MB max
      );
    }

    // Adjust based on stall history
    if (metrics != null && metrics.recentStallCount > 0) {
      // Increase buffer by 50% for each recent stall, up to 2x
      final stallMultiplier =
          1.0 + (metrics.recentStallCount * 0.5).clamp(0, 1);
      basePreload = (basePreload * stallMultiplier).round();
      _debugLog(
        'Proxy: Stall-adjusted buffer for $fileId: ${basePreload ~/ 1024}KB '
        '(${metrics.recentStallCount} stalls)',
      );
    }

    // Post-seek optimization: use smaller initial buffer for faster response
    // but ensure we still have enough data to avoid immediate buffering
    if (isRecentSeek) {
      // After seek: use 50% of calculated buffer (min 1MB)
      // This gives faster response while still being adaptive
      final seekPreload = (basePreload * 0.5).round().clamp(
        _fastNetworkPreload,
        basePreload,
      );
      _debugLog(
        'Proxy: Post-seek adaptive buffer for $fileId: ${seekPreload ~/ 1024}KB '
        '(base: ${basePreload ~/ 1024}KB)',
      );
      return seekPreload;
    }

    _debugLog(
      'Proxy: Adaptive buffer for $fileId: ${basePreload ~/ 1024}KB '
      '(speed: ${metrics?.bytesPerSecond ?? 0 ~/ 1024}KB/s)',
    );
    return basePreload;
  }

  // NOTE: Read-ahead feature was removed because TDLib cancels ongoing downloads
  // when a new downloadFile call is made for the same file_id with a different offset.
  // This limitation makes proactive read-ahead counterproductive.

  // ============================================================
  // MOOV PRE-DETECTION AND POST-SEEK PRELOAD
  // ============================================================

  /// Minimum prefix size needed to attempt moov detection at file start
  static const int _moovDetectionMinPrefix = 1024; // 1KB

  /// Prefix size to infer moov-at-end (no moov found in initial bytes)
  static const int _moovAtEndInferenceThreshold = 5 * 1024 * 1024; // 5MB

  /// Tracks files that have already had early detection triggered
  final Set<int> _earlyMoovDetectionTriggered = {};

  /// Triggers early MOOV detection when sufficient bytes arrive.
  /// This is called from _onUpdate to detect moov position as early as possible.
  /// - For moov-at-start: Detection happens as soon as 1KB is downloaded
  /// - For moov-at-end: Detection triggers after 5MB without finding moov
  void _triggerEarlyMoovDetection(int fileId, ProxyFileInfo info) {
    // Skip if already detected or triggered
    if (_getOrCreateState(fileId).moovPosition != null) return;
    if (info.totalSize < 1024 * 1024) return; // Skip small files < 1MB

    final prefix = info.downloadedPrefixSize;

    // Stage 1: Try to detect moov at start (need ~1KB)
    if (prefix >= _moovDetectionMinPrefix &&
        !_earlyMoovDetectionTriggered.contains(fileId)) {
      _earlyMoovDetectionTriggered.add(fileId);

      // Asynchronously detect - this is non-blocking
      _detectMoovPosition(fileId, info.totalSize).then((position) {
        if (position == MoovPosition.start) {
          // Great! Video is optimized for streaming
          _debugLog('Proxy: EARLY DETECT - File $fileId has MOOV at START');
        } else if (position == MoovPosition.end) {
          // Video not optimized - update state for UI
          _getOrCreateState(fileId).isMoovAtEnd = true;
          _debugLog('Proxy: EARLY DETECT - File $fileId has MOOV at END');
        }
        // MoovPosition.unknown means we need more data
      });
    }

    // Stage 2: Infer moov-at-end if we have substantial prefix without finding moov
    // GUARD: Skip inference if async detection (Stage 1) is still in progress
    // This prevents race condition where sync inference sets END before async finds START
    if (prefix >= _moovAtEndInferenceThreshold &&
        _getOrCreateState(fileId).moovPosition == null &&
        !_earlyMoovDetectionTriggered.contains(fileId)) {
      // If we downloaded 5MB+ and async detection never started, infer END
      _getOrCreateState(fileId).moovPosition = MoovPosition.end;
      _getOrCreateState(fileId).isMoovAtEnd = true;
      _debugLog(
        'Proxy: EARLY DETECT - File $fileId inferred MOOV at END (${prefix ~/ (1024 * 1024)}MB downloaded)',
      );
    }
  }

  /// Pre-detects the position of the MOOV atom by analyzing the first bytes of the file.
  /// Returns immediately if already cached.
  /// This detection does NOT start downloads - only analyzes already available data.
  Future<MoovPosition> _detectMoovPosition(int fileId, int totalSize) async {
    // Check cache first
    final cachedPosition = _getOrCreateState(fileId).moovPosition;
    if (cachedPosition != null) {
      return cachedPosition;
    }

    final cached = _filePaths[fileId];
    if (cached == null || cached.path.isEmpty) {
      return MoovPosition.unknown;
    }

    try {
      final file = File(cached.path);
      if (!await file.exists()) {
        return MoovPosition.unknown;
      }

      final raf = await file.open(mode: FileMode.read);
      try {
        // MP4 files start with ftyp or moov atom
        // Read first 32 bytes to check atom header
        final header = await raf.read(32);
        if (header.length < 8) {
          return MoovPosition.unknown;
        }

        // Check for 'ftyp' or 'moov' in first atom
        final atomType = String.fromCharCodes(header.sublist(4, 8));

        if (atomType == 'moov') {
          _getOrCreateState(fileId).moovPosition = MoovPosition.start;
          _debugLog('Proxy: MOOV PRE-DETECT - File $fileId has MOOV at START');
          return MoovPosition.start;
        }

        // If ftyp, check next atom (usually within first 100 bytes)
        if (atomType == 'ftyp') {
          // Parse ftyp size to find next atom
          final ftypSize = _readMoovUint32BE(header, 0);
          if (ftypSize > 0 &&
              ftypSize < 1000 &&
              cached.downloadedPrefixSize > ftypSize + 8) {
            await raf.setPosition(ftypSize);
            final nextHeader = await raf.read(8);
            if (nextHeader.length >= 8) {
              final nextAtomType = String.fromCharCodes(
                nextHeader.sublist(4, 8),
              );
              if (nextAtomType == 'moov') {
                _getOrCreateState(fileId).moovPosition = MoovPosition.start;
                _debugLog(
                  'Proxy: MOOV PRE-DETECT - File $fileId has MOOV at START (after ftyp)',
                );
                return MoovPosition.start;
              }
            }
          }
        }

        // If we have enough prefix but no moov found near start, assume end
        // GUARD: Only infer if not already detected to prevent race condition
        if (cached.downloadedPrefixSize > 5 * 1024 * 1024 &&
            _getOrCreateState(fileId).moovPosition == null) {
          _getOrCreateState(fileId).moovPosition = MoovPosition.end;
          _getOrCreateState(fileId).isMoovAtEnd =
              true; // Sync with existing flag
          _debugLog(
            'Proxy: MOOV PRE-DETECT - File $fileId has MOOV at END (inferred)',
          );
          return MoovPosition.end;
        }
      } finally {
        await raf.close();
      }
    } catch (e) {
      _debugLog('Proxy: MOOV PRE-DETECT error for $fileId: $e');
    }

    return MoovPosition.unknown;
  }

  /// Read uint32 big-endian from byte list
  int _readMoovUint32BE(List<int> data, int offset) {
    if (data.length < offset + 4) return 0;
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  /// Triggers proactive preload after a seek has completed.
  /// Called when data is available at the new position.
  void _triggerPostSeekPreload(int fileId, int currentOffset) {
    final cached = _filePaths[fileId];
    if (cached == null || cached.isCompleted) return;

    // Only preload if we're in active playback (not during initial load)
    final primaryOffset = _getOrCreateState(fileId).primaryPlaybackOffset;
    if (primaryOffset == null) return;

    // Only if currentOffset is close to primary (seek just completed)
    if ((currentOffset - primaryOffset).abs() > 5 * 1024 * 1024) return;

    // Calculate target offset: 1MB ahead of current position
    const preloadAheadBytes = 1024 * 1024; // 1MB
    final targetOffset = currentOffset + preloadAheadBytes;

    // Don't preload if we already have data there
    if (cached.availableBytesFrom(targetOffset) > 0) return;

    // Don't preload if we're near end of file
    if (cached.totalSize > 0 &&
        targetOffset >= cached.totalSize - 1024 * 1024) {
      return;
    }

    _debugLog(
      'Proxy: POST-SEEK PRELOAD for $fileId: ${currentOffset ~/ 1024}KB -> ${targetOffset ~/ 1024}KB',
    );

    // Trigger preload with high but not critical priority
    TelegramService().send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': DownloadPriority.highFloor, // High but below critical
      'offset': targetOffset,
      'limit': preloadAheadBytes,
      'synchronous': false,
    });
  }

  // ============================================================
  // SEEK PREVIEW PRELOADING
  // ============================================================

  // Cache for parsed MP4 sample tables
  final Map<int, Mp4SampleTable?> _sampleTableCache = {};

  // Track last preview time to avoid spamming
  final Map<int, DateTime> _lastPreviewTime = {};
  static const int _previewCooldownMs =
      100; // Reduced from 300ms for faster preview

  /// Preview seek target - start downloading at estimated offset with lower priority
  /// This is called during slider drag to preload data before user releases
  void previewSeekTarget(int fileId, int estimatedOffset) {
    final cached = _filePaths[fileId];
    if (cached == null || cached.isCompleted) return;

    // Check cooldown to avoid spamming TDLib during rapid dragging
    final now = DateTime.now();
    final lastPreview = _lastPreviewTime[fileId];
    if (lastPreview != null &&
        now.difference(lastPreview).inMilliseconds < _previewCooldownMs) {
      return;
    }

    // If data is already available at this offset, skip
    if (cached.availableBytesFrom(estimatedOffset) > 0) {
      return;
    }

    // Start download with medium priority (16) - not highest to avoid
    // interrupting active playback if video is still playing during drag
    _debugLog('Proxy: Preview seek preload at $estimatedOffset for $fileId');

    _lastPreviewTime[fileId] = now;

    TelegramService().send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': DownloadPriority.highFloor, // High priority for seek preview
      'offset': estimatedOffset,
      'limit': 2 * 1024 * 1024, // Preload 2MB around target
      'synchronous': false,
    });
  }

  /// Get accurate byte offset for time using parsed sample table
  /// Falls back to linear estimation if parsing fails
  Future<int> getByteOffsetForTime(
    int fileId,
    int timeMs,
    int totalDurationMs,
    int totalBytes,
  ) async {
    // Try to get cached sample table
    if (!_sampleTableCache.containsKey(fileId)) {
      await _parseSampleTable(fileId);
    }

    final sampleTable = _sampleTableCache[fileId];
    if (sampleTable != null) {
      return sampleTable.getByteOffsetForTime(timeMs);
    }

    // Fallback: linear estimation (works for CBR, approximate for VBR)
    if (totalDurationMs <= 0) return 0;
    return (timeMs / totalDurationMs * totalBytes).round();
  }

  Future<void> _parseSampleTable(int fileId) async {
    final fileInfo = _filePaths[fileId];
    if (fileInfo == null || fileInfo.path.isEmpty) {
      _sampleTableCache[fileId] = null;
      return;
    }

    // Generate cache key based on fileId and fileSize for uniqueness
    final cacheKey = '${fileId}_${fileInfo.totalSize}';
    final cachePath = await _getSampleTableCachePath(cacheKey);

    // Try to load from disk cache first
    if (cachePath != null) {
      final cached = await Mp4SampleTable.loadFromFile(cachePath);
      if (cached != null) {
        _sampleTableCache[fileId] = cached;
        _debugLog(
          'Proxy: Loaded sample table from cache for $fileId: '
          '${cached.samples.length} samples, ${cached.keyframeSampleIndices.length} keyframes',
        );
        return;
      }
    }

    // Parse from file
    try {
      final file = File(fileInfo.path);
      if (!await file.exists()) {
        _sampleTableCache[fileId] = null;
        return;
      }

      final raf = await file.open(mode: FileMode.read);
      try {
        _sampleTableCache[fileId] = await Mp4SampleTable.parse(
          raf,
          fileInfo.totalSize,
        );
        final parsed = _sampleTableCache[fileId];
        if (parsed != null) {
          _debugLog(
            'Proxy: Parsed MP4 sample table for $fileId: '
            '${parsed.samples.length} samples, '
            '${parsed.keyframeSampleIndices.length} keyframes',
          );

          // Save to disk cache for future use
          if (cachePath != null) {
            await parsed.saveToFile(cachePath);
            _debugLog('Proxy: Saved sample table to cache for $fileId');
          }
        }
      } finally {
        await raf.close();
      }
    } catch (e) {
      _debugLog('Proxy: Failed to parse sample table for $fileId: $e');
      _sampleTableCache[fileId] = null;
    }
  }

  /// Get the cache directory path for sample tables
  String? _sampleTableCacheDir;

  Future<String?> _getSampleTableCachePath(String cacheKey) async {
    try {
      if (_sampleTableCacheDir == null) {
        // Use the same base directory as TDLib
        final docsDir = await _getDocumentsDirectory();
        if (docsDir == null) return null;
        _sampleTableCacheDir = '$docsDir/antigravity_tdlib/sample_table_cache';
        await Directory(_sampleTableCacheDir!).create(recursive: true);
      }
      return '$_sampleTableCacheDir/$cacheKey.json';
    } catch (e) {
      _debugLog('Proxy: Failed to get cache path: $e');
      return null;
    }
  }

  Future<String?> _getDocumentsDirectory() async {
    try {
      // Platform-specific documents directory
      if (Platform.isWindows) {
        return '${Platform.environment['USERPROFILE']!}\\Documents';
      } else if (Platform.isMacOS || Platform.isLinux) {
        return '${Platform.environment['HOME']!}/Documents';
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // SEEK DEBOUNCE
  // ============================================================

  /// Debounced seek handler to prevent flooding TDLib with rapid cancellations.
  /// Instead of immediately cancelling and restarting download on each seek,
  /// this coalesces rapid seeks into a single request.
  void _handleDebouncedSeek(int fileId, int seekOffset) {
    // Cancel any pending debounce timer for this file
    _seekDebounceTimers[fileId]?.cancel();

    // Store the pending seek offset
    _pendingSeekOffsets[fileId] = seekOffset;

    // Set up debounce timer
    _seekDebounceTimers[fileId] = Timer(
      Duration(milliseconds: _seekDebounceMs),
      () {
        final pendingOffset = _pendingSeekOffsets.remove(fileId);
        _seekDebounceTimers.remove(fileId);

        if (pendingOffset != null && !_abortedRequests.contains(fileId)) {
          _log(
            'Executing debounced seek for $fileId to offset ${pendingOffset ~/ 1024}KB',
          );
          // Execute the actual seek by starting download at the debounced offset
          _startDownloadAtOffset(fileId, pendingOffset);
        }
      },
    );
  }
}
