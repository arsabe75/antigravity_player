import '../use_case.dart';
import '../services/storage_key_service.dart';
import '../../infrastructure/services/playback_storage_service.dart';
import '../../infrastructure/services/recent_videos_service.dart';

/// Parameters for saving playback progress.
class SaveProgressParams {
  /// Current video path (URL or local file)
  final String videoPath;

  /// Current playback position
  final Duration position;

  /// Total video duration
  final Duration duration;

  /// Telegram chat ID for stable key generation
  final int? telegramChatId;

  /// Telegram message ID for stable key generation
  final int? telegramMessageId;

  /// Proxy file ID (extracted from URL)
  final int? proxyFileId;

  const SaveProgressParams({
    required this.videoPath,
    required this.position,
    required this.duration,
    this.telegramChatId,
    this.telegramMessageId,
    this.proxyFileId,
  });
}

/// Result of saving progress.
class SaveProgressResult {
  /// True if progress was cleared (video finished)
  final bool wasCleared;

  /// The storage key used
  final String storageKey;

  const SaveProgressResult({
    required this.wasCleared,
    required this.storageKey,
  });
}

/// Use case for saving playback progress.
///
/// Handles:
/// - Generating stable storage key
/// - Saving position to storage
/// - Clearing position if video reached the end
/// - Updating recent videos list with current position
class SaveProgressUseCase
    extends UseCase<SaveProgressResult, SaveProgressParams> {
  final PlaybackStorageService _storageService;
  final RecentVideosService _recentVideosService;

  /// Threshold for considering video as "finished" (within this duration of end)
  static const Duration _finishedThreshold = Duration(milliseconds: 500);

  SaveProgressUseCase({
    required PlaybackStorageService storageService,
    required RecentVideosService recentVideosService,
  }) : _storageService = storageService,
       _recentVideosService = recentVideosService;

  @override
  Future<SaveProgressResult> call(SaveProgressParams params) async {
    final storageKey = StorageKeyService.getStableKey(
      telegramChatId: params.telegramChatId,
      telegramMessageId: params.telegramMessageId,
      proxyFileId: params.proxyFileId,
      fallbackPath: params.videoPath,
    );

    // Check if video has reached the end
    final isAtEnd = _isVideoFinished(params.position, params.duration);

    if (isAtEnd) {
      // Clear progress for finished videos
      await _storageService.clearPosition(storageKey);
      return SaveProgressResult(wasCleared: true, storageKey: storageKey);
    } else {
      // Save current position
      await _storageService.savePosition(
        storageKey,
        params.position.inMilliseconds,
      );

      // Update position in Recent Videos list for UI consistency
      await _recentVideosService.updatePosition(
        params.videoPath,
        params.position,
      );

      return SaveProgressResult(wasCleared: false, storageKey: storageKey);
    }
  }

  /// Check if video has reached the end (within threshold of duration)
  bool _isVideoFinished(Duration position, Duration duration) {
    return duration > Duration.zero &&
        position >= duration - _finishedThreshold;
  }
}
