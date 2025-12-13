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

  // TWO-PHASE DOWNLOAD TRACKING:
  // Phase 1: Download end of file for moov atom (MP4 metadata)
  // Phase 2: Download from playback position
  // We allow exactly TWO downloadFile calls per file - one for each phase
  final Set<int> _moovDownloadInitiated = {};
  final Set<int> _moovCompleted =
      {}; // Track when moov region is fully downloaded
  final Set<int> _playbackDownloadInitiated = {};

  // Re-trigger throttling to prevent ping-pong between offsets
  final Map<int, DateTime> _lastRetriggerTime = {};
  static const int _retriggerCooldownMs =
      1500; // 1.5 second cooldown between re-triggers (reduced for faster seeking)

  // Threshold for re-triggering download at new offset (increased to reduce jumps)
  static const int _retriggerThresholdBytes = 100 * 1024 * 1024; // 100MB

  // Size of moov region to download at end of file (16MB should be enough for most files)
  static const int _moovRegionSize = 16 * 1024 * 1024;

  int get port => _port;

  void abortRequest(int fileId) {
    // Prevent duplicate abort calls
    if (_abortedRequests.contains(fileId)) {
      return;
    }

    debugPrint('Proxy: Aborting request for fileId $fileId');
    _abortedRequests.add(fileId);
    _activeDownloadRequests.remove(fileId);

    // NOTE: Following Unigram's pattern - we do NOT call cancelDownloadFile here.
    // Unigram intentionally lets downloads continue in the background.
    // Calling cancelDownloadFile while TDLib is mid-operation can cause
    // PartsManager crashes. Instead, we just stop serving data to the player.

    // Notify any waiting loops to wake up and check abort status
    _fileUpdateNotifiers[fileId]?.add(null);
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
    try {
      fileIdStr = request.uri.queryParameters['file_id'];
      final sizeStr = request.uri.queryParameters['size'];

      if (fileIdStr == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final fileId = int.parse(fileIdStr);
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
      int start = 0;
      int? end;

      if (rangeHeader != null) {
        final parts = rangeHeader.replaceFirst('bytes=', '').split('-');
        start = int.parse(parts[0]);
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.parse(parts[1]);
        }
      }

      // 2. Ensure File Info is available
      if (!_filePaths.containsKey(fileId) || _filePaths[fileId]!.path.isEmpty) {
        await _fetchFileInfo(fileId);
      }

      final fileInfo = _filePaths[fileId];
      if (fileInfo == null || fileInfo.path.isEmpty) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final file = File(fileInfo.path);

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

            // PREFETCH: Ensure download is initiated using two-phase approach
            _ensureDownloadInitiated(fileId, currentReadOffset);
          } else {
            // NO DATA AVAILABLE -> BLOCKING WAIT
            final cached = _filePaths[fileId];
            debugPrint(
              'Proxy: Waiting for data at $currentReadOffset for $fileId '
              '(CachedOffset: ${cached?.downloadOffset}, CachedPrefix: ${cached?.downloadedPrefixSize})...',
            );

            // Ensure download is initiated using two-phase approach
            _ensureDownloadInitiated(fileId, currentReadOffset);

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

  /// Ensure download is initiated using TWO-PHASE approach for MP4 compatibility
  /// Phase 1: Download end of file (moov atom / metadata)
  /// Phase 2: Download from playback position
  /// This prevents PartsManager crashes while allowing MP4 files to play
  void _ensureDownloadInitiated(int fileId, int requestedOffset) {
    // Check if file is already complete - no download needed
    final cached = _filePaths[fileId];
    if (cached != null && cached.isCompleted) {
      return;
    }

    final totalSize = cached?.totalSize ?? 0;

    // Determine if this is a request for the end of file (moov atom area)
    // MP4 files often have metadata at the end, and the player needs to read it first
    final isEndOfFileRequest =
        totalSize > 0 &&
        requestedOffset > totalSize - _moovRegionSize - (1024 * 1024);

    if (isEndOfFileRequest && !_moovDownloadInitiated.contains(fileId)) {
      // PHASE 1: Download end of file for moov atom
      final moovOffset = totalSize > _moovRegionSize
          ? totalSize - _moovRegionSize
          : 0;

      debugPrint(
        'Proxy: Phase 1 - Downloading moov region for $fileId from offset $moovOffset',
      );
      _moovDownloadInitiated.add(fileId);

      TelegramService().send({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 32,
        'offset': moovOffset,
        'limit': _moovRegionSize,
        'synchronous': false,
      });
    } else if (!isEndOfFileRequest) {
      // PHASE 2: Download from playback position
      // Only do this if moov is already complete (or not needed)

      // Check if TDLib offset is far from what we need - we may need to restart
      final currentOffset = cached?.downloadOffset ?? 0;
      final distanceFromCurrent = (currentOffset - requestedOffset).abs();
      final needsRestart = distanceFromCurrent > _retriggerThresholdBytes;

      // Throttling: Check if we've re-triggered recently (prevent ping-pong)
      final now = DateTime.now();
      final lastRetrigger = _lastRetriggerTime[fileId];
      final canRetrigger =
          lastRetrigger == null ||
          now.difference(lastRetrigger).inMilliseconds >= _retriggerCooldownMs;

      // Check if we've already confirmed moov completion
      if (_moovCompleted.contains(fileId)) {
        // Moov is confirmed complete
        // Check if we need to restart at a different position (e.g., resume from saved position)
        if (!_playbackDownloadInitiated.contains(fileId) ||
            (needsRestart && canRetrigger)) {
          if (needsRestart) {
            debugPrint(
              'Proxy: Re-triggering playback for $fileId (TDLib at $currentOffset, player needs $requestedOffset)',
            );
            _lastRetriggerTime[fileId] = now; // Record re-trigger time
          } else {
            debugPrint(
              'Proxy: Phase 2 - Downloading playback region for $fileId from offset $requestedOffset',
            );
          }
          _playbackDownloadInitiated.add(fileId);

          TelegramService().send({
            '@type': 'downloadFile',
            'file_id': fileId,
            'priority': 32,
            'offset': requestedOffset,
            'limit': 0,
            'synchronous': false,
          });
        }
        return;
      }

      // Check if moov has been downloaded - we need the last 16MB of the file
      final moovOffset = totalSize > _moovRegionSize
          ? totalSize - _moovRegionSize
          : 0;
      final downloadedFromMoov = cached?.downloadOffset ?? 0;
      final downloadedPrefixAtMoov = cached?.downloadedPrefixSize ?? 0;

      // Check if moov region is complete: we have data at moov offset with sufficient prefix
      final moovIsComplete =
          totalSize == 0 || // No size info, assume ok
          (downloadedFromMoov >= moovOffset &&
              downloadedPrefixAtMoov >= _moovRegionSize) ||
          (downloadedFromMoov == 0 &&
              downloadedPrefixAtMoov >=
                  totalSize - moovOffset); // Downloaded from start past moov

      // Also check if moov download hasn't started - then we can start playback
      final moovNotStarted = !_moovDownloadInitiated.contains(fileId);

      // Only trigger playback if moov is complete OR moov hasn't started
      final canStartPlayback = moovIsComplete || moovNotStarted;

      if (moovIsComplete) {
        _moovCompleted.add(fileId); // Remember this for future calls
      }

      // Use the variables already calculated above for needsRestart check

      if (canStartPlayback &&
          (!_playbackDownloadInitiated.contains(fileId) ||
              (needsRestart && canRetrigger))) {
        if (needsRestart && moovIsComplete) {
          debugPrint(
            'Proxy: Re-triggering playback download for $fileId (moov complete, TDLib at $currentOffset, need $requestedOffset)',
          );
          _lastRetriggerTime[fileId] = now; // Record re-trigger time
        } else if (!_playbackDownloadInitiated.contains(fileId)) {
          debugPrint(
            'Proxy: Phase 2 - Downloading playback region for $fileId from offset $requestedOffset',
          );
        }
        _playbackDownloadInitiated.add(fileId);

        TelegramService().send({
          '@type': 'downloadFile',
          'file_id': fileId,
          'priority': 32,
          'offset': requestedOffset,
          'limit': 0, // Download rest of file from this point
          'synchronous': false,
        });
      } else if (!canStartPlayback) {
        debugPrint(
          'Proxy: Waiting for moov download to complete for $fileId (moovOffset: $moovOffset, currentOffset: $downloadedFromMoov, prefix: $downloadedPrefixAtMoov)',
        );
      }
    }
  }
}
