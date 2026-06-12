import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'package:flutter_media_session/flutter_media_session.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/licenses/native_licenses.dart';
import 'config/router/app_router.dart';
import 'config/theme/app_theme.dart';
import 'config/constants/app_constants.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/locale_provider.dart';
import 'l10n/l10n.dart';
import 'infrastructure/services/player_settings_service.dart';
import 'infrastructure/services/secure_storage_service.dart';
import 'presentation/providers/video_repository_provider.dart';
import 'presentation/providers/player_notifier.dart';
import 'infrastructure/services/external_file_handler.dart';
import 'infrastructure/services/media_control_service.dart';

class _PreloadedBackendNotifier extends PlayerBackend {
  final String initialBackend;
  _PreloadedBackendNotifier(this.initialBackend);

  @override
  String build() => initialBackend;
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register native library licenses before the app starts.
  // This adds attributions for DLLs (mpv, FFmpeg, libvlc, etc.) to the
  // LicensePage, which already includes Dart packages via NOTICES.Z.
  registerNativeLibraryLicenses();

  // Fire I/O-heavy init that isn't needed for the first frame in parallel.
  // dotenv is only used by TelegramAuth (lazy provider, accessed on navigation).
  // MediaKit is only needed when creating a video player.
  unawaited(dotenv.load(fileName: ".env")); // only needed by lazy TelegramAuth
  MediaKit.ensureInitialized();

  // Initialize encrypted storage (blocking: needed for backend selection below)
  await SecureStorageService.initialize();

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
  // Restored `await` here. Wayland requires the window to be fully realized
  // before displaying it, otherwise it loses frame decorations, snaps to top-left,
  // and breaks hit-testing (mouse clicks). 
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(true);
  });

  // Register Windows SMTC (SystemMediaTransportControls) for media key integration.
  // This must be called before activating the media session so the Windows volume
  // overlay shows the application name instead of "Unknown Application".
  if (Platform.isWindows) {
    await FlutterMediaSession().setWindowsAppUserModelId(
      'video_player_app',
      displayName: 'Video Player App',
    );
  }

  // Windows Single Instance Check
  // Note: Windows hook relies on window creation, so it runs after GUI init.
  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      "video_player_app",
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

    // Create the XDG desktop entry after the first frame so file I/O
    // doesn't compete with initial rendering on cold boots.
    if (Platform.isLinux) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MediaControlService.ensureDesktopEntry();
      });
    }
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
    final locale = ref.watch(localeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'VideoPlayerApp',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [
        Locale('es'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
