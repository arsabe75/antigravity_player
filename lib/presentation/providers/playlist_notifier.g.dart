// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PlaylistNotifier)
const playlistProvider = PlaylistNotifierProvider._();

final class PlaylistNotifierProvider
    extends $NotifierProvider<PlaylistNotifier, PlaylistEntity> {
  const PlaylistNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playlistProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playlistNotifierHash();

  @$internal
  @override
  PlaylistNotifier create() => PlaylistNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaylistEntity value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaylistEntity>(value),
    );
  }
}

String _$playlistNotifierHash() => r'ef3c24d0974b448b0a221422bbe04e6c08d119a0';

abstract class _$PlaylistNotifier extends $Notifier<PlaylistEntity> {
  PlaylistEntity build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<PlaylistEntity, PlaylistEntity>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PlaylistEntity, PlaylistEntity>,
              PlaylistEntity,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
