// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(videoRepository)
const videoRepositoryProvider = VideoRepositoryProvider._();

final class VideoRepositoryProvider
    extends
        $FunctionalProvider<VideoRepository, VideoRepository, VideoRepository>
    with $Provider<VideoRepository> {
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

String _$videoRepositoryHash() => r'81ecba53f4accc3872c4878c1365ad905499ec49';

@ProviderFor(playbackStorageService)
const playbackStorageServiceProvider = PlaybackStorageServiceProvider._();

final class PlaybackStorageServiceProvider
    extends
        $FunctionalProvider<
          PlaybackStorageService,
          PlaybackStorageService,
          PlaybackStorageService
        >
    with $Provider<PlaybackStorageService> {
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
    r'7974daa4585a9943ed8c9cfca508cd61de9653a7';

@ProviderFor(PlayerNotifier)
const playerProvider = PlayerNotifierProvider._();

final class PlayerNotifierProvider
    extends $NotifierProvider<PlayerNotifier, PlayerState> {
  const PlayerNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playerNotifierHash();

  @$internal
  @override
  PlayerNotifier create() => PlayerNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlayerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlayerState>(value),
    );
  }
}

String _$playerNotifierHash() => r'9ca1a20a03659687cbd492d04a279e3e6290ca18';

abstract class _$PlayerNotifier extends $Notifier<PlayerState> {
  PlayerState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<PlayerState, PlayerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PlayerState, PlayerState>,
              PlayerState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
