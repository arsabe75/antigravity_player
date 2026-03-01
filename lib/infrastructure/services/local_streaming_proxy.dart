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
import 'downloaded_ranges.dart';
import '../../domain/value_objects/loading_progress.dart';
import '../../domain/value_objects/streaming_error.dart';

class ProxyFileInfo {
  final String path;
  final int totalSize;
  final int downloadOffset;
  final int downloadedPrefixSize;
  final bool isDownloadingActive;
  final bool isCompleted;

  /// Rangos descargados multi-rango (compartida, no copiada por ProxyFileInfo).
  DownloadedRanges? ranges;

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

    // 1. Consultar rangos multi-rango si disponibles
    if (ranges != null) {
      final available = ranges!.availableBytesFrom(offset);
      if (available > 0) return available;
    }

    // 2. Fallback: rango único TDLib (compatibilidad)
    final begin = downloadOffset;
    final end = downloadOffset + downloadedPrefixSize;

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

  /// Rangos descargados conocidos por archivo (sliding window multi-rango).
  /// Se actualiza con cada updateFile de TDLib y persiste entre cambios de offset.
  final Map<int, DownloadedRanges> _downloadedRanges = {};

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

  // FIX R2: Seek generation counter per file. Incremented on each user seek.
  // Stream loops capture the generation at start and break if it changes.
  // This replaces the Set-based approach (Fix R) which had a race condition:
  // new HTTP connections cleared the flag before old loops could see it.
  final Map<int, int> _seekGeneration = {};

  // FIX T: Connection flood detector for broken videos.
  // Tracks eviction timestamps per file. If evictions exceed threshold
  // in a time window, the video is marked as corrupt and rejected.
  final Map<int, List<DateTime>> _evictionTimestamps = {};
  static const int _floodEvictionThreshold = 30;
  static const Duration _floodTimeWindow = Duration(seconds: 10);

  // ============================================================
  // TELEGRAM ANDROID-INSPIRED IMPROVEMENTS
  // ============================================================

  // MÉTRICAS DE VELOCIDAD: Track download speed for adaptive decisions
  final Map<int, DownloadMetrics> _downloadMetrics = {};

  // IN-MEMORY LRU CACHE: Cache recently read data for instant backward seeks
  final Map<int, StreamingLRUCache> _streamingCaches = {};
  // GLOBAL RAM LIMIT: LRU order of file IDs by cache access (most recent at end).
  // Used to evict oldest file's cache when global budget is exceeded.
  final List<int> _cacheLruOrder = [];
  // Track all active HTTP request offsets per file for cleanup on close
  final Map<int, Set<int>> _activeHttpRequestOffsets = {};
  // CONNECTION LIMITER: Count active HTTP connections per file.
  // Prevents the player from creating hundreds of concurrent connections
  // that overwhelm the Windows message queue via TDLib event floods.
  final Map<int, int> _activeConnectionCount = {};
  // FIX O2: Eviction mechanism for zombie connections. When the connection
  // limit is reached, the oldest/most-stale connection is flagged for eviction.
  // The stream loop checks this set and exits gracefully.
  final Map<int, Set<int>> _evictedConnectionOffsets = {};
  // FIX O3: Track connections whose counter was already pre-decremented
  // during eviction, so the finally block doesn't double-decrement.
  final Map<int, Set<int>> _connectionsSkipDecrement = {};

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
  // STALL DETECTION: Track last download offset to detect TDLib offset switches
  final Map<int, int> _lastStallCheckOffset = {};
  // STALL DETECTION: High water mark (max of offset+prefix ever seen) to detect true progress
  final Map<int, int> _downloadHighWaterMark = {};
  // STALL DETECTION: Debounce - prevent multiple timers from recording stalls simultaneously
  final Map<int, DateTime> _lastStallRecordedTime = {};

  // PER-FILE STALL TIMER: Single timer per file instead of per HTTP connection.
  // Prevents N connections from creating N independent timers that all flood
  // TDLib with downloadFile calls.
  final Map<int, Timer> _perFileStallTimers = {};

  // PREFETCH BUFFER: Proactive downloading ahead of playback position.
  // Detects when TDLib goes idle and fills gaps ahead of playback.
  final Map<int, Timer?> _prefetchDebounceTimers = {};
  final Map<int, Timer?> _prefetchPeriodicTimers = {};
  final Map<int, bool> _wasDownloadingActive = {};

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

    // CRITICAL FIX: También resetear el loadState si estaba en error/timeout.
    // Sin esto, el circuit breaker rechaza todas las requests futuras (503)
    // incluyendo seeks del usuario, haciendo el video irrecuperable.
    final state = _getOrCreateState(fileId);
    if (state.loadState == FileLoadState.error ||
        state.loadState == FileLoadState.timeout) {
      state.loadState = FileLoadState.idle;
      _debugLog(
        'Proxy: Retry count reset for $fileId - loadState restored to idle',
      );
    } else {
      _debugLog('Proxy: Retry count reset for $fileId (playback recovered)');
    }
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

    // FLOOD PREVENTION: When error is terminal, wake up and clear all waiters
    // so their _handleRequest loops exit immediately instead of re-requesting data.
    if (!error.isRecoverable) {
      final waiters = _byteAvailabilityWaiters.remove(fileId);
      if (waiters != null) {
        for (final entry in waiters) {
          if (!entry.value.isCompleted) {
            entry.value.complete();
          }
        }
      }
    }

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

    // Cancel TDLib download to free bandwidth for the next video.
    // Without this, TDLib continues downloading the aborted file in background,
    // competing for bandwidth with the new file's download.
    TelegramService().send({
      '@type': 'cancelDownloadFile',
      'file_id': fileId,
      'only_if_pending': false,
    });

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

    // Cancel per-file stall timer
    _cancelStallTimer(fileId);

    // Cancel prefetch timers
    _cancelPrefetchTimer(fileId);
    _wasDownloadingActive.remove(fileId);

    // Cancel seek debounce timer
    _seekDebounceTimers[fileId]?.cancel();
    _seekDebounceTimers.remove(fileId);
    _pendingSeekOffsets.remove(fileId);

    // Clear LRU streaming cache for this file (releases up to 32MB)
    _streamingCaches[fileId]?.clear();
    _streamingCaches.remove(fileId);
    _cacheLruOrder.remove(fileId);

    // Remove all per-file state to prevent memory growth
    _filePaths.remove(fileId);
    _downloadedRanges.remove(fileId);
    _fileStates.remove(fileId);
    _downloadMetrics.remove(fileId);
    _activeHttpRequestOffsets.remove(fileId);
    _activeConnectionCount.remove(fileId);
    _evictedConnectionOffsets.remove(fileId);
    _connectionsSkipDecrement.remove(fileId);
    _seekGeneration.remove(fileId);
    _evictionTimestamps.remove(fileId);
    _lastDownloadProgress.remove(fileId);
    _lastStallCheckOffset.remove(fileId);
    _downloadHighWaterMark.remove(fileId);
    _lastStallRecordedTime.remove(fileId);

