import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'config/router/app_router.dart';
import 'config/theme/app_theme.dart';
import 'config/constants/app_constants.dart';
import 'presentation/providers/theme_provider.dart';
import 'infrastructure/services/player_settings_service.dart';
import 'infrastructure/services/secure_storage_service.dart';
import 'presentation/providers/video_repository_provider.dart';
import 'presentation/providers/player_notifier.dart';
import 'infrastructure/services/external_file_handler.dart';

class _PreloadedBackendNotifier extends PlayerBackend {
  final String initialBackend;
  _PreloadedBackendNotifier(this.initialBackend);

  @override
  String build() => initialBackend;
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize encrypted storage
  await SecureStorageService.initialize();

  // Initialize MediaKit
  MediaKit.ensureInitialized();

  // Load Player Settings
  final settingsService = PlayerSettingsService();
  final backend = await settingsService.getPlayerEngine();

  // Create explicitly to allow programmatic access from outside the widget tree
  final container = ProviderContainer(
    overrides: [
      playerBackendProvider.overrideWith(
        () => _PreloadedBackendNotifier(backend),
      ),
    ],
  );

  // Linux Single Instance Check (Done early, before GUI is prepared)
  // If it's a second instance, write IPC and exit immediately.
  if (Platform.isLinux) {
    if (!(await FlutterSingleInstance().isFirstInstance())) {
      debugPrint("Instance already running. Focusing existing instance.");
      if (args.isNotEmpty) {
        await ExternalFileHandler.writeLinuxIpcFile(args.first);
      }
      final err = await FlutterSingleInstance().focus();
      if (err != null) {
        debugPrint("Error focusing existing instance: $err");
      }
      exit(0);
    }
  }

  // Initialize Window Manager
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(
      AppConstants.defaultWindowWidth,
      AppConstants.defaultWindowHeight,
    ),
    minimumSize: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  // Wait for the UI frame to render before showing the window
  // CRITICAL: DO NOT `await` this call. Awaiting it will block Flutter from
  // reaching `runApp()`, creating a deadlock that only resolves via timeout,
  // which causes the "empty window for seconds" glitch on Linux/Wayland.
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(true);
  });

  // Windows Single Instance Check
  // Note: Windows hook relies on window creation, so it runs after GUI init.
  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      "antigravity_player",
      onSecondWindow: (newArgs) {
        debugPrint("Second window attempted to open on Windows with args: $newArgs");
        if (newArgs.isNotEmpty) {
          ExternalFileHandler.handleExternalFile(
            newArgs.first,
            container,
            rootNavigatorKey.currentContext,
          );
        }
      },
      bringWindowToFront: true,
    );
  }

  // Handle initial file launch for the first instance
  if (args.isNotEmpty) {
    // Delayed slightly to allow the app routing and UI to mount
    Future.delayed(const Duration(milliseconds: 500), () {
      ExternalFileHandler.handleExternalFile(
        args.first,
        container,
        rootNavigatorKey.currentContext,
      );
    });
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const VideoPlayerApp(),
    ),
  );

}

class VideoPlayerApp extends ConsumerStatefulWidget {
  const VideoPlayerApp({super.key});

  @override
  ConsumerState<VideoPlayerApp> createState() => _VideoPlayerAppState();
}

class _VideoPlayerAppState extends ConsumerState<VideoPlayerApp>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Enable window close interception for proper cleanup
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    // Stop player immediately to prevent audio from continuing after close
    try {
      await ref.read(playerProvider.notifier).stop();
    } catch (_) {
      // Ignore if provider doesn't exist (e.g., never navigated to player)
    }

    if (Platform.isLinux) {
      // On Linux, use immediate exit to bypass the problematic OpenGL shader
      // cleanup phase. The warnings occur because Flutter tries to cleanup
      // compositor shaders after the OpenGL context is already lost.
      exit(0);
    } else {
      // On Windows, using setPreventClose(false) + close() is faster than destroy()
      // because it sends the native WM_CLOSE signal directly instead of waiting
      // for Flutter's full cleanup cycle
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  @override
  Future<void> onWindowFocus() async {
    // Check for IPC file when gaining focus (Linux IPC)
    if (Platform.isLinux && mounted) {
      final container = ProviderScope.containerOf(context);
      // We must use rootNavigatorKey.currentContext for navigation,
      // as the state context is above the Router.
      await ExternalFileHandler.processLinuxIpcFile(
        container,
        rootNavigatorKey.currentContext,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
