import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'telegram_service.dart';

class ProxyFileInfo {
  final String path;
  final int totalSize;
  final int downloadedPrefixSize;
  bool isCompleted;

  ProxyFileInfo({
    required this.path,
    required this.totalSize,
    this.downloadedPrefixSize = 0,
    this.isCompleted = false,
  });
}

class LocalStreamingProxy {
  static final LocalStreamingProxy _instance = LocalStreamingProxy._internal();
  factory LocalStreamingProxy() => _instance;
  LocalStreamingProxy._internal();

  HttpServer? _server;
  int _port = 0;

  // Cache of file_id -> ProxyFileInfo
  final Map<int, ProxyFileInfo> _filePaths = {}; // ID -> Info
  final Set<int> _activeDownloadRequests = {};

  // Buffering Logic
  final Set<int> _activeFileIds = {};
  Timer? _bufferingTimer;
  // Map to track the "playback position" roughly by the last requested range start for each file
  // This helps us know where to buffer FROM.
  final Map<int, int> _lastReadPositions = {};

  void _startBufferingLoop() {
    if (_bufferingTimer != null && _bufferingTimer!.isActive) return;
    debugPrint('Proxy: Starting active buffering loop...');
    _bufferingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_activeFileIds.isEmpty) {
        timer.cancel();
        _bufferingTimer = null;
        debugPrint('Proxy: Buffering loop stopped (no active files).');
        return;
      }

