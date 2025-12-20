import '../use_case.dart';
import '../../domain/repositories/video_repository.dart';
import '../../infrastructure/services/playback_storage_service.dart';

/// Parameters for toggling playback.
class TogglePlaybackParams {
  final bool isCurrentlyPlaying;
  final Duration currentPosition;
  final String? storageKey;

  const TogglePlaybackParams({
    required this.isCurrentlyPlaying,
    required this.currentPosition,
    this.storageKey,
  });
}

/// Result of toggling playback.
class TogglePlaybackResult {
  final bool isNowPlaying;

  const TogglePlaybackResult({required this.isNowPlaying});
}

/// Use case for toggling playback state (play/pause).
class TogglePlaybackUseCase
    extends UseCase<TogglePlaybackResult, TogglePlaybackParams> {
  final VideoRepository _videoRepository;
  final PlaybackStorageService _storageService;

  TogglePlaybackUseCase({
    required VideoRepository videoRepository,
    required PlaybackStorageService storageService,
  }) : _videoRepository = videoRepository,
       _storageService = storageService;

  @override
  Future<TogglePlaybackResult> call(TogglePlaybackParams params) async {
    if (params.isCurrentlyPlaying) {
      await _videoRepository.pause();

      // Save position when pausing
      if (params.storageKey != null) {
        await _storageService.savePosition(
          params.storageKey!,
          params.currentPosition.inMilliseconds,
        );
      }

      return const TogglePlaybackResult(isNowPlaying: false);
    } else {
      await _videoRepository.resume();
      return const TogglePlaybackResult(isNowPlaying: true);
    }
  }
}
