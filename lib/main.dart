import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'config/router/app_router.dart';
import 'config/theme/app_theme.dart';
import 'config/constants/app_constants.dart';
import 'presentation/providers/theme_provider.dart';
import 'infrastructure/services/player_settings_service.dart';
import 'presentation/providers/video_repository_provider.dart';

class _PreloadedBackendNotifier extends PlayerBackend {
  final String initialBackend;
  _PreloadedBackendNotifier(this.initialBackend);

  @override
  String build() => initialBackend;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize MediaKit
  MediaKit.ensureInitialized();

  // Load Player Settings
  final settingsService = PlayerSettingsService();
  final backend = await settingsService.getPlayerEngine();

  // Initialize Window Manager
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(
      AppConstants.defaultWindowWidth,
      AppConstants.defaultWindowHeight,
    ),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(true);
  });

  runApp(
    ProviderScope(
      overrides: [
        playerBackendProvider.overrideWith(
          () => _PreloadedBackendNotifier(backend),
        ),
      ],
      child: const VideoPlayerApp(),
    ),
  );
}

class VideoPlayerApp extends ConsumerWidget {
  const VideoPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'VideoPlayerApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
    );
  }
}
