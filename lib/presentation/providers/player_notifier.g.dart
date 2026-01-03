// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

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
        dependencies: const <ProviderOrFamily>[
          videoRepositoryProvider,
          playbackStorageServiceProvider,
          streamingRepositoryProvider,
          playerBackendProvider,
        ],
        $allTransitiveDependencies: const <ProviderOrFamily>{
          PlayerNotifierProvider.$allTransitiveDependencies0,
          PlayerNotifierProvider.$allTransitiveDependencies1,
          PlayerNotifierProvider.$allTransitiveDependencies2,
          PlayerNotifierProvider.$allTransitiveDependencies3,
        },
      );

  static const $allTransitiveDependencies0 = videoRepositoryProvider;
  static const $allTransitiveDependencies1 =
      VideoRepositoryProvider.$allTransitiveDependencies0;
  static const $allTransitiveDependencies2 = playbackStorageServiceProvider;
  static const $allTransitiveDependencies3 = streamingRepositoryProvider;

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

String _$playerNotifierHash() => r'f5af3ca4762a08116788e22343dfe2f671601a6d';

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
