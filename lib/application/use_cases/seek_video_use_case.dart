import '../use_case.dart';
import '../../domain/repositories/video_repository.dart';
import '../../infrastructure/services/playback_storage_service.dart';

/// Parameters for seeking to a position.
class SeekVideoParams {
  final Duration position;
  final String? videoPath;
  final String? storageKey;

  const SeekVideoParams({
    required this.position,
    this.videoPath,
    this.storageKey,
  });
}

/// Use case for seeking to a position and saving progress.
class SeekVideoUseCase extends UseCase<void, SeekVideoParams> {
  final VideoRepository _videoRepository;
  final PlaybackStorageService _storageService;

  SeekVideoUseCase({
    required VideoRepository videoRepository,
    required PlaybackStorageService storageService,
  }) : _videoRepository = videoRepository,
       _storageService = storageService;

  @override
  Future<void> call(SeekVideoParams params) async {
    await _videoRepository.seekTo(params.position);

    // Save position if we have a storage key
    final key = params.storageKey ?? params.videoPath;
    if (key != null) {
      await _storageService.savePosition(key, params.position.inMilliseconds);
    }
  }
}
