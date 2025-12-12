import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'telegram_service.dart';

class LocalStreamingProxy {
  static final LocalStreamingProxy _instance = LocalStreamingProxy._internal();
  factory LocalStreamingProxy() => _instance;
  LocalStreamingProxy._internal();

  HttpServer? _server;
  int _port = 0;

  // Cache of file_id -> local_path
  final Map<int, String> _filePaths = {};
  // Track active download requests to avoid spamming TDLib
  final Set<int> _activeDownloadRequests = {};
  // Track aborted requests to cancel waiting loops
  final Set<int> _abortedRequests = {};

  int get port => _port;

  void abortRequest(int fileId) {
    debugPrint('Proxy: Aborting request for fileId $fileId');
    _abortedRequests.add(fileId);
    // Also remove from active so we can retry later if user returns
    _activeDownloadRequests.remove(fileId);
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
          if (!_filePaths.containsKey(id)) {
            debugPrint('Proxy: Path resolved for $id -> $path');
          }
          _filePaths[id] = path;
        }
      }
    });
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
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

      // Ensure download is active with HIGH priority
      if (!_activeDownloadRequests.contains(fileId)) {
        _activeDownloadRequests.add(fileId);
        TelegramService().send({
          '@type': 'downloadFile',
          'file_id': fileId,
          'priority': 1, // High priority for active playback
          'offset': 0,
          'limit': 0,
          'synchronous': false,
        });

        // Clear from active requests after a delay to allow retries if needed
        Future.delayed(const Duration(seconds: 5), () {
          _activeDownloadRequests.remove(fileId);
        });
      }

      // Wait for path if not available
      debugPrint('Proxy: Waiting for file path for $fileId...');

      int attempts = 0;
      bool pathValid = false;

      while (attempts < 300 && !pathValid) {
        // CHECK CANCELLATION
        if (_abortedRequests.contains(fileId)) {
          debugPrint('Proxy: Request for $fileId aborted by player exit.');
          request.response.statusCode =
              HttpStatus.requestHeaderFieldsTooLarge; // arbitrary 4xx
          await request.response.close();
          // Cleanup
          _abortedRequests.remove(fileId);
          return;
        }

        if (_filePaths.containsKey(fileId)) {
          final candidate = _filePaths[fileId]!;
          if (await File(candidate).exists()) {
            pathValid = true;
            break;
          } else {
            // Path known but file missing?
            if (attempts % 5 == 0) {
              debugPrint(
                'Proxy: Path $candidate known but missing. Waiting...',
              );
            }
          }
        }

        // Always ping getFile/downloadFile periodically to force update
        if (attempts % 10 == 0) {
          // Ask for file info explicitly (triggers updateFile)
          TelegramService().send({'@type': 'getFile', 'file_id': fileId});
          // Re-assert download priority
          TelegramService().send({
            '@type': 'downloadFile',
            'file_id': fileId,
            'priority': 32, // MAX PRIORITY
            'offset': 0,
            'limit': 0,
            'synchronous': false,
          });
        }

        await Future.delayed(const Duration(milliseconds: 200));
        attempts++;
        if (attempts % 10 == 0) {
          debugPrint('Proxy: Waiting... attempt $attempts/300');
        }
      }

      final filePath = _filePaths[fileId];
      if (filePath == null) {
        debugPrint('Proxy: File path not found after timeout for $fileId');
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      // debugPrint('Proxy: File path found: $filePath');

      var file = File(filePath);

      // Handle Range Header
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
              'offset': 0,
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
              final newPath = _filePaths[fileId];
              if (newPath != null && newPath != file.path) {
                debugPrint(
                  'Proxy: File moved from ${file.path} to $newPath, restarting stream...',
                );
                // Close current RAF and switch
                await raf.close();
                file = File(newPath);
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
            // Read in larger chunks (512KB) to reduce I/O overhead and context switching
            final chunkSize = min(available, 512 * 1024);
            final data = await raf.read(chunkSize);

            if (data.isNotEmpty) {
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
              // Every 5s
              TelegramService().send({
                '@type': 'downloadFile',
                'file_id': fileId,
                'priority': 32,
                'offset': 0,
                'limit': 0,
                'synchronous': false,
              });
            }

            await Future.delayed(const Duration(milliseconds: 50));
            noDataRetries++;
          }
        }
      } catch (e) {
        debugPrint('Proxy: Streaming error: $e');
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
