import 'package:flutter_riverpod/flutter_riverpod.dart';
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

// Helper provider to read settings
final playerSettingsServiceProvider = Provider(
  (ref) => PlayerSettingsService(),
);

// Provider for playback storage service
final playbackStorageServiceProvider = Provider(
  (ref) => PlaybackStorageService(),
);

// The generic video repository provider
// It needs to be initialized asynchronously or check settings synchronously if possible.
// Riverpod recommended way for async initialization is FutureProvider,
// but PlayerNotifier needs the repo.
// We will use a FutureProvider for the *type* of backend, and then a Provider logic to return the instance.
// OR simpler: PlayerNotifier reads settings on build and instantiates the repo.

// Holds the active player backend preference.
// Can be overridden in main() with initial value.
// Holds the active player backend preference.
class PlayerBackendNotifier extends Notifier<String> {
  @override
  String build() => throw UnimplementedError();

  void setBackend(String backend) {
    state = backend;
  }
}

final playerBackendProvider = NotifierProvider<PlayerBackendNotifier, String>(
  PlayerBackendNotifier.new,
);

// The active VideoRepository based on the backend
final videoRepositoryProvider = Provider.autoDispose<VideoRepository>((ref) {
  final backend = ref.watch(playerBackendProvider);

  final repository = (backend == PlayerSettingsService.engineFvp)
      ? FvpVideoRepository()
      : MediaKitVideoRepository();

  ref.onDispose(() {
    repository.dispose();
  });

  return repository;
});

// Provider for the streaming repository
final streamingRepositoryProvider = Provider<StreamingRepository>((ref) {
  return LocalStreamingRepository();
});

// ============================================================================
// Use Case Providers
// ============================================================================

/// Provider for LoadVideoUseCase with injected dependencies
final loadVideoUseCaseProvider = Provider.autoDispose<LoadVideoUseCase>((ref) {
  return LoadVideoUseCase(
    videoRepository: ref.watch(videoRepositoryProvider),
    streamingRepository: ref.watch(streamingRepositoryProvider),
    storageService: ref.watch(playbackStorageServiceProvider),
    recentVideosService: RecentVideosService(),
  );
});

/// Provider for SeekVideoUseCase with injected dependencies
final seekVideoUseCaseProvider = Provider.autoDispose<SeekVideoUseCase>((ref) {
  return SeekVideoUseCase(
    videoRepository: ref.watch(videoRepositoryProvider),
    storageService: ref.watch(playbackStorageServiceProvider),
  );
});

/// Provider for TogglePlaybackUseCase with injected dependencies
final togglePlaybackUseCaseProvider =
    Provider.autoDispose<TogglePlaybackUseCase>((ref) {
      return TogglePlaybackUseCase(
        videoRepository: ref.watch(videoRepositoryProvider),
        storageService: ref.watch(playbackStorageServiceProvider),
      );
    });
