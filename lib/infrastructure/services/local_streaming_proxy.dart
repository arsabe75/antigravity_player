import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'tdlib_client.dart';
import 'cache_service.dart';
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

  LocalStreamingProxy._internal()
      : _tdlib = TelegramService(),
        _cacheService = TelegramCacheService();

  /// Constructor for testing — accepts fake implementations.
  LocalStreamingProxy.testing({
    required TdlibClient tdlib,
    required CacheService cacheService,
  })  : _tdlib = tdlib,
        _cacheService = cacheService;

  final TdlibClient _tdlib;
  final CacheService _cacheService;

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

    _lastDiskCheckResult = await _cacheService.checkDiskSafety();
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

  // H1: Captura la generación de seek al momento de programar la detección
  // de MOOV. Se usa en _startProactiveMoovDownload para detectar si un seek
  // del usuario ocurrió entre la programación y la ejecución asíncrona.
  final Map<int, int> _moovDetectionSeekGen = {};

  // FIX T: Connection flood detector for broken videos.
  // Tracks eviction timestamps per file. If evictions exceed threshold
  // in a time window, the video is marked as corrupt and rejected.
  final Map<int, List<DateTime>> _evictionTimestamps = {};
  static const int _floodEvictionThreshold = 15;
  static const Duration _floodTimeWindow = Duration(seconds: 10);

  // ============================================================
  // TELEGRAM ANDROID-INSPIRED IMPROVEMENTS
  // ============================================================

  // MÉTRICAS DE VELOCIDAD: Track download speed for adaptive decisions
  final Map<int, DownloadMetrics> _downloadMetrics = {};

  // IN-MEMORY LRU CACHE: Cache recently read data for instant backward seeks
  final Map<int, StreamingLRUCache> _streamingCaches = {};
  // Cache for parsed MP4 sample tables (used by getByteOffsetForTime and MOOV detection)
  final Map<int, Mp4SampleTable?> _sampleTableCache = {};
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
  // I-E: Soporta override en runtime para tuning
  static int get _seekDebounceMs =>
      ProxyConfig.config<int>('seekDebounceMs', 150);

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
  // Maps fileId -> last time "Ignoring request (moov lock)" was logged
  final Map<int, DateTime> _lastMoovIgnoreLogTime = {};
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

  // L12: _pendingSeekAfterMoov migrado a ProxyFileState.pendingSeekAfterMoov

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

  /// Force-restart a file that failed with a recoverable error.
  ///
  /// More aggressive than [clearError]: resets the circuit breaker, the retry
  /// tracker, the error state, AND immediately starts a download with critical
  /// priority at the primary playback offset. Use this when the user explicitly
  /// chooses "Forzar reproducción" on a video that hit max-retries but might
  /// still be playable.
  void forceRetry(int fileId) {
    _logInfo('FORCE RETRY for $fileId - bypassing circuit breaker and restarting', fileId: fileId);

    final state = _getOrCreateState(fileId);
    state.lastError = null;
    state.loadState = FileLoadState.idle;

    // Reset retry tracker to give a fresh chance
    _retryTracker.reset(fileId);
    _downloadMetrics[fileId]?.resetStallCount();

    // Remove from aborted list so new requests are accepted
    _abortedRequests.remove(fileId);

    // If there are waiters, wake them up — they'll re-request and get fresh data
    final waiters = _byteAvailabilityWaiters.remove(fileId);
    if (waiters != null) {
      for (final entry in waiters) {
        if (!entry.value.isCompleted) entry.value.complete();
      }
    }

    // Immediately start download at the primary offset (or 0) with max priority.
    // This ensures data starts flowing BEFORE the player's next HTTP request.
    final primaryOffset = state.primaryPlaybackOffset ?? 0;
    _startDownloadAtOffset(fileId, primaryOffset,
        isBlocking: true, forceRestart: true);
  }

  /// Internal method to notify error and update state.
  /// Returns true if error was notified (new), false if it was a duplicate.
  ///
  /// Uses a severity hierarchy so more severe errors replace less severe ones:
  ///   unknown < networkError < maxRetriesExceeded < timeout
  ///   < fileNotFound < diskFull < playbackStall < unsupportedCodec < corruptFile
  /// Within the same severity level, the first error is kept (deduplication).
  bool _notifyErrorIfNew(int fileId, StreamingError error) {
    final state = _getOrCreateState(fileId);

    final existing = state.lastError;
    if (existing != null) {
      // Same type: deduplicate to prevent concurrent timers from spamming
      if (existing.type == error.type) return false;

      // Severity hierarchy: only replace if new error is more severe
      final newSeverity = _errorSeverity(error.type);
      final oldSeverity = _errorSeverity(existing.type);
      if (newSeverity <= oldSeverity) {
        _logTrace(
          'Keeping existing error ${existing.type} (sev $oldSeverity) '
          'over incoming ${error.type} (sev $newSeverity) for $fileId',
          fileId: fileId,
        );
        return false;
      }
      _logWarning(
        'Replacing error ${existing.type} with more severe ${error.type} for $fileId',
        fileId: fileId,
      );
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

  /// Severity score for [StreamingErrorType].
  ///
  /// Higher values represent more severe / less recoverable errors.
  /// Used by [_notifyErrorIfNew] to decide whether an incoming error
  /// should replace an existing one.
  ///
  /// Levels:
  ///   0 — unknown, networkError (generic, may resolve on retry)
  ///   1 — maxRetriesExceeded, timeout (retries exhausted, but may recover)
  ///   2 — degraded (early warning, video still watchable)
  ///   3 — fileNotFound, diskFull (external / permanent, not file corruption)
  ///   4 — playbackStall (file causes UI-blocking thrashing)
  ///   5 — unsupportedCodec, corruptFile (file is genuinely broken)
  static int _errorSeverity(StreamingErrorType type) {
    return switch (type) {
      StreamingErrorType.unknown => 0,
      StreamingErrorType.networkError => 0,
      StreamingErrorType.maxRetriesExceeded => 1,
      StreamingErrorType.timeout => 1,
      StreamingErrorType.degraded => 2,
      StreamingErrorType.fileNotFound => 3,
      StreamingErrorType.diskFull => 3,
      StreamingErrorType.playbackStall => 4,
      StreamingErrorType.unsupportedCodec => 5,
      StreamingErrorType.corruptFile => 5,
    };
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
  int? getPendingSeekPosition(int fileId) =>
      _getOrCreateState(fileId).pendingSeekAfterMoov;

  /// Acknowledge that a pending seek has been processed.
  /// Call this after the player has successfully seeked to the pending position.
  void acknowledgePendingSeek(int fileId) {
    _getOrCreateState(fileId).pendingSeekAfterMoov = null;
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
    _tdlib.send({
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
    _moovDetectionSeekGen.remove(fileId); // H1
    _evictionTimestamps.remove(fileId);
    _lastDownloadProgress.remove(fileId);
    _lastStallCheckOffset.remove(fileId);
    _downloadHighWaterMark.remove(fileId);
    _lastStallRecordedTime.remove(fileId);

    _lastWaitingLogTime.remove(fileId);
    _lastProtectedLogTime.remove(fileId);
    _lastMoovIgnoreLogTime.remove(fileId);
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
    _moovDetectionSeekGen.clear(); // H1
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

    // Clear file load states
    for (final state in _fileStates.values) {
      state.pendingSeekAfterMoov = null;
    }
    _fileStates.clear();
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

    // FIX 5: Clear pre-seek stall state. The stall timer uses waitingForOffset
    // to decide where to restart downloads. If this still points to the pre-seek
    // offset, the stall timer will call _startDownloadAtOffset for the OLD offset,
    // canceling the new download at the seek target. Also reset the rate limiter
    // timestamp so the first downloadFile for the new seek target isn't blocked.
    _getOrCreateState(fileId).waitingForOffset = null;
    _getOrCreateState(fileId).lastDownloadFileCallTime = null;

    // M8: Invalidar lastServedOffset en seeks explícitos.
    // Si dos seeks consecutivos caen en rangos de bytes similares,
    // el segundo no sería detectado como seek si lastServedOffset
    // mantiene el valor del seek anterior.
    _getOrCreateState(fileId).lastServedOffset = null;

    // I-D: Registrar inicio del seek para telemetría de latencia
    _getOrCreateState(fileId).seekStartTime = DateTime.now();
    _getOrCreateState(fileId).seekTargetTimeMs = targetTimeMs;
    _getOrCreateState(fileId).seekLatencyMs = null;

    // FIX 5b: Release the MOOV download lock. The proactive MOOV download sets
    // forcedMoovOffset, which causes the streaming loop to skip ALL calls to
    // _startDownloadAtOffset. Since _startDownloadAtOffset is the only place
    // that can release forcedMoovOffset, a deadlock forms:
    //   streaming loop won't call _startDownloadAtOffset → lock never released
    //   → TDLib never redirected to seek target → player starves → reload from 0
    // On user seek, the MOOV download is no longer the priority — the seek target is.
    final moovState = _getOrCreateState(fileId);
    if (moovState.forcedMoovOffset != null) {
      _debugLog(
        'Proxy: FIX 5b - Releasing MOOV lock for $fileId '
        '(was at offset ${moovState.forcedMoovOffset}) due to user seek',
      );
      moovState.forcedMoovOffset = null;
      moovState.forcedMoovStartTime = null;
      moovState.forcedMoovAbsoluteStartTime = null;
      moovState.forcedMoovLastProgress = 0;
    }

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

    _tdlib.updates.listen(_onUpdate);
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
    await _cacheService.enforceVideoSizeLimit();
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
      final result = await _tdlib.sendWithResult({
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
        final size = result['size'];
        if (size is int) {
          return size;
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
    int? end;
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

      // EARLY RANGE PARSING: Parse the Range header before connection limit
      // check so `start` has the correct offset value for eviction decisions.
      // Without this, `start` is always 0 and all connections appear to be at
      // offset 0, causing incorrect eviction choices and false flood detection.
      // Also extracts `end` to avoid a second parse later.
      {
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        if (rangeHeader != null) {
          final parts = rangeHeader.replaceFirst('bytes=', '').split('-');
          start = int.parse(parts[0]);
          if (parts.length > 1 && parts[1].isNotEmpty) {
            end = int.parse(parts[1]);
          }
        }
      }

      // CONNECTION LIMITER with EVICTION (FIX O/O2):
      if (!await _enforceConnectionLimit(fileId, start, request)) return;

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
        // Wait for TDLib readiness + stabilize after aborts
        if (!await _waitForTdlibReady(fileId, request)) return;

        // Register this HTTP request offset for cleanup on close
        _activeHttpRequestOffsets.putIfAbsent(fileId, () => {});
        _activeHttpRequestOffsets[fileId]!.add(start);

        // ============================================================
        // P0/P1 FIX: MOOV-FIRST STATE MACHINE LOGIC
        final moovResult = handleMoovFirstRedirect(fileId, start, seekThreshold);
        final moovFirstRedirect = moovResult.moovFirstRedirect;
        start = moovResult.adjustedStart;

        // SEEK DETECTION
        bool isSeekRequest = detectSeek(fileId, start, totalSize,
            seekThreshold, scrubThreshold, moovFirstRedirect);

        // PRIMARY PLAYBACK TRACKING (STABILIZED)
        isSeekRequest = _updatePrimaryPlaybackOffset(
            fileId, start, isSeekRequest, totalSize,
            significantJump, scrubThreshold);

        // 2. Ensure File Info is available
        final fileResult = await _ensureFileAvailable(fileId, request);
        if (fileResult == null) return; // 404 already sent

        // FIX 3.1b: Re-validate state after await. _ensureFileAvailable can
        // take seconds (file download, re-fetch). During this time:
        // - signalUserSeek may have fired (seekGeneration changed)
        // - The file may have entered a terminal error state
        // - forcedMoovOffset may have been set by an async callback
        // If the seek generation changed, abort — the stream loop will also
        // detect this, but aborting early saves work.
        final currentGen = _seekGeneration[fileId] ?? 0;
        if (mySeekGeneration != currentGen) {
          _debugLog(
            'Proxy: Seek generation changed during _ensureFileAvailable '
            '($mySeekGeneration -> $currentGen), aborting request for $fileId',
          );
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        // Also check if file became terminal during the await
        final reloadedState = _getOrCreateState(fileId);
        if (reloadedState.loadState == FileLoadState.unsupported ||
            reloadedState.loadState == FileLoadState.error ||
            reloadedState.loadState == FileLoadState.timeout) {
          _debugLog(
            'Proxy: File $fileId entered terminal state during _ensureFileAvailable, aborting',
          );
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }

        final file = fileResult.file;

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
        await _streamData(
          fileId, start, contentLength, request, file,
          mySeekGeneration, isSeekRequest,
          moovReadyBytes, significantJump, primaryProgressBase, totalSize,
          isClientDisconnected, disconnectCompleter,
        );
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

  /// Core streaming loop: reads data from disk/LRU cache and writes to the
  /// HTTP response. Handles both the data-available fast path and the
  /// blocking-wait slow path with stall detection, adaptive timeouts, and
  /// per-connection cumulative wait tracking.
  Future<void> _streamData(
    int fileId,
    int start,
    int contentLength,
    HttpRequest request,
    File file,
    int mySeekGeneration,
    bool isSeekRequest,
    int moovReadyBytes,
    int significantJump,
    int primaryProgressBase,
    int totalSize,
    bool isClientDisconnected,
    Completer<bool> disconnectCompleter,
  ) async {
    RandomAccessFile? raf;
    try {
      raf = await _openFileWithRetry(file, fileId);
      if (raf == null) {
        throw FileSystemException('Failed to open file after retries');
      }

      int currentReadOffset = start;
      int remainingToSend = contentLength;

      DateTime? connectionWaitStart;
      int connectionWaitOffsetRegion = -1;
      int connectionCumulativeWaitMs = 0;
      const int maxConnectionWaitMs = 60000;

      if (!_fileUpdateNotifiers.containsKey(fileId)) {
        _fileUpdateNotifiers[fileId] = StreamController.broadcast();
      }

      while (remainingToSend > 0) {
        if (_abortedRequests.contains(fileId)) {
          _debugLog('Proxy: Request aborted for $fileId');
          break;
        }
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

        final available = await _getDownloadedPrefixSize(
          fileId,
          currentReadOffset,
        );

        if (available > 0) {
          final chunkToRead = min(
            available,
            min(remainingToSend, ProxyConfig.streamChunkSize),
          );

          _streamingCaches.putIfAbsent(fileId, () => StreamingLRUCache());
          final cache = _streamingCaches[fileId]!;
          var cachedData = cache.get(currentReadOffset, chunkToRead);

          Uint8List data;
          if (cachedData != null) {
            _cacheLruOrder.remove(fileId);
            _cacheLruOrder.add(fileId);
            data = cachedData;
          } else {
            await raf.setPosition(currentReadOffset);
            data = await raf.read(chunkToRead);

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

          _downloadMetrics.putIfAbsent(fileId, () => DownloadMetrics());
          _downloadMetrics[fileId]!.recordBytes(data.length);

          _getOrCreateState(fileId).lastServedOffset = currentReadOffset;

          // I-D: Medir latencia de seek cuando se sirven los primeros bytes
          // en la nueva posición después de un seek del usuario.
          final fileState = _getOrCreateState(fileId);
          if (fileState.seekStartTime != null && fileState.seekLatencyMs == null) {
            final targetOffset = fileState.lastExplicitSeekOffset;
            if (targetOffset != null && currentReadOffset >= targetOffset) {
              fileState.seekLatencyMs = DateTime.now()
                  .difference(fileState.seekStartTime!)
                  .inMilliseconds;
              _logInfo(
                'Proxy: I-D - Seek latency for $fileId: '
                '${fileState.seekLatencyMs}ms '
                '(target offset: ${targetOffset ~/ 1024}KB)',
              );
            }
          }
          if (fileState.loadState == FileLoadState.loadingMoov &&
              currentReadOffset >= moovReadyBytes) {
            fileState.loadState = FileLoadState.moovReady;
            final pendingSeek = fileState.pendingSeekAfterMoov;
            if (pendingSeek != null) {
              _debugLog(
                'Proxy: P0 FIX - MOOV ready for $fileId. '
                'Player should now seek to ${pendingSeek ~/ 1024}KB',
              );
            } else {
              _stalePlaybackPositions.remove(fileId);
              fileState.loadState = FileLoadState.playing;
            }
          }

          if (remainingToSend > 0 &&
              _getOrCreateState(fileId).forcedMoovOffset == null) {
            _startDownloadAtOffset(
              fileId,
              currentReadOffset,
              isSeekRequest: isSeekRequest,
              seekGeneration: mySeekGeneration,
            );

            final lastSeek = _getOrCreateState(fileId).lastSeekTime;
            if (lastSeek != null &&
                DateTime.now().difference(lastSeek).inMilliseconds <
                    ProxyConfig.stagnantPrimaryMs) {
              _triggerPostSeekPreload(fileId, currentReadOffset);
            }
          }

          {
            final streamState = _getOrCreateState(fileId);
            final lastPrimary = streamState.primaryPlaybackOffset ?? 0;
            final lastUpdateTime = streamState.lastPrimaryUpdateTime;

            if (currentReadOffset > lastPrimary &&
                (currentReadOffset - lastPrimary) < significantJump) {
              final now = DateTime.now();
              int allowedProgress = primaryProgressBase;
              if (lastUpdateTime != null) {
                final elapsedMs = now
                    .difference(lastUpdateTime)
                    .inMilliseconds;
                final timeBasedAllowance =
                    (elapsedMs /
                            1000 *
                            ProxyConfig.primaryProgressRateBytesPerSec)
                        .round();
                allowedProgress += timeBasedAllowance;
              }

              if ((currentReadOffset - lastPrimary) <= allowedProgress) {
                if (lastUpdateTime == null ||
                    now.difference(lastUpdateTime).inMilliseconds >
                        ProxyConfig.primaryUpdateThrottleMs) {
                  streamState.primaryPlaybackOffset = currentReadOffset;
                  streamState.lastPrimaryUpdateTime = now;
                }
              }
            } else if (currentReadOffset > lastPrimary &&
                (currentReadOffset - lastPrimary) > significantJump) {
              final lastExplicitSeek = streamState.lastExplicitSeekOffset;

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
          }
        } else {
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

          _startDownloadAtOffset(
            fileId,
            currentReadOffset,
            isBlocking: true,
            isSeekRequest: isSeekRequest,
            seekGeneration: mySeekGeneration,
          );

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

          final timeout = _getAdaptiveTimeout(fileId, isMoovRequest);

          final completer = Completer<void>();
          _byteAvailabilityWaiters.putIfAbsent(fileId, () => []);
          _byteAvailabilityWaiters[fileId]!.add(
            MapEntry(currentReadOffset, completer),
          );

          if (!completer.isCompleted) {
            final postCheck = _filePaths[fileId];
            if (postCheck != null &&
                postCheck.availableBytesFrom(currentReadOffset) > 0) {
              completer.complete();
            }
          }

          _getOrCreateState(fileId).waitingForOffset = currentReadOffset;
          _ensureStallTimer(fileId);
          _ensurePrefetchTimer(fileId);

          connectionWaitStart = DateTime.now();

          try {
            final waitResult = await Future.any([
              completer.future
                  .timeout(
                    timeout,
                    onTimeout: () {
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

            if (_abortedRequests.contains(fileId)) {
              _debugLog('Proxy: Wait aborted for $fileId');
              break;
            }
          } catch (_) {
            // Timeout or error - continue loop to retry
          } finally {
            _getOrCreateState(fileId).waitingForOffset = null;
          }

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

          {
            final offsetRegion = currentReadOffset ~/ ProxyConfig.earlyExitOffsetTolerance;
            if (offsetRegion == connectionWaitOffsetRegion) {
              connectionCumulativeWaitMs += DateTime.now().difference(connectionWaitStart).inMilliseconds;
            } else {
              connectionWaitOffsetRegion = offsetRegion;
              connectionCumulativeWaitMs = 0;
            }
            connectionWaitStart = null;

            if (connectionCumulativeWaitMs >= maxConnectionWaitMs &&
                !_abortedRequests.contains(fileId)) {
              _logWarning(
                'PER-CONNECTION STALL for $fileId: connection at offset '
                '${start ~/ 1024}KB waited ${connectionCumulativeWaitMs ~/ 1000}s '
                'at readOffset ${currentReadOffset ~/ 1024}KB. Breaking connection '
                'and delegating recovery to per-file stall timer.',
                fileId: fileId,
              );

              // Instead of independently firing _notifyErrorIfNew (which
              // competes with the per-file stall timer — see H9), delegate
              // to the unified per-file recovery path:
              // 1. Record a retry in the tracker (counts toward max retries)
              // 2. Attempt a force-restart of the download
              // 3. The per-file stall timer will fire the error on next cycle
              //    if the retry limit is exhausted.
              _retryTracker.recordRetry(fileId);

              if (_retryTracker.canRetry(fileId)) {
                final backoff = _retryTracker.getBackoffDelay(
                  fileId,
                  baseMs: ProxyConfig.retryBackoffBaseMs,
                  maxMs: ProxyConfig.retryBackoffMaxMs,
                  multiplier: ProxyConfig.retryBackoffMultiplier,
                );
                Timer(backoff, () {
                  if (_abortedRequests.contains(fileId)) return;
                  _startDownloadAtOffset(
                    fileId,
                    currentReadOffset,
                    forceRestart: true,
                  );
                });
              }
              // Break this connection; the per-file stall timer handles
              // error reporting and further retries.
              _abortedRequests.add(fileId);

              final waiters = _byteAvailabilityWaiters.remove(fileId);
              if (waiters != null) {
                for (final entry in waiters) {
                  if (!entry.value.isCompleted) entry.value.complete();
                }
              }
              break;
            }
          }
        }
      }

      _handleStreamLoopExit(fileId, start, currentReadOffset,
          remainingToSend, contentLength);
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
    }

    if (_abortedRequests.contains(fileId)) {
      try {
        await request.response.close();
      } catch (_) {}
    } else {
      await request.response.close();
    }
  }

  /// Logs the streaming loop result and detects connection thrashing (repeated
  /// early exits at the same offset). Marks the file as [StreamingErrorType.playbackStall]
  /// when the threshold is reached.
  void _handleStreamLoopExit(
    int fileId,
    int start,
    int currentReadOffset,
    int remainingToSend,
    int contentLength,
  ) {
    if (remainingToSend <= 0) {
      _debugLog(
        'Proxy: Stream loop COMPLETED normally for $fileId '
        '(served ${contentLength ~/ 1024}KB from offset $start)',
      );
      return;
    }

    _debugLog(
      'Proxy: Stream loop EXITED EARLY for $fileId '
      '(served ${(contentLength - remainingToSend) ~/ 1024}KB of '
      '${contentLength ~/ 1024}KB, readOffset: $currentReadOffset)',
    );

    if (_abortedRequests.contains(fileId)) return;

    final thrashState = _getOrCreateState(fileId);
    final now = DateTime.now();
    final lastOffset = thrashState.lastEarlyExitReadOffset;
    final isSameOffset = lastOffset != null &&
        (currentReadOffset - lastOffset).abs() <
            ProxyConfig.earlyExitOffsetTolerance;

    if (isSameOffset) {
      thrashState.earlyExitCount++;
    } else {
      thrashState.earlyExitCount = 1;
      thrashState.firstEarlyExitTime = now;
    }
    thrashState.lastEarlyExitReadOffset = currentReadOffset;

    final windowStart = thrashState.firstEarlyExitTime ?? now;
    final elapsed = now.difference(windowStart).inSeconds;

    if (elapsed > ProxyConfig.earlyExitWindowSeconds) {
      thrashState.earlyExitCount = 1;
      thrashState.firstEarlyExitTime = now;
    } else if (thrashState.earlyExitCount >=
        ProxyConfig.earlyExitThreshold) {
      _logError(
        'CONNECTION THRASHING DETECTED for $fileId: '
        '${thrashState.earlyExitCount} early exits at offset '
        '${currentReadOffset ~/ 1024}KB within ${elapsed}s. '
        'Marking as playback error.',
        fileId: fileId,
      );
      final error = StreamingError.playbackStall(
        fileId,
        thrashState.earlyExitCount,
      );
      _notifyErrorIfNew(fileId, error);
      _abortedRequests.add(fileId);

      final waiters = _byteAvailabilityWaiters.remove(fileId);
      if (waiters != null) {
        for (final entry in waiters) {
          if (!entry.value.isCompleted) entry.value.complete();
        }
      }

      _cancelStallTimer(fileId);
      _cancelPrefetchTimer(fileId);
    } else if (thrashState.earlyExitCount >=
        ProxyConfig.degradedWarningThreshold) {
      // Non-blocking warning: show UI overlay but keep proxy operational.
      // The video may still be watchable with occasional pauses.
      // When earlyExitThreshold is reached later, playbackStall replaces this.
      final existing = thrashState.lastError;
      if (existing == null || existing.type != StreamingErrorType.degraded) {
        final warning = StreamingError.degraded(
          fileId,
          thrashState.earlyExitCount,
        );
        thrashState.lastError = warning;
        onStreamingError?.call(warning);
        _logWarning(
          'DEGRADED PLAYBACK for $fileId: '
          '${thrashState.earlyExitCount} early exits at offset '
          '${currentReadOffset ~/ 1024}KB within ${elapsed}s. '
          'Warning user but keeping playback active.',
          fileId: fileId,
        );
      }
    }
  }

  /// Ensures the file exists on disk and has valid info in the proxy cache.
  ///
  /// If the file was deleted by cache cleanup, forces TDLib to re-allocate it.
  /// Preserves [_downloadedRanges] to avoid losing MOOV bytes knowledge.
  ///
  /// Returns null if the file is unavailable (HTTP 404 already sent).
  Future<({File file, ProxyFileInfo fileInfo})?> _ensureFileAvailable(
    int fileId,
    HttpRequest request,
  ) async {
    if (!_filePaths.containsKey(fileId) ||
        _filePaths[fileId]!.path.isEmpty) {
      await _fetchFileInfo(fileId);
    }

    var fileInfo = _filePaths[fileId];
    if (fileInfo == null || fileInfo.path.isEmpty) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return null;
    }

    var file = File(fileInfo.path);

    if (!await file.exists()) {
      _debugLog(
        'Proxy: File does not exist on disk: ${fileInfo.path}, re-fetching...',
      );

      _filePaths.remove(fileId);
      _downloadedRanges.remove(fileId);
      _getOrCreateState(fileId).resetDownloadState();

      _debugLog(
        'Proxy: File missing on disk, forcing TDLib delete for $fileId',
      );
      await _tdlib.sendWithResult({
        '@type': 'deleteFile',
        'file_id': fileId,
      });

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
        return null;
      }

      file = File(fileInfo.path);

      if (!await file.exists()) {
        _debugLog('Proxy: New file still does not exist: ${fileInfo.path}');
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return null;
      }
    }

    return (file: file, fileInfo: fileInfo);
  }

  /// Determines whether [start] should become the new primary playback offset.
  ///
  /// Handles: initial primary, explicit user seeks (P1/FIX J), rapid divergence,
  /// resume-from-start (FIX Q), MOOV probe rejection (FIX Q2/Q3), stagnant
  /// recovery, sequential tracking, read-ahead detection, and zombie protection.
  ///
  /// Returns the (potentially modified) [isSeekRequest] value — set to false
  /// when a divergent seek is ignored.
  bool _updatePrimaryPlaybackOffset(
    int fileId,
    int start,
    bool isSeekRequest,
    int totalSize,
    int significantJump,
    int scrubThreshold,
  ) {
    final playbackState = _getOrCreateState(fileId);
    final existingPrimary = playbackState.primaryPlaybackOffset;
    final lastPrimaryUpdate = playbackState.lastPrimaryUpdateTime;

    bool shouldUpdatePrimary = false;

    if (existingPrimary == null) {
      shouldUpdatePrimary = true;
    } else if (playbackState.userSeekInProgress) {
      final distFromPrimary = (start - existingPrimary).abs();
      if (distFromPrimary > significantJump) {
        final isEndOfFileProbe = totalSize > 0 &&
            (totalSize - start) < totalSize * 0.10 &&
            existingPrimary < totalSize * 0.85;
        if (isEndOfFileProbe) {
          _debugLog(
            'Proxy: IGNORING end-of-file probe during user seek for $fileId. '
            'Probe at ${start ~/ 1024}KB (${(totalSize - start) ~/ (1024 * 1024)}MB from end), '
            'keeping primary at ${existingPrimary ~/ 1024}KB',
          );
        } else {
          _debugLog(
            'Proxy: EXPLICIT USER SEEK for $fileId. Primary $existingPrimary -> $start.',
          );
          shouldUpdatePrimary = true;
          playbackState.userSeekInProgress = false;
          playbackState.lastExplicitSeekOffset = start;
          playbackState.lastExplicitSeekTime = DateTime.now();
        }
      } else {
        _debugLog(
          'Proxy: USER SEEK SIGNAL active but offset $start too close to Primary $existingPrimary (${distFromPrimary ~/ 1024}KB)',
        );
      }
    } else if (isSeekRequest) {
      if (lastPrimaryUpdate != null &&
          DateTime.now().difference(lastPrimaryUpdate).inMilliseconds <
              ProxyConfig.rapidDivergenceWindowMs) {
        if ((start - existingPrimary).abs() > scrubThreshold) {
          final endOfFileThreshold = totalSize > 0
              ? max(significantJump * 2, (totalSize * 0.10).toInt())
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
            isSeekRequest = false;
          }
        } else {
          shouldUpdatePrimary = true;
        }
      } else {
        final endOfFileThresholdStable = totalSize > 0
            ? max(significantJump * 2, (totalSize * 0.10).toInt())
            : significantJump * 2;
        final isMoovStable =
            totalSize > 0 && (totalSize - start) < endOfFileThresholdStable;
        if (isMoovStable && existingPrimary < totalSize * 0.85) {
          _debugLog(
            'Proxy: IGNORING end-of-file stable seek for $fileId at ${start ~/ 1024}KB, '
            'keeping primary at ${existingPrimary ~/ 1024}KB',
          );
        } else {
          shouldUpdatePrimary = true;
        }
      }
    } else if (start < existingPrimary) {
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
      final jumpForward = start - existingPrimary;
      if (jumpForward > 0) {
        if (jumpForward < significantJump) {
          shouldUpdatePrimary = true;
        } else if (lastPrimaryUpdate != null &&
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
          isSeekRequest = false;
        }
      }
    }

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
      final lastSeekTime = playbackState.lastExplicitSeekTime;
      final isRecentSeek = lastSeekTime != null &&
          DateTime.now().difference(lastSeekTime).inMilliseconds < 3000;

      if (isRecentSeek && existingPrimary != null) {
        final distFromPrimary = (start - existingPrimary).abs();
        if (distFromPrimary > significantJump) {
          _logTrace(
            'ZOMBIE BLOCKED: Ignorando primary update $existingPrimary -> $start '
            '(seek reciente, dist: ${distFromPrimary ~/ (1024 * 1024)}MB)',
            fileId: fileId,
          );
          shouldUpdatePrimary = false;
          playbackState.zombieBlockCount++; // L11
        }
      }

      if (shouldUpdatePrimary) {
        playbackState.primaryPlaybackOffset = start;
        playbackState.lastPrimaryUpdateTime = DateTime.now();
      }
    }

    return isSeekRequest;
  }

  /// Handles MOOV-first redirect when a file has a stale playback position
  /// (after cache clear). For MOOV-at-end files the pending seek is stored
  /// without redirecting; for others start is redirected to 0.
  @visibleForTesting
  ({int adjustedStart, bool moovFirstRedirect}) handleMoovFirstRedirect(
    int fileId,
    int start,
    int seekThreshold,
  ) {
    bool moovFirstRedirect = false;

    if (_stalePlaybackPositions.contains(fileId) && start > seekThreshold) {
      final currentState = _getOrCreateState(fileId).loadState;

      if (currentState == FileLoadState.idle ||
          currentState == FileLoadState.loadingMoov) {
        _getOrCreateState(fileId).pendingSeekAfterMoov = start;
        _getOrCreateState(fileId).loadState = FileLoadState.loadingMoov;

        final isMoovAtEnd = _getOrCreateState(fileId).isMoovAtEnd;

        if (isMoovAtEnd) {
          _debugLog(
            'Proxy: P1 FIX - Stale position for $fileId (MOOV at END). '
            'Requested: ${start ~/ 1024}KB. Pending seek stored. '
            'Letting moov-at-end logic handle MOOV fetch.',
          );
        } else {
          _debugLog(
            'Proxy: P1 FIX - Stale position for $fileId (MOOV at START). '
            'Requested: ${start ~/ 1024}KB, forcing start from 0.',
          );
          moovFirstRedirect = true;
          start = 0;
        }
      } else if (currentState == FileLoadState.moovReady) {
        _debugLog(
          'Proxy: P1 FIX - MOOV ready for $fileId. Processing pending seek to ${start ~/ 1024}KB',
        );
        _getOrCreateState(fileId).loadState = FileLoadState.seeking;
        _stalePlaybackPositions.remove(fileId);
        _getOrCreateState(fileId).pendingSeekAfterMoov = null;
      }
    } else if (_stalePlaybackPositions.contains(fileId) &&
        start <= seekThreshold) {
      _getOrCreateState(fileId).loadState = FileLoadState.loadingMoov;
    }

    return (adjustedStart: start, moovFirstRedirect: moovFirstRedirect);
  }

  /// Detects if the current request is a seek (jump > configured threshold
  /// from the last served offset). Only sets [_lastSeekTime] for true
  /// scrubbing (user dragging seek bar).
  @visibleForTesting
  bool detectSeek(
    int fileId,
    int start,
    int totalSize,
    int seekThreshold,
    int scrubThreshold,
    bool moovFirstRedirect,
  ) {
    final lastOffset = moovFirstRedirect
        ? null
        : _getOrCreateState(fileId).lastServedOffset;
    if (lastOffset == null) return false;

    final jump = (start - lastOffset).abs();
    if (jump <= seekThreshold) return false;

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

    _logTrace(
      'Detected seek for $fileId: $lastOffset -> $start (jump: ${jump ~/ 1024}KB)',
      fileId: fileId,
    );
    return true;
  }

  /// Waits for TDLib client to be ready and gives it time to stabilize
  /// after recent file aborts. Also cleans up stale cache entries.
  ///
  /// Returns `true` if the caller should proceed, `false` if the request
  /// was rejected (HTTP response already sent).
  Future<bool> _waitForTdlibReady(int fileId, HttpRequest request) async {
    if (!_tdlib.isClientReady) {
      _debugLog('Proxy: Waiting for TDLib client to initialize...');
      int attempts = 0;
      while (!_tdlib.isClientReady &&
          attempts < ProxyConfig.tdlibInitMaxAttempts) {
        await Future.delayed(
          const Duration(milliseconds: ProxyConfig.tdlibInitWaitMs),
        );
        attempts++;
      }
      if (!_tdlib.isClientReady) {
        _debugLog(
          'Proxy: TDLib client failed to initialize after 10 seconds',
        );
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return false;
      }
      _debugLog(
        'Proxy: TDLib client ready after ${attempts * ProxyConfig.tdlibInitWaitMs}ms',
      );
    }

    if (_abortedRequests.isNotEmpty) {
      final thisFileWasAborted = _abortedRequests.contains(fileId);
      _debugLog(
        'Proxy: Waiting for TDLib to stabilize (${_abortedRequests.length} aborted files, current file aborted: $thisFileWasAborted)...',
      );
      _abortedRequests.clear();

      final waitMs = thisFileWasAborted
          ? ProxyConfig.abortStabilizationAbortedMs
          : ProxyConfig.abortStabilizationOtherMs;
      await Future.delayed(Duration(milliseconds: waitMs));
      _debugLog('Proxy: TDLib stabilization wait complete (${waitMs}ms)');
    }

    if (_filePaths.containsKey(fileId)) {
      final cached = _filePaths[fileId]!;
      if (cached.isDownloadingActive) {
        _filePaths.remove(fileId);
      }
    }

    return true;
  }

  /// Enforces per-file max concurrent HTTP connections.
  ///
  /// When the limit is reached, evicts the most stale connection (furthest behind
  /// primary playback) instead of rejecting. Protects against connection floods
  /// caused by broken videos (FIX T: flood detection).
  ///
  /// Returns `true` if the connection is accepted and the caller should proceed,
  /// `false` if the connection was rejected (HTTP response already sent).
  Future<bool> _enforceConnectionLimit(
    int fileId,
    int start,
    HttpRequest request,
  ) async {
    final currentConnections = _activeConnectionCount[fileId] ?? 0;
    if (currentConnections >= ProxyConfig.maxConnectionsPerFile) {
      final offsets = _activeHttpRequestOffsets[fileId];
      final primary = _getOrCreateState(fileId).primaryPlaybackOffset ?? 0;
      if (offsets != null && offsets.length > 1) {
        int? mostStale;
        int maxDist = -1;
        for (final o in offsets) {
          if (o < primary) {
            final dist = primary - o;
            if (dist > maxDist) {
              maxDist = dist;
              mostStale = o;
            }
          }
        }
        final newDist = start < primary ? primary - start : 0;
        if (maxDist != -1 && newDist > maxDist) {
          _debugLog(
            'Proxy: CONNECTION LIMIT for $fileId. Rejecting exceptionally stale '
            'connection at ${start ~/ 1024}KB (worse than ${mostStale! ~/ 1024}KB)',
          );
          await Future.delayed(const Duration(milliseconds: 500));
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return false;
        }

        mostStale ??= offsets.reduce((a, b) => a < b ? a : b);
        _evictedConnectionOffsets.putIfAbsent(fileId, () => {}).add(mostStale);
        _connectionsSkipDecrement.putIfAbsent(fileId, () => {}).add(mostStale);
        _activeConnectionCount[fileId] = currentConnections;
        _debugLog(
          'Proxy: CONNECTION LIMIT for $fileId '
          '($currentConnections/${ProxyConfig.maxConnectionsPerFile}), '
          'evicting stale connection at ${mostStale ~/ 1024}KB '
          '(primary: ${primary ~/ 1024}KB, new: ${start ~/ 1024}KB)',
        );

        final now = DateTime.now();
        final timestamps = _evictionTimestamps.putIfAbsent(fileId, () => []);
        timestamps.add(now);
        final cutoff = now.subtract(_floodTimeWindow);
        timestamps.removeWhere((t) => t.isBefore(cutoff));
        if (timestamps.length >= _floodEvictionThreshold) {
          // FIX: Distinguir flood por scrubbing del usuario vs. video dañado.
          // Si hubo seeks explícitos en la ventana de flood, el exceso de
          // conexiones probablemente es causado por scrubbing rápido, no por
          // un archivo corrupto. En ese caso, rechazar sólo esta request (503)
          // sin marcar el archivo como dañado permanentemente.
          final seekTime = _getOrCreateState(fileId).lastExplicitSeekTime;
          final isRecentSeek = seekTime != null &&
              now.difference(seekTime) < _floodTimeWindow;

          if (isRecentSeek) {
            _logWarning(
              'CONNECTION FLOOD with recent user seek for $fileId: '
              '${timestamps.length} evictions in ${_floodTimeWindow.inSeconds}s. '
              'Likely caused by aggressive scrubbing — rejecting request but '
              'keeping file available.',
              fileId: fileId,
            );
            _evictionTimestamps.remove(fileId);
            await Future.delayed(const Duration(milliseconds: 500));
            request.response.statusCode = HttpStatus.serviceUnavailable;
            await request.response.close();
            return false;
          }

          _logError(
            'CONNECTION FLOOD detected for $fileId: '
            '${timestamps.length} evictions in ${_floodTimeWindow.inSeconds}s. '
            'File appears damaged — blocking further requests.',
            fileId: fileId,
          );
          _evictionTimestamps.remove(fileId);
          final error = StreamingError.corruptFile(fileId);
          _notifyErrorIfNew(fileId, error);
          _abortedRequests.add(fileId);
          final waiters = _byteAvailabilityWaiters.remove(fileId);
          if (waiters != null) {
            for (final entry in waiters) {
              if (!entry.value.isCompleted) entry.value.complete();
            }
          }
          await Future.delayed(const Duration(milliseconds: 500));
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return false;
        }

        final completers = _byteAvailabilityWaiters[fileId];
        if (completers != null) {
          final toRemove =
              completers.where((e) => e.key == mostStale).toList();
          for (final entry in toRemove) {
            if (!entry.value.isCompleted) {
              entry.value.complete();
            }
          }
        }
      } else {
        _debugLog(
          'Proxy: CONNECTION LIMIT for $fileId, no evictable connections, '
          'rejecting at offset ${start ~/ 1024}KB',
        );
        await Future.delayed(const Duration(milliseconds: 500));
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return false;
      }
    } else {
      _activeConnectionCount[fileId] = currentConnections + 1;
    }
    return true;
  }

  Future<void> _fetchFileInfo(int fileId) async {
    try {
      final fileJson = await _tdlib.sendWithResult({
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
          final deleteResult = await _tdlib.sendWithResult({
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
          final newFileJson = await _tdlib.sendWithResult({
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
          _tdlib.send({
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
    bool isSeekRequest = false,
    bool isPreview = false, // H2: preview seek target
    int? seekGeneration,
  }) async {
    // Guard pipeline — each returns if the request should be aborted
    if (!await _checkDiskSafetyCached()) return;

    final cached = _filePaths[fileId];
    if (isFileComplete(cached)) return;
    if (isEofRequest(requestedOffset, cached)) return;
    if (isStaleSeekGeneration(seekGeneration, fileId)) return;

    final totalSize = cached?.totalSize ?? 0;
    final localSeekThreshold = _computeLocalSeekThreshold(totalSize);
    final sequentialWindow = _computeSequentialWindow(totalSize);

    if (await _handleForcedMoov(fileId, requestedOffset, cached)) return;

    // Guard pipeline continued
    if (_isScrubbingDebounced(fileId, requestedOffset, totalSize)) return;
    if (await _isDataAvailableNow(fileId, requestedOffset)) return;
    // H2: Preview seeks tienen su propio cooldown (previewCooldownMs).
    // No aplicar rate limiting del pipeline principal.
    if (!isPreview && _isRateLimited(fileId, isBlocking: isBlocking, forceRestart: forceRestart, isSeekRequest: isSeekRequest)) return;

    final currentDownloadOffset = cached?.downloadOffset ?? 0;
    final currentPrefix = cached?.downloadedPrefixSize ?? 0;
    final currentActiveOffset = _getOrCreateState(fileId).activeDownloadOffset;
    if (_isAtFrontier(fileId, requestedOffset, currentDownloadOffset, currentPrefix, totalSize, forceRestart: forceRestart)) return;
    if (_isAlreadyTargeting(fileId, requestedOffset, cached, currentActiveOffset: currentActiveOffset, forceRestart: forceRestart)) return;

    _detectMoovAtEnd(fileId, requestedOffset, cached?.totalSize ?? 0);

    final now = DateTime.now();
    final activeDownloadTarget = currentActiveOffset ?? 0;
    final distanceFromCurrent = (requestedOffset - activeDownloadTarget).abs();
    final primaryOffset = _getOrCreateState(fileId).primaryPlaybackOffset ?? 0;
    final distanceToPlayback = (requestedOffset - primaryOffset).abs();

    bool effectiveSeekRequest = isSeekRequest ||
        _detectLocalSeek(fileId, requestedOffset, localSeekThreshold);
    if (_isCooldownBlocked(fileId, requestedOffset, cached, activeDownloadTarget,
        distanceFromCurrent, sequentialWindow, now, isBlocking: isBlocking)) {
      return;
    }

    final isMoovDownload = _isMoovDownloadRequest(fileId, requestedOffset, totalSize);
    final shouldForcePriority = evaluateBlockingPriority(
        fileId, requestedOffset, totalSize, primaryOffset,
        isMoovDownload, isBlocking);

    final computedPriority = resolvePriority(
        fileId, requestedOffset, totalSize, primaryOffset,
        distanceToPlayback, shouldForcePriority, isMoovDownload);
    // H2: Preview seeks usan prioridad medium (16) para no competir
    // con la descarga principal del playback activo.
    final priority = isPreview ? DownloadPriority.medium : computedPriority;

    if (_isDisplacementBlocked(fileId, requestedOffset, priority,
        activeDownloadTarget, sequentialWindow, now,
        isBlocking: isBlocking, forceRestart: forceRestart,
        isSeekRequest: effectiveSeekRequest)) {
      return;
    }

    await _executeDownload(fileId, requestedOffset, priority, isMoovDownload,
        forceRestart: forceRestart);
  }

  // ============================================================
  // PRIORITY & EXECUTION helpers for _startDownloadAtOffset
  // ============================================================

  bool _detectLocalSeek(int fileId, int requestedOffset, int localSeekThreshold) {
    final lastServed = _getOrCreateState(fileId).lastServedOffset;
    if (lastServed == null) return false;
    return (requestedOffset - lastServed).abs() > localSeekThreshold;
  }

  bool _isCooldownBlocked(
    int fileId,
    int requestedOffset,
    ProxyFileInfo? cached,
    int activeDownloadTarget,
    int distanceFromCurrent,
    int sequentialWindow,
    DateTime now, {
    required bool isBlocking,
  }) {
    final lastChange = _getOrCreateState(fileId).lastOffsetChangeTime;
    if (lastChange == null) return false;

    final isSequentialRead =
        requestedOffset > activeDownloadTarget &&
        distanceFromCurrent < sequentialWindow;

    final cooldownMs = isSequentialRead
        ? ProxyConfig.cooldownSequentialMs
        : ProxyConfig.cooldownNonSequentialMs;
    final minDistance = isSequentialRead
        ? ProxyConfig.minDistanceSequentialBytes
        : ProxyConfig.minDistanceNonSequentialBytes;

    final timeSinceLastChange = now.difference(lastChange).inMilliseconds;

    bool isEffectiveActive = true;
    if (timeSinceLastChange > ProxyConfig.deadlockCheckMs) {
      if (cached == null ||
          (!cached.isDownloadingActive && !cached.isCompleted)) {
        isEffectiveActive = false;
      } else if ((cached.downloadOffset - activeDownloadTarget).abs() >
          sequentialWindow) {
        isEffectiveActive = false;
      }
    }

    return !isBlocking &&
        isEffectiveActive &&
        (timeSinceLastChange < cooldownMs ||
            distanceFromCurrent < minDistance);
  }

  bool _isMoovDownloadRequest(int fileId, int requestedOffset, int totalSize) {
    return _getOrCreateState(fileId).isMoovAtEnd &&
        totalSize > 0 &&
        (totalSize - requestedOffset) <
            (totalSize * ProxyConfig.moovDownloadThresholdPercent)
                .round()
                .clamp(
                  ProxyConfig.moovRegionMinBytes,
                  ProxyConfig.moovDownloadRegionMaxBytes,
                );
  }

  @visibleForTesting
  bool evaluateBlockingPriority(
    int fileId,
    int requestedOffset,
    int totalSize,
    int primaryOffset,
    bool isMoovDownload,
    bool isBlocking,
  ) {
    if (!isBlocking) return isMoovDownload;

    final primary = _getOrCreateState(fileId).primaryPlaybackOffset;
    if (primary == null || isMoovDownload) return true;

    final dist = requestedOffset - primary;
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

    if (dist >= 0 && dist < maxForwardBuffer) return true;
    if (dist < 0 && dist.abs() < maxBackwardOverlap) return true;

    final cached = _filePaths[fileId];
    if (cached != null) {
      final cacheEnd = cached.downloadOffset + cached.downloadedPrefixSize;
      final distToCacheEnd = (requestedOffset - cacheEnd).abs();
      if (distToCacheEnd < cacheEdgeProximity) {
        _logTrace(
          'CACHE EDGE ALLOWED for $requestedOffset (CacheEnd: $cacheEnd, Dist: ${distToCacheEnd ~/ 1024}KB)',
          fileId: fileId,
        );
        return true;
      }
      if (requestedOffset < earlyFileThreshold) {
        _debugLog(
          'Proxy: LOW OFFSET ALLOWED for $requestedOffset (early file data)',
        );
        return true;
      }
    }

    _debugLog(
      'Proxy: DENIED Blocking Priority for $requestedOffset (Primary: $primary, Dist: ${dist ~/ 1024}KB). Treated as background.',
    );
    return false;
  }

  @visibleForTesting
  int resolvePriority(
    int fileId,
    int requestedOffset,
    int totalSize,
    int primaryOffset,
    int distanceToPlayback,
    bool shouldForcePriority,
    bool isMoovDownload,
  ) {
    int blockingPriority = DownloadPriority.critical;
    if (shouldForcePriority) {
      final distToPrimary = (requestedOffset - primaryOffset).abs();
      final isLowOffsetRequest =
          requestedOffset < DownloadPriority.lowOffsetThresholdBytes;
      if (distToPrimary > DownloadPriority.closestToPrimaryBytes &&
          !isMoovDownload &&
          !isLowOffsetRequest) {
        blockingPriority = DownloadPriority.deepBuffer;
      }
    }

    final calculatedPriority = shouldForcePriority
        ? blockingPriority
        : _calculateDynamicPriority(distanceToPlayback);

    final isLowOffsetRequest =
        requestedOffset < DownloadPriority.lowOffsetThresholdBytes;
    final distToPrimaryForFloor = (requestedOffset - primaryOffset).abs();
    final isClosestToPrimary =
        distToPrimaryForFloor < DownloadPriority.closestToPrimaryBytes;

    if (!isLowOffsetRequest) return calculatedPriority;

    final hasActiveHighPriority =
        _getOrCreateState(fileId).activePriority >= DownloadPriority.deepBuffer;

    if (hasActiveHighPriority) {
      return (calculatedPriority > DownloadPriority.highFloor)
          ? DownloadPriority.highFloor
          : calculatedPriority;
    }
    if (calculatedPriority < DownloadPriority.highFloor) {
      return isClosestToPrimary
          ? DownloadPriority.critical
          : DownloadPriority.highFloor;
    }
    return calculatedPriority;
  }

  bool _isDisplacementBlocked(
    int fileId,
    int requestedOffset,
    int priority,
    int activeDownloadTarget,
    int sequentialWindow,
    DateTime now, {
    required bool isBlocking,
    required bool forceRestart,
    required bool isSeekRequest,
  }) {
    final activePriority = _getOrCreateState(fileId).activePriority;
    final isHighPriorityActive = activePriority >= DownloadPriority.highFloor;

    final lastStart = _getOrCreateState(fileId).lastOffsetChangeTime;
    if (lastStart != null &&
        now.difference(lastStart).inMilliseconds <
            ProxyConfig.rapidSwitchDebounceMs &&
        !isBlocking &&
        !isSeekRequest) {
      final activeOffset = _getOrCreateState(fileId).activeDownloadOffset ?? -1;
      if (!(requestedOffset >= activeOffset &&
          requestedOffset < activeOffset + sequentialWindow)) {
        _debugLog(
          'Proxy: DEBOUNCED rapid switch from $activeOffset to $requestedOffset. Ignoring.',
        );
        return true;
      }
    }

    final isLowOffsetRequestForProtection =
        requestedOffset < DownloadPriority.lowOffsetThresholdBytes;
    if (!isBlocking &&
        !forceRestart &&
        !isLowOffsetRequestForProtection &&
        isHighPriorityActive &&
        priority < activePriority - DownloadPriority.priorityProtectionGap &&
        (requestedOffset - activeDownloadTarget).abs() >
            DownloadPriority.cacheEdgeDistanceBytes) {
      final throttleNow = DateTime.now();
      final lastLog = _lastProtectedLogTime[fileId];
      if (lastLog == null || throttleNow.difference(lastLog) >= _protectedLogThrottle) {
        _lastProtectedLogTime[fileId] = throttleNow;
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
      return true;
    }

    return false;
  }

  Future<void> _executeDownload(
    int fileId,
    int requestedOffset,
    int priority,
    bool isMoovDownload, {
    required bool forceRestart,
  }) async {
    _logTrace(
      'Downloading from offset $requestedOffset for $fileId '
      '(priority: $priority, limit: unlimited)',
      fileId: fileId,
    );

    final state = _getOrCreateState(fileId);
    state.activeDownloadOffset = requestedOffset;
    state.activePriority = priority;
    state.lastOffsetChangeTime = DateTime.now();
    state.downloadStartTime = DateTime.now();
    state.lastDownloadFileCallTime = DateTime.now();

    const int downloadLimit = 0;

    if (forceRestart) {
      _logTrace(
        'Processing force restart for $fileId: sending cancelDownloadFile first',
        fileId: fileId,
      );
      _tdlib.send({
        '@type': 'cancelDownloadFile',
        'file_id': fileId,
        'only_if_pending': false,
      });
      await Future.delayed(
        const Duration(milliseconds: ProxyConfig.cancelToDownloadDelayMs),
      );

      final cachedAfterCancel = _filePaths[fileId];
      if (cachedAfterCancel != null && cachedAfterCancel.isDownloadingActive) {
        _logTrace(
          'Cancelación no confirmada para $fileId después de '
          '${ProxyConfig.cancelToDownloadDelayMs}ms, enviando segundo cancel',
          fileId: fileId,
        );
        _tdlib.send({
          '@type': 'cancelDownloadFile',
          'file_id': fileId,
          'only_if_pending': false,
        });
        await Future.delayed(
          const Duration(milliseconds: ProxyConfig.cancelRetryDelayMs),
        );
      }
    }

    _tdlib.send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': priority,
      'offset': requestedOffset,
      'limit': downloadLimit,
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
  int _calculateDynamicPriority(int distanceBytes) {
    return DownloadPriority.fromDistance(distanceBytes);
  }

  // ============================================================
  // GUARD CLAUSES for _startDownloadAtOffset
  // ============================================================

  @visibleForTesting
  bool isFileComplete(ProxyFileInfo? cached) {
    return cached != null && cached.isCompleted;
  }

  @visibleForTesting
  bool isEofRequest(int requestedOffset, ProxyFileInfo? cached) {
    final totalSize = cached?.totalSize ?? 0;
    return totalSize > 0 && requestedOffset >= totalSize;
  }

  @visibleForTesting
  bool isStaleSeekGeneration(int? seekGeneration, int fileId) {
    return seekGeneration != null &&
        seekGeneration != (_seekGeneration[fileId] ?? 0);
  }

  int _computeLocalSeekThreshold(int totalSize) {
    return ProxyConfig.scaled(
      totalSize,
      ProxyConfig.seekDetectionThresholdPercent,
      ProxyConfig.seekDetectionMinBytes,
      ProxyConfig.seekDetectionMaxBytes,
    );
  }

  int _computeSequentialWindow(int totalSize) {
    return ProxyConfig.scaled(
      totalSize,
      ProxyConfig.sequentialReadThresholdPercent,
      ProxyConfig.sequentialReadMinBytes,
      ProxyConfig.sequentialReadMaxBytes,
    );
  }

  /// Handles the forced MOOV download lifecycle: release when complete,
  /// timeout after no progress, or block non-MOOV requests while loading.
  ///
  /// Returns `true` if the request was handled (caller should return),
  /// `false` if the caller should proceed with normal download logic.
  Future<bool> _handleForcedMoov(
    int fileId,
    int requestedOffset,
    ProxyFileInfo? cached,
  ) async {
    final forcedOffset = _getOrCreateState(fileId).forcedMoovOffset;
    if (forcedOffset == null) return false;

    final availableAtForced = await _getDownloadedPrefixSize(fileId, forcedOffset);
    final totalSize = cached?.totalSize ?? 0;
    final neededSize = totalSize > forcedOffset ? totalSize - forcedOffset : 0;

    final targetSize = neededSize > 0
        ? min(neededSize, ProxyConfig.moovDownloadMaxBytes)
        : ProxyConfig.scaled(
            totalSize,
            ProxyConfig.moovPreloadThresholdPercent,
            ProxyConfig.moovPreloadMinBytes,
            ProxyConfig.moovPreloadMaxBytes,
          );

    if (availableAtForced >= targetSize) {
      _debugLog(
        'Proxy: Forced moov download satisfied ($availableAtForced bytes >= $targetSize), releasing lock for $fileId',
      );
      _getOrCreateState(fileId).forcedMoovOffset = null;
      _getOrCreateState(fileId).forcedMoovStartTime = null;
      _getOrCreateState(fileId).forcedMoovAbsoluteStartTime = null;
      _getOrCreateState(fileId).forcedMoovLastProgress = 0;
      _getOrCreateState(fileId).activePriority = 0;

      if (!_abortedRequests.contains(fileId)) {
        final primaryOffset =
            _getOrCreateState(fileId).primaryPlaybackOffset ?? 0;
        _debugLog(
          'Proxy: POST-MOOV resuming download from offset $primaryOffset for $fileId',
        );
        _getOrCreateState(fileId).activeDownloadOffset = primaryOffset;
        _getOrCreateState(fileId).lastOffsetChangeTime = DateTime.now();
        _tdlib.send({
          '@type': 'downloadFile',
          'file_id': fileId,
          'priority': DownloadPriority.critical,
          'offset': primaryOffset,
          'limit': 0,
          'synchronous': false,
        });
      }
      return false;
    }

    if (requestedOffset != forcedOffset) {
      final moovState = _getOrCreateState(fileId);

      // H6 FIX: Absolute timeout — never resets, fires even if tiny progress
      // keeps resetting the progress timer. Prevents the file from being
      // locked in loadingMoov indefinitely.
      final absStartTime = moovState.forcedMoovAbsoluteStartTime;
      if (absStartTime != null &&
          DateTime.now().difference(absStartTime).inSeconds >=
              ProxyConfig.moovDownloadAbsoluteTimeoutSeconds) {
        _logError(
          'MOOV DOWNLOAD ABSOLUTE TIMEOUT for $fileId: '
          '${DateTime.now().difference(absStartTime).inSeconds}s total '
          '(have $availableAtForced/$targetSize bytes). '
          'File appears damaged — blocking further requests.',
          fileId: fileId,
        );
        moovState.forcedMoovOffset = null;
        moovState.forcedMoovStartTime = null;
        moovState.forcedMoovAbsoluteStartTime = null;
        moovState.forcedMoovLastProgress = 0;
        final error = StreamingError.corruptFile(fileId);
        _notifyErrorIfNew(fileId, error);
        _abortedRequests.add(fileId);
        final waiters = _byteAvailabilityWaiters.remove(fileId);
        if (waiters != null) {
          for (final entry in waiters) {
            if (!entry.value.isCompleted) entry.value.complete();
          }
        }
        return true;
      }

      final moovStartTime = moovState.forcedMoovStartTime;
      if (moovStartTime != null) {
        final moovElapsed = DateTime.now().difference(moovStartTime);
        if (availableAtForced > moovState.forcedMoovLastProgress) {
          moovState.forcedMoovStartTime = DateTime.now();
          moovState.forcedMoovLastProgress = availableAtForced;
        } else if (moovElapsed.inSeconds >= ProxyConfig.moovDownloadTimeoutSeconds) {
          _logError(
            'MOOV DOWNLOAD TIMEOUT for $fileId: no progress for ${moovElapsed.inSeconds}s '
            '(have $availableAtForced/$targetSize bytes at offset $forcedOffset). '
            'File appears damaged — blocking further requests.',
            fileId: fileId,
          );
          moovState.forcedMoovOffset = null;
          moovState.forcedMoovStartTime = null;
          moovState.forcedMoovAbsoluteStartTime = null;
          moovState.forcedMoovLastProgress = 0;
          final error = StreamingError.corruptFile(fileId);
          _notifyErrorIfNew(fileId, error);
          _abortedRequests.add(fileId);
          final waiters = _byteAvailabilityWaiters.remove(fileId);
          if (waiters != null) {
            for (final entry in waiters) {
              if (!entry.value.isCompleted) entry.value.complete();
            }
          }
          return true;
        }
      }
      final moovLogNow = DateTime.now();
      final lastMoovLog = _lastMoovIgnoreLogTime[fileId];
      if (lastMoovLog == null ||
          moovLogNow.difference(lastMoovLog) >= _waitingLogThrottle) {
        _lastMoovIgnoreLogTime[fileId] = moovLogNow;
        _debugLog(
          'Proxy: Ignoring request for $requestedOffset while forcing moov download at $forcedOffset for $fileId (have $availableAtForced/$targetSize)',
        );
      }
      return true;
    }

    return false;
  }

  bool _isScrubbingDebounced(int fileId, int requestedOffset, int totalSize) {
    final lastServed = _getOrCreateState(fileId).lastServedOffset ?? 0;
    final isActivePlayback =
        lastServed >
        ProxyConfig.scaled(
          totalSize,
          ProxyConfig.activePlaybackThresholdPercent,
          ProxyConfig.activePlaybackMinBytes,
          ProxyConfig.activePlaybackMaxBytes,
        );

    if (!isActivePlayback) return false;

    // M6: Solo debouncear si ya hay un seek pendiente (2do+ seek en secuencia).
    // El primer seek de una secuencia pasa sin debounce, eliminando 150ms de
    // latencia innecesaria para seeks individuales.
    if (_pendingSeekOffsets.containsKey(fileId)) {
      _handleDebouncedSeek(fileId, requestedOffset);
      return true;
    }

    // M6: Edge case — ventana muy corta (50ms) para capturar races donde
    // el primer seek debounced ya disparó su timer pero el streaming loop
    // no lo ha procesado todavía.
    final debounceLastSeek = _getOrCreateState(fileId).lastSeekTime;
    if (debounceLastSeek != null &&
        DateTime.now().difference(debounceLastSeek).inMilliseconds < 50) {
      _handleDebouncedSeek(fileId, requestedOffset);
      return true;
    }

    return false;
  }

  Future<bool> _isDataAvailableNow(int fileId, int requestedOffset) async {
    final availableAtOffset = await _getDownloadedPrefixSize(
      fileId,
      requestedOffset,
    );
    return availableAtOffset > 0;
  }

  bool _isRateLimited(
    int fileId, {
    required bool isBlocking,
    required bool forceRestart,
    required bool isSeekRequest,
  }) {
    final fs = _getOrCreateState(fileId);
    final lastCall = fs.lastDownloadFileCallTime;
    if (lastCall != null && !isBlocking && !forceRestart && !isSeekRequest) {
      final elapsed = DateTime.now().difference(lastCall).inMilliseconds;
      if (elapsed < ProxyConfig.minDownloadCallIntervalMs) {
        _logTrace(
          'Rate limited downloadFile for $fileId '
          '(${elapsed}ms since last call)',
          fileId: fileId,
        );
        return true;
      }
    }
    return false;
  }

  bool _isAtFrontier(
    int fileId,
    int requestedOffset,
    int currentDownloadOffset,
    int currentPrefix,
    int totalSize, {
    required bool forceRestart,
  }) {
    final downloadFrontier = currentDownloadOffset + currentPrefix;
    final distanceFromFrontier = requestedOffset - downloadFrontier;
    final isDownloading = _filePaths[fileId]?.isDownloadingActive ?? false;
    final frontierProximity = ProxyConfig.scaled(
      totalSize,
      ProxyConfig.frontierProximityThresholdPercent,
      ProxyConfig.frontierProximityMinBytes,
      ProxyConfig.frontierProximityMaxBytes,
    );
    final recentDownload = _getOrCreateState(
      fileId,
    ).isRecentDownload(const Duration(seconds: 10));
    final atFrontier =
        distanceFromFrontier >= 0 && distanceFromFrontier < frontierProximity;

    return !forceRestart && atFrontier && (isDownloading || recentDownload);
  }

  bool _isAlreadyTargeting(
    int fileId,
    int requestedOffset,
    ProxyFileInfo? cached, {
    int? currentActiveOffset,
    required bool forceRestart,
  }) {
    final isDownloadingCached = cached?.isDownloadingActive ?? false;
    return !forceRestart &&
        currentActiveOffset == requestedOffset &&
        isDownloadingCached;
  }

  void _detectMoovAtEnd(int fileId, int requestedOffset, int fileSize) {
    if (fileSize <= 0) return;
    final distanceFromEnd = fileSize - requestedOffset;
    final moovThresholdBytes = ProxyConfig.scaled(
      fileSize,
      ProxyConfig.moovRegionThresholdPercent,
      ProxyConfig.moovRegionMinBytes,
      ProxyConfig.moovRegionMaxBytes,
    );

    final mightBeMoovRequest = distanceFromEnd < moovThresholdBytes;

    final sampleTable = _sampleTableCache[fileId];
    bool isConfirmedVideoData = false;
    if (sampleTable != null && sampleTable.samples.isNotEmpty) {
      final lastSample = sampleTable.samples.last;
      final lastVideoByteOffset = lastSample.byteOffset + lastSample.size;
      isConfirmedVideoData = requestedOffset < lastVideoByteOffset;

      if (mightBeMoovRequest && isConfirmedVideoData) {
        _debugLog(
          'Proxy: Offset $requestedOffset is near end but confirmed as video data '
          '(last sample ends at $lastVideoByteOffset)',
        );
      }
    }

    final isMoovAtomRequest = mightBeMoovRequest && !isConfirmedVideoData;
    if (isMoovAtomRequest && !_getOrCreateState(fileId).isMoovAtEnd) {
      _getOrCreateState(fileId).isMoovAtEnd = true;
      _debugLog(
        'Proxy: File $fileId has moov atom at end (not optimized for streaming)',
      );
    }
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

    // M7: Grace period adaptativo post-seek debounced.
    // Fast network: 1s, Normal: 3s, Slow: 6s.
    // Evita falsos stalls en redes lentas y acelera recuperación en rápidas.
    final lastDebounced = state.lastDebouncedSeekTime;
    if (lastDebounced != null) {
      final metricsForGrace = _downloadMetrics[fileId];
      final Duration debounceGrace;
      if (metricsForGrace == null || metricsForGrace.bytesPerSecond == 0) {
        debounceGrace = const Duration(seconds: 3);
      } else if (metricsForGrace.isFastNetwork) {
        debounceGrace = const Duration(seconds: 1);
      } else if (metricsForGrace.isSlowNetwork) {
        debounceGrace = const Duration(seconds: 6);
      } else {
        debounceGrace = const Duration(seconds: 3);
      }
      if (DateTime.now().difference(lastDebounced) < debounceGrace) {
        return;
      }
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

        // FIX: Validate that the waiting offset hasn't changed during backoff.
        // If no connection is waiting anymore, skip the restart entirely.
        // If a different offset is now being waited on, use that instead.
        final currentWaitingOffset = currentState.waitingForOffset;
        if (currentWaitingOffset == null) {
          _logTrace(
            'Stall backoff skipped for $fileId - no connection waiting',
            fileId: fileId,
          );
          return;
        }
        final effectiveOffset = currentWaitingOffset != waitingOffset
            ? currentWaitingOffset
            : waitingOffset;
        if (effectiveOffset != waitingOffset) {
          _debugLog(
            'Proxy: Stall backoff - waiting offset changed from '
            '${waitingOffset ~/ 1024}KB to ${effectiveOffset ~/ 1024}KB, '
            'using new offset',
          );
        }
        _startDownloadAtOffset(fileId, effectiveOffset, forceRestart: true);
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
    if (totalSize <= 0) return;

    final state = _getOrCreateState(fileId);
    if (state.forcedMoovOffset != null) return; // Ya en progreso
    if (state.loadState == FileLoadState.moovReady ||
        state.loadState == FileLoadState.playing) {
      return;
    }
    if (_abortedRequests.contains(fileId)) return;

    // H1: Skip proactive MOOV if user seeked since detection was scheduled.
    // Reemplaza la ventana de 3s por tiempo con una verificación basada en
    // generación de seek. Si la generación cambió, el seek del usuario tiene
    // prioridad sobre la precarga del MOOV.
    // Esto evita la condición de carrera donde un callback asíncrono re-adquiere
    // forcedMoovOffset después de que signalUserSeek ya lo liberó.
    final detectionGen = _moovDetectionSeekGen[fileId];
    final currentGen = _seekGeneration[fileId] ?? 0;
    if (detectionGen != null && detectionGen != currentGen) {
      _debugLog(
        'Proxy: H1 - Skipping proactive MOOV for $fileId: '
        'seek generation changed ($detectionGen -> $currentGen) '
        'since detection was scheduled',
      );
      _moovDetectionSeekGen.remove(fileId);
      return;
    }

    // Si ya detectamos offset exacto de MOOV, usarlo directamente para
    // ahorrar megabytes. Si no, calculamos el porcentaje máximo.
    int moovOffset;
    if (state.exactMoovOffset != null && state.exactMoovOffset! > 0 && state.exactMoovOffset! < totalSize) {
      moovOffset = state.exactMoovOffset!;
      _debugLog('Proxy: P1 PROACTIVE MOOV - Using exact MDAT bounding offset $moovOffset');
    } else {
      final moovPreloadBytes = ProxyConfig.scaled(
        totalSize,
        ProxyConfig.moovPreloadThresholdPercent,
        ProxyConfig.moovPreloadMinBytes,
        ProxyConfig.moovPreloadMaxBytes,
      );
      moovOffset = totalSize - moovPreloadBytes;
    }

    // Activar lock: bloquea otras descargas hasta que MOOV termine
    state.forcedMoovOffset = moovOffset;
    state.forcedMoovStartTime = DateTime.now();
    state.forcedMoovAbsoluteStartTime = DateTime.now(); // H6: absolute deadline
    state.forcedMoovLastProgress = 0;
    state.loadState = FileLoadState.loadingMoov;

    _debugLog(
      'Proxy: P1 PROACTIVE MOOV - Starting download at offset $moovOffset '
      '(last ${(totalSize - moovOffset) ~/ 1024}KB) for file $fileId',
    );

    // Iniciar descarga - cancela la descarga secuencial desde 0.
    // CRITICAL FIX: Usar isBlocking + forceRestart para garantizar que:
    // 1. isBlocking: bypasea el cooldown de _startDownloadAtOffset (que lo
    //    silenciaba si el streaming loop acababa de llamar _startDownloadAtOffset).
    // 2. forceRestart: envía cancelDownloadFile primero, evitando que TDLib
    //    ignore el downloadFile como NO-OP si ya hay una descarga activa.
    // Sin esto, el MOOV se queda en 0 bytes indefinidamente bloqueando todo.
    _startDownloadAtOffset(fileId, moovOffset,
        isBlocking: true, forceRestart: true);
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

      // H1: Capturar la generación de seek ANTES de programar el async,
      // para detectar si un seek ocurrió durante la detección asíncrona.
      _moovDetectionSeekGen[fileId] = _seekGeneration[fileId] ?? 0;
      final capturedSeekGen = _moovDetectionSeekGen[fileId]!;

      // Asynchronously detect - this is non-blocking
      _detectMoovPosition(fileId, info.totalSize).then((position) {
        // H1: Verificar que no hubo un seek del usuario mientras tanto
        final currentGen = _seekGeneration[fileId] ?? 0;
        if (currentGen != capturedSeekGen) {
          _debugLog(
            'Proxy: H1 - Skipping async MOOV detection result for $fileId: '
            'seek generation changed ($capturedSeekGen -> $currentGen)',
          );
          return;
        }
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
      // H1: Capturar generación antes de la descarga proactiva (mismo patrón)
      _moovDetectionSeekGen[fileId] = _seekGeneration[fileId] ?? 0;
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
          int atomSize = _readMoovUint32BE(header, offset);
          final atomType = String.fromCharCodes(
            header.sublist(offset + 4, offset + 8),
          );

          int headerBytes = 8;
          // Handle 64-bit atom sizes (atomSize == 1 means 64-bit size is at offset+8)
          if (atomSize == 1) {
            if (offset + 16 > header.length) break;
            atomSize = _readMoovUint64BE(header, offset + 8);
            headerBytes = 16;
          }

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
            
            // Calculate EXACT offset of MOOV atom which naturally follows MDAT chunks
            // By doing this we can download just the exact MOOV bytes instead of a crude larger chunk
            if (atomSize > 0) {
              final exactMoov = offset + atomSize;
              _getOrCreateState(fileId).exactMoovOffset = exactMoov;
              _debugLog(
                'Proxy: MOOV PRE-DETECT - File $fileId has MOOV at END (mdat implies MOOV at exact offset $exactMoov)',
              );
            } else {
              _debugLog(
                'Proxy: MOOV PRE-DETECT - File $fileId has MOOV at END (mdat found at offset $offset, unknown size)',
              );
            }
            return MoovPosition.end;
          }

          // Skip known non-media atoms and keep walking
          if (_skipAtomTypes.contains(atomType)) {
            if (atomSize < headerBytes) break; // Malformed atom, stop
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

  /// Read uint64 big-endian from byte list
  int _readMoovUint64BE(List<int> data, int offset) {
    if (data.length < offset + 8) return 0;
    int high = _readMoovUint32BE(data, offset);
    int low = _readMoovUint32BE(data, offset + 4);
    // Unsigned 64-bit combination within Dart's int max value bounds
    return (high * 4294967296) + low;
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
    _tdlib.send({
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

    // H2: Rutear preview a través del pipeline de guardias de
    // _startDownloadAtOffset para beneficiarse de rate limiting,
    // displacement blocking, cooldown y zombie protection.
    // Usa prioridad medium (16) para no competir con playback principal.
    _debugLog('Proxy: Preview seek preload at $estimatedOffset for $fileId');

    _lastPreviewTime[fileId] = now;

    _startDownloadAtOffset(
      fileId,
      estimatedOffset,
      isPreview: true,
      isBlocking: false,
      forceRestart: false,
    );
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

    // I-B: Parse from file in an isolate to avoid blocking the event loop.
    // Mp4SampleTable.parse() does extensive binary parsing that can block
    // the main isolate for hundreds of ms on files with many samples.
    try {
      final file = File(fileInfo.path);
      if (!await file.exists()) {
        _sampleTableCache[fileId] = null;
        return;
      }

      _sampleTableCache[fileId] = await Isolate.run(
        () => _parseSampleTableInIsolate(fileInfo.path, fileInfo.totalSize),
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

// ============================================================
// I-B: Top-level function for isolate-based sample table parsing
// ============================================================

/// Parses an MP4 sample table in a separate isolate to avoid blocking
/// the main event loop during extensive binary parsing.
///
/// [filePath] must be an absolute path to an existing MP4 file.
/// Returns null if the file doesn't exist or parsing fails.
Future<Mp4SampleTable?> _parseSampleTableInIsolate(
  String filePath,
  int fileSize,
) async {
  final file = File(filePath);
  if (!await file.exists()) return null;
  final raf = await file.open(mode: FileMode.read);
  try {
    return await Mp4SampleTable.parse(raf, fileSize);
  } finally {
    await raf.close();
  }
}
