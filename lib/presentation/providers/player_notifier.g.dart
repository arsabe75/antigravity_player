// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Manages video playback state and coordinates between UI and video backends.
///
/// This notifier uses Riverpod 3's code generation pattern with `@Riverpod`.
/// The `build()` method initializes dependencies and returns initial state.
/// State updates are broadcast to all widgets watching [playerProvider].
///
/// ## Key Features:
/// - **Multi-backend support**: Works with both FVP (libmpv) and MediaKit
/// - **Progress persistence**: Saves playback position every 5 seconds
/// - **Telegram integration**: Uses stable message IDs for progress keys
/// - **Proxy port correction**: Fixes stale URLs after app restart
/// - **UX optimizations**: Buffering indicators, initial loading state
///
/// ## Usage:
/// ```dart
/// // In a widget
/// final state = ref.watch(playerProvider);
/// final notifier = ref.read(playerProvider.notifier);
///
/// // Load a video
/// notifier.loadVideo(
///   'http://example.com/video.mp4',
///   isNetwork: true,
///   title: 'My Video',
/// );
///
/// // Control playback
/// notifier.togglePlay();
/// notifier.seekTo(Duration(minutes: 5));
/// ```

@ProviderFor(PlayerNotifier)
const playerProvider = PlayerNotifierProvider._();

/// Manages video playback state and coordinates between UI and video backends.
///
/// This notifier uses Riverpod 3's code generation pattern with `@Riverpod`.
/// The `build()` method initializes dependencies and returns initial state.
/// State updates are broadcast to all widgets watching [playerProvider].
///
/// ## Key Features:
/// - **Multi-backend support**: Works with both FVP (libmpv) and MediaKit
/// - **Progress persistence**: Saves playback position every 5 seconds
/// - **Telegram integration**: Uses stable message IDs for progress keys
/// - **Proxy port correction**: Fixes stale URLs after app restart
/// - **UX optimizations**: Buffering indicators, initial loading state
///
/// ## Usage:
/// ```dart
/// // In a widget
/// final state = ref.watch(playerProvider);
/// final notifier = ref.read(playerProvider.notifier);
///
/// // Load a video
/// notifier.loadVideo(
///   'http://example.com/video.mp4',
///   isNetwork: true,
///   title: 'My Video',
/// );
///
/// // Control playback
/// notifier.togglePlay();
/// notifier.seekTo(Duration(minutes: 5));
/// ```
final class PlayerNotifierProvider
    extends $NotifierProvider<PlayerNotifier, PlayerState> {
  /// Manages video playback state and coordinates between UI and video backends.
  ///
  /// This notifier uses Riverpod 3's code generation pattern with `@Riverpod`.
  /// The `build()` method initializes dependencies and returns initial state.
  /// State updates are broadcast to all widgets watching [playerProvider].
  ///
  /// ## Key Features:
  /// - **Multi-backend support**: Works with both FVP (libmpv) and MediaKit
  /// - **Progress persistence**: Saves playback position every 5 seconds
  /// - **Telegram integration**: Uses stable message IDs for progress keys
  /// - **Proxy port correction**: Fixes stale URLs after app restart
  /// - **UX optimizations**: Buffering indicators, initial loading state
  ///
  /// ## Usage:
  /// ```dart
  /// // In a widget
  /// final state = ref.watch(playerProvider);
  /// final notifier = ref.read(playerProvider.notifier);
  ///
  /// // Load a video
  /// notifier.loadVideo(
  ///   'http://example.com/video.mp4',
  ///   isNetwork: true,
  ///   title: 'My Video',
  /// );
  ///
  /// // Control playback
  /// notifier.togglePlay();
  /// notifier.seekTo(Duration(minutes: 5));
  /// ```
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
          saveProgressUseCaseProvider,
          clearFinishedProgressUseCaseProvider,
        ],
        $allTransitiveDependencies: const <ProviderOrFamily>{
          PlayerNotifierProvider.$allTransitiveDependencies0,
          PlayerNotifierProvider.$allTransitiveDependencies1,
          PlayerNotifierProvider.$allTransitiveDependencies2,
          PlayerNotifierProvider.$allTransitiveDependencies3,
          PlayerNotifierProvider.$allTransitiveDependencies4,
          PlayerNotifierProvider.$allTransitiveDependencies5,
          PlayerNotifierProvider.$allTransitiveDependencies6,
        },
      );

  static const $allTransitiveDependencies0 = videoRepositoryProvider;
  static const $allTransitiveDependencies1 =
      VideoRepositoryProvider.$allTransitiveDependencies0;
  static const $allTransitiveDependencies2 = playbackStorageServiceProvider;
  static const $allTransitiveDependencies3 = streamingRepositoryProvider;
  static const $allTransitiveDependencies4 = saveProgressUseCaseProvider;
  static const $allTransitiveDependencies5 =
      SaveProgressUseCaseProvider.$allTransitiveDependencies1;
  static const $allTransitiveDependencies6 =
      clearFinishedProgressUseCaseProvider;

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

String _$playerNotifierHash() => r'dbf7ab087724d5db1093f75e599e7bf08ce3cfaf';

/// Manages video playback state and coordinates between UI and video backends.
///
/// This notifier uses Riverpod 3's code generation pattern with `@Riverpod`.
/// The `build()` method initializes dependencies and returns initial state.
/// State updates are broadcast to all widgets watching [playerProvider].
///
/// ## Key Features:
/// - **Multi-backend support**: Works with both FVP (libmpv) and MediaKit
/// - **Progress persistence**: Saves playback position every 5 seconds
/// - **Telegram integration**: Uses stable message IDs for progress keys
/// - **Proxy port correction**: Fixes stale URLs after app restart
/// - **UX optimizations**: Buffering indicators, initial loading state
///
/// ## Usage:
/// ```dart
/// // In a widget
/// final state = ref.watch(playerProvider);
/// final notifier = ref.read(playerProvider.notifier);
///
/// // Load a video
/// notifier.loadVideo(
///   'http://example.com/video.mp4',
///   isNetwork: true,
///   title: 'My Video',
/// );
///
/// // Control playback
/// notifier.togglePlay();
/// notifier.seekTo(Duration(minutes: 5));
/// ```

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
