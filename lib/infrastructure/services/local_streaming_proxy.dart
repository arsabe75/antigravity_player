import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'telegram_service.dart';
import 'mp4_sample_table.dart';
import 'telegram_cache_service.dart';

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

/// Loading state machine for MOOV-first initialization.
/// Ensures proper sequence: MOOV loaded first, then seek to saved position.
enum FileLoadState {
  /// Initial state - no loading started
  idle,

  /// Loading MOOV atom (required for playback metadata)
  loadingMoov,

  /// MOOV is ready, file can be played
  moovReady,

  /// Seeking to a specific position
  seeking,

  /// Normal playback in progress
  playing,
}

/// Metrics for tracking download speed per file.
/// Used for adaptive buffer decisions inspired by Telegram Android's approach.
class _DownloadMetrics {
  DateTime _lastUpdateTime = DateTime.now();
  int _bytesInWindow = 0;
  int _totalBytesDownloaded = 0;
  double _averageBytesPerSecond = 0;

  /// Total bytes downloaded since tracking started
  int get totalBytesDownloaded => _totalBytesDownloaded;
  void recordBytes(int bytes) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastUpdateTime).inMilliseconds;

    _bytesInWindow += bytes;
    _totalBytesDownloaded += bytes;

    // Update average every 500ms
    if (elapsed >= 500) {
      final currentSpeed = _bytesInWindow / (elapsed / 1000);
      // Exponential moving average
      _averageBytesPerSecond = _averageBytesPerSecond == 0
          ? currentSpeed
          : (_averageBytesPerSecond * 0.7 + currentSpeed * 0.3);
      _bytesInWindow = 0;
      _lastUpdateTime = now;
    }
  }

  /// Current download speed in bytes/second
  double get bytesPerSecond => _averageBytesPerSecond;

  /// Is the network considered "fast"? (> 2 MB/s)
  bool get isFastNetwork => _averageBytesPerSecond > 2 * 1024 * 1024;

  /// Is download stalled? (< 50 KB/s for more than 2s)
  bool get isStalled {
    final elapsed = DateTime.now().difference(_lastUpdateTime).inMilliseconds;
    return elapsed > 2000 && _averageBytesPerSecond < 50 * 1024;
  }

  // ============================================================
  // STALL TRACKING FOR ADAPTIVE POST-SEEK BUFFER
  // ============================================================

  int _recentStallCount = 0;
  DateTime? _lastStallTime;

  /// Record a stall event
  void recordStall() {
    _recentStallCount++;
    _lastStallTime = DateTime.now();
  }

  /// Returns stall count in last 30 seconds
  int get recentStallCount {
    final now = DateTime.now();
    if (_lastStallTime != null &&
        now.difference(_lastStallTime!).inSeconds > 30) {
      _recentStallCount = 0; // Reset after 30s without stalls
    }
    return _recentStallCount;
  }

  /// Reset stall count (e.g., after successful playback)
  void resetStallCount() {
    _recentStallCount = 0;
  }
}

/// LRU Cache for streaming data.
/// Caches recently read chunks to enable instant backward seeks.
class _StreamingLRUCache {
  static const int maxCacheSize = 32 * 1024 * 1024; // 32MB max per file
  static const int chunkSize = 512 * 1024; // 512KB chunks

  final Map<int, Uint8List> _chunks = {}; // chunkIndex -> data
  final Map<int, int> _chunkOffsets =
      {}; // chunkIndex -> offset within chunk (for partial chunks)
  final List<int> _lruOrder = []; // Most recently used at end
  int _currentSize = 0;

  /// Get cached data for the given range.
  /// Returns null if data is not fully cached.
  Uint8List? get(int offset, int length) {
    if (length <= 0) return null;

    final startChunk = offset ~/ chunkSize;
    final endChunk = (offset + length - 1) ~/ chunkSize;

    // Check if all required chunks are cached AND contain the data we need
    for (int i = startChunk; i <= endChunk; i++) {
      if (!_chunks.containsKey(i)) {
        return null; // Cache miss
      }

      // Verify the chunk contains the range we need
      final chunk = _chunks[i]!;
      final chunkStartOffset = _chunkOffsets[i] ?? 0;
      final chunkStart = i * chunkSize + chunkStartOffset;
      final chunkEnd = chunkStart + chunk.length;

      // Calculate the range we need from this chunk
      final needStart = i == startChunk ? offset : i * chunkSize;
      final needEnd = i == endChunk ? offset + length : (i + 1) * chunkSize;

      if (needStart < chunkStart || needEnd > chunkEnd) {
        return null; // Chunk doesn't cover required range
      }
    }

    // All chunks are cached - assemble the result
    final result = Uint8List(length);
    int resultOffset = 0;

    for (int i = startChunk; i <= endChunk; i++) {
      final chunk = _chunks[i]!;
      final chunkStartOffset = _chunkOffsets[i] ?? 0;
      final chunkAbsoluteStart = i * chunkSize + chunkStartOffset;

      // Calculate which part of this chunk we need
      final requestStart = i == startChunk ? offset : i * chunkSize;
      final requestEnd = i == endChunk ? offset + length : (i + 1) * chunkSize;

      // Convert to chunk-local offsets
      final copyStart = requestStart - chunkAbsoluteStart;
      // FIX: Ensure copyEnd doesn't exceed actual chunk length
      final copyEnd = min(requestEnd - chunkAbsoluteStart, chunk.length);
      final copyLen = min(copyEnd - copyStart, length - resultOffset);

      if (copyStart >= 0 && copyStart < chunk.length && copyLen > 0) {
        // FIX: Ensure we don't read beyond chunk boundary
        final safeEnd = min(copyStart + copyLen, chunk.length);
        result.setRange(
          resultOffset,
          resultOffset + (safeEnd - copyStart),
          chunk.sublist(copyStart, safeEnd),
        );
        resultOffset += safeEnd - copyStart;
      }

      // Update LRU order
      _lruOrder.remove(i);
      _lruOrder.add(i);
    }

    // Verify we got all the data we expected
    if (resultOffset < length) {
      return null; // Incomplete data
    }

    return result;
  }

  /// Store data in cache, evicting old chunks if necessary.
  /// Handles non-aligned offsets by storing partial chunks with their offset.
  void put(int offset, Uint8List data) {
    if (data.isEmpty) return;

    final startChunk = offset ~/ chunkSize;
    final startChunkOffset = offset % chunkSize;

    int dataOffset = 0;
    int chunkIndex = startChunk;

    while (dataOffset < data.length) {
      final isFirstChunk = chunkIndex == startChunk;

      // For the first chunk, we may start from a non-zero offset within the chunk
      final offsetInChunk = isFirstChunk ? startChunkOffset : 0;

      // Calculate how much data goes into this chunk
      final spaceInChunk = chunkSize - offsetInChunk;
      final remaining = data.length - dataOffset;
      final chunkLen = min(spaceInChunk, remaining);

      if (chunkLen > 0) {
        final chunkData = data.sublist(dataOffset, dataOffset + chunkLen);

        // Check if we should merge with existing chunk
        if (_chunks.containsKey(chunkIndex)) {
          final existingChunk = _chunks[chunkIndex]!;
          final existingOffset = _chunkOffsets[chunkIndex] ?? 0;

          // Try to merge if ranges are adjacent or overlapping
          final existingStart = existingOffset;
          final existingEnd = existingOffset + existingChunk.length;
          final newStart = offsetInChunk;
          final newEnd = offsetInChunk + chunkLen;

          if (newEnd >= existingStart && newStart <= existingEnd) {
            // Ranges overlap or are adjacent - merge
            final mergedStart = min(existingStart, newStart);
            final mergedEnd = max(existingEnd, newEnd);
            final mergedLen = mergedEnd - mergedStart;

            final merged = Uint8List(mergedLen);

            // Copy existing data
            merged.setRange(
              existingStart - mergedStart,
              existingStart - mergedStart + existingChunk.length,
              existingChunk,
            );

            // Copy new data (may overwrite some existing data)
            merged.setRange(
              newStart - mergedStart,
              newStart - mergedStart + chunkLen,
              chunkData,
            );

            // Update size tracking
            _currentSize = _currentSize - existingChunk.length + merged.length;
            _chunks[chunkIndex] = merged;
            _chunkOffsets[chunkIndex] = mergedStart;
          }
          // If ranges don't overlap/adjacent, keep existing (don't fragment cache)
        } else {
          // No existing chunk - store new data

          // Evict if necessary
          while (_currentSize + chunkLen > maxCacheSize &&
              _lruOrder.isNotEmpty) {
            final evictIndex = _lruOrder.removeAt(0);
            final evicted = _chunks.remove(evictIndex);
            _chunkOffsets.remove(evictIndex);
            if (evicted != null) {
              _currentSize -= evicted.length;
            }
          }

          _chunks[chunkIndex] = chunkData;
          _chunkOffsets[chunkIndex] = offsetInChunk;
          _currentSize += chunkLen;
        }

        _lruOrder.remove(chunkIndex);
        _lruOrder.add(chunkIndex);
      }

      dataOffset += chunkLen;
      chunkIndex++;
    }
  }

  /// Clear all cached data.
  void clear() {
    _chunks.clear();
    _chunkOffsets.clear();
    _lruOrder.clear();
    _currentSize = 0;
  }

  /// Current cache size in bytes.
  int get size => _currentSize;

  /// Number of cached chunks.
  int get chunkCount => _chunks.length;
}

class LocalStreamingProxy {
  static final LocalStreamingProxy _instance = LocalStreamingProxy._internal();
  factory LocalStreamingProxy() => _instance;
  LocalStreamingProxy._internal();

  HttpServer? _server;
  int _port = 0;

  // Cache of file_id -> ProxyFileInfo
  final Map<int, ProxyFileInfo> _filePaths = {};

  // Active download requests
  final Set<int> _activeDownloadRequests = {};

  // File update notifiers for blocking waits
  final Map<int, StreamController<void>> _fileUpdateNotifiers = {};

  // Track aborted requests to cancel waiting loops
  final Set<int> _abortedRequests = {};

