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
    r'2871a9f47020b1960140a0871dd072f65d325268';

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
    r'f296c36645a0c5f35e53bbcbf9a8d18cd0dd69b8';

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
        dependencies: null,
        $allTransitiveDependencies: null,
      );

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

String _$videoRepositoryHash() => r'3effe97f220dab9082441b04bc58b5dbf5aec320';

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
        dependencies: null,
        $allTransitiveDependencies: null,
      );

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

String _$loadVideoUseCaseHash() => r'25497967385453d7f4e2b3722a578927cdf4a4ba';

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
        dependencies: null,
        $allTransitiveDependencies: null,
      );

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

String _$seekVideoUseCaseHash() => r'b305a980ce8dabe336526efda8d1bbf3721caa55';

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
        dependencies: null,
        $allTransitiveDependencies: null,
      );

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
    r'1c3b7e46a3893ca3d9be63d31ca249a52f0ad104';
