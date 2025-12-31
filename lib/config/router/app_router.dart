import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'routes.dart';

part 'app_router.g.dart';

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
  );
}
