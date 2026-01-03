// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_repository_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Helper provider to read settings

@ProviderFor(playerSettingsService)
const playerSettingsServiceProvider = PlayerSettingsServiceProvider._();

/// Helper provider to read settings

final class PlayerSettingsServiceProvider
    extends
        $FunctionalProvider<
          PlayerSettingsService,
          PlayerSettingsService,
          PlayerSettingsService
        >
    with $Provider<PlayerSettingsService> {
  /// Helper provider to read settings
  const PlayerSettingsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playerSettingsServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playerSettingsServiceHash();

  @$internal
  @override
  $ProviderElement<PlayerSettingsService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlayerSettingsService create(Ref ref) {
    return playerSettingsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlayerSettingsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlayerSettingsService>(value),
    );
  }
}

String _$playerSettingsServiceHash() =>
    r'a311a6648a89ca95f0fe24a609a8a109cd05d7c7';

/// Provider for playback storage service

@ProviderFor(playbackStorageService)
const playbackStorageServiceProvider = PlaybackStorageServiceProvider._();

/// Provider for playback storage service

final class PlaybackStorageServiceProvider
    extends
        $FunctionalProvider<
          PlaybackStorageService,
          PlaybackStorageService,
          PlaybackStorageService
        >
    with $Provider<PlaybackStorageService> {
  /// Provider for playback storage service
  const PlaybackStorageServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playbackStorageServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playbackStorageServiceHash();

  @$internal
  @override
  $ProviderElement<PlaybackStorageService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlaybackStorageService create(Ref ref) {
    return playbackStorageService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaybackStorageService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaybackStorageService>(value),
    );
  }
}

String _$playbackStorageServiceHash() =>
    r'f5a7094d7edc60f6b3eb63099d8de8a81b195746';

/// Holds the active player backend preference.
/// Can be overridden in main() with initial value.

@ProviderFor(PlayerBackend)
const playerBackendProvider = PlayerBackendProvider._();

/// Holds the active player backend preference.
/// Can be overridden in main() with initial value.
final class PlayerBackendProvider
    extends $NotifierProvider<PlayerBackend, String> {
  /// Holds the active player backend preference.
  /// Can be overridden in main() with initial value.
  const PlayerBackendProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playerBackendProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playerBackendHash();

  @$internal
  @override
  PlayerBackend create() => PlayerBackend();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$playerBackendHash() => r'0b72617845813a7ab5d3f9c68756609e623faf47';

/// Holds the active player backend preference.
/// Can be overridden in main() with initial value.

abstract class _$PlayerBackend extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// The active VideoRepository based on the backend

@ProviderFor(videoRepository)
const videoRepositoryProvider = VideoRepositoryProvider._();

/// The active VideoRepository based on the backend

final class VideoRepositoryProvider
    extends
        $FunctionalProvider<VideoRepository, VideoRepository, VideoRepository>
    with $Provider<VideoRepository> {
  /// The active VideoRepository based on the backend
  const VideoRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'videoRepositoryProvider',
        isAutoDispose: true,
        dependencies: const <ProviderOrFamily>[playerBackendProvider],
        $allTransitiveDependencies: const <ProviderOrFamily>[
          VideoRepositoryProvider.$allTransitiveDependencies0,
        ],
      );

  static const $allTransitiveDependencies0 = playerBackendProvider;

  @override
  String debugGetCreateSourceHash() => _$videoRepositoryHash();

  @$internal
  @override
  $ProviderElement<VideoRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VideoRepository create(Ref ref) {
    return videoRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VideoRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VideoRepository>(value),
    );
  }
}

String _$videoRepositoryHash() => r'6c18f811792dc2947beb0278320ef8018a4b053d';

/// Provider for the streaming repository

@ProviderFor(streamingRepository)
const streamingRepositoryProvider = StreamingRepositoryProvider._();

/// Provider for the streaming repository

final class StreamingRepositoryProvider
    extends
        $FunctionalProvider<
          StreamingRepository,
          StreamingRepository,
          StreamingRepository
        >
    with $Provider<StreamingRepository> {
  /// Provider for the streaming repository
  const StreamingRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'streamingRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$streamingRepositoryHash();

  @$internal
  @override
  $ProviderElement<StreamingRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StreamingRepository create(Ref ref) {
    return streamingRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StreamingRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StreamingRepository>(value),
    );
  }
}

String _$streamingRepositoryHash() =>
    r'4ed84bab5e0263656da00dd6200f5948565b254a';

/// Provider for LoadVideoUseCase with injected dependencies

@ProviderFor(loadVideoUseCase)
const loadVideoUseCaseProvider = LoadVideoUseCaseProvider._();

/// Provider for LoadVideoUseCase with injected dependencies

