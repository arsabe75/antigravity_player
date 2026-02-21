import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../presentation/providers/telegram_auth_notifier.dart';
import '../../presentation/screens/error_screen.dart';
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

class _RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  _RouterNotifier(this._ref) {
    _ref.listen(telegramAuthProvider, (previous, next) => notifyListeners());
  }
}

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
  final notifier = _RouterNotifier(ref);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    routes: $appRoutes, // Generated from routes.g.dart
    extraCodec: const _ExtraCodec(),
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(telegramAuthProvider);
      final isAuthReady = authState.list == AuthState.ready;
      final isAuthLoading = authState.list == AuthState.initial;

      final location = state.matchedLocation;

      // If trying to access a sub-route of telegram and not ready, redirect to /telegram
      // (which handles the login / loading state).
      // Note: we only protect the subroutes like /telegram/selection, /telegram/topics/:id, etc.
      // because /telegram itself shows the TelegramLoginScreen if not authenticated.
      final isGoingToTelegramSubRoute = location.startsWith('/telegram/');

      if (isGoingToTelegramSubRoute && !isAuthReady && !isAuthLoading) {
        return '/telegram';
      }

      return null;
    },
    errorBuilder: (context, state) => ErrorScreen(error: state.error),
  );
}