    _lastWaitingLogTime.remove(fileId);
    _lastProtectedLogTime.remove(fileId);
    _pendingFileUpdates.remove(fileId);
  }

  /// Invalidates all cached file information.
  /// Call this when Telegram cache is cleared to ensure fresh file info is fetched.
  void invalidateAllFiles() {
    _log('Invalidating all cached file info');
    _filePaths.clear();
    _downloadedRanges.clear();
    _activeHttpRequestOffsets.clear();
    _activeConnectionCount.clear();
    _evictedConnectionOffsets.clear();
    _connectionsSkipDecrement.clear();
    _seekGeneration.clear();
    _evictionTimestamps.clear();

    _downloadMetrics.clear();
    _sampleTableCache.clear();

    // Clear consolidated file states
    _fileStates.clear();

    // Clear LRU streaming caches
    for (final cache in _streamingCaches.values) {
      cache.clear();
    }
    _streamingCaches.clear();
    _cacheLruOrder.clear();

    // Clear file load states (handled by _fileStates.clear())
    _pendingSeekAfterMoov.clear();
    _stalePlaybackPositions.clear();

    // Cancel all per-file stall timers
    for (final timer in _perFileStallTimers.values) {
      timer.cancel();
    }
    _perFileStallTimers.clear();

    // Cancel all prefetch timers
    for (final timer in _prefetchPeriodicTimers.values) {
      timer?.cancel();
    }
    _prefetchPeriodicTimers.clear();
    for (final timer in _prefetchDebounceTimers.values) {
      timer?.cancel();
    }
    _prefetchDebounceTimers.clear();
    _wasDownloadingActive.clear();

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
    _downloadedRanges.remove(fileId);
    _activeHttpRequestOffsets.remove(fileId);

    // Clear LRU streaming cache for this file
    _streamingCaches[fileId]?.clear();
    _streamingCaches.remove(fileId);
  }

  /// Signal that user explicitly initiated a seek.
  /// Call this from MediaKitVideoRepository.seekTo() BEFORE the player seeks.
  void signalUserSeek(int fileId, int targetTimeMs) {
    _log('USER SEEK SIGNALED for $fileId to ${targetTimeMs}ms');
    // FIX J: Restaurar la señal explícita de seek para que la detección
    // de primary offset en _handleRequest la use (línea ~1334).
    // Sin esto, el proxy depende de heurísticas que pueden fallar.
    _getOrCreateState(fileId).userSeekInProgress = true;

    // FIX R2: Increment seek generation to force all existing connections to close.
    // Each stream loop captures the generation at start. When it changes, loops break.
    // This replaces the Set-based approach which had a race condition: new connections
    // cleared the flag before old loops could check it.
    final newGen = (_seekGeneration[fileId] ?? 0) + 1;
    _seekGeneration[fileId] = newGen;
    // Also complete any pending byte-availability waiters so they unblock
    final waiters = _byteAvailabilityWaiters.remove(fileId);
    if (waiters != null) {
      for (final entry in waiters) {
        if (!entry.value.isCompleted) {
          entry.value.complete();
        }
      }
    }
    _debugLog(
      'Proxy: FIX R2 - Seek generation $newGen for $fileId, breaking all connections (seek to ${targetTimeMs}ms)',
    );
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

    // SAFETY VALVE: Don't process updates for files in terminal error state.
    // This prevents event cascades: when max retries are hit, TDLib may still
    // send updateFile events that would wake waiters, trigger new downloadFile
    // calls, and overflow the Windows message queue.
    final fileState = _fileStates[id];
    if (fileState != null) {
      final ls = fileState.loadState;
      if (ls == FileLoadState.error ||
          ls == FileLoadState.timeout ||
          ls == FileLoadState.unsupported) {
        return;
      }
    }

    final local = file['local'] as Map<String, dynamic>?;
    final info = ProxyFileInfo(
      path: local?['path'] as String? ?? '',
      totalSize: file['size'] as int? ?? 0,
      downloadOffset: local?['download_offset'] as int? ?? 0,
      downloadedPrefixSize: local?['downloaded_prefix_size'] as int? ?? 0,
      isDownloadingActive: local?['is_downloading_active'] as bool? ?? false,
      isCompleted: local?['is_downloading_completed'] as bool? ?? false,
    );

    // CRITICAL FIX: Always process immediately if there are active waiters
    // for this file. This ensures MOOV-at-end videos don't stall.
    final hasActiveWaiter = _fileUpdateNotifiers.containsKey(id);
    final hasActiveByteWaiter = _byteAvailabilityWaiters.containsKey(id);
    if (hasActiveWaiter || hasActiveByteWaiter) {
      // Process this update immediately - someone is waiting for it
      _updateFileAndEnforce(id, info);

      // EARLY MOOV DETECTION: Trigger as soon as we have enough bytes
      // This allows us to detect moov-at-start immediately and prepare
      // for moov-at-end videos before the player even requests data.
      _triggerEarlyMoovDetection(id, info);

      return;
    }

    // OPTIMIZATION: Buffer non-critical updates and process with throttling
    _pendingFileUpdates[id] = info;

    // Throttle: process at most every 100ms
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
      _updateFileAndEnforce(entry.key, entry.value);
    }
    _pendingFileUpdates.clear();
  }

  /// Updates file info and triggers cache enforcement if needed
  void _updateFileAndEnforce(int id, ProxyFileInfo info) {
    // CACHE LIMIT ENFORCEMENT (STREAMING MODE):
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
          _totalBytesDownloadedSinceEnforcement = 0; // Reset immediately
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

    _filePaths[id] = info;

    // Actualizar rangos descargados multi-rango (sliding window)
    final ranges = _downloadedRanges.putIfAbsent(id, () => DownloadedRanges());
    if (info.isCompleted) {
      ranges.markComplete(info.totalSize);
    } else if (info.downloadedPrefixSize > 0) {
      ranges.addRange(
        info.downloadOffset,
        info.downloadOffset + info.downloadedPrefixSize,
      );
    }
    info.ranges = ranges;

    // Notify anyone waiting for updates on this file
    _fileUpdateNotifiers[id]?.add(null);

    // EVENT-DRIVEN: Wake up only byte waiters whose offsets are now satisfied.
    // Selective wakeup avoids thundering herd when multiple connections wait
    // on different offsets (e.g., MOOV-at-end initialization).
    if (_byteAvailabilityWaiters.containsKey(id)) {
      final waiters = _byteAvailabilityWaiters[id]!;
      waiters.removeWhere((entry) {
        final requiredOffset = entry.key;
        final completer = entry.value;
        if (info.availableBytesFrom(requiredOffset) > 0) {
          if (!completer.isCompleted) {
            completer.complete();
          }
          return true;
        }
        return false;
      });
      if (waiters.isEmpty) {
        _byteAvailabilityWaiters.remove(id);
      }
    }

    // PREFETCH: Detectar transición idle de TDLib y programar prefetch
    final wasActive = _wasDownloadingActive[id] ?? false;
    final isNowActive = info.isDownloadingActive;
    _wasDownloadingActive[id] = isNowActive;

    if (wasActive && !isNowActive && !info.isCompleted) {
      _schedulePrefetchEval(id);
    }
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

  /// Enforce global RAM budget for LRU caches + sample tables.
  /// Evicts least recently used file caches when total exceeds budget.
  /// [activeFileId] is never evicted (currently being accessed).
  void _enforceGlobalCacheBudget(int activeFileId) {
    // Update LRU order: move active file to end (most recent)
    _cacheLruOrder.remove(activeFileId);
    _cacheLruOrder.add(activeFileId);

    // Calculate total cache RAM
    int totalCacheBytes = 0;
    for (final cache in _streamingCaches.values) {
      totalCacheBytes += cache.size;
    }

    // Evict oldest files until within budget
    while (totalCacheBytes > ProxyConfig.globalCacheBudgetBytes &&
        _cacheLruOrder.length > 1) {
      final oldestFileId = _cacheLruOrder.first;
      if (oldestFileId == activeFileId) break;

      final evictedCache = _streamingCaches[oldestFileId];
      final evictedSize = evictedCache?.size ?? 0;

      // Evict LRU cache
      evictedCache?.clear();
      _streamingCaches.remove(oldestFileId);

      // Also evict sample table (secondary RAM consumer)
      _sampleTableCache.remove(oldestFileId);

      _cacheLruOrder.removeAt(0);
      totalCacheBytes -= evictedSize;

      _debugLog(
        'Proxy: GLOBAL RAM LIMIT - Evicted cache for file $oldestFileId '
        '(${evictedSize ~/ 1024}KB freed, total: ${totalCacheBytes ~/ (1024 * 1024)}MB)',
      );
    }
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
    _downloadedRanges.clear();
    _abortedRequests.clear();
    _cacheLruOrder.clear();

    // Cancel all prefetch timers
    for (final timer in _prefetchPeriodicTimers.values) {
      timer?.cancel();
    }
    _prefetchPeriodicTimers.clear();
    for (final timer in _prefetchDebounceTimers.values) {
      timer?.cancel();
    }
    _prefetchDebounceTimers.clear();
    _wasDownloadingActive.clear();
  }

  String getUrl(int fileId, int size) {
    return 'http://127.0.0.1:$_port/stream?token=$_sessionToken&file_id=$fileId&size=$size';
  }

  // Helper to get available bytes from the given offset
  // Uses local cache first (like Unigram), then queries TDLib if needed
  Future<int> _getDownloadedPrefixSize(int fileId, int offset) async {
    // 1. Check local cache first (Unigram pattern, ahora con multi-rango)
    final cached = _filePaths[fileId];
    if (cached != null && cached.path.isNotEmpty) {
      final available = cached.availableBytesFrom(offset);
      if (available > 0) {
        return available;
      }
    }

    // 1b. Verificar rangos directamente (si ProxyFileInfo no tiene referencia)
    final ranges = _downloadedRanges[fileId];
    if (ranges != null) {
      final available = ranges.availableBytesFrom(offset);
      if (available > 0) return available;
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
      _logTrace('Received request for ${request.uri}');

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

      // Scaled thresholds proportional to file size (fixes small file degradation)
      final significantJump = ProxyConfig.scaled(
        totalSize,
        0.10,
        ProxyConfig.significantJumpMinBytes,
        50 * 1024 * 1024,
      );
      final scrubThreshold = ProxyConfig.scaled(
        totalSize,
        0.05,
        ProxyConfig.activePlaybackMinBytes,
        10 * 1024 * 1024,
      );
      // Proportional thresholds for correct small-file behavior
      final seekThreshold = ProxyConfig.scaled(
        totalSize,
        ProxyConfig.seekDetectionThresholdPercent,
        ProxyConfig.seekDetectionMinBytes,
        ProxyConfig.seekDetectionMaxBytes,
      );
      final moovReadyBytes = ProxyConfig.scaled(
        totalSize,
        ProxyConfig.moovReadyThresholdPercent,
        ProxyConfig.moovReadyMinBytes,
        ProxyConfig.moovReadyMaxBytes,
      );
      final primaryProgressBase = ProxyConfig.scaled(
        totalSize,
        ProxyConfig.primaryProgressBaseThresholdPercent,
        ProxyConfig.primaryProgressBaseMinBytes,
        ProxyConfig.primaryProgressBaseMaxBytes,
      );

      // Track when video was first opened for initialization grace period
      final state = _getOrCreateState(fileId);
      state.openTime ??= DateTime.now();

      // FIX R2: Capture seek generation for this connection.
      // Old connections have a stale generation and will break.
      // New connections capture the current generation and are safe.
      final mySeekGeneration = _seekGeneration[fileId] ?? 0;

      // CIRCUIT BREAKER: Reject requests for files in terminal error state.
      // This covers unsupported codecs, corrupt files, max retries exceeded,
      // and timeouts. Prevents the player from endlessly retrying and
      // flooding TDLib with downloadFile calls.
      if (state.loadState == FileLoadState.unsupported ||
          state.loadState == FileLoadState.error ||
          state.loadState == FileLoadState.timeout) {
        _debugLog(
          'Proxy: Rejecting request for file $fileId in state ${state.loadState}',
        );
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }

      // CONNECTION LIMITER with EVICTION (FIX O/O2):
      // mpv/ffmpeg opens new HTTP connections for each seek and track switch
      // but never closes old ones. Without management, connections accumulate
      // and eventually a 503 rejection causes ffmpeg to report "partial file"
      // → false EOF → playback stops.
      // Solution: when the limit is reached, evict the most stale connection
      // (furthest behind the primary playback offset) instead of rejecting.
      final currentConnections = _activeConnectionCount[fileId] ?? 0;
      if (currentConnections >= ProxyConfig.maxConnectionsPerFile) {
        final offsets = _activeHttpRequestOffsets[fileId];
        final primary = _getOrCreateState(fileId).primaryPlaybackOffset ?? 0;
        if (offsets != null && offsets.length > 1) {
          // Find the connection whose start offset is furthest behind primary
          int? mostStale;
          int maxDist = -1;
          for (final o in offsets) {
            // Only evict connections behind the primary playback offset
            if (o < primary) {
              final dist = primary - o;
              if (dist > maxDist) {
                maxDist = dist;
                mostStale = o;
              }
            }
          }
          // If no connection is behind primary, evict the oldest (smallest offset)
          mostStale ??= offsets.reduce((a, b) => a < b ? a : b);
          _evictedConnectionOffsets.putIfAbsent(fileId, () => {}).add(mostStale);
          // FIX O3: Pre-decrement the counter for the evicted connection so it
          // doesn't climb while waiting for the evicted stream loop to exit.
          // Track the offset so the finally block skips its decrement.
          _connectionsSkipDecrement.putIfAbsent(fileId, () => {}).add(mostStale);
          _activeConnectionCount[fileId] = currentConnections; // -1 evicted, +1 new = net 0
          _debugLog(
            'Proxy: CONNECTION LIMIT for $fileId '
            '($currentConnections/${ProxyConfig.maxConnectionsPerFile}), '
            'evicting stale connection at ${mostStale ~/ 1024}KB '
            '(primary: ${primary ~/ 1024}KB, new: ${start ~/ 1024}KB)',
          );

          // FIX T: Track eviction rate to detect broken videos flooding connections.
          // A healthy video may evict occasionally (seek, track switch).
          // A broken video floods: dozens of evictions per second as mpv
          // keeps reopening connections that immediately fail.
          final now = DateTime.now();
          final timestamps = _evictionTimestamps.putIfAbsent(fileId, () => []);
          timestamps.add(now);
          // Prune old timestamps outside the window
          final cutoff = now.subtract(_floodTimeWindow);
          timestamps.removeWhere((t) => t.isBefore(cutoff));
          if (timestamps.length >= _floodEvictionThreshold) {
            _logError(
              'CONNECTION FLOOD detected for $fileId: '
              '${timestamps.length} evictions in ${_floodTimeWindow.inSeconds}s. '
              'File appears damaged — blocking further requests.',
              fileId: fileId,
            );
            _evictionTimestamps.remove(fileId);
            final error = StreamingError.corruptFile(fileId);
            _notifyErrorIfNew(fileId, error);
            // Abort all pending operations for this file
            _abortedRequests.add(fileId);
            final waiters = _byteAvailabilityWaiters.remove(fileId);
            if (waiters != null) {
              for (final entry in waiters) {
                if (!entry.value.isCompleted) entry.value.complete();
              }
            }
            request.response.statusCode = HttpStatus.serviceUnavailable;
            await request.response.close();
            return;
          }
          // Allow the new connection through — counter already adjusted
        } else {
          // No evictable connections, reject as last resort
          _debugLog(
            'Proxy: CONNECTION LIMIT for $fileId, no evictable connections, '
            'rejecting at offset ${start ~/ 1024}KB',
          );
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
      } else {
        // Normal case: under the limit, just increment
        _activeConnectionCount[fileId] = currentConnections + 1;
      }

      // TRACK CLIENT DISCONNECTS TO PREVENT CONNECTION LEAKS DURING STALLS
      bool isClientDisconnected = false;
      final disconnectCompleter = Completer<bool>();
      request.response.done
          .then((_) {
            isClientDisconnected = true;
            if (!disconnectCompleter.isCompleted) {
              disconnectCompleter.complete(true);
            }
          })
          .catchError((_) {
            isClientDisconnected = true;
            if (!disconnectCompleter.isCompleted) {
              disconnectCompleter.complete(true);
            }
          });

      try {
        // Wait for TDLib client to be ready (max 10 seconds)
        // This is crucial on app start when TDLib might still be initializing
        if (!TelegramService().isClientReady) {
          _debugLog('Proxy: Waiting for TDLib client to initialize...');
          int attempts = 0;
          while (!TelegramService().isClientReady &&
              attempts < ProxyConfig.tdlibInitMaxAttempts) {
            await Future.delayed(
              const Duration(milliseconds: ProxyConfig.tdlibInitWaitMs),
            );
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
          _debugLog(
            'Proxy: TDLib client ready after ${attempts * ProxyConfig.tdlibInitWaitMs}ms',
          );
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
          final waitMs = thisFileWasAborted
              ? ProxyConfig.abortStabilizationAbortedMs
              : ProxyConfig.abortStabilizationOtherMs;
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
            _downloadedRanges.remove(fileId);
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

        if (_stalePlaybackPositions.contains(fileId) && start > seekThreshold) {
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
            start <= seekThreshold) {
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
          if (jump > seekThreshold) {
            isSeekRequest = true;

            // Don't set _lastSeekTime for moov requests (near end of file) OR
            // for seeks TO the beginning (initial playback).
            // _lastSeekTime should only be set for TRUE SCRUBBING: user dragging
            // the seek bar while video is playing (both positions > 10MB).
            final isMoovRequest =
                totalSize > 0 &&
                (totalSize - start) <
                    (totalSize * ProxyConfig.scrubMoovDetectionThresholdPercent)
                        .round()
                        .clamp(
                          scrubThreshold,
                          ProxyConfig.moovRegionClampMaxBytes,
                        );
            final isSeekToBeginning = start < scrubThreshold;
            final isTrueScrubbing =
                !isMoovRequest &&
                !isSeekToBeginning &&
                lastOffset > scrubThreshold;

            if (isTrueScrubbing) {
              _getOrCreateState(fileId).lastSeekTime = DateTime.now();
            }

            // CRITICAL FIX: When a seek is detected, reset the primary offset to the seek target
            // This prevents the primary from getting stuck at 0 when seeking forward
            // _primaryPlaybackOffset[fileId] = start; // MOVED BELOW for centralized logic
            _logTrace(
              'Detected seek for $fileId: $lastOffset -> $start (jump: ${jump ~/ 1024}KB)',
              fileId: fileId,
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
          if (distFromPrimary > significantJump) {
            // FIX Q: After a seek, mpv sends track-detection probes near the end
            // of the file (subtitle/data streams). These are NOT the actual seek
            // target. Don't adopt them as primary — wait for the real video request.
            final isEndOfFileProbe = totalSize > 0 &&
                (totalSize - start) < totalSize * 0.10 &&
                existingPrimary < totalSize * 0.85;
            if (isEndOfFileProbe) {
              _debugLog(
                'Proxy: IGNORING end-of-file probe during user seek for $fileId. '
                'Probe at ${start ~/ 1024}KB (${(totalSize - start) ~/ (1024 * 1024)}MB from end), '
                'keeping primary at ${existingPrimary ~/ 1024}KB',
              );
              // Don't clear userSeekInProgress — the real seek request comes next
            } else {
              _debugLog(
                'Proxy: EXPLICIT USER SEEK for $fileId. Primary $existingPrimary -> $start.',
              );
              shouldUpdatePrimary = true;
              playbackState.userSeekInProgress = false;
              // P1 FIX: Track this seek to protect from stagnant adoption
              playbackState.lastExplicitSeekOffset = start;
              playbackState.lastExplicitSeekTime = DateTime.now();
            }
          } else {
            _debugLog(
              'Proxy: USER SEEK SIGNAL active but offset $start too close to Primary $existingPrimary (${distFromPrimary ~/ 1024}KB)',
            );
          }
        } else if (isSeekRequest) {
          // Check for Rapid Divergence
          if (lastPrimaryUpdate != null &&
              DateTime.now().difference(lastPrimaryUpdate).inMilliseconds <
                  ProxyConfig.rapidDivergenceWindowMs) {
            // Rapid update! distinct from previous primary?
            if ((start - existingPrimary).abs() > scrubThreshold) {
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
              // MOOV FIX / FIX Q: Don't adopt end-of-file probes as Primary.
              // mpv sends track-detection probes to the last portion of the file.
              // Use 10% of file size (min 100MB) to catch probes that are further
              // from the end than the old significantJump*2 (100MB) threshold.
              final endOfFileThreshold = totalSize > 0
                  ? (totalSize * 0.10).clamp(significantJump * 2, totalSize * 0.10).toInt()
                  : significantJump * 2;
              final isMoovRequestForCheck =
                  totalSize > 0 && (totalSize - start) < endOfFileThreshold;

              final isResumeFromStart =
                  !isMoovRequestForCheck &&
                  existingPrimary < significantJump &&
                  start > significantJump;

              if (isResumeFromStart) {
                _debugLog(
                  'Proxy: RESUME DETECTED ($existingPrimary -> $start). Forcing Primary update.',
                );
                shouldUpdatePrimary = true;
              } else if (!isMoovRequestForCheck &&
                  DateTime.now()
                      .difference(lastPrimaryUpdate)
                      .inMilliseconds >
                  2000) {
                _logTrace(
                  'Recovering Primary Offset (Stagnant 2s in Seek) -> Adopting $start',
                  fileId: fileId,
                );
                shouldUpdatePrimary = true;
              } else {
                _logTrace(
                  'IGNORING rapid divergent seek to $start (kept primary at $existingPrimary)',
                  fileId: fileId,
                );
                shouldUpdatePrimary = false;
                // Reset isSeekRequest to false so this request doesn't bypass debounce!
                isSeekRequest = false;
              }
            } else {
              shouldUpdatePrimary = true; // Close enough, update it
            }
          } else {
            // FIX Q3: Don't adopt end-of-file probes as "stable seek" either
            final endOfFileThresholdStable = totalSize > 0
                ? (totalSize * 0.10).clamp(significantJump * 2, totalSize * 0.10).toInt()
                : significantJump * 2;
            final isMoovStable =
                totalSize > 0 && (totalSize - start) < endOfFileThresholdStable;
            if (isMoovStable && existingPrimary < totalSize * 0.85) {
              _debugLog(
                'Proxy: IGNORING end-of-file stable seek for $fileId at ${start ~/ 1024}KB, '
                'keeping primary at ${existingPrimary ~/ 1024}KB',
              );
            } else {
              shouldUpdatePrimary = true; // Stable seek
            }
          }
        } else if (start < existingPrimary) {
          // Only track lower offsets if they are reasonable (not huge jumps back which are likely zombie streams)
          final jumpBack = existingPrimary - start;
          if (jumpBack < significantJump) {
            shouldUpdatePrimary = true;
          } else {
            _logTrace(
              'Ignoring primary offset reset $existingPrimary -> $start (diff: ${jumpBack ~/ (1024 * 1024)}MB) - likely zombie stream',
              fileId: fileId,
            );
          }
        } else {
          // SEQUENTIAL TRACKING:
          // If legitimate playback progresses forward, we must advance the Primary Offset so the
          // "Blocking Guard" (50MB radius) moves with the user.
          final jumpForward = start - existingPrimary;
          if (jumpForward > 0) {
            // 1. Standard Sequential: within 50MB
            if (jumpForward < significantJump) {
              shouldUpdatePrimary = true;
            }
            // 2. READ-AHEAD DETECTION:
            // If jump is > significantJump, it might be a Buffer Request (Parallel Read-Ahead).
            // We should NOT update Primary immediately, because the player is likely still
            // playing at 'existingPrimary'.
            // However, if Primary is STAGNANT ( hasn't moved for > 2000ms),
            // it might be a legitimate Seek that we misidentified.
            else if (lastPrimaryUpdate != null &&
                DateTime.now().difference(lastPrimaryUpdate).inMilliseconds >
                    ProxyConfig.stagnantPrimaryMs) {
              _logTrace(
                'Recovering Primary Offset (Stagnant 2s on Forward Jump) -> Adopting $start',
                fileId: fileId,
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

        // PROTECCIÓN CONTRA ZOMBIES CON SECUENCIA DE SEEK:
        // Si hubo un seek reciente (seekSequenceNumber incrementó), rechazar
        // actualizaciones no-seek de primary offset que podrían venir de
        // conexiones HTTP stale creadas antes del seek.
        if (shouldUpdatePrimary && isSeekRequest) {
          playbackState.seekSequenceNumber++;
          playbackState.primaryPlaybackOffset = start;
          playbackState.lastPrimaryUpdateTime = DateTime.now();
          _logTrace(
            'Primary Target UPDATED to $start via SEEK '
            '(seekSeq: ${playbackState.seekSequenceNumber})',
            fileId: fileId,
          );
        } else if (shouldUpdatePrimary) {
          // Actualización no-seek (backward o sequential): verificar que no haya
          // un seek reciente que esta conexión desconoce.
          final lastSeekTime = playbackState.lastExplicitSeekTime;
          final isRecentSeek = lastSeekTime != null &&
              DateTime.now().difference(lastSeekTime).inMilliseconds < 3000;

          if (isRecentSeek && existingPrimary != null) {
            // Hay un seek reciente — solo aceptar si la conexión va en la misma
            // dirección que el seek (offset cercano al primary actual).
            final distFromPrimary = (start - existingPrimary).abs();
            if (distFromPrimary > significantJump) {
              _logTrace(
                'ZOMBIE BLOCKED: Ignorando primary update $existingPrimary -> $start '
                '(seek reciente, dist: ${distFromPrimary ~/ (1024 * 1024)}MB)',
                fileId: fileId,
              );
              shouldUpdatePrimary = false;
            }
          }

          if (shouldUpdatePrimary) {
            playbackState.primaryPlaybackOffset = start;
            playbackState.lastPrimaryUpdateTime = DateTime.now();
          }
        }

        // 2. Ensure File Info is available
        if (!_filePaths.containsKey(fileId) ||
            _filePaths[fileId]!.path.isEmpty) {
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
          _downloadedRanges.remove(fileId);

          // CRITICAL FIX: Explicitly tell TDLib to delete the file logic.
          // Even if the file is gone from disk, TDLib might still have the path in its database.
          // Without this, getFile returns the old path and we enter an infinite loop.
          // Start with internal state reset.
          _getOrCreateState(fileId).resetDownloadState();

          _debugLog(
            'Proxy: File missing on disk, forcing TDLib delete for $fileId',
          );
          await TelegramService().sendWithResult({
            '@type': 'deleteFile',
            'file_id': fileId,
          });

          // Small wait for TDLib to process the deletion and clear the path
          await Future.delayed(
            const Duration(
              milliseconds: ProxyConfig.tdlibDeleteStabilizationMs,
            ),
          );

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

        // DIAG: Log HTTP response headers for debugging
        _debugLog(
          'Proxy: HTTP 206 for $fileId: Range $start-$effectiveEnd/$effectiveTotalSize '
          '(contentLength: $contentLength, ${contentLength ~/ (1024 * 1024)}MB)',
        );

        // 4. Stream Data Loop
        RandomAccessFile? raf;
        try {
          // FILE LOCKING FIX (Windows): TDLib may have the file locked while writing.
          // Retry with exponential backoff to handle temporary file access issues.
          raf = await _openFileWithRetry(file, fileId);
          if (raf == null) {
            throw FileSystemException('Failed to open file after retries');
          }

          int currentReadOffset = start;
          int remainingToSend = contentLength;

          // Ensure notifier exists
          if (!_fileUpdateNotifiers.containsKey(fileId)) {
            _fileUpdateNotifiers[fileId] = StreamController.broadcast();
          }

          // FIX F: Contador de timeouts consecutivos en gap MOOV inllenable
          int moovGapConsecutiveTimeouts = 0;
          const int moovGapMaxTimeouts = 5; // ~50s total

          while (remainingToSend > 0) {
            if (_abortedRequests.contains(fileId)) {
              _debugLog('Proxy: Request aborted for $fileId');
              break;
            }
            // FIX R2: User seek increments generation, stale connections break
            if ((_seekGeneration[fileId] ?? 0) != mySeekGeneration) {
              _debugLog(
                'Proxy: Seek-break (gen $mySeekGeneration→${_seekGeneration[fileId]}) for $fileId at offset ${currentReadOffset ~/ 1024}KB',
              );
              break;
            }
            if (isClientDisconnected) {
              _debugLog('Proxy: Client disconnected prematurely ($fileId)');
              break;
            }
            // FIX O2: Check if this connection was evicted to make room for a new one
            if (_evictedConnectionOffsets[fileId]?.contains(start) == true) {
              _evictedConnectionOffsets[fileId]!.remove(start);
              if (_evictedConnectionOffsets[fileId]!.isEmpty) {
                _evictedConnectionOffsets.remove(fileId);
              }
              _debugLog(
                'Proxy: Connection evicted for $fileId at offset '
                '${start ~/ 1024}KB (readOffset: ${currentReadOffset ~/ 1024}KB)',
              );
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
                min(remainingToSend, ProxyConfig.streamChunkSize),
              );

              // LRU Cache: Try cache first, fall back to disk read
              _streamingCaches.putIfAbsent(fileId, () => StreamingLRUCache());
              final cache = _streamingCaches[fileId]!;
              var cachedData = cache.get(currentReadOffset, chunkToRead);

              Uint8List data;
              if (cachedData != null) {
                // Cache hit - update global LRU order
                _cacheLruOrder.remove(fileId);
                _cacheLruOrder.add(fileId);
                data = cachedData;
              } else {
                // Cache miss - read from disk
                await raf.setPosition(currentReadOffset);
                data = await raf.read(chunkToRead);

                // Store in cache for future use
                if (data.isNotEmpty) {
                  _enforceGlobalCacheBudget(fileId);
                  cache.put(currentReadOffset, data);
                }
              }

              if (data.isEmpty) {
                await Future.delayed(
                  const Duration(milliseconds: ProxyConfig.emptyDataRetryMs),
                );
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
                  currentReadOffset >= moovReadyBytes) {
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
                    DateTime.now().difference(lastSeek).inMilliseconds <
                        ProxyConfig.stagnantPrimaryMs) {
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
                    (currentReadOffset - lastPrimary) < significantJump) {
                  final now = DateTime.now();
                  // Determine allowed progress based on time elapsed
                  // Base 2MB allowed instantly
                  int allowedProgress = primaryProgressBase;
                  if (lastUpdateTime != null) {
                    final elapsedMs = now
                        .difference(lastUpdateTime)
                        .inMilliseconds;
                    // Allow up to 3MB per second of additional progress (approx 3x realtime 1080p)
                    // Total max rate ~ 5MB/s roughly.
                    // (elapsedMs / 1000 * 3MB)
                    final timeBasedAllowance =
                        (elapsedMs /
                                1000 *
                                ProxyConfig.primaryProgressRateBytesPerSec)
                            .round();
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
                        now.difference(lastUpdateTime).inMilliseconds >
                            ProxyConfig.primaryUpdateThrottleMs) {
                      streamState.primaryPlaybackOffset = currentReadOffset;
                      streamState.lastPrimaryUpdateTime = now;
                    }
                  }
                } else if (currentReadOffset > lastPrimary &&
                    (currentReadOffset - lastPrimary) > significantJump) {
                  // STAGNANT ADOPTION (Stream Loop):
                  // We are streaming far ahead of Primary (>significantJump).
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
                      (lastPrimary - lastExplicitSeek).abs() <
                          significantJump * 2;
                  final proposedIsFarForward =
                      lastExplicitSeek != null &&
                      currentReadOffset > lastExplicitSeek &&
                      (currentReadOffset - lastExplicitSeek) > significantJump;
                  final isOverridingBackwardSeek =
                      primaryNearSeek && proposedIsFarForward;

                  // FIX Q2: Never adopt end-of-file offsets as primary via
                  // stagnant recovery. These are track-detection probes (subtitle,
                  // data streams), not actual playback. Last 10% of file.
                  final isEndOfFilePrimary = totalSize > 0 &&
                      (totalSize - currentReadOffset) < totalSize * 0.10 &&
                      lastPrimary < totalSize * 0.85;

                  if (isEndOfFilePrimary) {
                    _logTrace(
                      'BLOCKED end-of-file Stagnant Adoption for $fileId '
                      '(proposed: ${currentReadOffset ~/ (1024 * 1024)}MB, '
                      '${(totalSize - currentReadOffset) ~/ (1024 * 1024)}MB from end, '
                      'primary: ${lastPrimary ~/ (1024 * 1024)}MB)',
                      fileId: fileId,
                    );
                    streamState.lastPrimaryUpdateTime = DateTime.now();
                  } else if (isOverridingBackwardSeek) {
                    _logTrace(
                      'BLOCKED Stagnant Adoption for $fileId. Would override recent backward seek '
                      '(seekTarget: ${lastExplicitSeek ~/ (1024 * 1024)}MB, primary: ${lastPrimary ~/ (1024 * 1024)}MB, proposed: ${currentReadOffset ~/ (1024 * 1024)}MB)',
                      fileId: fileId,
                    );
                    // Don't adopt - keep the user's seek position
                    // Reset stagnant timer to prevent repeated adoption attempts
                    streamState.lastPrimaryUpdateTime = DateTime.now();
                  } else if (lastUpdateTime != null &&
                      DateTime.now().difference(lastUpdateTime).inMilliseconds >
                          ProxyConfig.stagnantPrimaryMs) {
                    _logTrace(
                      'Recovering Primary Offset (Stagnant 2s in StreamLoop) -> Adopting $currentReadOffset',
                      fileId: fileId,
                    );
                    streamState.primaryPlaybackOffset = currentReadOffset;
                    streamState.lastPrimaryUpdateTime = DateTime.now();
                  }
                }
              } else {
                // FIX G: Detección temprana del gap MOOV inllenable.
                // Si el offset está en el gap entre el frontier principal y la
                // región MOOV, no tiene sentido esperar ni redirigir TDLib ahí.
                if (_isInMoovGap(fileId, currentReadOffset)) {
                  _debugLog(
                    'Proxy: MOOV gap detected at $currentReadOffset for $fileId - ending stream',
                  );
                  break;
                }

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
                final moovWaitThreshold = ProxyConfig.scaled(
                  totalFileSize,
                  ProxyConfig.moovRegionThresholdPercent,
                  ProxyConfig.moovRegionMinBytes,
                  ProxyConfig.moovRegionMaxBytes,
                );
                final isMoovRequest =
                    distanceFromEnd > 0 && distanceFromEnd < moovWaitThreshold;

                // ADAPTIVE TIMEOUT: grows with retry count via exponential backoff
                final timeout = _getAdaptiveTimeout(fileId, isMoovRequest);

                // EVENT-DRIVEN WAIT: Register a Completer and wait for _onUpdate to wake us
                final completer = Completer<void>();
                _byteAvailabilityWaiters.putIfAbsent(fileId, () => []);
                _byteAvailabilityWaiters[fileId]!.add(
                  MapEntry(currentReadOffset, completer),
                );

                // Doble verificación post-registro para prevenir wakeups perdidos.
                // Si updateFile llegó entre el check de datos y el registro del waiter,
                // los datos ya están disponibles pero nadie despertará al completer.
                if (!completer.isCompleted) {
                  final postCheck = _filePaths[fileId];
                  if (postCheck != null &&
                      postCheck.availableBytesFrom(currentReadOffset) > 0) {
                    completer.complete();
                  }
                }

                try {
                  // Wait for data to become available, timeout, or client disconnect
                  final waitResult = await Future.any([
                    completer.future
                        .timeout(
                          timeout,
                          onTimeout: () {
                            // Timeout - remove our waiter and check manually
                            _byteAvailabilityWaiters[fileId]?.removeWhere(
                              (e) => e.value == completer,
                            );
                            if (_byteAvailabilityWaiters[fileId]?.isEmpty ??
                                false) {
                              _byteAvailabilityWaiters.remove(fileId);
                            }
                          },
                        )
                        .then((_) => false),
                    disconnectCompleter.future,
                  ]);

                  if (waitResult == true) {
                    _debugLog(
                      'Proxy: Client disconnected during wait ($fileId).',
                    );
                    _byteAvailabilityWaiters[fileId]?.removeWhere(
                      (e) => e.value == completer,
                    );
                    return;
                  }

                  // Check if aborted during wait
                  if (_abortedRequests.contains(fileId)) {
                    _debugLog('Proxy: Wait aborted for $fileId');
                    return;
                  }
                } catch (_) {
                  // Timeout or error - check data availability manually on next loop
                }

                // CIRCUIT BREAKER: Check if file entered terminal error state
                final currentLoadState = _getOrCreateState(fileId).loadState;
                if (currentLoadState == FileLoadState.error ||
                    currentLoadState == FileLoadState.timeout ||
                    currentLoadState == FileLoadState.unsupported) {
                  _debugLog(
                    'Proxy: CIRCUIT BREAKER - killing stream for $fileId at offset '
                    '$currentReadOffset (loadState: $currentLoadState)',
                  );
                  break;
                }

                // FIX F: MOOV gap timeout - detectar conexiones atrapadas en gap inllenable
                if (_getOrCreateState(fileId).isMoovAtEnd) {
                  final gapRanges = _downloadedRanges[fileId];
                  if (gapRanges != null &&
                      gapRanges.availableBytesFrom(currentReadOffset) == 0) {
                    moovGapConsecutiveTimeouts++;
                    if (moovGapConsecutiveTimeouts >= moovGapMaxTimeouts) {
                      _debugLog(
                        'Proxy: MOOV gap timeout at $currentReadOffset for $fileId '
                        '($moovGapConsecutiveTimeouts timeouts) - breaking wait',
                      );
                      break;
                    }
                  } else {
                    moovGapConsecutiveTimeouts = 0;
                  }
                }
              }

              // Read-ahead DISABLED due to TDLib limitation
              // TDLib cancels any ongoing download when a new downloadFile is called
              // for the same file_id with a different offset. This causes more harm
              // than benefit, so read-ahead is disabled until TDLib supports parallel
              // range requests for the same file.
              // _scheduleReadAhead(fileId, currentReadOffset);
            } else {
              // FIX G: Detección temprana del gap MOOV inllenable.
              if (_isInMoovGap(fileId, currentReadOffset)) {
                _debugLog(
                  'Proxy: MOOV gap detected at $currentReadOffset for $fileId - ending stream',
                );
                break;
              }

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
              final fileInfo = _filePaths[fileId];
              final totalFileSize = fileInfo?.totalSize ?? 0;
              final distanceFromEnd = totalFileSize > 0
                  ? totalFileSize - currentReadOffset
                  : 0;
              final moovWaitThreshold = ProxyConfig.scaled(
                totalFileSize,
                ProxyConfig.moovRegionThresholdPercent,
                ProxyConfig.moovRegionMinBytes,
                ProxyConfig.moovRegionMaxBytes,
              );
              final isMoovRequest =
                  distanceFromEnd > 0 && distanceFromEnd < moovWaitThreshold;

              // ADAPTIVE TIMEOUT: grows with retry count via exponential backoff
              final timeout = _getAdaptiveTimeout(fileId, isMoovRequest);

              // EVENT-DRIVEN WAIT: Register a Completer and wait for _onUpdate to wake us
              final completer = Completer<void>();
              _byteAvailabilityWaiters.putIfAbsent(fileId, () => []);
              _byteAvailabilityWaiters[fileId]!.add(
                MapEntry(currentReadOffset, completer),
              );

              // Doble verificación post-registro para prevenir wakeups perdidos.
              if (!completer.isCompleted) {
                final postCheck = _filePaths[fileId];
                if (postCheck != null &&
                    postCheck.availableBytesFrom(currentReadOffset) > 0) {
                  completer.complete();
                }
              }

              // PER-FILE STALL DETECTION: Update the offset we're waiting for
              // and ensure a shared stall timer is running for this file.
              // Unlike per-connection timers, this prevents N connections from
              // creating N timers that all restart downloads simultaneously.
              _getOrCreateState(fileId).waitingForOffset = currentReadOffset;
              _ensureStallTimer(fileId);
              _ensurePrefetchTimer(fileId);

              try {
                // Wait for data to become available, timeout, or client disconnect
                final waitResult = await Future.any([
                  completer.future
                      .timeout(
                        timeout,
                        onTimeout: () {
                          // Timeout - clean up and fall through
                          _byteAvailabilityWaiters[fileId]?.removeWhere(
                            (e) => e.value == completer,
                          );
                          if (_byteAvailabilityWaiters[fileId]?.isEmpty ??
                              false) {
                            _byteAvailabilityWaiters.remove(fileId);
                          }
                        },
                      )
                      .then((_) => false),
                  disconnectCompleter.future,
                ]);

                if (waitResult == true) {
                  _debugLog(
                    'Proxy: Client disconnected during wait ($fileId).',
                  );
                  _byteAvailabilityWaiters[fileId]?.removeWhere(
                    (e) => e.value == completer,
                  );
                  break;
                }

                // Check if aborted during wait
                if (_abortedRequests.contains(fileId)) {
                  _debugLog('Proxy: Wait aborted for $fileId');
                  break;
                }
              } catch (_) {
                // Timeout or error - continue loop to retry
              } finally {
                // Clear waiting offset (this connection is no longer blocked)
                // Don't cancel the per-file timer - other connections may need it
                _getOrCreateState(fileId).waitingForOffset = null;
              }

              // CIRCUIT BREAKER: Break out if stall timer detected terminal error
              {
                final ls = _getOrCreateState(fileId).loadState;
                if (ls == FileLoadState.error ||
                    ls == FileLoadState.timeout ||
                    ls == FileLoadState.unsupported) {
                  _debugLog(
                    'Proxy: Breaking stream loop - file $fileId in terminal state: $ls',
                  );
                  break;
                }
              }

              // FIX F: MOOV gap timeout - detectar conexiones atrapadas en gap inllenable
              if (_getOrCreateState(fileId).isMoovAtEnd) {
                final gapRanges = _downloadedRanges[fileId];
                if (gapRanges != null &&
                    gapRanges.availableBytesFrom(currentReadOffset) == 0) {
                  moovGapConsecutiveTimeouts++;
                  if (moovGapConsecutiveTimeouts >= moovGapMaxTimeouts) {
                    _debugLog(
                      'Proxy: MOOV gap timeout at $currentReadOffset for $fileId '
                      '($moovGapConsecutiveTimeouts timeouts) - breaking wait',
                    );
                    break;
                  }
                } else {
                  moovGapConsecutiveTimeouts = 0;
                }
              }
            }
          }

          // DIAG: Log when streaming loop exits normally
          if (remainingToSend <= 0) {
            _debugLog(
              'Proxy: Stream loop COMPLETED normally for $fileId '
              '(served ${contentLength ~/ 1024}KB from offset $start)',
            );
          } else {
            _debugLog(
              'Proxy: Stream loop EXITED EARLY for $fileId '
              '(served ${(contentLength - remainingToSend) ~/ 1024}KB of '
              '${contentLength ~/ 1024}KB, readOffset: $currentReadOffset)',
            );
          }
        } catch (e) {
          if (e is! SocketException && e is! HttpException) {
            _debugLog('Proxy: Error streaming $fileId: $e');
          } else {
            _debugLog(
              'Proxy: Stream connection closed for $fileId at offset '
              '$start (${e.runtimeType})',
            );
          }
        } finally {
          await raf?.close();
          // Note: offset tracking and connection count cleanup is done
          // in the outer finally block to avoid double-decrement.
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
        try {
          if (!_abortedRequests.contains(fileId)) {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          }
        } catch (_) {}
      } finally {
        // Clean up this request's offset tracking
        _activeHttpRequestOffsets[fileId]?.remove(start);
        if (_activeHttpRequestOffsets[fileId]?.isEmpty == true) {
          _activeHttpRequestOffsets.remove(fileId);
        }
        // FIX O3: If this connection was pre-decremented during eviction, skip
        if (_connectionsSkipDecrement[fileId]?.remove(start) == true) {
          if (_connectionsSkipDecrement[fileId]?.isEmpty == true) {
            _connectionsSkipDecrement.remove(fileId);
          }
        } else {
          // Decrement connection count exactly once per request
          final remaining = (_activeConnectionCount[fileId] ?? 1) - 1;
          if (remaining <= 0) {
            _activeConnectionCount.remove(fileId);
          } else {
            _activeConnectionCount[fileId] = remaining;
          }
        }
      }
    } catch (e) {
      _debugLog('Proxy: Fatal error in _handleRequest setup: $e');
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
        // Scaled: 70MB→3.5MB, 500MB+→5MB
        final minUsableData = ProxyConfig.scaled(
          totalSize,
          ProxyConfig.cacheEdgeProximityPercent,
          ProxyConfig.cacheEdgeProximityMinBytes,
          ProxyConfig.cacheEdgeProximityMaxBytes,
        );
        // FIX P: Never delete a file that has active connections serving it.
        // TDLib can report transient states (downloading: false, small prefix)
        // during seeks/track switches, which would falsely trigger stale detection
        // and destroy gigabytes of already-downloaded data.
        final hasActiveConnections = (_activeConnectionCount[fileId] ?? 0) > 0;
        final isStaleWithLittleData =
            path.isNotEmpty &&
            !isCompleted &&
            !isDownloadingActive &&
            !hasActiveConnections &&
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
          _downloadedRanges.remove(fileId);

          // Wait a bit for TDLib to process
          await Future.delayed(
            const Duration(milliseconds: ProxyConfig.tdlibStaleCleanupDelayMs),
          );

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
        if (totalSize > ProxyConfig.moovDetectionMinFileSize && !isCompleted) {
          Future.delayed(
            const Duration(milliseconds: ProxyConfig.moovDetectScheduleDelayMs),
            () {
              if (!_abortedRequests.contains(fileId)) {
                _detectMoovPosition(fileId, totalSize).then((position) {
                  // P1: Descarga proactiva si se detecta MOOV al final
                  if (position == MoovPosition.end &&
                      !_abortedRequests.contains(fileId)) {
                    _startProactiveMoovDownload(fileId, totalSize);
                  }
                });
              }
            },
          );
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
          const maxAttempts = ProxyConfig.fetchMaxAttempts;

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
                const Duration(milliseconds: ProxyConfig.fetchWaitIntervalMs),
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
    bool forceRestart = false,
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

    // FIX H: No redirigir TDLib al gap MOOV inllenable.
    // Si el offset está en el gap entre el frontier de descarga y la región MOOV,
    // enviar downloadFile aquí mata la descarga secuencial principal sin beneficio.
    if (_isInMoovGap(fileId, requestedOffset)) {
      _logTrace(
        'Ignoring download request in MOOV gap at $requestedOffset for $fileId',
        fileId: fileId,
      );
      return;
    }

    // Proportional thresholds for correct small-file behavior
    final localSeekThreshold = ProxyConfig.scaled(
      totalSize,
      ProxyConfig.seekDetectionThresholdPercent,
      ProxyConfig.seekDetectionMinBytes,
      ProxyConfig.seekDetectionMaxBytes,
    );
    final sequentialWindow = ProxyConfig.scaled(
      totalSize,
      ProxyConfig.sequentialReadThresholdPercent,
      ProxyConfig.sequentialReadMinBytes,
      ProxyConfig.sequentialReadMaxBytes,
    );

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
          ? min(neededSize, ProxyConfig.moovDownloadMaxBytes)
          : ProxyConfig.scaled(
              totalSize,
              ProxyConfig.moovPreloadThresholdPercent,
              ProxyConfig.moovPreloadMinBytes,
              ProxyConfig.moovPreloadMaxBytes,
            ); // Scaled default when total size unknown

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
        lastServed >
        ProxyConfig.scaled(
          totalSize,
          ProxyConfig.activePlaybackThresholdPercent,
          ProxyConfig.activePlaybackMinBytes,
          ProxyConfig.activePlaybackMaxBytes,
        );

    final debounceLastSeek = _getOrCreateState(fileId).lastSeekTime;
    final debounceNow = DateTime.now();
    final isRapidSeek =
        isActivePlayback &&
        debounceLastSeek != null &&
        debounceNow.difference(debounceLastSeek).inMilliseconds <
            ProxyConfig.seekDebounceMs;

    // Check if there's already a pending debounced seek - if so, let it handle this
    if (isActivePlayback && _pendingSeekOffsets.containsKey(fileId)) {
      // Update the pending offset to the latest request
      _handleDebouncedSeek(fileId, requestedOffset);
      return;
    }

    // If this is a rapid seek (second+ seek within 500ms), use debounce
    if (isRapidSeek) {
      _logTrace(
        'Rapid seek detected for $fileId, debouncing to ${requestedOffset ~/ 1024}KB',
        fileId: fileId,
      );
      _handleDebouncedSeek(fileId, requestedOffset);
      return;
    }

    // Check if we're already downloading from this offset (or very close)
    final currentActiveOffset = _getOrCreateState(fileId).activeDownloadOffset;
    final currentDownloadOffset = cached?.downloadOffset ?? 0;
    final currentPrefix = cached?.downloadedPrefixSize ?? 0;

    // UNIGRAM PATTERN: Check if data is already available at the requested offset.
    // Uses getFileDownloadedPrefixSize which checks ALL downloaded ranges in TDLib's
    // temp file, not just the current downloadOffset+prefix range. This is critical
    // for MOOV-at-end files where data at earlier offsets persists after TDLib
    // switches to download the MOOV at the end.
    final availableAtOffset = await _getDownloadedPrefixSize(
      fileId,
      requestedOffset,
    );
    if (availableAtOffset > 0) {
      return;
    }

    // RATE LIMITER: Prevent flooding TDLib with downloadFile calls.
    // Multiple HTTP connections and stall timers can independently call this
    // method, generating cascading TDLib events that overflow the Windows
    // message queue. Max 1 downloadFile call per file per second.
    {
      final fs = _getOrCreateState(fileId);
      final lastCall = fs.lastDownloadFileCallTime;
      // SKIP RATE LIMIT for blocking requests (e.g. initial load or stall recovery)
      if (lastCall != null && !isBlocking && !forceRestart) {
        final elapsed = DateTime.now().difference(lastCall).inMilliseconds;
        if (elapsed < ProxyConfig.minDownloadCallIntervalMs) {
          _logTrace(
            'Rate limited downloadFile for $fileId '
            '(${elapsed}ms since last call)',
            fileId: fileId,
          );
          return;
        }
      }
    }

    // RESUME FIX: Cache-gap detection
    // When resuming far ahead, we need to fill the gap from cache edge first.
    // Otherwise the player stalls waiting for data that never comes.
    // Detect: requestedOffset is way ahead of cached data (>50MB gap)
    final cacheEnd = currentDownloadOffset + currentPrefix;
    final gapFromCache = requestedOffset - cacheEnd;
    final localSignificantJump = ProxyConfig.scaled(
      totalSize,
      ProxyConfig.significantJumpThresholdPercent,
      ProxyConfig.significantJumpMinBytes,
      ProxyConfig.significantJumpMaxBytes,
    );
    if (gapFromCache > localSignificantJump && cacheEnd > 0 && !isBlocking) {
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
    // Scaled: 70MB→3.5MB, 500MB+→5MB
    final downloadFrontier = currentDownloadOffset + currentPrefix;
    final distanceFromFrontier = requestedOffset - downloadFrontier;
    final isDownloading = cached?.isDownloadingActive ?? false;
    final frontierProximity = ProxyConfig.scaled(
      totalSize,
      ProxyConfig.frontierProximityThresholdPercent,
      ProxyConfig.frontierProximityMinBytes,
      ProxyConfig.frontierProximityMaxBytes,
    );

    // CRITICAL: Don't cancel a download that's at or near the frontier.
    // TDLib may briefly report isDownloadingActive=false between chunks,
    // causing a spurious downloadFile that cancels the ongoing sequential
    // download. Use a time-based guard: if download started recently (<10s),
    // trust that TDLib is still producing data even if isDownloadingActive
    // is momentarily false.
    final recentDownload = _getOrCreateState(
      fileId,
    ).isRecentDownload(const Duration(seconds: 10));
    final atFrontier =
        distanceFromFrontier >= 0 && distanceFromFrontier < frontierProximity;

    if (!forceRestart && atFrontier && (isDownloading || recentDownload)) {
      // Current download will reach our offset soon, don't restart
      return;
    }

    // Check if already targeting this offset
    // CRITICAL STALL FIX: Only return if download is ACTUALLY active in TDLib.
    // If we think we are downloading X, but TDLib stopped (isDownloadingActive=false),
    // we MUST fall through to restart the download. Also bypass if forcing restart.
    final isDownloadingCached = cached?.isDownloadingActive ?? false;
    if (!forceRestart &&
        currentActiveOffset == requestedOffset &&
        isDownloadingCached) {
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
      final moovThresholdBytes = ProxyConfig.scaled(
        fileSize,
        ProxyConfig.moovRegionThresholdPercent,
        ProxyConfig.moovRegionMinBytes,
        ProxyConfig.moovRegionMaxBytes,
      );

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

    // NOTE: POST-SEEK BLOCK has been DISABLED after testing showed it was
    // blocking legitimate resume requests and causing videos to not start.
    // The general cooldown (500-1000ms) and distance threshold (2-5MB) provide
    // sufficient protection against rapid offset changes.

    // Determine if this is a Seek Request (jump > 1MB from last served offset)
    bool isSeekRequest = false;
    final lastServedForCheck = _getOrCreateState(fileId).lastServedOffset;
    if (lastServedForCheck != null) {
      final jump = (requestedOffset - lastServedForCheck).abs();
      if (jump > localSeekThreshold) {
        isSeekRequest = true;
      }
    }

    // PARTSMANAGER FIX: Increased cooldown to prevent TDLib crashes
    // TDLib's PartsManager can crash if offset changes happen too rapidly
    final lastChange = _getOrCreateState(fileId).lastOffsetChangeTime;
    final isSequentialRead =
        requestedOffset > activeDownloadTarget &&
        distanceFromCurrent < sequentialWindow; // Within sequential window

    // PHASE1 OPTIMIZATION: Reduced cooldown for faster seek response
    // TDLib handles rapid changes better than previously assumed
    final cooldownMs = isSequentialRead
        ? ProxyConfig.cooldownSequentialMs
        : ProxyConfig.cooldownNonSequentialMs;

    if (lastChange != null) {
      final timeSinceLastChange = now.difference(lastChange).inMilliseconds;
      // PHASE1 OPTIMIZATION: Reduced distance threshold for more responsive seeks
      final minDistance = isSequentialRead
          ? ProxyConfig.minDistanceSequentialBytes
          : ProxyConfig.minDistanceNonSequentialBytes;

      // DEADLOCK PREVENTION:
      // If we think we are downloading at offset X, but cache says we are inactive
      // or at a totally different offset (e.g. Moov), then our "active" status is phantom.
      // We should not let this phantom status block new requests.
      bool isEffectiveActive = true;
      if (timeSinceLastChange > ProxyConfig.deadlockCheckMs) {
        // Only check after 1s to allow initial setup
        if (cached == null ||
            (!cached.isDownloadingActive && !cached.isCompleted)) {
          // Not active according to TDLib (and not complete) triggers reset
          isEffectiveActive = false;
        } else if ((cached.downloadOffset - activeDownloadTarget).abs() >
            sequentialWindow) {
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
            (totalSize * ProxyConfig.moovDownloadThresholdPercent)
                .round()
                .clamp(
                  ProxyConfig.moovRegionMinBytes,
                  ProxyConfig.moovDownloadRegionMaxBytes,
                );

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
        // Scaled thresholds for priority allow rules
        // 70MB: forward=56MB(80%), backward=35MB(50%), early=35MB(50%)
        // 500MB+: forward=500MB, backward=100MB, early=300MB (sin cambio)
        final maxForwardBuffer = ProxyConfig.scaled(
          totalSize,
          ProxyConfig.maxForwardBufferPercent,
          ProxyConfig.maxForwardBufferMinBytes,
          ProxyConfig.maxForwardBufferMaxBytes,
        );
        final maxBackwardOverlap = ProxyConfig.scaled(
          totalSize,
          ProxyConfig.maxBackwardOverlapPercent,
          ProxyConfig.maxBackwardOverlapMinBytes,
          ProxyConfig.maxBackwardOverlapMaxBytes,
        );
        final earlyFileThreshold = ProxyConfig.scaled(
          totalSize,
          ProxyConfig.earlyFileThresholdPercent,
          ProxyConfig.earlyFileThresholdMinBytes,
          ProxyConfig.earlyFileThresholdMaxBytes,
        );
        final cacheEdgeProximity = ProxyConfig.scaled(
          totalSize,
          ProxyConfig.cacheEdgeProximityPercent,
          ProxyConfig.cacheEdgeProximityMinBytes,
          ProxyConfig.cacheEdgeProximityMaxBytes,
        );
        if (dist >= 0 && dist < maxForwardBuffer) {
          shouldForcePriority = true; // Normal forward playback buffer
        } else if (dist < 0 && dist.abs() < maxBackwardOverlap) {
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
            if (distToCacheEnd < cacheEdgeProximity) {
              // Request is near cache edge - this is buffering continuation
              _logTrace(
                'CACHE EDGE ALLOWED for $requestedOffset (CacheEnd: $cacheEnd, Dist: ${distToCacheEnd ~/ 1024}KB)',
                fileId: fileId,
              );
              shouldForcePriority = true;
            } else if (requestedOffset < earlyFileThreshold) {
              // If request is for early part of file, it's likely trying
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
        now.difference(lastStart).inMilliseconds <
            ProxyConfig.rapidSwitchDebounceMs &&
        !isBlocking &&
        !isSeekRequest) {
      final activeOffset = _getOrCreateState(fileId).activeDownloadOffset ?? -1;
      // Allow if sequential (reading forward within 2MB)
      if (requestedOffset >= activeOffset &&
          requestedOffset < activeOffset + sequentialWindow) {
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
        !forceRestart &&
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

    // Start download at exactly the offset the player requested
    _logTrace(
      'Downloading from offset $requestedOffset for $fileId '
      '(priority: $priority, limit: unlimited)',
      fileId: fileId,
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

    // Use limit=0 (unlimited) so TDLib downloads continuously from offset
    // to EOF. A finite limit causes stop-start patterns (TDLib stops every
    // N bytes, proxy must re-request) and premature cancellation of MOOV
    // downloads when new requests arrive for other offsets.
    const int downloadLimit = 0;

    // Record call time for rate limiter before sending
    _getOrCreateState(fileId).lastDownloadFileCallTime = DateTime.now();

    // FORCE RESTART FIX: If TDLib is stuck but still considers the file
    // actively downloading, sending a duplicate downloadFile command is a NO-OP.
    // We must forcibly cancel the active download first to genuinely restart it.
    if (forceRestart) {
      _logTrace(
        'Processing force restart for $fileId: sending cancelDownloadFile first',
        fileId: fileId,
      );
      TelegramService().send({
        '@type': 'cancelDownloadFile',
        'file_id': fileId,
        'only_if_pending': false,
      });
      // Retardo configurable para que TDLib procese la cancelación vía FFI.
      // 50ms era insuficiente en Windows; 200ms da margen al message queue.
      await Future.delayed(
        const Duration(milliseconds: ProxyConfig.cancelToDownloadDelayMs),
      );

      // Verificar si la cancelación fue procesada; si no, reintentar
      final cachedAfterCancel = _filePaths[fileId];
      if (cachedAfterCancel != null && cachedAfterCancel.isDownloadingActive) {
        _logTrace(
          'Cancelación no confirmada para $fileId después de '
          '${ProxyConfig.cancelToDownloadDelayMs}ms, enviando segundo cancel',
          fileId: fileId,
        );
        TelegramService().send({
          '@type': 'cancelDownloadFile',
          'file_id': fileId,
          'only_if_pending': false,
        });
        await Future.delayed(
          const Duration(milliseconds: ProxyConfig.cancelRetryDelayMs),
        );
      }
    }

    TelegramService().send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': priority,
      'offset': requestedOffset,
      'limit': downloadLimit,
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

  // NOTE: Read-ahead feature was removed because TDLib cancels ongoing downloads
  // when a new downloadFile call is made for the same file_id with a different offset.
  // This limitation makes proactive read-ahead counterproductive.

  // ============================================================
  // MOOV PRE-DETECTION AND POST-SEEK PRELOAD
  // ============================================================

  /// Tracks files that have already had early detection triggered
  final Set<int> _earlyMoovDetectionTriggered = {};

  // ============================================================
  // FILE OPEN WITH RETRY (Windows file locking protection)
  // ============================================================

  /// Opens a file for reading with exponential backoff retry.
  /// TDLib may hold a write lock on the file while downloading on Windows,
  /// causing sporadic FileSystemException. This helper retries with backoff
  /// (50ms, 100ms, 200ms, 400ms, 800ms) before giving up.
  /// Returns null if the file cannot be opened after all attempts.
  Future<RandomAccessFile?> _openFileWithRetry(File file, [int? fileId]) async {
    const maxRetries = ProxyConfig.fileOpenMaxRetries;
    FileSystemException? lastError;

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await file.open(mode: FileMode.read);
      } on FileSystemException catch (e) {
        lastError = e;
        if (attempt < maxRetries - 1) {
          final delayMs = ProxyConfig.fileOpenRetryBaseMs * (1 << attempt);
          _debugLog(
            'Proxy: File locked${fileId != null ? ' ($fileId)' : ''}, '
            'retrying in ${delayMs}ms '
            '(attempt ${attempt + 1}/$maxRetries): ${e.message}',
          );
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
    }

    _debugLog(
      'Proxy: Failed to open file${fileId != null ? ' ($fileId)' : ''} '
      'after $maxRetries attempts: ${lastError?.message}',
    );
    return null;
  }

  // ============================================================
  // ADAPTIVE TIMEOUT
  // ============================================================

  /// Calculates an adaptive timeout that grows with retry count.
  /// MOOV requests always use the fixed moovDataTimeout.
  /// Normal requests start at 8s and grow up to 30s via exponential backoff.
  Duration _getAdaptiveTimeout(int fileId, bool isMoovRequest) {
    if (isMoovRequest) return ProxyConfig.moovDataTimeout;
    final attempts = _retryTracker.totalAttempts(fileId);
    final baseMs = ProxyConfig.normalDataTimeoutInitial.inMilliseconds;
    final maxMs = ProxyConfig.normalDataTimeoutMax.inMilliseconds;
    final backoffMs =
        (baseMs * pow(ProxyConfig.timeoutBackoffMultiplier, attempts))
            .round()
            .clamp(baseMs, maxMs);
    return Duration(milliseconds: backoffMs);
  }

  // ============================================================
  // PER-FILE STALL TIMER
  // ============================================================

  /// Ensure exactly ONE stall timer exists per file.
  /// Multiple HTTP connections share this timer instead of creating their own.
  void _ensureStallTimer(int fileId) {
    if (_perFileStallTimers.containsKey(fileId)) return;
    _perFileStallTimers[fileId] = Timer.periodic(
      ProxyConfig.stallCheckInterval,
      (_) => _checkStallForFile(fileId),
    );
  }

  /// Cancel and remove the stall timer for a file.
  void _cancelStallTimer(int fileId) {
    _perFileStallTimers[fileId]?.cancel();
    _perFileStallTimers.remove(fileId);
  }

  /// Centralized stall check for a file. Called by the per-file stall timer.
  /// Uses [ProxyFileState.waitingForOffset] for the target offset.
  void _checkStallForFile(int fileId) {
    final state = _getOrCreateState(fileId);

    // If no connection is waiting, nothing to check
    final waitingOffset = state.waitingForOffset;
    if (waitingOffset == null) return;

    // If file is in terminal state, cancel timer
    if (state.loadState == FileLoadState.error ||
        state.loadState == FileLoadState.timeout ||
        state.loadState == FileLoadState.unsupported) {
      _cancelStallTimer(fileId);
      return;
    }

    // COORDINACIÓN CON SEEK DEBOUNCE: Si hay un seek pendiente por ejecutar,
    // no interferir — el debounce se encargará de reiniciar la descarga.
    if (_pendingSeekOffsets.containsKey(fileId)) return;

    // Si un seek debounced se ejecutó recientemente, dar tiempo a TDLib
    // para procesar la nueva descarga antes de declarar stall.
    final lastDebounced = state.lastDebouncedSeekTime;
    if (lastDebounced != null &&
        DateTime.now().difference(lastDebounced) < const Duration(seconds: 3)) {
      return;
    }

    // MOOV PROTECTION
    if (state.forcedMoovOffset != null) return;

    // INITIALIZATION GRACE PERIOD
    if (state.isWithinGracePeriod(_initializationGracePeriod)) return;

    final updatedCache = _filePaths[fileId];
    if (updatedCache == null) return;

    // DOWNLOAD COOLDOWN PROTECTION (diferenciado según contexto)
    // Post-seek: cooldown reducido (2s) para recuperación rápida de fallos.
    // Normal: cooldown estándar (5s) para evitar reinicios innecesarios.
    final isPostSeek = state.lastSeekTime != null &&
        DateTime.now().difference(state.lastSeekTime!) <
            const Duration(seconds: 10);
    final stallCooldown = isPostSeek
        ? Duration(milliseconds: ProxyConfig.stallCooldownPostSeekMs)
        : Duration(milliseconds: ProxyConfig.stallCooldownNormalMs);
    if (state.isRecentDownload(stallCooldown)) return;

    // ACTIVE DOWNLOAD PROTECTION
    // REMOVED early return. We must analyze progress because TDLib might
    // report isDownloadingActive=true even if the connection dropped/stalled
    // silently and no bytes are flowing.
    if (updatedCache.isDownloadingActive) {
      final activeOffset = state.activeDownloadOffset;
      if (activeOffset != null && activeOffset != waitingOffset) {
        _logTrace(
          'Stall timer - download active at different offset '
          '($activeOffset vs waiting for $waitingOffset), analyzing progress anyway...',
          fileId: fileId,
        );
      }
    }

    final currentPrefix = updatedCache.downloadedPrefixSize;
    final currentOffset = updatedCache.downloadOffset;
    final lastOffset = _lastStallCheckOffset[fileId];
    _lastStallCheckOffset[fileId] = currentOffset;

    // HIGH WATER MARK
    final currentFrontier = currentOffset + currentPrefix;
    final prevHighWater = _downloadHighWaterMark[fileId] ?? 0;
    final newHighWater = currentFrontier > prevHighWater
        ? currentFrontier
        : prevHighWater;
    _downloadHighWaterMark[fileId] = newHighWater;

    // CHECK 1: Offset changed → TDLib switching streams
    if (lastOffset != null && currentOffset != lastOffset) {
      _logTrace(
        'Stall timer - TDLib offset changed ($lastOffset -> $currentOffset), not a stall',
        fileId: fileId,
      );
      _lastDownloadProgress[fileId] = currentPrefix;
      return;
    }

    // CHECK 2: Frontier advanced
    if (newHighWater > prevHighWater) {
      _lastDownloadProgress[fileId] = currentPrefix;
      return;
    }

    // CHECK 3: Prefix grew
    final lastPrefix = _lastDownloadProgress[fileId] ?? 0;
    if (currentPrefix > lastPrefix) {
      _lastDownloadProgress[fileId] = currentPrefix;
      return;
    }

    // FIX N: BUFFER-AHEAD PROTECTION
    // If the download frontier is significantly ahead of the primary playback
    // offset, TDLib's download pause is harmless — the player has plenty of
    // buffered data. Restarting the download now would be counterproductive:
    // cancelDownloadFile + downloadFile creates gaps (TDLib aligns to chunk
    // boundaries), triggers offset redirections from other HTTP connections,
    // and can cascade into download disruptions that starve the player.
    final primaryOffset = state.primaryPlaybackOffset ?? 0;
    final bufferAhead = newHighWater - primaryOffset;
    if (bufferAhead > ProxyConfig.stallBufferAheadBytes) {
      _logTrace(
        'Stall timer - BUFFER AHEAD PROTECTION for $fileId: '
        'frontier ${newHighWater ~/ (1024 * 1024)}MB is '
        '${bufferAhead ~/ (1024 * 1024)}MB ahead of playback '
        '${primaryOffset ~/ (1024 * 1024)}MB (threshold: '
        '${ProxyConfig.stallBufferAheadBytes ~/ (1024 * 1024)}MB). '
        'Not restarting download.',
        fileId: fileId,
      );
      _lastDownloadProgress[fileId] = currentPrefix;
      return;
    }

    // DEBOUNCE
    final now = DateTime.now();
    final lastStallTime = _lastStallRecordedTime[fileId];
    if (lastStallTime != null &&
        now.difference(lastStallTime) < ProxyConfig.stallCheckInterval) {
      return;
    }

    // TRUE STALL detected

    // PROTECCIÓN MOOV-AT-END GAP: Cuando el archivo tiene MOOV al final y el
    // download principal ya cubrió >90% del archivo, queda un gap pequeño entre
    // el frontier y la región MOOV (ya descargada). El prefetch intenta llenar
    // ese gap pero compite con el stall timer por el mismo file_id en TDLib,
    // causando cancelaciones mutuas que se acumulan falsamente como stalls.
    // No contar stalls en este escenario — el gap se llenará eventualmente.
    final totalFileSize = updatedCache.totalSize;
    if (totalFileSize > 0 && state.isMoovAtEnd) {
      final mainDownloadProgress = newHighWater.toDouble() / totalFileSize;
      if (mainDownloadProgress > 0.90) {
        // FIX E: NO hacer forceRestart si TDLib ya está descargando activamente.
        // El forceRestart cancela la descarga en curso, creando un ciclo
        // cancel-restart cada 5s que impide a TDLib completar el gap pequeño
        // (~440KB) entre el frontier principal y la región MOOV.
        if (updatedCache.isDownloadingActive) {
          _logTrace(
            'Stall timer - MOOV-at-end file $fileId, ${(mainDownloadProgress * 100).toStringAsFixed(1)}% descargado, '
            'TDLib activo - NO reiniciar (dejar que complete el gap)',
            fileId: fileId,
          );
        } else {
          _logTrace(
            'Stall timer - MOOV-at-end file $fileId, ${(mainDownloadProgress * 100).toStringAsFixed(1)}% descargado, '
            'TDLib idle - reiniciando descarga en gap MOOV',
            fileId: fileId,
          );
          _startDownloadAtOffset(fileId, waitingOffset, forceRestart: true);
        }
        return;
      }
    }

    // NEAR-EOF PROTECTION
    if (totalFileSize > 0) {
      final remainingBytes = totalFileSize - newHighWater;
      // Threshold mayor para MOOV-at-end: el gap MOOV puede ser >5MB
      final nearEofThreshold = state.isMoovAtEnd
          ? ProxyConfig.scaled(totalFileSize, 0.05, 5 * 1024 * 1024, 20 * 1024 * 1024)
          : ProxyConfig.scaled(totalFileSize, 0.05, 1 * 1024 * 1024, 5 * 1024 * 1024);
      if (remainingBytes >= 0 && remainingBytes < nearEofThreshold) {
        _logTrace(
          'Stall timer - file $fileId near EOF '
          '(${remainingBytes ~/ 1024}KB remaining), '
          'restarting download without counting stall',
          fileId: fileId,
        );
        _startDownloadAtOffset(fileId, waitingOffset, forceRestart: true);
        return;
      }
    }

    _lastStallRecordedTime[fileId] = now;

    // ADAPTIVE RETRY COUNT: Adjust max retries based on network speed.
    // Fast networks get fewer retries (fail fast), slow networks get more (be patient).
    final metrics = _downloadMetrics[fileId];
    final adaptiveMaxRetries = metrics != null
        ? (metrics.isFastNetwork
              ? ProxyConfig.retryMinCount
              : metrics.isSlowNetwork
              ? ProxyConfig.retryMaxCount
              : ProxyConfig.retryDefaultCount)
        : ProxyConfig.retryDefaultCount;
    _retryTracker.setMaxRetries(fileId, adaptiveMaxRetries);

    if (!_retryTracker.canRetry(fileId)) {
      // Max retries exceeded - transition to recoverable error state
      final attempts = _retryTracker.totalAttempts(fileId);
      final error = StreamingError.maxRetries(fileId, attempts);
      final wasNotified = _notifyErrorIfNew(fileId, error);
      _cancelStallTimer(fileId);
      if (wasNotified) {
        _debugLog(
          'Proxy: MAX RETRIES EXCEEDED for $fileId after $attempts attempts '
          '(max: $adaptiveMaxRetries)',
        );
      }
      return;
    }

    // Record retry attempt
    _retryTracker.recordRetry(fileId);
    final remaining = _retryTracker.remainingRetries(fileId);

    if (metrics != null) {
      metrics.recordStall();
      _debugLog(
        'Proxy: P2 STALL RECORDED for $fileId '
        '(stalls: ${metrics.recentStallCount}, retries remaining: $remaining, '
        'max: $adaptiveMaxRetries, frontier: ${newHighWater ~/ 1024}KB)',
      );
    }

    // BACKOFF DELAY: Wait before retrying to avoid hammering TDLib.
    // Uses exponential backoff: 1s, 2s, 4s, 8s... capped at 15s.
    final backoff = _retryTracker.getBackoffDelay(
      fileId,
      baseMs: ProxyConfig.retryBackoffBaseMs,
      maxMs: ProxyConfig.retryBackoffMaxMs,
      multiplier: ProxyConfig.retryBackoffMultiplier,
    );
    if (backoff.inMilliseconds > 0) {
      _debugLog(
        'Proxy: Backoff ${backoff.inMilliseconds}ms before retry for $fileId',
      );
      Timer(backoff, () {
        // Re-check state after backoff - file may have been aborted or recovered
        final currentState = _getOrCreateState(fileId);
        if (currentState.loadState == FileLoadState.error ||
            currentState.loadState == FileLoadState.timeout ||
            currentState.loadState == FileLoadState.unsupported) {
          return;
        }
        if (_abortedRequests.contains(fileId)) return;
        _startDownloadAtOffset(fileId, waitingOffset, forceRestart: true);
      });
    } else {
      _startDownloadAtOffset(fileId, waitingOffset, forceRestart: true);
    }
    _lastDownloadProgress[fileId] = currentPrefix;
  }

  /// P1: Inicia descarga proactiva del MOOV atom desde el final del archivo.
  /// Se activa tan pronto como se detecta MOOV-at-end, sin esperar a que el
  /// player lo descubra. Usa forcedMoovOffset para bloquear otras descargas
  /// hasta que MOOV termine. Los bytes ya descargados desde offset 0 se
  /// preservan vía DownloadedRanges (P2).
  void _startProactiveMoovDownload(int fileId, int totalSize) {
    // Evitar descarga duplicada (forcedMoovOffset activo o ya completada)
    final state = _getOrCreateState(fileId);
    if (state.forcedMoovOffset != null) return;
    if (state.loadState == FileLoadState.moovReady ||
        state.loadState == FileLoadState.playing) {
      return;
    }
    if (totalSize <= 0) return;
    if (_abortedRequests.contains(fileId)) return;

    // Calcular offset estimado del MOOV usando constantes existentes
    final moovPreloadBytes = ProxyConfig.scaled(
      totalSize,
      ProxyConfig.moovPreloadThresholdPercent,
      ProxyConfig.moovPreloadMinBytes,
      ProxyConfig.moovPreloadMaxBytes,
    );
    final moovOffset = totalSize - moovPreloadBytes;

    // Activar lock: bloquea otras descargas hasta que MOOV termine
    _getOrCreateState(fileId).forcedMoovOffset = moovOffset;
    _getOrCreateState(fileId).loadState = FileLoadState.loadingMoov;

    _debugLog(
      'Proxy: P1 PROACTIVE MOOV - Starting download at offset $moovOffset '
      '(last ${moovPreloadBytes ~/ 1024}KB) for file $fileId',
    );

    // Iniciar descarga - cancela la descarga secuencial desde 0
    _startDownloadAtOffset(fileId, moovOffset);
  }

  /// Triggers early MOOV detection when sufficient bytes arrive.
  /// This is called from _onUpdate to detect moov position as early as possible.
  /// - For moov-at-start: Detection happens as soon as 1KB is downloaded
  /// - For moov-at-end: Detection triggers after 5MB without finding moov
  void _triggerEarlyMoovDetection(int fileId, ProxyFileInfo info) {
    // Skip if already detected or triggered
    if (_getOrCreateState(fileId).moovPosition != null) return;
    if (info.totalSize < ProxyConfig.moovDetectionMinFileSize) {
      return; // Skip small files
    }

    final prefix = info.downloadedPrefixSize;

    // Stage 1: Try to detect moov at start (need ~1KB)
    if (prefix >= ProxyConfig.moovDetectionMinPrefix &&
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
          // P1: Descarga proactiva del MOOV atom
          _startProactiveMoovDownload(fileId, info.totalSize);
        }
        // MoovPosition.unknown means we need more data
      });
    }

    // Stage 2: Infer moov-at-end if we have substantial prefix without finding moov
    // GUARD: Skip inference if async detection (Stage 1) is still in progress
    // This prevents race condition where sync inference sets END before async finds START
    if (prefix >= ProxyConfig.moovAtEndInferenceThreshold &&
        _getOrCreateState(fileId).moovPosition == null &&
        !_earlyMoovDetectionTriggered.contains(fileId)) {
      // If we downloaded 5MB+ and async detection never started, infer END
      _getOrCreateState(fileId).moovPosition = MoovPosition.end;
      _getOrCreateState(fileId).isMoovAtEnd = true;
      _debugLog(
        'Proxy: EARLY DETECT - File $fileId inferred MOOV at END (${prefix ~/ (1024 * 1024)}MB downloaded)',
      );
      // P1: Descarga proactiva por inferencia
      _startProactiveMoovDownload(fileId, info.totalSize);
    }
  }

  /// Pre-detects the position of the MOOV atom by analyzing the first bytes of the file.
  /// Returns immediately if already cached.
  /// This detection does NOT start downloads - only analyzes already available data.
  /// Atoms that are known non-media containers; we walk past them looking for moov.
  static const _skipAtomTypes = {
    'ftyp',
    'free',
    'skip',
    'wide',
    'pdin',
    'uuid',
  };

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

      final raf = await _openFileWithRetry(file, fileId);
      if (raf == null) return MoovPosition.unknown;
      try {
        // Read first 4KB — enough to walk past ftyp + free/skip/wide atoms
        const headerSize = 4096;
        final availableBytes = cached.downloadedPrefixSize.clamp(0, totalSize);
        final readSize = availableBytes < headerSize
            ? availableBytes
            : headerSize;
        if (readSize < 8) return MoovPosition.unknown;

        final header = await raf.read(readSize);
        if (header.length < 8) return MoovPosition.unknown;

        // Walk top-level atoms within the buffer
        var offset = 0;
        while (offset + 8 <= header.length) {
          final atomSize = _readMoovUint32BE(header, offset);
          final atomType = String.fromCharCodes(
            header.sublist(offset + 4, offset + 8),
          );

          // moov found near start → streaming-optimized
          if (atomType == 'moov') {
            _getOrCreateState(fileId).moovPosition = MoovPosition.start;
            _debugLog(
              'Proxy: MOOV PRE-DETECT - File $fileId has MOOV at START (offset $offset)',
            );
            return MoovPosition.start;
          }

          // mdat before moov → moov is at end
          if (atomType == 'mdat') {
            _getOrCreateState(fileId).moovPosition = MoovPosition.end;
            _getOrCreateState(fileId).isMoovAtEnd = true;
            _debugLog(
              'Proxy: MOOV PRE-DETECT - File $fileId has MOOV at END (mdat found at offset $offset)',
            );
            return MoovPosition.end;
          }

          // Skip known non-media atoms and keep walking
          if (_skipAtomTypes.contains(atomType)) {
            if (atomSize < 8) break; // Malformed atom, stop
            offset += atomSize;
            continue;
          }

          // Unknown atom type — stop walking to avoid misinterpreting data
          break;
        }

        // Fallback: if we have enough downloaded data but no moov near start, infer end
        if (cached.downloadedPrefixSize >
                ProxyConfig.moovAtEndInferenceThreshold &&
            _getOrCreateState(fileId).moovPosition == null) {
          _getOrCreateState(fileId).moovPosition = MoovPosition.end;
          _getOrCreateState(fileId).isMoovAtEnd = true;
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
    final seekProximity = ProxyConfig.scaled(
      cached.totalSize,
      0.05,
      1 * 1024 * 1024,
      5 * 1024 * 1024,
    );
    if ((currentOffset - primaryOffset).abs() > seekProximity) return;

    // Calculate post-seek preload proportional to file size
    final postSeekPreload = ProxyConfig.scaled(
      cached.totalSize,
      0.05,
      ProxyConfig.postSeekPreloadMinBytes,
      ProxyConfig.postSeekPreloadMaxBytes,
    );
    final targetOffset = currentOffset + postSeekPreload;

    // Don't preload if we already have data there
    if (cached.availableBytesFrom(targetOffset) > 0) return;

    // Don't preload if we're near end of file
    if (cached.totalSize > 0 &&
        targetOffset >= cached.totalSize - postSeekPreload) {
      return;
    }

    _logTrace(
      'POST-SEEK PRELOAD for $fileId: ${currentOffset ~/ 1024}KB -> ${targetOffset ~/ 1024}KB',
    );

    // Trigger preload with high but not critical priority
    TelegramService().send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': DownloadPriority.highFloor, // High but below critical
      'offset': targetOffset,
      'limit': postSeekPreload,
      'synchronous': false,
    });
  }

  // ============================================================
  // PREFETCH BUFFER AHEAD OF PLAYBACK
  // ============================================================

  /// Evaluates whether prefetch downloading should be triggered for [fileId].
  ///
  /// Called when TDLib transitions to idle for this file, or periodically.
  /// Only acts if the file is in active playback, TDLib is idle, and
  /// the buffer ahead of playback is below the adaptive threshold.
  void _evaluatePrefetch(int fileId) {
    final state = _getOrCreateState(fileId);
    final cached = _filePaths[fileId];
    if (cached == null || cached.isCompleted) return;

    // Solo prefetch durante reproducción activa
    if (state.loadState != FileLoadState.playing &&
        state.loadState != FileLoadState.moovReady) {
      return;
    }

    // No prefetch si TDLib está descargando activamente
    if (cached.isDownloadingActive) return;

    // No prefetch durante descarga forzada de MOOV
    if (state.forcedMoovOffset != null) return;

    // Necesitamos posición de reproducción
    final playbackOffset = state.primaryPlaybackOffset;
    if (playbackOffset == null) return;

    final totalSize = cached.totalSize;
    if (totalSize <= 0) return;

    // No prefetch cerca del final del archivo
    if (playbackOffset >= totalSize - ProxyConfig.prefetchMinBytes) return;

    // Calcular target adaptativo basado en velocidad de red
    final bufferTarget = _calculatePrefetchTarget(fileId);

    // Verificar cuánto buffer hay adelante
    final ranges = _downloadedRanges[fileId];
    if (ranges == null) return;

    final availableAhead = ranges.availableBytesFrom(playbackOffset);

    // Si hay suficiente buffer, no hacer nada
    final triggerThreshold = (bufferTarget * ProxyConfig.prefetchTriggerRatio)
        .round();
    if (availableAhead >= triggerThreshold) {
      state.prefetchActive = false;
      return;
    }

    // Buscar gaps en la ventana de buffer target
    final lookAheadEnd = min(playbackOffset + bufferTarget, totalSize);
    final gaps = ranges.gaps(playbackOffset, lookAheadEnd);
    if (gaps.isEmpty) {
      state.prefetchActive = false;
      return;
    }

    // Buscar primer gap que valga la pena llenar
    for (final gap in gaps) {
      final gapSize = gap.end - gap.start;
      if (gapSize < ProxyConfig.prefetchMinGapBytes) continue;

      _debugLog(
        'Proxy: PREFETCH file $fileId: gap ${gap.start ~/ 1024}KB-${gap.end ~/ 1024}KB '
        '(buffer: ${availableAhead ~/ 1024}KB/${bufferTarget ~/ 1024}KB, '
        'playback: ${playbackOffset ~/ 1024}KB)',
      );

      state.prefetchActive = true;
      state.lastPrefetchEvalTime = DateTime.now();
      _startDownloadAtOffset(fileId, gap.start);
      return;
    }
  }

  /// Calcula target de prefetch adaptativo basado en velocidad de red.
  int _calculatePrefetchTarget(int fileId) {
    final metrics = _downloadMetrics[fileId];
    final speed = metrics?.bytesPerSecond ?? 0;

    if (speed <= 0) return ProxyConfig.prefetchDefaultBytes;

    final targetSeconds = (metrics!.isFastNetwork)
        ? ProxyConfig.prefetchSecondsFast
        : (metrics.isSlowNetwork)
        ? ProxyConfig.prefetchSecondsSlow
        : ProxyConfig.prefetchSecondsNormal;

    final speedBasedTarget = (speed * targetSeconds).round();
    return speedBasedTarget.clamp(
      ProxyConfig.prefetchMinBytes,
      ProxyConfig.prefetchMaxBytes,
    );
  }

  /// Programa evaluación de prefetch con debounce tras idle de TDLib.
  void _schedulePrefetchEval(int fileId) {
    _prefetchDebounceTimers[fileId]?.cancel();
    _prefetchDebounceTimers[fileId] = Timer(
      const Duration(milliseconds: ProxyConfig.prefetchDebounceMs),
      () {
        _prefetchDebounceTimers.remove(fileId);
        _evaluatePrefetch(fileId);
      },
    );
  }

  /// Asegura que existe un timer periódico de prefetch para [fileId].
  void _ensurePrefetchTimer(int fileId) {
    if (_prefetchPeriodicTimers.containsKey(fileId)) return;
    _prefetchPeriodicTimers[fileId] = Timer.periodic(
      const Duration(milliseconds: ProxyConfig.prefetchPeriodicCheckMs),
      (_) => _evaluatePrefetch(fileId),
    );
  }

  /// Cancela timers de prefetch para [fileId].
  void _cancelPrefetchTimer(int fileId) {
    _prefetchPeriodicTimers[fileId]?.cancel();
    _prefetchPeriodicTimers.remove(fileId);
    _prefetchDebounceTimers[fileId]?.cancel();
    _prefetchDebounceTimers.remove(fileId);
  }

  // ============================================================
  // SEEK PREVIEW PRELOADING
  // ============================================================

  // Cache for parsed MP4 sample tables
  final Map<int, Mp4SampleTable?> _sampleTableCache = {};

  // Track last preview time to avoid spamming
  final Map<int, DateTime> _lastPreviewTime = {};

  /// Preview seek target - start downloading at estimated offset with lower priority
  /// This is called during slider drag to preload data before user releases
  void previewSeekTarget(int fileId, int estimatedOffset) {
    final cached = _filePaths[fileId];
    if (cached == null || cached.isCompleted) return;

    // Check cooldown to avoid spamming TDLib during rapid dragging
    final now = DateTime.now();
    final lastPreview = _lastPreviewTime[fileId];
    if (lastPreview != null &&
        now.difference(lastPreview).inMilliseconds <
            ProxyConfig.previewCooldownMs) {
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
      'limit': ProxyConfig.previewPreloadBytes, // Preload around target
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

      final raf = await _openFileWithRetry(file, fileId);
      if (raf == null) {
        _sampleTableCache[fileId] = null;
        return;
      }
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

  /// FIX G: Detecta si un offset está en el gap inllenable entre el frontier
  /// principal de descarga y la región MOOV ya descargada al final del archivo.
  /// Retorna true si el offset está en dicho gap y no tiene datos disponibles.
  bool _isInMoovGap(int fileId, int offset) {
    final state = _getOrCreateState(fileId);
    if (!state.isMoovAtEnd) return false;

    final cached = _filePaths[fileId];
    if (cached == null) return false;
    final totalSize = cached.totalSize;
    if (totalSize <= 0) return false;

    // Solo aplica a offsets cercanos al final del archivo (último 5%)
    final nearEndThreshold = totalSize * 0.95;
    if (offset < nearEndThreshold) return false;

    final ranges = _downloadedRanges[fileId];
    if (ranges == null) return false;

    // No hay datos disponibles en el offset
    if (ranges.availableBytesFrom(offset) > 0) return false;

    // Verificar que hay datos descargados DESPUÉS del offset (la región MOOV)
    // Si el último byte del archivo está descargado, la MOOV ya está disponible
    if (!ranges.containsOffset(totalSize - 1)) return false;

    // Offset sin datos, cerca del final, MOOV disponible → estamos en el gap
    return true;
  }

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
          // FIX D: Invalidar seek debounced si el usuario ya movió la reproducción
          // a otro punto. Esto evita redirigir TDLib al gap MOOV cuando el usuario
          // ya hizo seeks hacia atrás.
          final primary = _getOrCreateState(fileId).primaryPlaybackOffset;
          if (primary != null) {
            final distFromPrimary = (pendingOffset - primary).abs();
            final totalSize = _filePaths[fileId]?.totalSize ?? 0;
            final staleThreshold = totalSize > 0
                ? ProxyConfig.scaled(totalSize, 0.01, 1 * 1024 * 1024, 10 * 1024 * 1024)
                : 10 * 1024 * 1024;
            if (distFromPrimary > staleThreshold) {
              _log(
                'Skipping STALE debounced seek for $fileId to ${pendingOffset ~/ 1024}KB '
                '(primary moved to ${primary ~/ 1024}KB, dist: ${distFromPrimary ~/ 1024}KB)',
              );
              return;
            }
          }
          _log(
            'Executing debounced seek for $fileId to offset ${pendingOffset ~/ 1024}KB',
          );
          // Registrar timestamp para coordinación con stall timer
          _getOrCreateState(fileId).lastDebouncedSeekTime = DateTime.now();
          // Execute the actual seek by starting download at the debounced offset
          _startDownloadAtOffset(fileId, pendingOffset);
        }
      },
    );
  }
}
