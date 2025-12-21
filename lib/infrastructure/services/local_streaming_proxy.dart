import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'telegram_service.dart';

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
  static const int _offsetChangeCooldownMs =
      500; // 500ms cooldown between offset changes

  // ============================================================
  // TELEGRAM ANDROID-INSPIRED IMPROVEMENTS
  // ============================================================

  // PRELOAD ADAPTATIVO: Bytes mínimos antes de servir datos al player
  // Inspired by ExoPlayer's bufferForPlaybackMs
  static const int _minPreloadBytes = 2 * 1024 * 1024; // 2MB default preload
  static const int _fastNetworkPreload = 512 * 1024; // 512KB for fast network
  static const int _slowNetworkPreload =
      4 * 1024 * 1024; // 4MB for slow network

  // MÉTRICAS DE VELOCIDAD: Track download speed for adaptive decisions
  final Map<int, _DownloadMetrics> _downloadMetrics = {};

  // SEEK RÁPIDO: Track if we recently seeked to reduce buffer requirement
  final Map<int, DateTime> _lastSeekTime = {};
  static const int _seekBufferReductionWindowMs = 5000; // 5s after seek

  // Track all active HTTP request offsets per file for cleanup on close
  final Map<int, Set<int>> _activeHttpRequestOffsets = {};

  // PRIMARY PLAYBACK TRACKING: Track the lowest requested offset as the "primary playback" position.
  // This helps distinguish actual playback from metadata probes at end-of-file (moov atom).
  // Stall recovery should only act on the primary playback position, not on metadata probes.
  final Map<int, int> _primaryPlaybackOffset = {};

  // Track last served offset to detect seeks
  final Map<int, int> _lastServedOffset = {};

  int get port => _port;

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
      fileIdStr = request.uri.queryParameters['file_id'];
      final sizeStr = request.uri.queryParameters['size'];

      if (fileIdStr == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      fileId = int.parse(fileIdStr);
      final totalSize = int.tryParse(sizeStr ?? '') ?? 0;

      // If ANY files were recently aborted, give TDLib time to clean up
      // This is crucial - TDLib can crash if we start new downloads while
      // it's still processing cancellations internally
      if (_abortedRequests.isNotEmpty) {
        debugPrint(
          'Proxy: Waiting for TDLib to stabilize (${_abortedRequests.length} aborted files)...',
        );
        // Clear our abort tracking - we're about to start fresh
        _abortedRequests.clear();
        // Give TDLib substantial time to clean up internal state
        await Future.delayed(const Duration(milliseconds: 500));
        debugPrint('Proxy: TDLib stabilization wait complete');
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

      // PRIMARY PLAYBACK TRACKING: Track the lowest offset as the "primary playback" position.
      // This helps stall recovery prioritize actual playback over metadata probes (moov atom at EOF).
      // Only update if this offset is earlier than the current primary, or if no primary is set.
      final existingPrimary = _primaryPlaybackOffset[fileId];
      if (existingPrimary == null || start < existingPrimary) {
        _primaryPlaybackOffset[fileId] = start;
      }

      // SEEK DETECTION: Mark if this is a seek (jump > 1MB from last served offset)
      final lastOffset = _lastServedOffset[fileId];
      if (lastOffset != null) {
        final jump = (start - lastOffset).abs();
        if (jump > 1024 * 1024) {
          _lastSeekTime[fileId] = DateTime.now();
          debugPrint(
            'Proxy: Detected seek for $fileId: $lastOffset -> $start (jump: ${jump ~/ 1024}KB)',
          );
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
            const maxWaitAttempts =
                25; // 25 * 200ms = 5 seconds per chunk max wait

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
    // (within 10MB of the download frontier)
    // CRITICAL: Only wait if download is ACTUALLY ACTIVE, otherwise we'd wait forever!
    final downloadFrontier = currentDownloadOffset + currentPrefix;
    final distanceFromFrontier = requestedOffset - downloadFrontier;
    final isDownloading = cached?.isDownloadingActive ?? false;
    if (isDownloading &&
        distanceFromFrontier >= 0 &&
        distanceFromFrontier < 10 * 1024 * 1024) {
      // Current download will reach our offset soon, don't restart
      return;
    }

    // Check if already targeting this offset
    if (currentActiveOffset == requestedOffset) {
      return;
    }

    // Throttle offset changes to avoid excessive downloadFile calls
    final now = DateTime.now();
    final lastChange = _lastOffsetChangeTime[fileId];
    if (lastChange != null &&
        now.difference(lastChange).inMilliseconds < _offsetChangeCooldownMs) {
      return;
    }

    // TELEGRAM ANDROID-INSPIRED: Calculate dynamic priority based on distance
    // to primary playback position. Closer = higher priority.
    final primaryOffset = _primaryPlaybackOffset[fileId] ?? 0;
    final distanceToPlayback = (requestedOffset - primaryOffset).abs();
    final priority = _calculateDynamicPriority(distanceToPlayback);

    // ADAPTIVE PRELOAD: Determine minimum bytes before we start serving
    // Based on network speed and whether we just seeked
    final metrics = _downloadMetrics[fileId];
    final lastSeek = _lastSeekTime[fileId];
    final isRecentSeek =
        lastSeek != null &&
        now.difference(lastSeek).inMilliseconds < _seekBufferReductionWindowMs;

    int preloadBytes = _minPreloadBytes;
    if (isRecentSeek) {
      // After seek, use minimal preload for faster resume (like ExoPlayer's bufferForPlaybackMs)
      preloadBytes = _fastNetworkPreload;
      debugPrint(
        'Proxy: Post-seek mode for $fileId - using fast preload (${preloadBytes ~/ 1024}KB)',
      );
    } else if (metrics != null) {
      if (metrics.isFastNetwork) {
        preloadBytes = _fastNetworkPreload;
      } else if (metrics.isStalled) {
        preloadBytes = _slowNetworkPreload;
      }
    }

    // Start download at exactly the offset the player requested
    debugPrint(
      'Proxy: Downloading from offset $requestedOffset for $fileId '
      '(priority: $priority, preload: ${preloadBytes ~/ 1024}KB)',
    );

    _activeDownloadOffset[fileId] = requestedOffset;
    _lastOffsetChangeTime[fileId] = now;

    TelegramService().send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': priority,
      'offset': requestedOffset,
      'limit': 0,
      'synchronous': false,
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
}