      for (final fileId in _activeFileIds.toList()) {
        try {
          // Query file status
          final fileJson = await TelegramService().sendWithResult({
            '@type': 'getFile',
            'file_id': fileId,
          });

          if (fileJson['@type'] == 'file') {
            final local = fileJson['local'];
            final size = fileJson['size'] ?? 0;
            final downloadedSize = local?['downloaded_prefix_size'] ?? 0;
            final isCompleted = local?['is_downloading_completed'] ?? false;

            // Update cache
            _filePaths[fileId] = ProxyFileInfo(
              path: local?['path'] ?? '',
              totalSize: size,
              downloadedPrefixSize: downloadedSize,
              isCompleted: isCompleted,
            );

            if (isCompleted) {
              _activeFileIds.remove(fileId); // Done
              continue;
            }

            final lastRead = _lastReadPositions[fileId] ?? 0;
            const bufferAmount = 30 * 1024 * 1024; // 30MB
            final targetOffset = lastRead + bufferAmount;

            // CRITICAL FIX: Don't request past file size
            if (targetOffset >= size) {
              // Optional: check if we need to fill the gap to the end?
              // If lastRead < size, we might need [lastRead, size]
              // But active buffering is 'lookahead'.
              // Let's just stop if lookahead is out of bounds.
              continue;
            }

            // Trigger download ahead
            TelegramService().send({
              '@type': 'downloadFile',
              'file_id': fileId,
              'priority': 5, // Backgound
              'offset': targetOffset,
              'limit': bufferAmount, // Ask for next chunk
              'synchronous': false,
            });
          }
        } catch (e) {
          // Ignore errors
        }
      }
    });
  }

  // Track aborted requests to cancel waiting loops
  final Set<int> _abortedRequests = {};

  int get port => _port;

  void abortRequest(int fileId) {
    debugPrint('Proxy: Aborting request for fileId $fileId');
    _abortedRequests.add(fileId);
    // Also remove from active so we can retry later if user returns
    _activeDownloadRequests.remove(fileId);
    _activeFileIds.remove(fileId); // Remove from active buffering
  }

  Future<void> start() async {
    if (_server != null) return;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    debugPrint('LocalStreamingProxy running on port $_port');

    _server!.listen(_handleRequest);

    // Listen to TDLib updates to track file paths
    // Listen to TDLib updates to track file paths
    // Ensure we don't stack listeners (simple check, though single start() prevents this usually)
    TelegramService().updates.listen((update) {
      if (update['@type'] == 'updateFile') {
        final file = update['file'];
        final id = file['id'];
        final path = file['local']?['path'];
        final isDownloadingActive = file['local']?['is_downloading_active'];
        final isDownloadingCompleted =
            file['local']?['is_downloading_completed'];

        // Debug Log
        // Debug Log - Only log specific IDs or significant events (e.g. valid path but not complete)
        // Removed active=true check to prevent flood.
        if (id == 1326 || id == 1504) {
          debugPrint(
            'Proxy Trace: updateFile id=$id, path=$path, active=$isDownloadingActive, completed=$isDownloadingCompleted',
          );
        }

        if (path != null && path.toString().isNotEmpty) {
          final size = file['size'] ?? 0;
          if (!_filePaths.containsKey(id)) {
            debugPrint(
              'Proxy: Path resolved for $id -> $path (Size: $size, Complete: $isDownloadingCompleted)',
            );
          } else {
            // Update existing info
            if (_filePaths[id]!.isCompleted != isDownloadingCompleted) {
              debugPrint(
                'Proxy: File $id completed status changed to $isDownloadingCompleted',
              );
            }
          }
          _filePaths[id] = ProxyFileInfo(
            path: path,
            totalSize: size,
            isCompleted: isDownloadingCompleted,
          );
        }
      }
    });
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    _activeFileIds.clear();
    _lastReadPositions.clear();
  }

  String getUrl(int fileId, int size) {
    return 'http://127.0.0.1:$_port/stream?file_id=$fileId&size=$size';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final fileIdStr = request.uri.queryParameters['file_id'];
      final totalSizeStr = request.uri.queryParameters['size'];

      if (fileIdStr == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final fileId = int.parse(fileIdStr);
      final totalSize = int.tryParse(totalSizeStr ?? '') ?? 0;

      // CRITICAL FIX: Reset abort status for new requests
      // This ensures re-entry works even if previously aborted
      _abortedRequests.remove(fileId);

      // START HOISTED RANGE PARSING
      // Handle Range Header early to get 'start' offset for download priority
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
      // END HOISTED RANGE PARSING

      // Track read position for buffering
      _lastReadPositions[fileId] = start;
      debugPrint(
        'Proxy: Handle request for fileId $fileId (Range: $rangeHeader, Start: $start)',
      );

      if (!_activeFileIds.contains(fileId)) {
        _activeFileIds.add(fileId);
        _startBufferingLoop(); // Ensure loop is running
      }

      // Ensure we have the file info.
      // CRITICAL FIX: Use sendWithResult to explicitly get file info
      if (!_filePaths.containsKey(fileId) || _filePaths[fileId]!.path.isEmpty) {
        try {
          final fileJson = await TelegramService().sendWithResult({
            '@type': 'getFile',
            'file_id': fileId,
          });

          if (fileJson['@type'] == 'file') {
            final path = fileJson['local']?['path'];
            final isCompleted =
                fileJson['local']?['is_downloading_completed'] ?? false;
            final size = fileJson['size'] ?? 0;

            if (path != null && path.toString().isNotEmpty) {
              _filePaths[fileId] = ProxyFileInfo(
                path: path,
                totalSize: size,
                isCompleted: isCompleted,
              );
              debugPrint(
                'Proxy: Path resolved via getFile for $fileId -> $path',
              );
            }
          }
        } catch (e) {
          debugPrint('Proxy: Error getting file info: $e');
        }
      }

      int waitAttempts = 0;
      // Wait for file path to be available (from getFile or updateFile)
      while ((_filePaths[fileId] == null || _filePaths[fileId]!.path.isEmpty) &&
          waitAttempts < 30) {
        // Reduced wait
        waitAttempts++;
        if (waitAttempts % 10 == 0) {
          debugPrint('Proxy: Waiting... attempt $waitAttempts/30');
        }
        await Future.delayed(const Duration(milliseconds: 100));
        if (_filePaths[fileId] != null && _filePaths[fileId]!.path.isNotEmpty) {
          break;
        }
      }

      final fileInfo = _filePaths[fileId]; // Type is ProxyFileInfo?
      if (fileInfo == null) {
        // Should not happen due to loop above
        debugPrint('Proxy: File info not found after timeout for $fileId');
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final filePath = fileInfo.path;
      // debugPrint('Proxy: File path found: $filePath');

      var file = File(filePath);

      // Handle Range Header - ALREADY PARSED ABOVE
      // int start = 0;
      // int? end;
      // ... (Removed redundant parsing logic)

      // Check available file size
      var currentFileSize = await file.length();

      // If requested start is beyond current size, we need to wait for data (buffering)
      if (currentFileSize <= start) {
        int waitAttempts = 0;
        while (waitAttempts < 300) {
          // 30s wait for initial byte
          if (_abortedRequests.contains(fileId)) {
            await request.response.close();
            return;
          }
          await Future.delayed(const Duration(milliseconds: 100));
          currentFileSize = await file.length();
          if (currentFileSize > start) break;
          waitAttempts++;
          // Kick download if stuck waiting for initial byte
          if (waitAttempts % 50 == 0) {
            TelegramService().send({
              '@type': 'downloadFile',
              'file_id': fileId,
              'priority': 32,
              'offset': start,
              'limit': 0,
              'synchronous': false,
            });
          }
        }
      }

      final availableEnd = (await file.length()) - 1;
      final effectiveEnd = end != null ? min(end, availableEnd) : availableEnd;

      if (start > availableEnd) {
        // Still not enough data
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$totalSize',
        );
        await request.response.close();
        return;
      }

      final contentLength = effectiveEnd - start + 1;

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$effectiveEnd/$totalSize',
      );
      request.response.headers.set(
        HttpHeaders.contentLengthHeader,
        contentLength,
      );
      request.response.headers.contentType = ContentType.parse(
        'video/mp4',
      ); // Generic, or detect?
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      // Use RandomAccessFile for manual tailing of growing files
      var raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(start);
        int bytesSent = 0;
        final targetLength = effectiveEnd - start + 1;
        int noDataRetries = 0;
        int holePersistenceCount = 0;
        int lastHolePosition = -1;

        while (bytesSent < targetLength) {
          if (_abortedRequests.contains(fileId)) {
            debugPrint('Proxy: Stream aborted by user for $fileId');
            break;
          }

          // Check file size dynamically
          int currentSize = 0;
          try {
            currentSize = await file.length();
          } catch (e) {
            if (e is FileSystemException && e.osError?.errorCode == 2) {
              // ENOENT - Moved?
              final newInfo = _filePaths[fileId];
              if (newInfo != null && newInfo.path != file.path) {
                debugPrint(
                  'Proxy: File moved from ${file.path} to ${newInfo.path}, restarting stream...',
                );
                // Close current RAF and switch
                await raf.close();
                file = File(newInfo.path);
                raf = await file.open(mode: FileMode.read);
                await raf.setPosition(start + bytesSent); // Resume
                continue;
              }
            }
            debugPrint('Proxy: Error checking file length: $e');
            break;
          }

          final readPosition = start + bytesSent;
          final available = currentSize - readPosition;

          if (available > 0) {
            final remaining = targetLength - bytesSent;
            // Read in larger chunks (512KB) to reduce I/O overhead and context switching
            // IMPORTANT: Cap chunk size by remaining bytes to avoid "Content size exceeds specified contentLength"
            final chunkSize = min(min(available, 512 * 1024), remaining);

            if (chunkSize <= 0) {
              // Should not happen if available > 0 and bytesSent < targetLength
              break;
            }

            final data = await raf.read(chunkSize);

            if (data.isNotEmpty) {
              // HOLE DETECTION: If we read a block of zeros and file is not complete, it's likely a hole.
              // We check a small sample to avoid iterating 512KB
              bool isHole = false;
              // Only check for holes if file is not complete
              final currentInfo = _filePaths[fileId];
              if (currentInfo != null && !currentInfo.isCompleted) {
                // Check if the chunk is all zeros
                // Optimization: Check first, middle, last byte + random sample?
                // Or just check all since we are in memory now?
                // 512KB is small enough to check quickly in Dart (~1ms)
                isHole = true;
                // Check every 8th byte (very sensitive) to avoid missing small data chunks
                for (int i = 0; i < data.length; i += 8) {
                  if (data[i] != 0) {
                    isHole = false;
                    break;
                  }
                }

                // VALIDATION: Check if this "hole" is actually covered by the downloaded prefix
                if (isHole && currentInfo != null) {
                  final endOfChunk = readPosition + data.length;
                  if (currentInfo.downloadedPrefixSize >= endOfChunk) {
                    // The data is fully covered by what TDLib says it has downloaded.
                    // Therefore, these zeros are REAL zeros (padding/empty space), not missing data.
                    isHole = false;
                    // debugPrint('Proxy: Valid zeros detected at $readPosition (Covered by prefix ${currentInfo.downloadedPrefixSize}). Ignored hole.');
                  }
                }

                // If NOT a hole, log prefix to confirm we are getting real data
                /*
                 if (!isHole) {
                     debugPrint('Proxy: Read VALID chunk at $readPosition (Length: ${data.length}). First bytes: ${data.take(10).toList()}');
                 }
                 */
              }

              if (isHole) {
                // FALLBACK: If hole persists for > 10 seconds, give up and yield zeros
                // PROTECT CRITICAL REGIONS: Never yield zeros in first 20MB or last 20MB
                // yielding zeros there corrupts headers/indices (moov/ftyp) which is fatal.
                if (readPosition == lastHolePosition) {
                  holePersistenceCount++;
                } else {
                  holePersistenceCount = 0;
                  lastHolePosition = readPosition;
                }

                if (holePersistenceCount > 100) {
                  // 100 * 100ms = 10s
                  // Only yield if safe
                  final isSafeZone =
                      readPosition > 20 * 1024 * 1024 &&
                      readPosition < (currentSize - 20 * 1024 * 1024);

                  if (isSafeZone) {
                    debugPrint(
                      'Proxy: Hole persisted at $readPosition (SAFE ZONE). Yielding zeros to unblock.',
                    );
                    isHole = false; // Treat as valid data (valid zeros)
                    holePersistenceCount = 0;
                  } else {
                    debugPrint(
                      'Proxy: Hole persisted at $readPosition (CRITICAL ZONE). Waiting indefinitely for valid data...',
                    );
                    // Reset count to log again later or just keep waiting
                    holePersistenceCount = 90; // Warn every second
                  }
                }
              }

              if (isHole) {
                // Treated as no data available
                // debugPrint('Proxy: Detected hole at $readPosition, waiting...');
                if (noDataRetries % 20 == 0) {
                  debugPrint(
                    'Proxy: Hole detected at $readPosition. Waiting/Retrying...',
                  );
                }
                // Don't send data. Treat as if 'if (available > 0)' failed or returned nothing useful.
                // Fallthrough to 'else' waiting block?
                // We need to undo the read?
                // RAF position advanced by data.length. We must seek back.
                await raf.setPosition(readPosition);

                // Force wait
                await Future.delayed(
                  const Duration(milliseconds: 100),
                ); // Wait a bit more
                noDataRetries++;

                // KICK THE DOWNLOADER
                if (noDataRetries % 10 == 0) {
                  // Force download a specific chunk (1MB) to prioritize filling this hole
                  // rather than "rest of file" which TDLib might deprioritize or ignore
                  final remaining = currentSize - readPosition;
                  final limit = min(1024 * 1024, remaining);

                  debugPrint(
                    'Proxy: Requesting hole fill at $readPosition (limit: $limit)',
                  );
                  TelegramService()
                      .sendWithResult({
                        '@type': 'downloadFile',
                        'file_id': fileId,
                        'priority': 1, // CRITICAL PRIORITY (1-32, 1 is highest)
                        'offset': readPosition,
                        'limit': limit,
                        'synchronous': false,
                      })
                      .then((result) {
                        if (result['@type'] == 'error') {
                          debugPrint(
                            'Proxy: Hole fill ERROR: ${result['message']}',
                          );
                        } else {
                          // debugPrint('Proxy: Hole fill requested successfully');
                        }
                      })
                      .catchError((e) {
                        debugPrint('Proxy: Hole fill request failed: $e');
                      });
                }
                if (noDataRetries > 2400) break; // Timeout
                continue; // Continue loop, will re-read
              }

              request.response.add(data);
              await request.response
                  .flush(); // Flush to keep connection alive logic happy?
              bytesSent += data.length;
              noDataRetries = 0; // Reset timeout
            }
          } else {
            // Waiting for more data to be downloaded
            if (noDataRetries > 2400) {
              // 120 seconds timeout (2400 * 50ms)
              debugPrint('Proxy: Timeout waiting for data at $readPosition');
              break;
            }

            // Kick download periodically if we are waiting for data
            if (noDataRetries % 100 == 0) {
              final remaining = currentSize - readPosition;
              final limit = min(1024 * 1024, remaining);

              // Every 5s
              TelegramService().send({
                '@type': 'downloadFile',
                'file_id': fileId,
                'priority': 32,
                'offset':
                    readPosition, // Request specifically what we need next
                'limit': limit, // 1MB explicit limit
                'synchronous': false,
              });
            }

            await Future.delayed(const Duration(milliseconds: 50));
            noDataRetries++;
          }
        }
      } catch (e) {
        // Suppress logs for normal disconnections or when 'Broken pipe' occurs
        if (e is SocketException ||
            e.toString().contains('Connection closed') ||
            e.toString().contains('Broken pipe')) {
          // debugPrint('Proxy: Client disconnected (normal)');
        } else {
          debugPrint('Proxy: Streaming error: $e');
        }
      } finally {
        await raf.close();
      }

      await request.response.close();
    } catch (e) {
      debugPrint('Proxy Error: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }
}
