// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Manages playlist state including items, current index, shuffle, and repeat mode.
///
/// This is a global notifier with `keepAlive: true`, meaning the playlist
/// persists even when no widget is watching it. This allows users to
/// switch between screens without losing their playlist.
///
/// ## Usage:
/// ```dart
/// // Read state
/// final playlist = ref.watch(playlistProvider);
/// print('Playing ${playlist.currentIndex + 1} of ${playlist.length}');
///
/// // Modify playlist
/// final notifier = ref.read(playlistProvider.notifier);
/// notifier.addItem('/path/to/video.mp4');
/// notifier.next(); // Advance to next video
/// ```
///
/// ## Coordination with PlayerNotifier:
/// ```dart
/// // In PlayerScreen's auto-advance listener:
/// if (playlistNotifier.next()) {
///   final nextItem = playlist.currentItem;
///   playerNotifier.loadVideo(nextItem!.path, isNetwork: nextItem.isNetwork);
/// }
/// ```

@ProviderFor(PlaylistNotifier)
const playlistProvider = PlaylistNotifierProvider._();

/// Manages playlist state including items, current index, shuffle, and repeat mode.
///
/// This is a global notifier with `keepAlive: true`, meaning the playlist
/// persists even when no widget is watching it. This allows users to
/// switch between screens without losing their playlist.
///
/// ## Usage:
/// ```dart
/// // Read state
/// final playlist = ref.watch(playlistProvider);
/// print('Playing ${playlist.currentIndex + 1} of ${playlist.length}');
///
/// // Modify playlist
/// final notifier = ref.read(playlistProvider.notifier);
/// notifier.addItem('/path/to/video.mp4');
/// notifier.next(); // Advance to next video
/// ```
///
/// ## Coordination with PlayerNotifier:
/// ```dart
/// // In PlayerScreen's auto-advance listener:
/// if (playlistNotifier.next()) {
///   final nextItem = playlist.currentItem;
///   playerNotifier.loadVideo(nextItem!.path, isNetwork: nextItem.isNetwork);
/// }
/// ```
final class PlaylistNotifierProvider
    extends $NotifierProvider<PlaylistNotifier, PlaylistEntity> {
  /// Manages playlist state including items, current index, shuffle, and repeat mode.
  ///
  /// This is a global notifier with `keepAlive: true`, meaning the playlist
  /// persists even when no widget is watching it. This allows users to
  /// switch between screens without losing their playlist.
  ///
  /// ## Usage:
  /// ```dart
  /// // Read state
  /// final playlist = ref.watch(playlistProvider);
  /// print('Playing ${playlist.currentIndex + 1} of ${playlist.length}');
  ///
  /// // Modify playlist
  /// final notifier = ref.read(playlistProvider.notifier);
  /// notifier.addItem('/path/to/video.mp4');
  /// notifier.next(); // Advance to next video
  /// ```
  ///
  /// ## Coordination with PlayerNotifier:
  /// ```dart
  /// // In PlayerScreen's auto-advance listener:
  /// if (playlistNotifier.next()) {
  ///   final nextItem = playlist.currentItem;
  ///   playerNotifier.loadVideo(nextItem!.path, isNetwork: nextItem.isNetwork);
  /// }
  /// ```
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

/// Manages playlist state including items, current index, shuffle, and repeat mode.
///
/// This is a global notifier with `keepAlive: true`, meaning the playlist
/// persists even when no widget is watching it. This allows users to
/// switch between screens without losing their playlist.
///
/// ## Usage:
/// ```dart
/// // Read state
/// final playlist = ref.watch(playlistProvider);
/// print('Playing ${playlist.currentIndex + 1} of ${playlist.length}');
///
/// // Modify playlist
/// final notifier = ref.read(playlistProvider.notifier);
/// notifier.addItem('/path/to/video.mp4');
/// notifier.next(); // Advance to next video
/// ```
///
/// ## Coordination with PlayerNotifier:
/// ```dart
/// // In PlayerScreen's auto-advance listener:
/// if (playlistNotifier.next()) {
///   final nextItem = playlist.currentItem;
///   playerNotifier.loadVideo(nextItem!.path, isNetwork: nextItem.isNetwork);
/// }
/// ```

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