final class LoadVideoUseCaseProvider
    extends
        $FunctionalProvider<
          LoadVideoUseCase,
          LoadVideoUseCase,
          LoadVideoUseCase
        >
    with $Provider<LoadVideoUseCase> {
  /// Provider for LoadVideoUseCase with injected dependencies
  const LoadVideoUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'loadVideoUseCaseProvider',
        isAutoDispose: true,
        dependencies: const <ProviderOrFamily>[
          videoRepositoryProvider,
          streamingRepositoryProvider,
          playbackStorageServiceProvider,
        ],
        $allTransitiveDependencies: const <ProviderOrFamily>{
          LoadVideoUseCaseProvider.$allTransitiveDependencies0,
          LoadVideoUseCaseProvider.$allTransitiveDependencies1,
          LoadVideoUseCaseProvider.$allTransitiveDependencies2,
          LoadVideoUseCaseProvider.$allTransitiveDependencies3,
        },
      );

  static const $allTransitiveDependencies0 = videoRepositoryProvider;
  static const $allTransitiveDependencies1 =
      VideoRepositoryProvider.$allTransitiveDependencies0;
  static const $allTransitiveDependencies2 = streamingRepositoryProvider;
  static const $allTransitiveDependencies3 = playbackStorageServiceProvider;

  @override
  String debugGetCreateSourceHash() => _$loadVideoUseCaseHash();

  @$internal
  @override
  $ProviderElement<LoadVideoUseCase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LoadVideoUseCase create(Ref ref) {
    return loadVideoUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LoadVideoUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LoadVideoUseCase>(value),
    );
  }
}

String _$loadVideoUseCaseHash() => r'df5be8259ce916af0c476c6eb5e449330d39954a';

/// Provider for SeekVideoUseCase with injected dependencies

@ProviderFor(seekVideoUseCase)
const seekVideoUseCaseProvider = SeekVideoUseCaseProvider._();

/// Provider for SeekVideoUseCase with injected dependencies

final class SeekVideoUseCaseProvider
    extends
        $FunctionalProvider<
          SeekVideoUseCase,
          SeekVideoUseCase,
          SeekVideoUseCase
        >
    with $Provider<SeekVideoUseCase> {
  /// Provider for SeekVideoUseCase with injected dependencies
  const SeekVideoUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seekVideoUseCaseProvider',
        isAutoDispose: true,
        dependencies: const <ProviderOrFamily>[
          videoRepositoryProvider,
          playbackStorageServiceProvider,
        ],
        $allTransitiveDependencies: const <ProviderOrFamily>[
          SeekVideoUseCaseProvider.$allTransitiveDependencies0,
          SeekVideoUseCaseProvider.$allTransitiveDependencies1,
          SeekVideoUseCaseProvider.$allTransitiveDependencies2,
        ],
      );

  static const $allTransitiveDependencies0 = videoRepositoryProvider;
  static const $allTransitiveDependencies1 =
      VideoRepositoryProvider.$allTransitiveDependencies0;
  static const $allTransitiveDependencies2 = playbackStorageServiceProvider;

  @override
  String debugGetCreateSourceHash() => _$seekVideoUseCaseHash();

  @$internal
  @override
  $ProviderElement<SeekVideoUseCase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SeekVideoUseCase create(Ref ref) {
    return seekVideoUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SeekVideoUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SeekVideoUseCase>(value),
    );
  }
}

String _$seekVideoUseCaseHash() => r'64cefbca7ce3f36b6f138fb5b869305b9f7a482f';

/// Provider for TogglePlaybackUseCase with injected dependencies

@ProviderFor(togglePlaybackUseCase)
const togglePlaybackUseCaseProvider = TogglePlaybackUseCaseProvider._();

/// Provider for TogglePlaybackUseCase with injected dependencies

final class TogglePlaybackUseCaseProvider
    extends
        $FunctionalProvider<
          TogglePlaybackUseCase,
          TogglePlaybackUseCase,
          TogglePlaybackUseCase
        >
    with $Provider<TogglePlaybackUseCase> {
  /// Provider for TogglePlaybackUseCase with injected dependencies
  const TogglePlaybackUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'togglePlaybackUseCaseProvider',
        isAutoDispose: true,
        dependencies: const <ProviderOrFamily>[
          videoRepositoryProvider,
          playbackStorageServiceProvider,
        ],
        $allTransitiveDependencies: const <ProviderOrFamily>[
          TogglePlaybackUseCaseProvider.$allTransitiveDependencies0,
          TogglePlaybackUseCaseProvider.$allTransitiveDependencies1,
          TogglePlaybackUseCaseProvider.$allTransitiveDependencies2,
        ],
      );

  static const $allTransitiveDependencies0 = videoRepositoryProvider;
  static const $allTransitiveDependencies1 =
      VideoRepositoryProvider.$allTransitiveDependencies0;
  static const $allTransitiveDependencies2 = playbackStorageServiceProvider;

  @override
  String debugGetCreateSourceHash() => _$togglePlaybackUseCaseHash();

  @$internal
  @override
  $ProviderElement<TogglePlaybackUseCase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TogglePlaybackUseCase create(Ref ref) {
    return togglePlaybackUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TogglePlaybackUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TogglePlaybackUseCase>(value),
    );
  }
}

String _$togglePlaybackUseCaseHash() =>
    r'f53a341733f13e39a150b434bbf9d996b970a417';
