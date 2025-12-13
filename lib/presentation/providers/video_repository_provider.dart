import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/repositories/video_repository.dart';
import '../../infrastructure/repositories/media_kit_video_repository.dart';
import '../../infrastructure/repositories/fvp_video_repository.dart';
import '../../infrastructure/services/player_settings_service.dart';
import '../../domain/repositories/streaming_repository.dart';
import '../../infrastructure/repositories/local_streaming_repository.dart';

// Helper provider to read settings
final playerSettingsServiceProvider = Provider(
  (ref) => PlayerSettingsService(),
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