  // DIRECT 1:1 MAPPING: Track the current download offset per file
  // No predictive/two-phase logic - we serve exactly what the player requests
  final Map<int, int> _activeDownloadOffset = {};

  // Throttle offset changes to avoid excessive downloadFile calls
  final Map<int, DateTime> _lastOffsetChangeTime = {};

  // ============================================================
  // TELEGRAM ANDROID-INSPIRED IMPROVEMENTS
  // ============================================================

  // PRELOAD ADAPTATIVO: Bytes mínimos antes de servir datos al player
  // Inspired by ExoPlayer's bufferForPlaybackMs
  static const int _minPreloadBytes = 2 * 1024 * 1024; // 2MB default preload
  static const int _fastNetworkPreload =
      1024 * 1024; // 1MB for fast network (increased from 512KB)
  static const int _slowNetworkPreload =
      4 * 1024 * 1024; // 4MB for slow network

  // MÉTRICAS DE VELOCIDAD: Track download speed for adaptive decisions
  final Map<int, _DownloadMetrics> _downloadMetrics = {};

  // IN-MEMORY LRU CACHE: Cache recently read data for instant backward seeks
  final Map<int, _StreamingLRUCache> _streamingCaches = {};

  // SEEK RÁPIDO: Track if we recently seeked to reduce buffer requirement
  final Map<int, DateTime> _lastSeekTime = {};
  // Note: Seek window is now 2000ms (inline in _startDownloadAtOffset for Phase 2)

  // Track all active HTTP request offsets per file for cleanup on close
  final Map<int, Set<int>> _activeHttpRequestOffsets = {};

  // PRIMARY PLAYBACK TRACKING: Track the lowest requested offset as the "primary playback" position.
  // This helps distinguish actual playback from metadata probes at end-of-file (moov atom).
  // Stall recovery should only act on the primary playback position, not on metadata probes.
  final Map<int, int> _primaryPlaybackOffset = {};

  // Track last served offset to detect seeks
  final Map<int, int> _lastServedOffset = {};

  // Map to track blacklisted "zombie" offsets that should be ignored temporarily
  // until the user explicitly seeks back to them OR they expire after 5 seconds.
  // key: fileId, value: (offset, timestamp)
  final Map<int, int> _zombieBlacklist = {};
  final Map<int, DateTime> _zombieBlacklistTime =
      {}; // When the zombie was created
  static const int _zombieExpirationMs = 5000; // Zombies expire after 5 seconds

  // VIRTUAL ACTIVE STATE: Track when download last finished to simulate "sticky" active state
  final Map<int, DateTime> _lastActiveDownloadEndTime = {};
  final Map<int, int> _lastActiveDownloadOffset = {};
  final Map<int, DateTime> _lastPrimaryUpdateTime = {};

  // MOOV ATOM PROTECTION: Track when download started for each file
  // This helps avoid canceling initial download when moov atom is requested
  final Map<int, DateTime> _downloadStartTime = {};

  // P1 FIX: EXPLICIT USER SEEK SIGNALING
  // When MediaKit calls seekTo(), it notifies the proxy explicitly.
  // This helps distinguish user seeks from read-ahead/buffer requests.
  final Set<int> _userSeekInProgress = {};
  final Map<int, int> _userSeekTargetMs = {}; // Target time in milliseconds

  // MOOV STABILIZE: Track when moov requests should be allowed (after delay)
  final Map<int, DateTime> _moovUnblockTime = {};

  // MOOV STABILIZE: Track files that have completed stabilization (don't re-trigger)
  final Set<int> _moovStabilizeCompleted = {};

  // P1 FIX: MOOV DOWNLOAD LOCK - Track active MOOV downloads to prevent cancellation
  // When MOOV is downloading, block requests for low offsets (< 50MB)
  final Map<int, DateTime> _moovDownloadStart = {};
  static const int _moovDownloadTimeoutMs = 15000; // Allow up to 15s for MOOV

  // ============================================================
  // PHASE 1: DRKLO-INSPIRED OPTIMIZATIONS
  // ============================================================

  // SEEK DEBOUNCE: Prevent flooding TDLib with rapid seek cancellations
  // During scrubbing, coalesce multiple seeks into single request
  final Map<int, Timer?> _seekDebounceTimers = {};
  final Map<int, int> _pendingSeekOffsets = {};
  static const int _seekDebounceMs =
      300; // Delay before executing seek (increased from 150ms for stability)

  // MOOV PRE-FETCH: Schedule moov download after initial buffering
  // This avoids the ping-pong effect for MP4s with moov at end
  final Map<int, bool> _moovPreFetchScheduled = {};
  final Map<int, bool> _moovPreFetchCompleted = {};
  static const int _moovPreFetchMinPrefix =
      2 * 1024 * 1024; // Wait for 2MB before fetching moov

  // MOOV-AT-END DETECTION: Track files where moov atom is at the end
  // These files are NOT optimized for streaming and require extra loading time
  final Map<int, bool> _isMoovAtEnd = {};

  // STALL DETECTION: Track last download progress to detect truly stalled downloads
  // Used to avoid ping-pong downloads between multiple concurrent requests
  final Map<int, int> _lastDownloadProgress = {};

  // RESUME PHASE DETECTION
  // When resuming from a saved position, temporarily serialize downloads
  // to prevent ping-pong between resume point and cache edge
  final Map<int, DateTime> _resumePhaseStart = {};
  final Map<int, int> _resumePrimaryOffset = {}; // The target resume offset
  final Set<int> _pendingQueuedOffsets =
      {}; // Offsets waiting for resume to stabilize
  static const int _resumePhaseMs = 15000; // 15 seconds resume window

  /// Check if a file has moov atom at the end (not optimized for streaming)
  /// Returns true if the video needs extra loading time due to metadata placement
  bool isVideoNotOptimizedForStreaming(int fileId) =>
      _isMoovAtEnd[fileId] ?? false;

  // OPTIMIZATION 1: DISABLED - TDLib doesn't support parallel downloads
  // Calling downloadFile with a different offset CANCELS any ongoing download.
  // The moov protection mechanism in _startDownloadAtOffset handles this instead.
  // This method is kept as a stub for potential future use if TDLib behavior changes.
  final Set<int> _moovPreloadStarted = {};

  void _preloadMoovAtom(int fileId, int totalSize) {
    // DISABLED: TDLib cancels previous downloads when starting a new offset.
    // The existing moov protection mechanism is sufficient.
    // Keeping this method as a no-op for interface compatibility.
    return;
  }

  // FORCE MOOV DOWNLOAD: Track files that MUST download moov before anything else
  // This prevents the player's request for the start of the file from canceling
  // the critical metadata download needed to determine duration.
  final Map<int, int> _forcedMoovOffset = {};

  // Track priorities to prevent low-priority requests from displacing high-priority ones
  final Map<int, int> _activePriority = {};

  // ============================================================
  // P0 FIX: MOOV-FIRST STATE MACHINE
  // ============================================================

  /// Track the current loading state for each file
  final Map<int, FileLoadState> _fileLoadStates = {};

  /// Track files with stale playback positions (after cache clear)
  /// These files need MOOV verification before seeking to saved position
  final Set<int> _stalePlaybackPositions = {};

  /// Track the saved position to seek to after MOOV is loaded
  /// Key: fileId, Value: byte offset to seek to
  final Map<int, int> _pendingSeekAfterMoov = {};

