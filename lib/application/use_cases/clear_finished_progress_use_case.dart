import '../use_case.dart';
import '../../infrastructure/services/playback_storage_service.dart';

/// Parameters for clearing progress of a finished video.
class ClearFinishedProgressParams {
  /// Storage key for the video
  final String storageKey;

  /// Final playback position
  final Duration position;

  /// Total video duration
  final Duration duration;

  const ClearFinishedProgressParams({
    required this.storageKey,
    required this.position,
    required this.duration,
  });
}

/// Use case for clearing progress of a finished video.
///
/// This is used when transitioning between videos to clear the progress
/// of the previous video if it was finished. The key difference from
/// SaveProgressUseCase is that this operates on captured values from
/// the previous video state, not the current state.
class ClearFinishedProgressUseCase
    extends UseCase<bool, ClearFinishedProgressParams> {
  final PlaybackStorageService _storageService;

  /// Threshold for considering video as "finished"
  static const Duration _finishedThreshold = Duration(milliseconds: 500);

  ClearFinishedProgressUseCase({required PlaybackStorageService storageService})
    : _storageService = storageService;

  @override
  Future<bool> call(ClearFinishedProgressParams params) async {
    // Check if video has reached the end
    final isAtEnd =
        params.duration > Duration.zero &&
        params.position >= params.duration - _finishedThreshold;

    if (isAtEnd) {
      await _storageService.clearPosition(params.storageKey);
      return true; // Progress was cleared
    }

    return false; // Progress was not cleared (video not finished)
  }
}
