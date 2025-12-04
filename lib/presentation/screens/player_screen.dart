import 'dart:async';
import 'package:go_router/go_router.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/player_notifier.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String? videoUrl;

  const PlayerScreen({super.key, this.videoUrl});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WindowListener {
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    if (widget.videoUrl != null) {
      final isNetwork = widget.videoUrl!.startsWith('http');
      Future.microtask(
        () => ref
            .read(playerProvider.notifier)
            .loadVideo(widget.videoUrl!, isNetwork: isNetwork),
      );
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    ref.read(playerProvider.notifier).setControlsVisibility(true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        ref.read(playerProvider.notifier).setControlsVisibility(false);
      }
    });
  }

  void _onHover() {
    _startHideTimer();
  }

  void _onExit() {
    _hideTimer?.cancel();
    if (mounted) {
      ref.read(playerProvider.notifier).setControlsVisibility(false);
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);

    // We need the controller to pass to VideoPlayer widget.
    // Since VideoPlayer widget requires a controller, and our repo holds it,
    // we might need to expose it or wrap it.
    // For this implementation, we'll assume the repo exposes it or we access it via a provider that exposes the controller.
    // Let's cast repo to impl to get controller for now, or better, add a getter in interface/impl.
    // I added `VideoPlayerController? get controller` to VideoRepositoryImpl, but not interface.
    // I'll cast it here for simplicity or update interface. Casting is quick for now.

    // Actually, VideoPlayer widget needs a controller.
    // Let's assume we can get it.
    final controller =
        (ref.read(videoRepositoryProvider) as dynamic).controller
            as VideoPlayerController?;

    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        cursor: state.isFullscreen && !state.areControlsVisible
            ? SystemMouseCursors.none
            : SystemMouseCursors.basic,
        onHover: (_) => _onHover(),
        onExit: (_) => _onExit(),
        child: Stack(
          children: [
            // Video Layer
            GestureDetector(
              onDoubleTap: () {
                notifier.toggleFullscreen();
                // Handle actual window fullscreen
                if (state.isFullscreen) {
                  windowManager.setFullScreen(false);
                } else {
                  windowManager.setFullScreen(true);
                }
              },
              child: Center(
                child: controller != null && controller.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: VideoPlayer(controller),
                      )
                    : const CircularProgressIndicator(color: Colors.white),
              ),
            ),

            // Controls Layer
            AnimatedOpacity(
              opacity: state.areControlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Stack(
                children: [
                  // Top Bar (Window Controls)
                  if (!state.isFullscreen)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: GestureDetector(
                        onPanStart: (_) => windowManager.startDragging(),
                        child: Container(
                          height: 40,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black54, Colors.transparent],
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.arrowLeft,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () => context.go('/'),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                state.currentVideoPath?.split('/').last ??
                                    'Video Player',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.minus,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () => windowManager.minimize(),
                              ),
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.maximize,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () async {
                                  if (await windowManager.isMaximized()) {
                                    windowManager.unmaximize();
                                  } else {
                                    windowManager.maximize();
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.x,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () => windowManager.close(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Bottom Bar (Player Controls)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Progress Bar
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                              activeTrackColor: Colors.blue,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: state.position.inMilliseconds
                                  .toDouble()
                                  .clamp(
                                    0,
                                    state.duration.inMilliseconds.toDouble(),
                                  ),
                              min: 0,
                              max: state.duration.inMilliseconds.toDouble() > 0
                                  ? state.duration.inMilliseconds.toDouble()
                                  : 1.0,
                              onChanged: (value) {
                                notifier.seekTo(
                                  Duration(milliseconds: value.toInt()),
                                );
                              },
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  state.isPlaying
                                      ? LucideIcons.pause
                                      : LucideIcons.play,
                                  color: Colors.white,
                                ),
                                onPressed: notifier.togglePlay,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_formatDuration(state.position)} / ${_formatDuration(state.duration)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              // Volume
                              SizedBox(
                                width: 100,
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 4,
                                    ),
                                    activeTrackColor: Colors.white,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                  ),
                                  child: Slider(
                                    value: state.volume,
                                    onChanged: (value) =>
                                        notifier.setVolume(value),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  state.isFullscreen
                                      ? LucideIcons.minimize
                                      : LucideIcons.maximize,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  notifier.toggleFullscreen();
                                  // Handle actual window fullscreen
                                  if (state.isFullscreen) {
                                    windowManager.setFullScreen(false);
                                  } else {
                                    windowManager.setFullScreen(true);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // File Picker Button (if no video loaded)
            if (state.currentVideoPath == null)
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Implement file picker logic here or in notifier
                    // For now, just load a sample
                    notifier.loadVideo(
                      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                      isNetwork: true,
                    );
                  },
                  icon: const Icon(LucideIcons.fileVideo),
                  label: const Text('Open Video'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
