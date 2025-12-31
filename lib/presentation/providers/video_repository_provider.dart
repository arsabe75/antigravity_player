import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/repositories/video_repository.dart';
import '../../infrastructure/repositories/media_kit_video_repository.dart';
import '../../infrastructure/repositories/fvp_video_repository.dart';
import '../../infrastructure/services/player_settings_service.dart';
import '../../domain/repositories/streaming_repository.dart';
import '../../infrastructure/repositories/local_streaming_repository.dart';
import '../../infrastructure/services/playback_storage_service.dart';
import '../../infrastructure/services/recent_videos_service.dart';
import '../../application/use_cases/load_video_use_case.dart';
import '../../application/use_cases/seek_video_use_case.dart';
import '../../application/use_cases/toggle_playback_use_case.dart';

part 'video_repository_provider.g.dart';

// ============================================================================
// Service Providers
// ============================================================================

/// Helper provider to read settings
@riverpod
PlayerSettingsService playerSettingsService(Ref ref) {
  return PlayerSettingsService();
}

/// Provider for playback storage service
@riverpod
PlaybackStorageService playbackStorageService(Ref ref) {
  return PlaybackStorageService();
}

// ============================================================================
// Player Backend Provider (keepAlive for overrides in main.dart)
// ============================================================================

/// Holds the active player backend preference.
/// Can be overridden in main() with initial value.
@Riverpod(keepAlive: true)
class PlayerBackend extends _$PlayerBackend {
  @override
  String build() => throw UnimplementedError();

  void setBackend(String backend) {
    state = backend;
  }
}

// ============================================================================
// Repository Providers
// ============================================================================

/// The active VideoRepository based on the backend
@Riverpod(dependencies: [PlayerBackend])
VideoRepository videoRepository(Ref ref) {
  final backend = ref.watch(playerBackendProvider);

  final repository = (backend == PlayerSettingsService.engineFvp)
      ? FvpVideoRepository()
      : MediaKitVideoRepository();

  ref.onDispose(() {
    repository.dispose();
  });

  return repository;
}

/// Provider for the streaming repository
@Riverpod(keepAlive: true)
StreamingRepository streamingRepository(Ref ref) {
  return LocalStreamingRepository();
}

// ============================================================================
// Use Case Providers
// ============================================================================

/// Provider for LoadVideoUseCase with injected dependencies
@Riverpod(
  dependencies: [videoRepository, streamingRepository, playbackStorageService],
)
LoadVideoUseCase loadVideoUseCase(Ref ref) {
  return LoadVideoUseCase(
    videoRepository: ref.watch(videoRepositoryProvider),
    streamingRepository: ref.watch(streamingRepositoryProvider),
    storageService: ref.watch(playbackStorageServiceProvider),
    recentVideosService: RecentVideosService(),
  );
}

/// Provider for SeekVideoUseCase with injected dependencies
@Riverpod(dependencies: [videoRepository, playbackStorageService])
SeekVideoUseCase seekVideoUseCase(Ref ref) {
  return SeekVideoUseCase(
    videoRepository: ref.watch(videoRepositoryProvider),
    storageService: ref.watch(playbackStorageServiceProvider),
  );
}

/// Provider for TogglePlaybackUseCase with injected dependencies
@Riverpod(dependencies: [videoRepository, playbackStorageService])
TogglePlaybackUseCase togglePlaybackUseCase(Ref ref) {
  return TogglePlaybackUseCase(
    videoRepository: ref.watch(videoRepositoryProvider),
    storageService: ref.watch(playbackStorageServiceProvider),
  );
}
