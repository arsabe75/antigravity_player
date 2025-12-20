import 'dart:io';
import 'package:flutter/foundation.dart';
import '../use_case.dart';
import '../../domain/entities/video_entity.dart';
import '../../domain/repositories/video_repository.dart';
import '../../domain/repositories/streaming_repository.dart';
import '../../infrastructure/services/playback_storage_service.dart';
import '../../infrastructure/services/recent_videos_service.dart';

/// Parameters for loading a video.
class LoadVideoParams {
  final String path;
  final bool isNetwork;
  final String? title;
  final int? telegramChatId;
  final int? telegramMessageId;
  final int? telegramFileSize;

  const LoadVideoParams({
    required this.path,
    this.isNetwork = false,
    this.title,
    this.telegramChatId,
    this.telegramMessageId,
    this.telegramFileSize,
  });
}

/// Result of loading a video.
class LoadVideoResult {
  final String correctedPath;
  final int? proxyFileId;
  final Duration? savedPosition;

  const LoadVideoResult({
    required this.correctedPath,
    this.proxyFileId,
    this.savedPosition,
  });
}

/// Use case for loading and preparing a video for playback.
///
/// This use case handles:
/// - Correcting proxy URLs to use the active port
/// - Validating local file existence
/// - Playing the video through the repository
/// - Saving to recent videos history
/// - Retrieving saved playback position
class LoadVideoUseCase extends UseCase<LoadVideoResult, LoadVideoParams> {
  final VideoRepository _videoRepository;
  final StreamingRepository _streamingRepository;
  final PlaybackStorageService _storageService;
  final RecentVideosService _recentVideosService;

  LoadVideoUseCase({
    required VideoRepository videoRepository,
    required StreamingRepository streamingRepository,
    required PlaybackStorageService storageService,
    RecentVideosService? recentVideosService,
  }) : _videoRepository = videoRepository,
       _streamingRepository = streamingRepository,
       _storageService = storageService,
       _recentVideosService = recentVideosService ?? RecentVideosService();

  @override
  Future<LoadVideoResult> call(LoadVideoParams params) async {
    var path = params.path;
    int? proxyFileId;

    // Extract and validate proxy file ID from streaming URLs
    if (path.contains('/stream?file_id=')) {
      try {
        final uri = Uri.parse(path);
        final fileIdStr = uri.queryParameters['file_id'];
        if (fileIdStr != null) {
          proxyFileId = int.tryParse(fileIdStr);
        }

        // Correct the port if this is a local proxy URL
        if (uri.authority.contains('127.0.0.1') ||
            uri.authority.contains('localhost')) {
          final activePort = _streamingRepository.port;
          if (activePort > 0 && uri.port != activePort) {
            path = path.replaceFirst(':${uri.port}/', ':$activePort/');
            debugPrint(
              'LoadVideoUseCase: Corrected port from ${uri.port} to $activePort',
            );
          }
        }
      } catch (_) {}
    }

    // Validate local file existence
    if (!params.isNetwork) {
      final file = File(path);
      if (!await file.exists()) {
        throw const FileSystemException('File not found');
      }
    }

    // Play the video
    final video = VideoEntity(path: path, isNetwork: params.isNetwork);
    await _videoRepository.play(video);

    // Save to recent videos history
    await _recentVideosService.addVideo(
      path,
      isNetwork: params.isNetwork,
      title: params.title,
      telegramChatId: params.telegramChatId,
      telegramMessageId: params.telegramMessageId,
      telegramFileSize: params.telegramFileSize,
    );

    // Get saved position
    final storageKey = _getStableStorageKey(
      path,
      proxyFileId,
      params.telegramChatId,
      params.telegramMessageId,
    );
    final savedPositionMs = await _storageService.getPosition(storageKey);
    final savedPosition = savedPositionMs != null && savedPositionMs > 0
        ? Duration(milliseconds: savedPositionMs)
        : null;

    return LoadVideoResult(
      correctedPath: path,
      proxyFileId: proxyFileId,
      savedPosition: savedPosition,
    );
  }

  /// Returns a stable storage key for progress persistence.
  String _getStableStorageKey(
    String path,
    int? proxyFileId,
    int? telegramChatId,
    int? telegramMessageId,
  ) {
    if (telegramChatId != null && telegramMessageId != null) {
      return 'telegram_${telegramChatId}_$telegramMessageId';
    }
    if (proxyFileId != null) {
      return 'file_$proxyFileId';
    }
    return path;
  }
}