  /// Get the current load state for a file
  FileLoadState getFileLoadState(int fileId) =>
      _fileLoadStates[fileId] ?? FileLoadState.idle;

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
    _fileLoadStates[fileId] = FileLoadState.playing;
    debugPrint('Proxy: P0 FIX - Pending seek acknowledged for $fileId');
  }

  int get port => _port;

  // OPTIMIZATION 2: Track files we've started preloading from list view
  final Set<int> _listPreloadStarted = {};
  int _activePreloads = 0;
  static const int _maxConcurrentPreloads = 3;

  /// P1: Two-tier preloading when videos appear in list view
  /// - isVisible=true: Priority 5, first 2MB (for visible videos)
  /// - isVisible=false: Priority 1, first 512KB only (for next-in-list)
  /// Limited to 3 concurrent preloads to avoid TDLib conflicts
  void preloadVideoStart(int fileId, int? totalSize, {bool isVisible = false}) {
    // Only preload once per file
    if (_listPreloadStarted.contains(fileId)) return;

    // Limit concurrent preloads to prevent TDLib download conflicts
    if (_activePreloads >= _maxConcurrentPreloads) {
      return;
    }

    // Skip if already cached or downloading
    final cached = _filePaths[fileId];
    final minSize = isVisible ? 2 * 1024 * 1024 : 512 * 1024;
    if (cached != null &&
        (cached.downloadedPrefixSize > minSize || cached.isCompleted)) {
      return;
    }

    _listPreloadStarted.add(fileId);
    _activePreloads++;

    final priority = isVisible ? 5 : 1;
    final limit = isVisible ? 2 * 1024 * 1024 : 512 * 1024;

    debugPrint(
      'Proxy: TWO-TIER PRELOAD for $fileId (visible: $isVisible, prio: $priority, active: $_activePreloads/$_maxConcurrentPreloads)',
    );

    // Start background download
    TelegramService().send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': priority,
      'offset': 0,
      'limit': limit,
      'synchronous': false,
    });

    // Reduce active count after a delay (preload is fire-and-forget)
    Future.delayed(const Duration(seconds: 3), () {
      if (_activePreloads > 0) _activePreloads--;
    });
  }

  void abortRequest(int fileId) {
    // Prevent duplicate abort calls
    if (_abortedRequests.contains(fileId)) {
      debugPrint('Proxy: Already aborted fileId $fileId, skipping');
      return;
    }

    debugPrint('Proxy: ===== ABORTING REQUEST for fileId $fileId =====');
    _abortedRequests.add(fileId);
    _activeDownloadRequests.remove(fileId);
    _activeDownloadOffset.remove(fileId);
    _lastOffsetChangeTime.remove(fileId);
    _primaryPlaybackOffset.remove(fileId);
    _downloadStartTime.remove(fileId);
    _isMoovAtEnd.remove(fileId);
    _moovPreloadStarted.remove(fileId);
    _resumePhaseStart.remove(fileId);
    _resumePrimaryOffset.remove(fileId);

    // NOTE: Following Unigram's pattern - we do NOT call cancelDownloadFile here.
    // Unigram intentionally lets downloads continue in the background.
    // Calling cancelDownloadFile while TDLib is mid-operation can cause
    // PartsManager crashes. Instead, we just stop serving data to the player.

    // Notify any waiting loops to wake up and check abort status
    _fileUpdateNotifiers[fileId]?.add(null);
  }

  /// Invalidates all cached file information.
  /// Call this when Telegram cache is cleared to ensure fresh file info is fetched.
  void invalidateAllFiles() {
    debugPrint('Proxy: Invalidating all cached file info');
    _filePaths.clear();
    _activeDownloadOffset.clear();
    _lastOffsetChangeTime.clear();
    _activeHttpRequestOffsets.clear();
    _primaryPlaybackOffset.clear();

    // Clear moov-related state to prevent stale behavior after cache clear
    _moovUnblockTime.clear();
    _moovStabilizeCompleted.clear();
    _isMoovAtEnd.clear();
    _downloadStartTime.clear();
    _downloadMetrics.clear();
    _sampleTableCache.clear();
    _listPreloadStarted.clear();
    _lastSeekTime.clear();
    _lastServedOffset.clear();
    _moovPreloadStarted.clear();
    _forcedMoovOffset.clear();

    // Clear Phase 1 optimization state
    for (final timer in _seekDebounceTimers.values) {
      timer?.cancel();
    }
    _seekDebounceTimers.clear();
    _pendingSeekOffsets.clear();
    _moovPreFetchScheduled.clear();
    _moovPreFetchCompleted.clear();

    // Clear zombie blacklist to prevent stale blocks after cache clear
    _zombieBlacklist.clear();
    _zombieBlacklistTime.clear();

    // Clear LRU streaming caches
    for (final cache in _streamingCaches.values) {
      cache.clear();
    }
    _streamingCaches.clear();

    // P0 FIX: Mark ALL files as having stale positions after cache clear
    // This ensures MOOV is verified before seeking to any saved position
    // We collect the file IDs from various sources since _filePaths was just cleared
    final allKnownFileIds = <int>{
      ..._fileLoadStates.keys,
      ..._lastServedOffset.keys,
    };
    for (final fileId in allKnownFileIds) {
      _stalePlaybackPositions.add(fileId);
    }
    _fileLoadStates.clear();
    _pendingSeekAfterMoov.clear();

    debugPrint(
      'Proxy: Marked ${allKnownFileIds.length} files as having stale positions',
    );
  }

  /// Invalidates cached info for a specific file.
  /// Call this when a specific file is deleted from cache.
  void invalidateFile(int fileId) {
    debugPrint('Proxy: Invalidating cached info for file $fileId');
    _filePaths.remove(fileId);
    _activeDownloadOffset.remove(fileId);
    _lastOffsetChangeTime.remove(fileId);
    _activeHttpRequestOffsets.remove(fileId);
    _primaryPlaybackOffset.remove(fileId);

    // Clear Phase 1 state for this file
    _seekDebounceTimers[fileId]?.cancel();
    _seekDebounceTimers.remove(fileId);
    _pendingSeekOffsets.remove(fileId);
    _moovPreFetchScheduled.remove(fileId);
    _moovPreFetchCompleted.remove(fileId);

    // Clear LRU streaming cache for this file
    _streamingCaches[fileId]?.clear();
    _streamingCaches.remove(fileId);
    _forcedMoovOffset.remove(fileId);
  }

  /// P1 FIX: Signal that user explicitly initiated a seek.
  /// This helps the proxy distinguish between user seeks and read-ahead/buffer requests.
  /// Call this from MediaKitVideoRepository.seekTo() BEFORE the player seeks.
  void signalUserSeek(int fileId, int targetTimeMs) {
    _userSeekInProgress.add(fileId);
    _userSeekTargetMs[fileId] = targetTimeMs;

    // Clear zombie blacklist on user seek - user intent takes priority
    _zombieBlacklist.remove(fileId);
    _zombieBlacklistTime.remove(fileId);

    debugPrint('Proxy: USER SEEK SIGNALED for $fileId to ${targetTimeMs}ms');

    // Auto-clear after 5 seconds if not consumed
    Future.delayed(const Duration(seconds: 5), () {
      if (_userSeekInProgress.contains(fileId)) {
        debugPrint('Proxy: USER SEEK EXPIRED for $fileId (not consumed in 5s)');
        _userSeekInProgress.remove(fileId);
        _userSeekTargetMs.remove(fileId);
      }
    });
  }

  Future<void> start() async {
    if (_server != null) return;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    debugPrint('LocalStreamingProxy running on port $_port');

    _server!.listen(_handleRequest);

    TelegramService().updates.listen(_onUpdate);
  }

  void _onUpdate(Map<String, dynamic> update) {
    if (update['@type'] == 'updateFile') {
      final file = update['file'];
      final id = file['id'] as int?;
      if (id == null) return;

      final local = file['local'] as Map<String, dynamic>?;
      final path = local?['path'] as String? ?? '';
      final isCompleted = local?['is_downloading_completed'] as bool? ?? false;
      final size = file['size'] as int? ?? 0;
      final downloadOffset = local?['download_offset'] as int? ?? 0;
      final downloadedPrefixSize =
          local?['downloaded_prefix_size'] as int? ?? 0;
      final isDownloadingActive =
          local?['is_downloading_active'] as bool? ?? false;

      // VIRTUAL ACTIVE STATE: Track when download STOPS being active
      // This allows us to simulate "Active" status for a short time (500ms)
      // to bridge the gap between chunks and prevent zombie attacks during the lull.
      final wasDownloading = _filePaths[id]?.isDownloadingActive ?? false;
      if (wasDownloading && !isDownloadingActive) {
        _lastActiveDownloadEndTime[id] = DateTime.now();
        _lastActiveDownloadOffset[id] = _filePaths[id]?.downloadOffset ?? 0;
      } else if (isDownloadingActive) {
        _lastActiveDownloadEndTime.remove(id);
      }

      // Always update the cache, even if path is empty (file not yet allocated)
      _filePaths[id] = ProxyFileInfo(
        path: path,
        totalSize: size,
        downloadOffset: downloadOffset,
        downloadedPrefixSize: downloadedPrefixSize,
        isDownloadingActive: isDownloadingActive,
        isCompleted: isCompleted,
      );

      // PHASE 1: DISABLED - Moov pre-fetch CANCELS active playback download!
      // TDLib only allows 1 concurrent download per file, so pre-fetching moov
      // interrupts the video buffering and breaks playback. The existing
      // MOOV STABILIZE mechanism handles moov fetching when the player requests it.
      // if (downloadedPrefixSize > 0 && size > 0 && !isCompleted) {
      //   _scheduleMoovPreFetch(id, downloadedPrefixSize, size);
      // }

      // Notify anyone waiting for updates on this file
      _fileUpdateNotifiers[id]?.add(null);
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
    _abortedRequests.clear();
  }

  String getUrl(int fileId, int size) {
    return 'http://127.0.0.1:$_port/stream?file_id=$fileId&size=$size';
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
        debugPrint(
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
      debugPrint('Proxy: Error getting prefix size: $e');
    }
    return 0;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    String? fileIdStr;
    int? fileId;
    int start = 0;
    try {
      debugPrint('Proxy: Received request for ${request.uri}');
      fileIdStr = request.uri.queryParameters['file_id'];
      final sizeStr = request.uri.queryParameters['size'];

      if (fileIdStr == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      fileId = int.parse(fileIdStr);
      final totalSize = int.tryParse(sizeStr ?? '') ?? 0;

      // Wait for TDLib client to be ready (max 10 seconds)
      // This is crucial on app start when TDLib might still be initializing
      if (!TelegramService().isClientReady) {
        debugPrint('Proxy: Waiting for TDLib client to initialize...');
        int attempts = 0;
        while (!TelegramService().isClientReady && attempts < 100) {
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
        }
        if (!TelegramService().isClientReady) {
          debugPrint(
            'Proxy: TDLib client failed to initialize after 10 seconds',
          );
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        debugPrint('Proxy: TDLib client ready after ${attempts * 100}ms');
      }

      // If ANY files were recently aborted, give TDLib time to clean up
      // This is crucial - TDLib can crash if we start new downloads while
      // it's still processing cancellations internally
      if (_abortedRequests.isNotEmpty) {
        // Check if THIS file was aborted - needs longer wait
        final thisFileWasAborted = _abortedRequests.contains(fileId);

        debugPrint(
          'Proxy: Waiting for TDLib to stabilize (${_abortedRequests.length} aborted files, current file aborted: $thisFileWasAborted)...',
        );
        // Clear our abort tracking - we're about to start fresh
        _abortedRequests.clear();

        // Use shorter wait for unrelated files, longer if this file was aborted
        final waitMs = thisFileWasAborted ? 500 : 200;
        await Future.delayed(Duration(milliseconds: waitMs));
        debugPrint('Proxy: TDLib stabilization wait complete (${waitMs}ms)');
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
        final currentState = _fileLoadStates[fileId] ?? FileLoadState.idle;

        if (currentState == FileLoadState.idle ||
            currentState == FileLoadState.loadingMoov) {
          // Store the desired seek position for after MOOV loads
          _pendingSeekAfterMoov[fileId] = start;
          _fileLoadStates[fileId] = FileLoadState.loadingMoov;

          // P1: Check if we know MOOV location for this file
          final isMoovAtEnd = _isMoovAtEnd[fileId] ?? false;

          if (isMoovAtEnd) {
            // MOOV is at end - don't redirect to 0, let the existing
            // moov-at-end handling logic fetch from the correct offset.
            // We just mark the state and store pending seek.
            debugPrint(
              'Proxy: P1 FIX - Stale position for $fileId (MOOV at END). '
              'Requested: ${start ~/ 1024}KB. Pending seek stored. '
              'Letting moov-at-end logic handle MOOV fetch.',
            );
            // Don't redirect - moov will be fetched when player requests end of file
          } else {
            // MOOV is at start (or unknown) - redirect to 0
            debugPrint(
              'Proxy: P1 FIX - Stale position for $fileId (MOOV at START). '
              'Requested: ${start ~/ 1024}KB, forcing start from 0.',
            );
            moovFirstRedirect = true;
            start = 0;
          }
        } else if (currentState == FileLoadState.moovReady) {
          // MOOV is loaded, we can now process the stale seek
          debugPrint(
            'Proxy: P1 FIX - MOOV ready for $fileId. Processing pending seek to ${start ~/ 1024}KB',
          );
          _fileLoadStates[fileId] = FileLoadState.seeking;
          _stalePlaybackPositions.remove(fileId);
          _pendingSeekAfterMoov.remove(fileId);
        }
      } else if (_stalePlaybackPositions.contains(fileId) &&
          start <= 1024 * 1024) {
        // Stale file but requesting near start - this is fine, likely loading MOOV
        // Mark as loading MOOV and clear stale status once we get some data
        _fileLoadStates[fileId] = FileLoadState.loadingMoov;
      }

      // SEEK DETECTION: Mark if this is a seek (jump > 1MB from last served offset)
      // IMPORTANT: Do this BEFORE primary tracking so we can reset primary on seek
      // Skip seek detection if we did MOOV-first redirect (start was changed to 0)
      bool isSeekRequest = false;
      final lastOffset = moovFirstRedirect ? null : _lastServedOffset[fileId];
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
            _lastSeekTime[fileId] = DateTime.now();

            // ZOMBIE FIX: Clear zombie blacklist on true user seeks
            // This allows the player to request data at the new position
            if (_zombieBlacklist.containsKey(fileId)) {
              debugPrint(
                'Proxy: Clearing zombie blacklist for $fileId on true scrubbing',
              );
              _zombieBlacklist.remove(fileId);
              _zombieBlacklistTime.remove(fileId);
            }
          }

          // CRITICAL FIX: When a seek is detected, reset the primary offset to the seek target
          // This prevents the primary from getting stuck at 0 when seeking forward
          // _primaryPlaybackOffset[fileId] = start; // MOVED BELOW for centralized logic
          debugPrint(
            'Proxy: Detected seek for $fileId: $lastOffset -> $start (jump: ${jump ~/ 1024}KB)',
          );
        }
      }

      // PRIMARY PLAYBACK TRACKING (STABILIZED):
      // The player often fires multiple "Seek" requests (video, audio, etc.) to different offsets.
      // We must lock onto the FIRST one (user's intent) and ignore subsequent divergent "seeks".
      final existingPrimary = _primaryPlaybackOffset[fileId];
      final lastPrimaryUpdate = _lastPrimaryUpdateTime[fileId];

      bool shouldUpdatePrimary = false;

      if (existingPrimary == null) {
        shouldUpdatePrimary = true;
      } else if (_userSeekInProgress.contains(fileId)) {
        // P1: User explicitly seeked via MediaKit - force Primary update
        // Don't require isSeekRequest because lastServedOffset may not be set yet
        // Accept any offset significantly different from current Primary (>50MB)
        final distFromPrimary = (start - existingPrimary).abs();
        if (distFromPrimary > 50 * 1024 * 1024) {
          debugPrint(
            'Proxy: EXPLICIT USER SEEK for $fileId. Primary $existingPrimary -> $start.',
          );
          shouldUpdatePrimary = true;
          _userSeekInProgress.remove(fileId);
        } else {
          debugPrint(
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
              debugPrint(
                'Proxy: RESUME DETECTED ($existingPrimary -> $start). Forcing Primary update.',
              );
              shouldUpdatePrimary = true;

              // NEW: Mark resume phase - serialize downloads for 3 seconds
              _resumePhaseStart[fileId] = DateTime.now();
              _resumePrimaryOffset[fileId] = start;
              debugPrint(
                'Proxy: RESUME PHASE started for $fileId at offset ${start ~/ (1024 * 1024)}MB',
              );
            } else if (DateTime.now()
                    .difference(lastPrimaryUpdate)
                    .inMilliseconds >
                2000) {
              debugPrint(
                'Proxy: Recovering Primary Offset (Stagnant 2s in Seek) -> Adopting $start',
              );
              shouldUpdatePrimary = true;
            } else {
              debugPrint(
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
          debugPrint(
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
            debugPrint(
              'Proxy: Recovering Primary Offset (Stagnant 2s on Forward Jump) -> Adopting $start',
            );
            shouldUpdatePrimary = true;
          } else {
            debugPrint(
              'Proxy: Ignoring likely Read-Ahead Buffer Request at $start (Primary at $existingPrimary)',
            );
            shouldUpdatePrimary = false;
            // Treat as background/buffer request, don't debounce as seek
            isSeekRequest = false;
          }
        }
      }

      if (shouldUpdatePrimary) {
        // RESUME PHASE DETECTION:
        // Check if this update represents a resume from start (primary near 0 jumping far ahead)
        final previousPrimary = existingPrimary ?? 0;
        final isResumeJump =
            previousPrimary < 50 * 1024 * 1024 &&
            start > 100 * 1024 * 1024 &&
            (start - previousPrimary) > 50 * 1024 * 1024;

        // Also check it's not a MOOV request (end of file)
        final isMoovArea =
            totalSize > 0 && (totalSize - start) < 100 * 1024 * 1024;

        if (isResumeJump &&
            !isMoovArea &&
            !_resumePhaseStart.containsKey(fileId)) {
          debugPrint(
            'Proxy: RESUME PHASE started for $fileId: ${previousPrimary ~/ (1024 * 1024)}MB -> ${start ~/ (1024 * 1024)}MB',
          );
          _resumePhaseStart[fileId] = DateTime.now();
          _resumePrimaryOffset[fileId] = start;
        }

        _primaryPlaybackOffset[fileId] = start;
        _lastPrimaryUpdateTime[fileId] = DateTime.now();
        if (isSeekRequest) {
          // Only log if it was a seek
          debugPrint('Proxy: Primary Target UPDATED to $start');
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
        debugPrint(
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
          debugPrint('Proxy: Failed to re-allocate file $fileId');
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        file = File(fileInfo.path);

        // Verify the new file exists
        if (!await file.exists()) {
          debugPrint('Proxy: New file still does not exist: ${fileInfo.path}');
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
        raf = await file.open(mode: FileMode.read);

        int currentReadOffset = start;
        int remainingToSend = contentLength;

        // Ensure notifier exists
        if (!_fileUpdateNotifiers.containsKey(fileId)) {
          _fileUpdateNotifiers[fileId] = StreamController.broadcast();
        }
        final updateStream = _fileUpdateNotifiers[fileId]!.stream;

        while (remainingToSend > 0) {
          if (_abortedRequests.contains(fileId)) {
            debugPrint('Proxy: Request aborted for $fileId');
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
            _streamingCaches.putIfAbsent(fileId, () => _StreamingLRUCache());
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
            _downloadMetrics.putIfAbsent(fileId, () => _DownloadMetrics());
            _downloadMetrics[fileId]!.recordBytes(data.length);

            // Update last served offset for seek detection
            _lastServedOffset[fileId] = currentReadOffset;

            // P0 FIX: MOOV state transition
            // If we were in loadingMoov state and have now loaded enough data (2MB),
            // transition to moovReady so pending seeks can proceed
            if (_fileLoadStates[fileId] == FileLoadState.loadingMoov &&
                currentReadOffset >= 2 * 1024 * 1024) {
              _fileLoadStates[fileId] = FileLoadState.moovReady;
              final pendingSeek = _pendingSeekAfterMoov[fileId];
              if (pendingSeek != null) {
                debugPrint(
                  'Proxy: P0 FIX - MOOV ready for $fileId. '
                  'Player should now seek to ${pendingSeek ~/ 1024}KB',
                );
              } else {
                // No pending seek means this was a fresh start, clear stale status
                _stalePlaybackPositions.remove(fileId);
                _fileLoadStates[fileId] = FileLoadState.playing;
              }
            }

            // Ensure download is started at the exact offset the player needs
            // FIX: Only start download if we still have data to send.
            // If we just finished the file (remainingToSend == 0), currentReadOffset == totalSize,
            // which causes TDLib crash if we request it.
            if (remainingToSend > 0) {
              _startDownloadAtOffset(fileId, currentReadOffset);
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
              final lastPrimary = _primaryPlaybackOffset[fileId] ?? 0;
              final lastUpdateTime = _lastPrimaryUpdateTime[fileId];

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
                    _primaryPlaybackOffset[fileId] = currentReadOffset;
                    _lastPrimaryUpdateTime[fileId] = now;
                  }
                }
              } else if (currentReadOffset > lastPrimary &&
                  (currentReadOffset - lastPrimary) > 50 * 1024 * 1024) {
                // STAGNANT ADOPTION (Stream Loop):
                // We are streaming far ahead of Primary (>50MB).
                // If the Primary hasn't moved for > 2000ms, assume the user seeked here
                // and the initial Seek Logic rejected it (or we missed it).
                if (lastUpdateTime != null &&
                    DateTime.now().difference(lastUpdateTime).inMilliseconds >
                        2000) {
                  debugPrint(
                    'Proxy: Recovering Primary Offset (Stagnant 2s in StreamLoop) -> Adopting $currentReadOffset',
                  );
                  _primaryPlaybackOffset[fileId] = currentReadOffset;
                  _lastPrimaryUpdateTime[fileId] = DateTime.now();
                }
              }
            } else {
              // NO DATA AVAILABLE -> BLOCKING WAIT
              final cached = _filePaths[fileId];
              debugPrint(
                'Proxy: Waiting for data at $currentReadOffset for $fileId '
                '(CachedOffset: ${cached?.downloadOffset}, CachedPrefix: ${cached?.downloadedPrefixSize})...',
              );

              // Ensure download is started at the exact offset the player needs
              _startDownloadAtOffset(
                fileId,
                currentReadOffset,
                isBlocking: true,
              );

              // Wait for updateFile that provides the data we need
              // This is more like Unigram's event-based waiting
              int waitAttempts = 0;

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
              final maxWaitAttempts = isMoovRequest
                  ? 75
                  : 25; // 75 * 200ms = 15 seconds

              while (waitAttempts < maxWaitAttempts) {
                if (_abortedRequests.contains(fileId)) {
                  debugPrint('Proxy: Wait aborted for $fileId');
                  return;
                }

                // Check if we have data NOW
                final currentCached = _filePaths[fileId];
                final prefix = currentCached?.downloadedPrefixSize ?? 0;
                final offset = currentCached?.downloadOffset ?? 0;

                // Condition 1: Prefix covers our read offset (Continuous from start)
                if (currentReadOffset < prefix) {
                  break; // Data is available!
                }

                // Condition 2: Download offset covers our read offset (Sparse download)
                if (currentReadOffset >= offset &&
                    currentReadOffset < (currentCached?.totalSize ?? 0)) {
                  // We might have data, but we need to verify if the file on disk typically
                  // has it. TDLib reports downloaded_prefix_size reliably, but for
                  // sparse parts, we rely on the file size growing.
                  // For simplicity, if we are in the "active zone", we retry reading.
                  break;
                }

                await Future.delayed(const Duration(milliseconds: 200));
                waitAttempts++;
              }
            }

            // PHASE 5: Read-ahead DISABLED due to TDLib limitation
            // TDLib cancels any ongoing download when a new downloadFile is called
            // for the same file_id with a different offset. This causes more harm
            // than benefit, so read-ahead is disabled until TDLib supports parallel
            // range requests for the same file.
            // _scheduleReadAhead(fileId, currentReadOffset);
          } else {
            // NO DATA AVAILABLE -> BLOCKING WAIT
            final cached = _filePaths[fileId];
            debugPrint(
              'Proxy: Waiting for data at $currentReadOffset for $fileId '
              '(CachedOffset: ${cached?.downloadOffset}, CachedPrefix: ${cached?.downloadedPrefixSize})...',
            );

            // Ensure download is started at the exact offset the player needs
            _startDownloadAtOffset(fileId, currentReadOffset, isBlocking: true);

            // Wait for updateFile that provides the data we need
            // This is more like Unigram's event-based waiting
            int waitAttempts = 0;

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
            final maxWaitAttempts = isMoovRequest
                ? 75
                : 25; // 75 * 200ms = 15 seconds

            while (waitAttempts < maxWaitAttempts) {
              if (_abortedRequests.contains(fileId)) {
                debugPrint('Proxy: Wait aborted for $fileId');
                break;
              }

              // Check if data became available in cache (from updateFile)
              final updatedCache = _filePaths[fileId];
              if (updatedCache != null) {
                final nowAvailable = updatedCache.availableBytesFrom(
                  currentReadOffset,
                );
                if (nowAvailable > 0) {
                  break; // Data is now available, exit wait loop
                }

                // DOWNLOAD STALL DETECTION: Only restart if download is truly stalled.
                // Don't restart just because current offset isn't being downloaded -
                // another request might be downloading at a different offset which
                // will eventually reach our position.
                // Restart only after 10 attempts (2 seconds) with no progress at all.
                final currentPrefix = updatedCache.downloadedPrefixSize;
                final lastPrefix = _lastDownloadProgress[fileId] ?? 0;
                if (waitAttempts % 10 == 9) {
                  if (currentPrefix <= lastPrefix &&
                      !updatedCache.isDownloadingActive) {
                    // No progress in last 2 seconds and download not active - restart
                    // P2: Record stall for adaptive buffer escalation
                    final metrics = _downloadMetrics[fileId];
                    if (metrics != null) {
                      metrics.recordStall();
                      debugPrint(
                        'Proxy: P2 STALL RECORDED for $fileId (total: ${metrics.recentStallCount})',
                      );
                    }
                    _startDownloadAtOffset(fileId, currentReadOffset);
                  }
                  _lastDownloadProgress[fileId] = currentPrefix;
                }
              }

              try {
                await updateStream.first.timeout(
                  const Duration(milliseconds: 200),
                );
              } catch (_) {
                // Timeout, check again
              }
              waitAttempts++;
            }
          }
        }
      } catch (e) {
        if (e is! SocketException && e is! HttpException) {
          debugPrint('Proxy: Error streaming: $e');
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
        debugPrint('Proxy: Top-level error: $e');
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

        debugPrint(
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
          debugPrint(
            'Proxy: Detected stale partial download for $fileId (only ${downloadedPrefixSize ~/ 1024}KB), cleaning up...',
          );

          // Delete the local file to reset TDLib's state
          final deleteResult = await TelegramService().sendWithResult({
            '@type': 'deleteFile',
            'file_id': fileId,
          });

          if (deleteResult['@type'] == 'ok') {
            debugPrint('Proxy: Successfully deleted partial file $fileId');
          } else {
            debugPrint('Proxy: Delete file result: ${deleteResult['@type']}');
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

        // OPTIMIZATION 1: Pre-load moov atom for large files
        if (totalSize > 50 * 1024 * 1024 && !isCompleted) {
          _preloadMoovAtom(fileId, totalSize);
        }

        // If path is empty, trigger download to allocate the file
        final currentInfo = _filePaths[fileId];
        if (currentInfo == null ||
            (currentInfo.path.isEmpty && !currentInfo.isCompleted)) {
          debugPrint(
            'Proxy: File path empty, triggering initial download for $fileId',
          );

          // Ensure notifier exists for waiting
          if (!_fileUpdateNotifiers.containsKey(fileId)) {
            _fileUpdateNotifiers[fileId] = StreamController.broadcast();
          }

          // Trigger download to allocate the file - use synchronous mode
          // to download sequentially and avoid PartsManager issues
          _downloadStartTime[fileId] =
              DateTime.now(); // Track when download started
          TelegramService().send({
            '@type': 'downloadFile',
            'file_id': fileId,
            'priority': 32,
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
              debugPrint('Proxy: Fetch aborted for $fileId');
              return;
            }

            final cached = _filePaths[fileId];
            if (cached != null && cached.path.isNotEmpty) {
              debugPrint('Proxy: File path obtained: ${cached.path}');
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

          debugPrint(
            'Proxy: Timed out waiting for file allocation for $fileId',
          );
        }
      }
    } catch (e) {
      debugPrint('Proxy: Error fetching file info: $e');
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
    // DISK SAFETY CHECK: Prevent crash if disk is full (< 50MB)
    // This allows the Binlog write to fail gracefully or just stops filling disk
    if (!await TelegramCacheService().checkDiskSafety()) {
      debugPrint(
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
      debugPrint(
        'Proxy: Ignoring request at EOF ($requestedOffset >= $totalSize) for $fileId',
      );
      return;
    }

    // CHECK FORCED MOOV: If we are forcing a moov download, ignore requests for other offsets
    // This allows the moov download to complete without being intercepted by start-of-file requests
    final forcedOffset = _forcedMoovOffset[fileId];
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
        // Got enough moov data
        debugPrint(
          'Proxy: Forced moov download satisfied ($availableAtForced bytes >= $targetSize), releasing lock for $fileId',
        );
        _forcedMoovOffset.remove(fileId);
      } else if (requestedOffset != forcedOffset) {
        debugPrint(
          'Proxy: Ignoring request for $requestedOffset while forcing moov download at $forcedOffset for $fileId (have $availableAtForced/$targetSize)',
        );
        return;
      }
    }

    // SCRUBBING DETECTION: If multiple seeks detected within 500ms, use debounce
    // to reduce TDLib download cancellations during rapid scrubbing.
    // IMPORTANT: Only debounce during ACTIVE PLAYBACK, not during initial load.
    // We detect active playback by checking if we've served at least 10MB of data.
    final lastServed = _lastServedOffset[fileId] ?? 0;
    final isActivePlayback =
        lastServed > 10 * 1024 * 1024; // At least 10MB served

    final debounceLastSeek = _lastSeekTime[fileId];
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
      debugPrint(
        'Proxy: Rapid seek detected for $fileId, debouncing to ${requestedOffset ~/ 1024}KB',
      );
      _handleDebouncedSeek(fileId, requestedOffset);
      return;
    }

    // Check if we're already downloading from this offset (or very close)
    final currentActiveOffset = _activeDownloadOffset[fileId];
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
      debugPrint(
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

    // PHASE 4: SMART MOOV ATOM DETECTION
    // Instead of blocking all requests near end of file, distinguish:
    // 1. Actual moov atom requests (metadata, no sample table entry)
    // 2. Legitimate seeks to end of video (has sample table entry)
    // variable 'totalSize' is already defined above, reuse it or use cached?.totalSize
    final fileSize = cached?.totalSize ?? 0;
    if (fileSize > 0) {
      final distanceFromEnd = fileSize - requestedOffset;

      // PHASE 4: Use percentage-based threshold for large files
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
          debugPrint(
            'Proxy: Offset $requestedOffset is near end but confirmed as video data '
            '(last sample ends at $lastVideoByteOffset)',
          );
        }
      }

      final isMoovAtomRequest = mightBeMoovRequest && !isConfirmedVideoData;

      // Mark file as not optimized for streaming if moov is at the end
      if (isMoovAtomRequest && !_isMoovAtEnd.containsKey(fileId)) {
        _isMoovAtEnd[fileId] = true;
        debugPrint(
          'Proxy: File $fileId has moov atom at end (not optimized for streaming)',
        );
      }

      // DISABLED: This was blocking moov downloads and preventing playback start.
      // The player NEEDS the moov atom to display video metadata and start playback.
      // Blocking moov requests causes a deadlock: player waits for moov, we wait for data.
      // final currentData = cached?.downloadedPrefixSize ?? 0;
      // final downloadStart = _downloadStartTime[fileId];
      // final isEarlyPhase = downloadStart != null &&
      //     DateTime.now().difference(downloadStart).inSeconds < 5;
      // if (isMoovAtomRequest && isEarlyPhase &&
      //     currentData < _getAdaptiveMoovThreshold(fileId)) {
      //   return; // This was causing videos to never load!
      // }

      // PARTSMANAGER FIX: When there's cached data at start and we're requesting moov,
      // TDLib can crash if the offset change is too rapid. Add a small delay.
      if (_isMoovAtEnd[fileId] == true) {
        final cachedPrefix = cached?.downloadedPrefixSize ?? 0;

        // Check if we have cached data at a DIFFERENT location than the moov
        // (i.e., we have data from start but requesting end, or vice versa)
        final isMoovRequest =
            totalSize > 0 &&
            (totalSize - requestedOffset) <
                (totalSize * 0.05).round().clamp(
                  10 * 1024 * 1024,
                  100 * 1024 * 1024,
                );
        final hasDataAtStart = cachedPrefix > 1024 * 1024; // >1MB from start
        final isJumpingToMoov =
            isMoovRequest &&
            hasDataAtStart &&
            (requestedOffset - cachedPrefix).abs() >
                50 * 1024 * 1024; // >50MB jump

        // FRESH-FILE MOOV PROTECTION: After cache clear, there's no cached data
        // but we still need to protect against large offset jumps which crash PartsManager.
        // This case occurs when: cachedPrefix < 1MB AND requestedOffset > 500MB
        final isFreshFileMoovJump =
            isMoovRequest &&
            !hasDataAtStart &&
            requestedOffset > 500 * 1024 * 1024;

        if (isFreshFileMoovJump && !_moovStabilizeCompleted.contains(fileId)) {
          debugPrint(
            'Proxy: Fresh-file moov jump detected for $fileId at ${requestedOffset ~/ (1024 * 1024)}MB - '
            'canceling download and waiting before moov fetch',
          );

          // Mark as in-progress to prevent re-entry
          _moovStabilizeCompleted.add(fileId);

          // Cancel any ongoing download to give TDLib time to settle (fire-and-forget)
          TelegramService().send({
            '@type': 'cancelDownloadFile',
            'file_id': fileId,
            'only_if_pending': false,
          });

          // Schedule the actual moov download after TDLib settles
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!_abortedRequests.contains(fileId)) {
              debugPrint(
                'Proxy: Fresh-file moov protection complete for $fileId - starting moov download',
              );

              // IMPORTANT: Clear seek time to prevent debounce from interfering
              // The next download request should proceed immediately, not be debounced
              _lastSeekTime.remove(fileId);
              _pendingSeekOffsets.remove(fileId);
              _seekDebounceTimers[fileId]?.cancel();
              _seekDebounceTimers.remove(fileId);

              // Trigger the moov download now that TDLib has settled
              _forcedMoovOffset[fileId] = requestedOffset;
              _startDownloadAtOffset(fileId, requestedOffset);
            }
          });

          // Return early - the delayed callback will handle the download
          return;
        }

        if (isJumpingToMoov) {
          // If this file has already completed stabilization, skip
          if (_moovStabilizeCompleted.contains(fileId)) {
            // Already stabilized, allow request through
            return; // Don't block, but don't start download here either
          }

          // DISABLED: MOOV STABILIZE was blocking playback start by delaying moov fetch.
          // The player cannot display video without moov metadata. Removed blocking.
          // The TDLib will handle the download naturally without our interference.
          debugPrint(
            'Proxy: Moov request for $fileId - proceeding without stabilize delay',
          );

          // Unblock time has passed - mark as completed and allow the request
          _moovUnblockTime.remove(fileId);
          _moovStabilizeCompleted.add(fileId);
          debugPrint(
            'Proxy: MOOV STABILIZE complete for $fileId - allowing moov fetch',
          );
        }
      }
    }

    final now = DateTime.now();

    // Calculate distance to CURRENT download offset
    final activeDownloadTarget = _activeDownloadOffset[fileId] ?? 0;
    final distanceFromCurrent = (requestedOffset - activeDownloadTarget).abs();

    // Calculate distance to primary offset for priority calculation
    final primaryOffset = _primaryPlaybackOffset[fileId] ?? 0;
    final distanceToPlayback = (requestedOffset - primaryOffset).abs();

    // Check if this is a recent seek (used for preload calculation)
    final lastSeek = _lastSeekTime[fileId];
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
    final lastServedForCheck = _lastServedOffset[fileId];
    if (lastServedForCheck != null) {
      final jump = (requestedOffset - lastServedForCheck).abs();
      if (jump > 1024 * 1024) {
        isSeekRequest = true;
      }
    }

    // PARTSMANAGER FIX: Increased cooldown to prevent TDLib crashes
    // TDLib's PartsManager can crash if offset changes happen too rapidly
    final lastChange = _lastOffsetChangeTime[fileId];
    final isSequentialRead =
        requestedOffset > activeDownloadTarget &&
        distanceFromCurrent < 2 * 1024 * 1024; // Within 2MB ahead

    // STABILITY FIX: Increased cooldown from 100-300ms to 500-1000ms
    // This gives TDLib more time to stabilize between offset changes
    final cooldownMs = isSequentialRead ? 500 : 1000;

    if (lastChange != null) {
      final timeSinceLastChange = now.difference(lastChange).inMilliseconds;
      // STABILITY FIX: Increased distance threshold from 512KB-1MB to 2MB-5MB
      // Larger thresholds reduce the frequency of download cancellations
      final minDistance = isSequentialRead ? 2 * 1024 * 1024 : 5 * 1024 * 1024;

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

    // PARTSMANAGER FIX: Define isMoovDownload to use for priority calculation
    // This prevents parallel range conflicts that cause PartsManager crashes
    final isMoovDownload =
        _isMoovAtEnd[fileId] == true &&
        totalSize > 0 &&
        (totalSize - requestedOffset) <
            (totalSize * 0.01).round().clamp(5 * 1024 * 1024, 50 * 1024 * 1024);

    // P1 FIX: MOOV DOWNLOAD PROTECTION
    // Prevent low-offset requests from canceling MOOV download.
    // When MOOV download is in progress, block requests for offsets < 50MB.
    final moovLockStart = _moovDownloadStart[fileId];
    final isMoovLocked =
        moovLockStart != null &&
        now.difference(moovLockStart).inMilliseconds < _moovDownloadTimeoutMs;

    if (isMoovDownload) {
      // Mark MOOV download start time
      if (!_moovDownloadStart.containsKey(fileId)) {
        _moovDownloadStart[fileId] = now;
        debugPrint('Proxy: P1 MOOV LOCK started for $fileId');
      }
    } else if (isMoovLocked && requestedOffset < 50 * 1024 * 1024) {
      // Block low-offset requests while MOOV is downloading
      debugPrint(
        'Proxy: P1 MOOV LOCK - Blocking request at ${requestedOffset ~/ 1024}KB while MOOV downloads',
      );
      return; // Don't start this download, wait for MOOV to complete
    }

    // Clear MOOV lock if we have MOOV data (moov typically downloads quickly)
    if (_moovDownloadStart.containsKey(fileId)) {
      final cached = _filePaths[fileId];
      // MOOV is considered complete if:
      // 1. We have data at the end of file (moov region)
      // 2. OR the download at MOOV offset has completed/progressed
      if (cached != null &&
          cached.downloadOffset > totalSize - 10 * 1024 * 1024) {
        _moovDownloadStart.remove(fileId);
        debugPrint(
          'Proxy: P1 MOOV LOCK released for $fileId (MOOV data available)',
        );
      }
    }

    // TELEGRAM ANDROID-INSPIRED: Calculate dynamic priority based on distance
    // to primary playback position. Closer = higher priority.
    // FORCE PRIORITY 32 for Moov downloads AND Blocking waits.
    // EXCEPTION: If "Blocking" request is extremely far (>50MB) from Primary Playback,
    // it's likely a stalled zombie stream. IGNORE the blocking flag to prevent hijacking.
    bool shouldForcePriority = isMoovDownload;
    if (isBlocking) {
      final primary = _primaryPlaybackOffset[fileId];
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
              debugPrint(
                'Proxy: CACHE EDGE ALLOWED for $requestedOffset (CacheEnd: $cacheEnd, Dist: ${distToCacheEnd ~/ 1024}KB)',
              );
              shouldForcePriority = true;
            } else if (requestedOffset < 300 * 1024 * 1024) {
              // LOW OFFSET EXCEPTION:
              // If request is for early part of file (<300MB), it's likely trying
              // to buffer contiguous data from the start. TDLib may report a
              // different downloadOffset if we jumped ahead for resume, but the
              // file data at the start still exists on disk.
              //
              // RESUME PHASE CHECK: During resume, defer low-offset requests
              // to prevent ping-pong with the resume target
              final resumeStart = _resumePhaseStart[fileId];
              final resumePrimary = _resumePrimaryOffset[fileId];
              final isInResumePhase =
                  resumeStart != null &&
                  DateTime.now().difference(resumeStart).inMilliseconds <
                      _resumePhaseMs;

              if (isInResumePhase && resumePrimary != null) {
                // During resume phase, only allow requests close to resume target
                final distToResume = (requestedOffset - resumePrimary).abs();
                if (distToResume > 20 * 1024 * 1024) {
                  // Request is far from resume target - queue it
                  debugPrint(
                    'Proxy: RESUME QUEUE - Deferring request at ${requestedOffset ~/ 1024}KB '
                    'during resume phase (target: ${resumePrimary ~/ (1024 * 1024)}MB)',
                  );
                  // Queue this request to retry after resume phase ends
                  _queueDeferredDownload(fileId, requestedOffset);
                  return; // Don't start this download now
                }
              }

              debugPrint(
                'Proxy: LOW OFFSET ALLOWED for $requestedOffset (early file data)',
              );
              shouldForcePriority = true;
            } else {
              debugPrint(
                'Proxy: DENIED Blocking Priority for $requestedOffset (Primary: $primary, Dist: ${dist ~/ 1024}KB). Treated as background.',
              );
              shouldForcePriority = false;
            }
          } else {
            debugPrint(
              'Proxy: DENIED Blocking Priority for $requestedOffset (Primary: $primary, Dist: ${dist ~/ 1024}KB). Treated as background.',
            );
            shouldForcePriority = false;
          }
        }
      }
    }

    // PRIORITY HIERARCHY FIX:
    // Split Blocking Priority into "Critical" (32) and "Deep Buffering" (28).
    // This prevents a "Deep Buffer" request (e.g. 500MB ahead) from displacing an
    // "Immediate Playback" request (e.g. 1MB ahead), which is also Prio 32.
    // They used to fight and cancel each other. Now Prio 32 wins.
    //
    // EXCEPTION: Low-offset requests (<150MB) always get priority 32 because
    // they represent contiguous cache data needed for playback.
    int blockingPriority = 32;
    if (shouldForcePriority) {
      final distToPrimary = (requestedOffset - primaryOffset).abs();
      final isLowOffsetRequest = requestedOffset < 300 * 1024 * 1024;
      if (distToPrimary > 20 * 1024 * 1024 &&
          !isMoovDownload &&
          !isLowOffsetRequest) {
        blockingPriority = 28; // Urgent, but interruptible by Critical
      }
    }

    final priority = shouldForcePriority
        ? blockingPriority
        : _calculateDynamicPriority(fileId, distanceToPlayback);

    // SAME-FILE DISPLACEMENT PROTECTION:
    // TDLib cancels the current download for File X if a new request comes for File X.
    // We must prevent a Low Priority request (e.g. background preload) from killing
    // a High Priority Active Download (e.g. user watching video).
    final activePriority = _activePriority[fileId] ?? 0;
    final isHighPriorityActive = activePriority >= 20;

    // STICKY PRIORITY PROTECTION:
    // If we have a FRESH High Priority download (e.g. from a recent seek),
    // don't let it be displaced by another High Priority request that is far away.
    // This handles race conditions where a stale request (for old position) arrives
    // late, updates the position state, and tries to start a download.
    final lastActiveChange = _lastOffsetChangeTime[fileId];
    final isActiveFresh =
        lastActiveChange != null &&
        now.difference(lastActiveChange).inMilliseconds < 1000;

    // VIRTUAL ACTIVE STATE:
    // Even if isHighPriorityActive is false (TDLib says inactive), we might be
    // in a tiny gap between chunks (e.g. 50ms). We must simulate "Active" status
    // during this gap to keep shielding against zombies.
    // If we were active recently (<500ms ago) near Primary, treat as Active.
    bool isVirtualActive = isHighPriorityActive;
    if (!isVirtualActive) {
      final lastActiveTime = _lastActiveDownloadEndTime[fileId];
      if (lastActiveTime != null &&
          now.difference(lastActiveTime).inMilliseconds < 500) {
        // Check if the LAST known active offset was close to primary
        final lastActiveOffset = _lastActiveDownloadOffset[fileId] ?? -1;
        // reuse primaryOffset from scope
        if ((lastActiveOffset - primaryOffset).abs() < 5 * 1024 * 1024) {
          isVirtualActive = true;
          // Inherit priority from previous active state (assume high)
          // This effectively extends the shield
        }
      }
    }

    // ZOMBIE KILLER: Blacklist logic
    // If we have a High Priority Active download near Primary, and we see a persistent
    // divergent request, we BLACKLIST the divergent region to prevent it from ever
    // slipping through during a momentary state gap.

    // ACTIVE STREAM PROTECTION VARIABLES RE-CALCULATION:
    // Need these for Zombie Killer logic below
    final distToPrimary = (requestedOffset - primaryOffset).abs();
    final isActiveCloseToPrimary =
        (_activeDownloadOffset[fileId] ?? -1 - primaryOffset).abs() <
        5 * 1024 * 1024;

    // TIGHTENED THRESHOLD: Any request > 2MB away from primary is considered divergent
    // if we have a locked-in High Priority stream.
    final isRequestFarFromPrimary =
        distToPrimary > 2 * 1024 * 1024; // Tightened from 10MB
    if (isHighPriorityActive &&
        isActiveCloseToPrimary &&
        isRequestFarFromPrimary &&
        !isBlocking) {
      // EXEMPTION: Never blacklist a Blocking Request
      debugPrint(
        'Proxy: PROTECTED active download (prio $activePriority) near Primary from divergent request '
        'at $requestedOffset (diff: ${distToPrimary ~/ 1024}KB). Ignoring to prevent ping-pong.',
      );

      // Add to blacklist WITH TIMESTAMP so future requests (even if active drops) are blocked temporarily
      _zombieBlacklist[fileId] = requestedOffset;
      _zombieBlacklistTime[fileId] = DateTime.now();
      return;
    }

    // DOWNLOAD DEBOUNCE:
    // If we just started a download (<500ms ago), DO NOT switch to a different offset
    // unless it is extremely close (sequential) or an explicit Seek.
    // This prevents "Thrashing" where multiple parallel requests (e.g. from player trying to find
    // a good spot) cause the proxy to rapidly switch between offsets 1, 2, 3... never completing any.
    // EXCEPTION: Blocking requests (waiting for data) MUST bypass debounce to upgrade priority.
    final lastStart = _lastOffsetChangeTime[fileId];
    if (lastStart != null &&
        now.difference(lastStart).inMilliseconds < 500 &&
        !isBlocking) {
      final activeOffset = _activeDownloadOffset[fileId] ?? -1;
      // Allow if sequential (reading forward)
      if (requestedOffset >= activeOffset &&
          requestedOffset < activeOffset + 2 * 1024 * 1024) {
        // Sequential: Allowed
      } else if (isSeekRequest) {
        // STRICT DEBOUNCE EXCEPTION:
        // Only allow the seek to break the lock if it targets the PRIMARY offset (User's Intent).
        // If it's a "fake seek" (divergent probe), it must wait.
        final primary = _primaryPlaybackOffset[fileId];
        if (primary != null &&
            (requestedOffset - primary).abs() > 2 * 1024 * 1024) {
          // SAFETY VALVE:
          // If the Primary has been stagnant for > 2000ms, and this "Divergent Seek" is persistent,
          // it likely means the Primary is WRONG (zombie false positive).
          // Force adoption to correct the Primary.
          final lastPrimaryUpdate = _lastPrimaryUpdateTime[fileId];
          if (lastPrimaryUpdate != null &&
              DateTime.now().difference(lastPrimaryUpdate).inMilliseconds >
                  2000) {
            debugPrint(
              'Proxy: SAFETY VALVE - Adopting Divergent Seek $requestedOffset (Primary stagnant > 2s)',
            );
            _primaryPlaybackOffset[fileId] = requestedOffset;
            _lastPrimaryUpdateTime[fileId] = DateTime.now();
            // Allow this request to proceed (break debounce)
          } else {
            debugPrint(
              'Proxy: DEBOUNCED divergent seek $requestedOffset (Primary is $primary). Ignoring.',
            );
            return;
          }
        }
        // Explicit Valid Seek: Allowed
      } else {
        debugPrint(
          'Proxy: DEBOUNCED rapid switch from $activeOffset to $requestedOffset (too fast). Ignoring.',
        );
        return;
      }
    }

    // Check Blacklist: blocked if within 2MB of a known zombie offset
    // UNLESS it interacts with the new Primary (user seeked back to it)
    // OR the zombie has expired (>5 seconds old)
    final blacklistOffset = _zombieBlacklist[fileId];
    final blacklistTime = _zombieBlacklistTime[fileId];
    if (blacklistOffset != null && blacklistTime != null) {
      final zombieAge = DateTime.now().difference(blacklistTime).inMilliseconds;

      // ZOMBIE EXPIRATION: If zombie is older than 5 seconds, clear it
      if (zombieAge > _zombieExpirationMs) {
        debugPrint(
          'Proxy: Zombie expired for $fileId (age: ${zombieAge}ms). Clearing blacklist.',
        );
        _zombieBlacklist.remove(fileId);
        _zombieBlacklistTime.remove(fileId);
      } else {
        final distToBlacklist = (requestedOffset - blacklistOffset).abs();
        final blacklistDistToPrimary = (blacklistOffset - primaryOffset).abs();

        // If blacklist is far from Primary (still irrelevant) AND request is near blacklist
        if (blacklistDistToPrimary > 10 * 1024 * 1024 &&
            distToBlacklist < 2 * 1024 * 1024) {
          debugPrint(
            'Proxy: BLOCKED request at $requestedOffset due to Zombie Blacklist (Zombie at $blacklistOffset, age: ${zombieAge}ms)',
          );
          return;
        } else if (blacklistDistToPrimary <= 10 * 1024 * 1024) {
          // User seeked back to the zombie region! Unblock it.
          _zombieBlacklist.remove(fileId);
          _zombieBlacklistTime.remove(fileId);
        }
      }
    }

    // Standard low-priority protection (existing logic, refactored)
    if (!isBlocking &&
        isHighPriorityActive &&
        priority >= 20 &&
        isActiveFresh &&
        (requestedOffset - activeDownloadTarget).abs() > 5 * 1024 * 1024) {
      debugPrint(
        'Proxy: PROTECTED fresh High Priority download ($activeDownloadTarget) '
        'from divergent request at $requestedOffset. Ignoring to prevent flapping.',
      );
      return;
    }

    // If we have a critical download running, and this new request is LOWER priority,
    // IGNORE IT (unless it's actually the same offset we want, or close to it).
    // Allowing if new request is also high priority (e.g. user seeked).
    // FIX: Respect Priority Hierarchy (32 vs 28). Even if both are "High" (>20),
    // we must protect "Critical" (32) from "Urgent" (28).
    //
    // EXCEPTION: If the new request is Blocking (Wait for Data) AND is significantly
    // AHEAD of the active download (>5MB), we assume the player jumped forward (e.g. via Cache)
    // and the old active download is stale/slow. We MUST allow the jump.
    bool cxIsForwardJump =
        isBlocking &&
        (requestedOffset > activeDownloadTarget + 5 * 1024 * 1024);

    // LOW OFFSET EXCEPTION: If request is for early file data (<150MB),
    // allow it to interrupt even high-priority downloads because this
    // represents contiguous cache data that the player needs.
    bool cxIsLowOffsetRequest = requestedOffset < 300 * 1024 * 1024;

    if (isHighPriorityActive &&
        priority < activePriority &&
        !cxIsForwardJump &&
        !cxIsLowOffsetRequest && // Allow low offset requests through
        (requestedOffset - activeDownloadTarget).abs() > 1024 * 1024) {
      debugPrint(
        'Proxy: PROTECTED active download (prio $activePriority) from lower-priority request '
        'at $requestedOffset (prio $priority). Ignoring.',
      );
      return;
    }

    // ADAPTIVE PRELOAD: Determine minimum bytes before we start serving
    // Based on network speed, recent stalls, and whether we just seeked
    // PHASE 1 IMPROVEMENT: Dynamic buffer calculation with safety margin
    final metrics = _downloadMetrics[fileId];

    int preloadBytes = _calculateSmartPreload(fileId, isRecentSeek, metrics);

    // Start download at exactly the offset the player requested
    debugPrint(
      'Proxy: Downloading from offset $requestedOffset for $fileId '
      '(priority: $priority, preload: ${preloadBytes ~/ 1024}KB)',
    );

    _activeDownloadOffset[fileId] = requestedOffset;
    _activePriority[fileId] = priority; // Track priority
    _lastOffsetChangeTime[fileId] = now;

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
        debugPrint(
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
  /// Follows the 32-level scale requested by User:
  /// - 32: Critical (Immediate playback, 0-1s ahead)
  /// - 20-31: High (Pre-buffering, 1-10s ahead) - Scaled linearly
  /// - 1-10: Low (Background/Far-ahead, >10s ahead)
  int _calculateDynamicPriority(int fileId, int distanceBytes) {
    // 1. Critical Priority (0-1s ahead or < 500KB if duration unknown)
    // We need to estimate byte rate to convert seconds to bytes.

    // Estimate bitrate mechanism: Default fallback 500KB/s (~4Mbps)
    // int bytesPerSecond = 500 * 1024; // Commented out until used or removed completely if heuristic is sufficient

    // Try to get more accurate bitrate from known file duration
    // Note: We don't have duration in ProxyFileInfo yet, but we might have it in Mp4SampleTable

    // Try to get more accurate bitrate from known file duration
    // Note: We don't have duration in ProxyFileInfo yet, but we might have it in Mp4SampleTable
    // or we can fallback to reasonable defaults.
    // For now, let's use the default fallback or adjust if we had duration.
    // Ideally we should pass duration to this method or store it.

    // Using simple byte thresholds corresponding to generic HD video (approx 500KB/s - 1MB/s)

    // Critical Window: 0 - 1MB (approx 1-2 seconds)
    // Priority 32
    if (distanceBytes < 1 * 1024 * 1024) {
      return 32;
    }

    // High Priority Window: 1MB - 10MB (approx 2s - 20s)
    // Priority 31 down to 20
    if (distanceBytes < 10 * 1024 * 1024) {
      // Map 1MB..10MB to 31..20
      const minDist = 1 * 1024 * 1024;
      const maxDist = 10 * 1024 * 1024;
      const range = maxDist - minDist;

      const maxPrio = 31;
      const minPrio = 20;

      // Calculate linear interpolation
      final progress = (distanceBytes - minDist) / range;
      // Invert progress because closer = higher priority
      // 0.0 (1MB) -> 31
      // 1.0 (10MB) -> 20
      final prio = maxPrio - (progress * (maxPrio - minPrio)).round();
      return prio.clamp(minPrio, maxPrio);
    }

    // Low Priority Window: > 10MB
    // Priority 10 down to 1
    // Let's cap the "far ahead" at 50MB for priority 1
    if (distanceBytes >= 10 * 1024 * 1024) {
      const minDist = 10 * 1024 * 1024;
      const maxDist = 50 * 1024 * 1024;

      if (distanceBytes >= maxDist) return 1;

      const range = maxDist - minDist;
      const maxPrio = 10;
      const minPrio = 1;

      final progress = (distanceBytes - minDist) / range;
      final prio = maxPrio - (progress * (maxPrio - minPrio)).round();
      return prio.clamp(minPrio, maxPrio);
    }

    return 1;
  }

  /// PHASE 1: Smart adaptive preload calculation
  /// Calculates buffer size based on:
  /// - Network speed (with 3x safety margin)
  /// - Recent stall history (increases buffer if stalls detected)
  /// - Post-seek mode (faster initial response, then builds up)
  int _calculateSmartPreload(
    int fileId,
    bool isRecentSeek,
    _DownloadMetrics? metrics,
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
      debugPrint(
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
      debugPrint(
        'Proxy: Post-seek adaptive buffer for $fileId: ${seekPreload ~/ 1024}KB '
        '(base: ${basePreload ~/ 1024}KB)',
      );
      return seekPreload;
    }

    debugPrint(
      'Proxy: Adaptive buffer for $fileId: ${basePreload ~/ 1024}KB '
      '(speed: ${metrics?.bytesPerSecond ?? 0 ~/ 1024}KB/s)',
    );
    return basePreload;
  }

  // NOTE: Read-ahead feature was removed because TDLib cancels ongoing downloads
  // when a new downloadFile call is made for the same file_id with a different offset.
  // This limitation makes proactive read-ahead counterproductive.

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
    debugPrint('Proxy: Preview seek preload at $estimatedOffset for $fileId');

    _lastPreviewTime[fileId] = now;

    TelegramService().send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': 20, // High priority (bottom of range) for seek preview
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
        if (_sampleTableCache[fileId] != null) {
          debugPrint(
            'Proxy: Parsed MP4 sample table for $fileId: '
            '${_sampleTableCache[fileId]!.samples.length} samples, '
            '${_sampleTableCache[fileId]!.keyframeSampleIndices.length} keyframes',
          );
        }
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('Proxy: Failed to parse sample table for $fileId: $e');
      _sampleTableCache[fileId] = null;
    }
  }

  // ============================================================
  // PHASE 1: INTELLIGENT MOOV PRE-FETCH
  // ============================================================

  /// Schedule moov atom pre-fetch after initial buffering reaches threshold.
  /// Called from _onUpdate when downloadedPrefixSize changes.
  /// This implements the DrKLO-inspired sequential moov fetch strategy.
  /// DISABLED: TDLib cancels active downloads when offset changes, breaking playback.
  // ignore: unused_element
  void _scheduleMoovPreFetch(int fileId, int currentPrefix, int totalSize) {
    // Skip if already scheduled or completed
    if (_moovPreFetchScheduled[fileId] == true ||
        _moovPreFetchCompleted[fileId] == true) {
      return;
    }

    // Skip if file is not marked as having moov at end
    if (_isMoovAtEnd[fileId] != true) {
      return;
    }

    // Skip if not enough data buffered yet
    if (currentPrefix < _moovPreFetchMinPrefix) {
      return;
    }

    // Skip for small files (moov will be reached quickly anyway)
    if (totalSize < 50 * 1024 * 1024) {
      return;
    }

    // Mark as scheduled to prevent duplicate scheduling
    _moovPreFetchScheduled[fileId] = true;

    debugPrint(
      'Proxy: PHASE1 - Scheduling moov pre-fetch for $fileId '
      '(prefix: ${currentPrefix ~/ 1024}KB, total: ${totalSize ~/ (1024 * 1024)}MB)',
    );

    // Schedule moov fetch with a short delay to let current download settle
    Future.delayed(const Duration(milliseconds: 300), () async {
      if (_abortedRequests.contains(fileId)) {
        debugPrint(
          'Proxy: PHASE1 - Moov pre-fetch cancelled (file aborted): $fileId',
        );
        return;
      }

      // Calculate moov position (last 1MB of file)
      final moovOffset = totalSize - (1024 * 1024);
      if (moovOffset <= 0) return;

      debugPrint(
        'Proxy: PHASE1 - Fetching moov atom for $fileId at offset ${moovOffset ~/ 1024}KB',
      );

      // Fetch moov with lower priority so it doesn't interrupt playback buffer
      TelegramService().send({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 8, // Lower priority than playback (32)
        'offset': moovOffset,
        'limit': 1024 * 1024, // 1MB for moov
        'synchronous': true, // Sequential to avoid PartsManager issues
      });

      _moovPreFetchCompleted[fileId] = true;
    });
  }

  // ============================================================
  // RESUME PHASE: DEFERRED DOWNLOAD QUEUE
  // ============================================================

  /// Queue a download request to be retried after resume phase ends.
  /// This prevents low-offset requests from ping-ponging with the resume target.
  void _queueDeferredDownload(int fileId, int offset) {
    final key =
        fileId * 1000000000 + offset; // Unique key combining fileId and offset
    if (_pendingQueuedOffsets.contains(key)) return; // Already queued

    _pendingQueuedOffsets.add(key);

    // Schedule retry after resume phase ends
    Future.delayed(Duration(milliseconds: _resumePhaseMs + 500), () {
      _pendingQueuedOffsets.remove(key);

      // Clear resume phase if expired
      final resumeStart = _resumePhaseStart[fileId];
      if (resumeStart != null &&
          DateTime.now().difference(resumeStart).inMilliseconds >
              _resumePhaseMs) {
        _resumePhaseStart.remove(fileId);
        _resumePrimaryOffset.remove(fileId);
        debugPrint('Proxy: RESUME PHASE ended for $fileId');
      }

      // Retry the download if file still active
      if (!_abortedRequests.contains(fileId)) {
        debugPrint(
          'Proxy: DEFERRED DOWNLOAD retry for $fileId at ${offset ~/ 1024}KB',
        );
        _startDownloadAtOffset(fileId, offset);
      }
    });
  }

  // ============================================================
  // PHASE 1: SEEK DEBOUNCE (RESERVED FOR FUTURE USE)
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
          debugPrint(
            'Proxy: PHASE1 - Executing debounced seek for $fileId to offset ${pendingOffset ~/ 1024}KB',
          );
          // Execute the actual seek by starting download at the debounced offset
          _startDownloadAtOffset(fileId, pendingOffset);
        }
      },
    );
  }

  /// Check if there's a pending debounced seek for a file.
  /// Returns the pending offset if exists, null otherwise.
  // ignore: unused_element
  int? _getPendingSeekOffset(int fileId) {
    return _pendingSeekOffsets[fileId];
  }
}
