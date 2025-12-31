import 'dart:convert';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'routes.dart';

part 'app_router.g.dart';

// ============================================================================
// Codec for PlayerRouteExtra serialization
// ============================================================================

/// Codec to properly serialize/deserialize extras in GoRouter
class _ExtraCodec extends Codec<Object?, Object?> {
  const _ExtraCodec();

  @override
  Converter<Object?, Object?> get decoder => const _ExtraDecoder();

  @override
  Converter<Object?, Object?> get encoder => const _ExtraEncoder();
}

class _ExtraEncoder extends Converter<Object?, Object?> {
  const _ExtraEncoder();

  @override
  Object? convert(Object? input) {
    if (input is PlayerRouteExtra) {
      return {'type': 'PlayerRouteExtra', 'data': input.toJson()};
    }
    return input;
  }
}

class _ExtraDecoder extends Converter<Object?, Object?> {
  const _ExtraDecoder();

  @override
  Object? convert(Object? input) {
    if (input is Map<String, dynamic>) {
      if (input['type'] == 'PlayerRouteExtra') {
        return PlayerRouteExtra.fromJson(input['data'] as Map<String, dynamic>);
      }
    }
    return input;
  }
}

// ============================================================================
// Type-Safe Router with Riverpod Integration
// ============================================================================

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
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    routes: $appRoutes, // Generated from routes.g.dart
    extraCodec: const _ExtraCodec(),
  );
}
