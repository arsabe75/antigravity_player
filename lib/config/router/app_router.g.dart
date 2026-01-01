// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provides the GoRouter instance with type-safe routes.
///
/// Usage:
/// ```dart
/// // In a widget
/// final router = ref.watch(appRouterProvider);
///
/// // Navigation with type-safety
/// const PlayerRoute(url: 'http://...', title: 'Video').go(context);
/// ```

@ProviderFor(appRouter)
const appRouterProvider = AppRouterProvider._();

/// Provides the GoRouter instance with type-safe routes.
///
/// Usage:
/// ```dart
/// // In a widget
/// final router = ref.watch(appRouterProvider);
///
/// // Navigation with type-safety
/// const PlayerRoute(url: 'http://...', title: 'Video').go(context);
/// ```

final class AppRouterProvider
    extends $FunctionalProvider<GoRouter, GoRouter, GoRouter>
    with $Provider<GoRouter> {
  /// Provides the GoRouter instance with type-safe routes.
  ///
  /// Usage:
  /// ```dart
  /// // In a widget
  /// final router = ref.watch(appRouterProvider);
  ///
  /// // Navigation with type-safety
  /// const PlayerRoute(url: 'http://...', title: 'Video').go(context);
  /// ```
  const AppRouterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appRouterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appRouterHash();

  @$internal
  @override
  $ProviderElement<GoRouter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GoRouter create(Ref ref) {
    return appRouter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoRouter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GoRouter>(value),
    );
  }
}

String _$appRouterHash() => r'66215661fb31a2a3e672ba248c1700fa696dd411';
