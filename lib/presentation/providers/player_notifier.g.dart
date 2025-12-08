// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

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
    r'f296c36645a0c5f35e53bbcbf9a8d18cd0dd69b8';

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

String _$playerNotifierHash() => r'8938f24a59f1046b62a4801f6f4b9fa95af2698d';

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
