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

  // Lookahead buffer: keep TDLib downloading ahead of playback position
  // 50MB is needed for high bitrate videos (>3GB files)
  static const int _lookAheadBytes = 50 * 1024 * 1024; // 50MB lookahead

  // Stall recovery: restart download after this many wait attempts (5 seconds)
  static const int _stallRecoveryAttempts = 25; // 25 * 200ms = 5 seconds

  // Track all active HTTP request offsets per file for cleanup on close
  final Map<int, Set<int>> _activeHttpRequestOffsets = {};

  // Throttle download requests to avoid spam
  static const int _downloadThrottleMs = 300; // 300ms between download calls
  final Map<int, DateTime> _lastDownloadRequestTime = {};

  // Debounce timers per file to prevent ping-ponging
  final Map<int, Timer> _debounceTimers = {};

  // PRIMARY PLAYBACK TRACKING: Track the lowest requested offset as the "primary playback" position.
  // This helps distinguish actual playback from metadata probes at end-of-file (moov atom).
  // Stall recovery should only act on the primary playback position, not on metadata probes.
  final Map<int, int> _primaryPlaybackOffset = {};

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
    _lastDownloadRequestTime.remove(fileId);
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
    _lastDownloadRequestTime.clear();
    _activeHttpRequestOffsets.clear();
    _primaryPlaybackOffset.clear();
    // Cancel all debounce timers
    for (var timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
  }

  /// Invalidates cached info for a specific file.
  /// Call this when a specific file is deleted from cache.
  void invalidateFile(int fileId) {
    debugPrint('Proxy: Invalidating cached info for file $fileId');
    _filePaths.remove(fileId);
    _activeDownloadOffset.remove(fileId);
    _lastDownloadRequestTime.remove(fileId);
    _activeHttpRequestOffsets.remove(fileId);
    _primaryPlaybackOffset.remove(fileId);
    _debounceTimers[fileId]?.cancel();
    _debounceTimers.remove(fileId);
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
    for (var timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
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
            // Extended timeout for large files (60 seconds total)
            int waitAttempts = 0;
            const maxWaitAttempts =
                300; // 300 * 200ms = 60 seconds per chunk max wait
            bool stallRecoveryTriggered = false;

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

              // Stall recovery: after 5 seconds, restart download with max priority
              // CRITICAL: Only trigger stall recovery if THIS request is the PRIMARY PLAYBACK request.
              // Metadata probes (moov atom at EOF) should NOT hijack the download.
              final primaryOffset = _primaryPlaybackOffset[fileId];
              final isThisPrimaryPlayback =
                  primaryOffset == null ||
                  currentReadOffset <=
                      primaryOffset + (4 * 1024 * 1024); // Allow 4MB tolerance

              if (waitAttempts == _stallRecoveryAttempts &&
                  !stallRecoveryTriggered &&
                  isThisPrimaryPlayback) {
                stallRecoveryTriggered = true;

                // Stall recovery: simple and robust.
                // If THIS request has been waiting for 5 seconds and is still alive (checked implicitly by running this code),
                // we force the download to switch to us.
                // This breaks deadlocks where the Proxy is "stuck" on a metadata request that isn't completing.
                debugPrint(
                  'Proxy: Stall recovery triggered for $fileId at offset $currentReadOffset (Primary: $primaryOffset, Active was: ${_activeDownloadOffset[fileId]})',
                );

                // Force restart download at exact offset
                _activeDownloadOffset.remove(fileId);
                _lastDownloadRequestTime.remove(fileId);

                // Start fresh with synchronous mode to force TDLib to prioritize
                TelegramService().send({
                  '@type': 'downloadFile',
                  'file_id': fileId,
                  'priority': 32,
                  'offset': currentReadOffset,
                  'limit': 0,
                  'synchronous':
                      true, // Force sequential download from this offset
                });
              } else if (waitAttempts == _stallRecoveryAttempts &&
                  !stallRecoveryTriggered &&
                  !isThisPrimaryPlayback) {
                // Log that we're skipping stall recovery for a metadata probe
                debugPrint(
                  'Proxy: Skipping stall recovery for metadata probe at $currentReadOffset (Primary: $primaryOffset)',
                );
                stallRecoveryTriggered =
                    true; // Mark to prevent repeated logging
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

  /// SIMPLIFIED with OFFSET LOCKING: Once a download starts at an offset,
  /// don't switch to a different offset for a minimum duration.
  /// This prevents TDLib from constantly switching between downloads.
  void _startDownloadAtOffset(int fileId, int requestedOffset) {
    // 1. Check if file is already complete - no download needed
    final cached = _filePaths[fileId];
    if (cached != null && cached.isCompleted) {
      return;
    }

    // 2. Check if data is already available at this offset
    if (cached != null && cached.availableBytesFrom(requestedOffset) > 0) {
      // Data available - optionally trigger lookahead download
      final downloadFrontier =
          cached.downloadOffset + cached.downloadedPrefixSize;
      final lookaheadTarget = requestedOffset + _lookAheadBytes;

      if (downloadFrontier < lookaheadTarget &&
          downloadFrontier < cached.totalSize) {
        // Trigger lookahead download (low priority, throttled)
        final now = DateTime.now();
        final lastRequest = _lastDownloadRequestTime[fileId];
        if (lastRequest == null ||
            now.difference(lastRequest).inMilliseconds >= _downloadThrottleMs) {
          _lastDownloadRequestTime[fileId] = now;
          TelegramService().send({
            '@type': 'downloadFile',
            'file_id': fileId,
            'priority': 16, // Medium priority for lookahead
            'offset': downloadFrontier,
            'limit': 0,
            'synchronous': false,
          });
        }
      }
      return;
    }

    // 2.5 Suppress redundant sequential requests
    // If we are already downloading from an offset close to this one, don't re-trigger.
    // This allows TDLib to maintain a continuous stream without interruption.
    final currentActiveOffset = _activeDownloadOffset[fileId];
    if (currentActiveOffset != null) {
      final diff = requestedOffset - currentActiveOffset;
      // If requested offset is ahead of current (but not too far, e.g. 32MB)
      // AND we requested it recently (< 15 seconds)
      if (diff >= 0 && diff < 32 * 1024 * 1024) {
        final lastRequest = _lastDownloadRequestTime[fileId];
        final now = DateTime.now();
        if (lastRequest != null && now.difference(lastRequest).inSeconds < 15) {
          // Ignore this redundant request
          // debugPrint('Proxy: Suppressing redundant request at $requestedOffset (Active: $currentActiveOffset)');
          return;
        }
      }
    }

    // 3. Debounce the download request
    // This allows the player to "probe" offsets (like metadata at end of file)
    // without immediately triggering a heavy TDLib download switch.
    // If the player STAYS on this offset for >200ms, we switch.

    // Cancel any pending switch
    _debounceTimers[fileId]?.cancel();

    // Start new debounce timer
    _debounceTimers[fileId] = Timer(const Duration(milliseconds: 200), () {
      if (_abortedRequests.contains(fileId)) return;

      final now = DateTime.now();
      final lastRequest = _lastDownloadRequestTime[fileId];

      // Simple throttle for identical repeated requests
      if (_activeDownloadOffset[fileId] == requestedOffset &&
          lastRequest != null &&
          now.difference(lastRequest).inMilliseconds < _downloadThrottleMs) {
        return;
      }

      // Check existence again effectively inside the closure before acting
      if (_filePaths[fileId]?.isCompleted ?? false) return;

      _lastDownloadRequestTime[fileId] = now;
      _activeDownloadOffset[fileId] = requestedOffset;

      debugPrint(
        'Proxy: Debounce triggered - Downloading from offset $requestedOffset for $fileId',
      );

      TelegramService().send({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 32, // Maximum priority
        'offset': requestedOffset,
        'limit': 0, // Download from offset to end
        'synchronous': false,
      });

      // Clean up timer reference
      _debounceTimers.remove(fileId);
    });
  }
}
