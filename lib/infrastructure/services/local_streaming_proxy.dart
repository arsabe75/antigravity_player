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

  int get port => _port;

  Future<void> start() async {
    if (_server != null) return;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    debugPrint('LocalStreamingProxy running on port $_port');

    _server!.listen(_handleRequest);

    // Listen to TDLib updates to track file paths
    TelegramService().updates.listen((update) {
      if (update['@type'] == 'updateFile') {
        final file = update['file'];
        final id = file['id'];
        final path = file['local']['path'];
        if (path != null && path.toString().isNotEmpty) {
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

      // Ensure download is active
      TelegramService().send({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 32,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      });

      // Wait for path if not available
      int attempts = 0;
      while (!_filePaths.containsKey(fileId) && attempts < 20) {
        await Future.delayed(const Duration(milliseconds: 200));
        attempts++;
      }

      final filePath = _filePaths[fileId];
      if (filePath == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final file = File(filePath);

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
      // We want to serve what spans we can, but since it's downloading,
      // the file grows. We might need to "tail" it or just serve what is currently there.
      // For streaming players, usually serving what's there and returning 206 is enough,
      // the player will request the rest later.

      final currentFileSize = await file.length();

      // If requested start is beyond current size, we might need to wait for data (buffering)
      // Simple implementation: wait a bit if file is too small
      if (currentFileSize <= start) {
        int waitAttempts = 0;
        while (waitAttempts < 30) {
          // Wait up to 3 seconds
          await Future.delayed(const Duration(milliseconds: 100));
          if ((await file.length()) > start) break;
          waitAttempts++;
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

      final stream = file.openRead(start, effectiveEnd + 1);
      await request.response.addStream(stream);
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
