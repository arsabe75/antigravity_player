import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'telegram_service.dart';
import 'mp4_sample_table.dart';

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
  final List<int> _lruOrder = []; // Most recently used at end
  int _currentSize = 0;

  /// Get cached data for the given range.
  /// Returns null if data is not fully cached.
  Uint8List? get(int offset, int length) {
    final startChunk = offset ~/ chunkSize;
    final endChunk = (offset + length - 1) ~/ chunkSize;

    // Check if all required chunks are cached
    for (int i = startChunk; i <= endChunk; i++) {
      if (!_chunks.containsKey(i)) {
        return null; // Cache miss
      }
    }

    // All chunks are cached - assemble the result
    final result = Uint8List(length);
    int resultOffset = 0;

    for (int i = startChunk; i <= endChunk; i++) {
      final chunk = _chunks[i]!;
      final chunkStart = i * chunkSize;

      // Calculate which part of this chunk we need
      final copyStart = i == startChunk ? offset - chunkStart : 0;
      final copyEnd = i == endChunk
          ? (offset + length) - chunkStart
          : chunk.length;
      final copyLen = min(copyEnd - copyStart, length - resultOffset);

      if (copyStart >= 0 && copyStart < chunk.length && copyLen > 0) {
        result.setRange(
          resultOffset,
          resultOffset + copyLen,
          chunk.sublist(copyStart, copyStart + copyLen),
        );
        resultOffset += copyLen;
      }

      // Update LRU order
      _lruOrder.remove(i);
      _lruOrder.add(i);
    }

    return result;
  }

  /// Store data in cache, evicting old chunks if necessary.
  void put(int offset, Uint8List data) {
    final startChunk = offset ~/ chunkSize;

    // Split data into chunks
    int dataOffset = 0;
    int chunkIndex = startChunk;

    // Handle partial start chunk
    final startChunkOffset = offset % chunkSize;
    if (startChunkOffset > 0 && !_chunks.containsKey(chunkIndex)) {
      // Skip partial first chunk if we don't have existing data
      dataOffset = chunkSize - startChunkOffset;
      chunkIndex++;
    }

    while (dataOffset < data.length) {
      final remaining = data.length - dataOffset;
      final chunkLen = min(chunkSize, remaining);

      // Only cache complete chunks
      if (chunkLen == chunkSize || dataOffset + chunkLen == data.length) {
        final chunkData = data.sublist(dataOffset, dataOffset + chunkLen);

        // Evict if necessary
        while (_currentSize + chunkLen > maxCacheSize && _lruOrder.isNotEmpty) {
          final evictIndex = _lruOrder.removeAt(0);
          final evicted = _chunks.remove(evictIndex);
          if (evicted != null) {
            _currentSize -= evicted.length;
          }
        }

        // Store chunk
        if (!_chunks.containsKey(chunkIndex)) {
          _chunks[chunkIndex] = chunkData;
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

  // MOOV ATOM PROTECTION: Track when download started for each file
  // This helps avoid canceling initial download when moov atom is requested
  final Map<int, DateTime> _downloadStartTime = {};

  // MOOV STABILIZE: Track when moov requests should be allowed (after delay)
  final Map<int, DateTime> _moovUnblockTime = {};

  // MOOV STABILIZE: Track files that have completed stabilization (don't re-trigger)
  final Set<int> _moovStabilizeCompleted = {};

  // ============================================================
  // PHASE 1: DRKLO-INSPIRED OPTIMIZATIONS
  // ============================================================

  // SEEK DEBOUNCE: Prevent flooding TDLib with rapid seek cancellations
  // During scrubbing, coalesce multiple seeks into single request
  final Map<int, Timer?> _seekDebounceTimers = {};
  final Map<int, int> _pendingSeekOffsets = {};
  static const int _seekDebounceMs = 150; // Delay before executing seek

  // MOOV PRE-FETCH: Schedule moov download after initial buffering
  // This avoids the ping-pong effect for MP4s with moov at end
  final Map<int, bool> _moovPreFetchScheduled = {};
  final Map<int, bool> _moovPreFetchCompleted = {};
  static const int _moovPreFetchMinPrefix =
      2 * 1024 * 1024; // Wait for 2MB before fetching moov

  // MOOV-AT-END DETECTION: Track files where moov atom is at the end
  // These files are NOT optimized for streaming and require extra loading time
  final Map<int, bool> _isMoovAtEnd = {};

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

  int get port => _port;

  // OPTIMIZATION 2: Track files we've started preloading from list view
  final Set<int> _listPreloadStarted = {};

  /// Preload the first 2MB of a video when it appears in the list view
  /// This enables faster start when user clicks to play
  void preloadVideoStart(int fileId, int? totalSize) {
    // Only preload once per file
    if (_listPreloadStarted.contains(fileId)) return;

    // Skip if already cached or downloading
    final cached = _filePaths[fileId];
    if (cached != null &&
        (cached.downloadedPrefixSize > 2 * 1024 * 1024 || cached.isCompleted)) {
      return;
    }

    _listPreloadStarted.add(fileId);

    debugPrint(
      'Proxy: OPTIMIZATION 2 - Preloading first 2MB for $fileId from list view',
    );

    // Start background download with MINIMUM priority (1)
    TelegramService().send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': 1, // Minimum priority - won't interfere with active playback
      'offset': 0,
      'limit': 2 * 1024 * 1024, // Just first 2MB
      'synchronous': false,
    });

    // Also preload moov if we know the total size
    if (totalSize != null && totalSize > 50 * 1024 * 1024) {
      _preloadMoovAtom(fileId, totalSize);
    }
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

    // Clear Phase 1 optimization state
    for (final timer in _seekDebounceTimers.values) {
      timer?.cancel();
    }
    _seekDebounceTimers.clear();
    _pendingSeekOffsets.clear();
    _moovPreFetchScheduled.clear();
    _moovPreFetchCompleted.clear();

    // Clear LRU streaming caches
    for (final cache in _streamingCaches.values) {
      cache.clear();
    }
    _streamingCaches.clear();
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

      // SEEK DETECTION: Mark if this is a seek (jump > 1MB from last served offset)
      // IMPORTANT: Do this BEFORE primary tracking so we can reset primary on seek
      bool isSeekRequest = false;
      final lastOffset = _lastServedOffset[fileId];
      if (lastOffset != null) {
        final jump = (start - lastOffset).abs();
        if (jump > 1024 * 1024) {
          isSeekRequest = true;
          _lastSeekTime[fileId] = DateTime.now();
          // CRITICAL FIX: When a seek is detected, reset the primary offset to the seek target
          // This prevents the primary from getting stuck at 0 when seeking forward
          _primaryPlaybackOffset[fileId] = start;
          debugPrint(
            'Proxy: Detected seek for $fileId: $lastOffset -> $start (jump: ${jump ~/ 1024}KB), primary reset to $start',
          );
        }
      }

      // PRIMARY PLAYBACK TRACKING: Track the lowest RECENT offset as the "primary playback" position.
      // This helps stall recovery prioritize actual playback over metadata probes (moov atom at EOF).
      // Only update if this offset is earlier than the current primary, or if no primary is set,
      // or if this is the first request after a seek.
      final existingPrimary = _primaryPlaybackOffset[fileId];
      if (existingPrimary == null) {
        _primaryPlaybackOffset[fileId] = start;
      } else if (!isSeekRequest && start < existingPrimary) {
        // Only track lower offsets if this is NOT a seek request
        // (seek requests already set the primary above)
        _primaryPlaybackOffset[fileId] = start;
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
      final effectiveEnd =
          end ?? (effectiveTotalSize > 0 ? effectiveTotalSize - 1 : 0);

      // Validate Range
      if (start > effectiveEnd) {
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

            // LRU CACHE: DISABLED - causes 'Error decoding audio' on backward seeks
            // The cache logic has bugs with non-aligned chunk boundaries that return
            // corrupted data. Needs redesign before re-enabling.
            // TODO: Fix chunk boundary handling for non-512KB-aligned offsets

            // _streamingCaches.putIfAbsent(fileId, () => _StreamingLRUCache());
            // final cachedData = _streamingCaches[fileId]!.get(
            //   currentReadOffset,
            //   chunkToRead,
            // );

            // Always read from disk for now
            await raf.setPosition(currentReadOffset);
            final data = await raf.read(chunkToRead);

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

            // Ensure download is started at the exact offset the player needs
            _startDownloadAtOffset(fileId, currentReadOffset);

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
            _startDownloadAtOffset(fileId, currentReadOffset);

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
  void _startDownloadAtOffset(int fileId, int requestedOffset) {
    // Check if file is already complete - no download needed
    final cached = _filePaths[fileId];
    if (cached != null && cached.isCompleted) {
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
    final totalSize = cached?.totalSize ?? 0;
    if (totalSize > 0) {
      final distanceFromEnd = totalSize - requestedOffset;

      // PHASE 4: Use percentage-based threshold for large files
      // For 2GB file: 0.5% = 10MB, for 500MB file: 0.5% = 2.5MB
      final moovThresholdBytes = totalSize > 500 * 1024 * 1024
          ? (totalSize * 0.005)
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
              // Trigger the moov download now that TDLib has settled
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
      if (timeSinceLastChange < cooldownMs ||
          distanceFromCurrent < minDistance) {
        return; // Too soon or too close
      }
    }

    // TELEGRAM ANDROID-INSPIRED: Calculate dynamic priority based on distance
    // to primary playback position. Closer = higher priority.
    final priority = _calculateDynamicPriority(distanceToPlayback);

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
    _lastOffsetChangeTime[fileId] = now;

    // PARTSMANAGER FIX: Use synchronous mode for moov atom downloads
    // This prevents parallel range conflicts that cause PartsManager crashes
    final isMoovDownload =
        _isMoovAtEnd[fileId] == true &&
        totalSize > 0 &&
        (totalSize - requestedOffset) <
            (totalSize * 0.01).round().clamp(5 * 1024 * 1024, 50 * 1024 * 1024);

    // DISABLED: This cancel-and-wait mechanism was causing race conditions.
    // It would cancel the current download, wait 1s, then try to download moov.
    // Removed cachedPrefix variable that was used for this mechanism.
    // But during that 1s wait, other requests kept coming and triggering new downloads,
    // which interfered with the deferred moov download.
    // Now we just let TDLib handle the offset change directly.
    // if (isMoovDownload && isLargeJump && cachedPrefix > 0) {
    //   debugPrint('Proxy: Canceling and waiting before moov jump...');
    //   TelegramService().send({'@type': 'cancelDownloadFile', ...});
    //   Future.delayed(...);
    //   return;
    // }

    // MOOV FIX: Use larger preload for moov downloads to ensure complete atom
    // Moov atoms can be 5-10MB for large videos, adaptive buffer might be too small
    final actualPreload = isMoovDownload
        ? (preloadBytes < 8 * 1024 * 1024 ? 8 * 1024 * 1024 : preloadBytes)
        : preloadBytes;

    if (isMoovDownload && actualPreload != preloadBytes) {
      debugPrint(
        'Proxy: Using larger preload for moov: ${actualPreload ~/ 1024}KB',
      );
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
  /// Inspired by Telegram Android's FileLoadOperation priority handling.
  /// Returns priority 8-32 where 32 is highest.
  int _calculateDynamicPriority(int distanceBytes) {
    if (distanceBytes < 1024 * 1024) {
      return 32; // < 1MB: Maximum priority (immediate playback)
    } else if (distanceBytes < 5 * 1024 * 1024) {
      return 24; // < 5MB: High priority (near-term playback)
    } else if (distanceBytes < 10 * 1024 * 1024) {
      return 16; // < 10MB: Medium priority (buffer building)
    } else {
      return 8; // >= 10MB: Low priority (preload/metadata)
    }
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
      'priority': 16,
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
  // PHASE 1: SEEK DEBOUNCE (RESERVED FOR FUTURE USE)
  // ============================================================

  /// Debounced seek handler to prevent flooding TDLib with rapid cancellations.
  /// Instead of immediately cancelling and restarting download on each seek,
  /// this coalesces rapid seeks into a single request.
  // ignore: unused_element
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
