import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';
import 'package:window_manager/window_manager.dart';

import '../../config/constants/app_constants.dart';
import '../../domain/entities/player_error.dart';

import '../providers/player_notifier.dart';
import '../providers/player_state.dart';
import '../providers/playlist_notifier.dart';
import '../providers/recent_videos_refresh_provider.dart';
import '../providers/video_repository_provider.dart';
import '../widgets/player/player_widgets.dart';
import '../widgets/player/track_selection_sheet.dart';
import '../../infrastructure/services/recent_videos_service.dart';
import '../../infrastructure/services/media_control_service.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String? videoUrl;
  final String? title;
  final int? telegramChatId;
  final int? telegramMessageId;
  final int? telegramFileSize;
  final int? telegramTopicId;
  final String? telegramTopicName;

  const PlayerScreen({
    super.key,
    this.videoUrl,
    this.title,
    this.telegramChatId,
    this.telegramMessageId,
    this.telegramFileSize,
    this.telegramTopicId,
    this.telegramTopicName,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WindowListener {
  Timer? _hideTimer;
  bool _isDisposing = false;
  bool _showPlaylist = false;
  final _mediaControl = MediaControlService();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    if (widget.videoUrl != null) {
      final isNetwork = widget.videoUrl!.startsWith('http');
      Future.microtask(
        () => ref
            .read(playerProvider.notifier)
            .loadVideo(
              widget.videoUrl!,
              isNetwork: isNetwork,
              title: widget.title,
              telegramChatId: widget.telegramChatId,
              telegramMessageId: widget.telegramMessageId,
              telegramFileSize: widget.telegramFileSize,
              telegramTopicId: widget.telegramTopicId,
              telegramTopicName: widget.telegramTopicName,
            ),
      );
    }

    // Prevent default close to handle cleanup
    windowManager.setPreventClose(true);

    _initMediaControl();
  }

  Future<void> _initMediaControl() async {
    // Set callbacks
    _mediaControl.onPlay = () => ref.read(playerProvider.notifier).togglePlay();
    _mediaControl.onPause = () =>
        ref.read(playerProvider.notifier).togglePlay();
    _mediaControl.onPlayPause = () =>
        ref.read(playerProvider.notifier).togglePlay();
    _mediaControl.onNext = () {
      final playlistNotifier = ref.read(playlistProvider.notifier);
      if (playlistNotifier.next()) {
        final newItem = ref.read(playlistProvider).currentItem;
        if (newItem != null) {
          ref
              .read(playerProvider.notifier)
              .loadVideo(newItem.path, isNetwork: newItem.isNetwork);
        }
      }
    };
    _mediaControl.onPrevious = () {
      final playlistNotifier = ref.read(playlistProvider.notifier);
      if (playlistNotifier.previous()) {
        final newItem = ref.read(playlistProvider).currentItem;
        if (newItem != null) {
          ref
              .read(playerProvider.notifier)
              .loadVideo(newItem.path, isNetwork: newItem.isNetwork);
        }
      }
    };
    _mediaControl.onSeek = (offset) {
      final state = ref.read(playerProvider);
      final newPos = state.position + offset;
      ref.read(playerProvider.notifier).seekTo(newPos);
    };

    // Send initial state
    final currentState = ref.read(playerProvider);
    _mediaControl.updatePlaybackState(
      isPlaying: currentState.isPlaying,
      position: currentState.position,
      speed: currentState.playbackSpeed,
    );
    if (currentState.currentVideoPath != null) {
      final filename = currentState.currentVideoPath!.split('/').last;
      _mediaControl.updateMetaData(
        title: filename,
        duration: currentState.duration,
      );
    }

    // Initialize service
    await _mediaControl.init();
  }

  @override
  void dispose() {
    _mediaControl.dispose();
    windowManager.removeListener(this);
    windowManager.setPreventClose(false);
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (_isDisposing) return;
    setState(() {
      _isDisposing = true;
    });

    // Trigger refresh before closing
    triggerRecentVideosRefresh(ref);

    // Wait for frame to unmount VideoPlayer
    await Future.delayed(AppConstants.disposeDelay * 2);

    if (mounted) {
      await ref.read(playerProvider.notifier).stop();
    }

    // Use exit(0) to force a clean shutdown of the process
    exit(0);
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    ref.read(playerProvider.notifier).setControlsVisibility(true);
    _hideTimer = Timer(AppConstants.controlsHideDelay, () {
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

  Future<void> _handleBack() async {
    if (_isDisposing) return;
    setState(() {
      _isDisposing = true;
    });

    // Trigger refresh of recent videos BEFORE we navigate away
    triggerRecentVideosRefresh(ref);

    await Future.delayed(AppConstants.disposeDelay);
    await ref.read(playerProvider.notifier).stop();
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }
  }

  void _handleToggleFullscreen() {
    final notifier = ref.read(playerProvider.notifier);
    final state = ref.read(playerProvider);
    notifier.toggleFullscreen();
    if (state.isFullscreen) {
      windowManager.setFullScreen(false);
    } else {
      windowManager.setFullScreen(true);
    }
  }

  /// Handle seek preview for Telegram streaming videos
  /// Extracts file ID from proxy URL and calls previewSeekTarget with accurate byte offset
  void _handleSeekPreview(PlayerState state, Duration previewDuration) {
    final videoPath = state.currentVideoPath;
    if (videoPath == null) return;

    // Only for Telegram streaming videos (proxy URLs)
    if (!videoPath.contains('/stream?file_id=')) return;

    try {
      final uri = Uri.parse(videoPath);
      final fileIdStr = uri.queryParameters['file_id'];
      final sizeStr = uri.queryParameters['size'];

      if (fileIdStr == null) return;

      final fileId = int.tryParse(fileIdStr);
      final totalBytes = int.tryParse(sizeStr ?? '') ?? 0;

      if (fileId == null || totalBytes <= 0) return;

      final durationMs = state.duration.inMilliseconds;
      final previewMs = previewDuration.inMilliseconds;

      if (durationMs <= 0) return;

      // Get streaming repository and request seek preview preload
      final streamingRepo = ref.read(streamingRepositoryProvider);

      // Use getByteOffsetForTime for accurate byte offset (uses MP4 sample table if available)
      streamingRepo
          .getByteOffsetForTime(fileId, previewMs, durationMs, totalBytes)
          .then((byteOffset) {
            streamingRepo.previewSeekTarget(fileId, byteOffset);
          });
    } catch (e) {
      // Ignore errors in seek preview - it's an optimization, not critical
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final controller = ref.read(videoRepositoryProvider).platformController;
    final playlist = ref.watch(playlistProvider);
    final playlistNotifier = ref.read(playlistProvider.notifier);

    // Auto-advance listener
    ref.listen(playerProvider, (previous, next) {
      if (previous?.isPlaying == true &&
          !next.isPlaying &&
          next.duration > Duration.zero &&
          next.position >= next.duration) {
        // Video finished, play next
        if (playlistNotifier.next()) {
          final newItem = ref.read(playlistProvider).currentItem;
          if (newItem != null) {
            notifier.loadVideo(newItem.path, isNetwork: newItem.isNetwork);
          }
        }
      }

      // Update Media Control
      if (previous?.isPlaying != next.isPlaying ||
          previous?.position != next.position ||
          previous?.playbackSpeed != next.playbackSpeed) {
        _mediaControl.updatePlaybackState(
          isPlaying: next.isPlaying,
          position: next.position,
          speed: next.playbackSpeed,
        );
      }

      if (previous?.currentVideoPath != next.currentVideoPath &&
          next.currentVideoPath != null) {
        final filename = next.currentVideoPath!.split('/').last;
        _mediaControl.updateMetaData(title: filename, duration: next.duration);
      }
      // Also update duration if it changes (e.g. loaded)
      if (previous?.duration != next.duration) {
        final filename = next.currentVideoPath?.split('/').last ?? 'Unknown';
        _mediaControl.updateMetaData(title: filename, duration: next.duration);
      }
    });

    void playNext() {
      if (playlistNotifier.next()) {
        final newItem = ref.read(playlistProvider).currentItem;
        if (newItem != null) {
          notifier.loadVideo(newItem.path, isNetwork: newItem.isNetwork);
        }
      }
    }

    void playPrevious() {
      if (playlistNotifier.previous()) {
        final newItem = ref.read(playlistProvider).currentItem;
        if (newItem != null) {
          notifier.loadVideo(newItem.path, isNetwork: newItem.isNetwork);
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: _buildKeyboardShortcuts(state, notifier),
        child: Focus(
          autofocus: true,
          child: MouseRegion(
            cursor: state.isFullscreen && !state.areControlsVisible
                ? SystemMouseCursors.none
                : SystemMouseCursors.basic,
            onHover: (_) => _onHover(),
            onExit: (_) => _onExit(),
            child: Stack(
              children: [
                // Video Layer
                _buildVideoLayer(controller, state, notifier),

                // Buffering Indicator - shows during initial load OR buffering
                BufferingIndicator(
                  isBuffering: state.isBuffering || state.isInitialLoading,
                  isVideoNotOptimizedForStreaming:
                      state.isVideoNotOptimizedForStreaming,
                ),

                // Controls Layer
                AnimatedOpacity(
                  opacity: state.areControlsVisible ? 1.0 : 0.0,
                  duration: AppConstants.controlsFadeDuration,
                  child: Stack(
                    children: [
                      // Top Bar (only when not fullscreen)
                      if (!state.isFullscreen)
                        PlayerTopBar(
                          videoTitle:
                              state.currentVideoTitle ?? state.currentVideoPath,
                          onBack: _handleBack,
                          onClose: () => windowManager.close(),
                        ),

                      // Bottom Bar
                      PlayerBottomBar(
                        isPlaying: state.isPlaying,
                        position: state.position,
                        duration: state.duration,
                        volume: state.volume,
                        playbackSpeed: state.playbackSpeed,
                        isFullscreen: state.isFullscreen,
                        isAlwaysOnTop: state.isAlwaysOnTop,
                        showPlaylist: _showPlaylist,
                        isPlaylistEmpty: playlist.isEmpty,
                        hasNext: playlist.hasNext,
                        hasPrevious: playlist.hasPrevious,
                        onTogglePlay: notifier.togglePlay,
                        onNext: playNext,
                        onPrevious: playPrevious,
                        onSeek: notifier.seekTo,
                        onSeekPreview: (previewDuration) {
                          // Seek preview preloading for Telegram streaming videos
                          _handleSeekPreview(state, previewDuration);
                        },
                        onVolumeChanged: notifier.setVolume,
                        onToggleMute: notifier.toggleMute,
                        onSpeedChanged: notifier.setPlaybackSpeed,
                        onToggleFullscreen: _handleToggleFullscreen,
                        onToggleAlwaysOnTop: notifier.toggleAlwaysOnTop,
                        onTogglePlaylist: () =>
                            setState(() => _showPlaylist = !_showPlaylist),
                        // Only show tracks for MediaKit
                        onToggleTracks: state.playerBackend == 'media_kit'
                            ? () {
                                showModalBottomSheet(
                                  context: context,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) =>
                                      const TrackSelectionSheet(),
                                );
                              }
                            : null,
                      ),
                    ],
                  ),
                ),

                // File Picker Button (if no video loaded)
                if (state.currentVideoPath == null && state.error == null)
                  _buildNoVideoPlaceholder(notifier),

                // Error Overlay
                if (state.error != null)
                  ErrorOverlay(
                    error: PlayerErrorFactory.fromException(state.error),
                    onRetry: () {
                      if (state.currentVideoPath != null) {
                        notifier.loadVideo(
                          state.currentVideoPath!,
                          isNetwork: state.currentVideoPath!.startsWith('http'),
                        );
                      }
                    },
                    onGoHome: _handleBack,
                    onRemoveFromHistory: () async {
                      if (state.currentVideoPath != null) {
                        final service = RecentVideosService();
                        await service.removeVideo(state.currentVideoPath!);
                        await _handleBack();
                      }
                    },
                  ),

                // Playlist Sidebar
                if (_showPlaylist)
                  Positioned(
                    right: 0,
                    top: state.isFullscreen ? 0 : 40, // Below window controls
                    bottom: 0,
                    child: PlaylistSidebar(
                      onVideoSelected: () {
                        // Play selected video from playlist
                        final playlist = ref.read(playlistProvider);
                        final item = playlist.currentItem;
                        if (item != null) {
                          notifier.loadVideo(
                            item.path,
                            isNetwork: item.isNetwork,
                          );
                        }
                      },
                      onClose: () => setState(() => _showPlaylist = false),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildKeyboardShortcuts(
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    return {
      const SingleActivator(LogicalKeyboardKey.space): notifier.togglePlay,
      const SingleActivator(LogicalKeyboardKey.keyK): notifier.togglePlay,
      const SingleActivator(LogicalKeyboardKey.keyF): _handleToggleFullscreen,
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (state.isFullscreen) {
          notifier.toggleFullscreen();
          windowManager.setFullScreen(false);
        }
      },
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
        final newPos = state.position - AppConstants.seekDuration;
        notifier.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
      },
      const SingleActivator(LogicalKeyboardKey.arrowRight): () {
        final newPos = state.position + AppConstants.seekDuration;
        notifier.seekTo(newPos > state.duration ? state.duration : newPos);
      },
      const SingleActivator(LogicalKeyboardKey.keyJ): () {
        final newPos = state.position - AppConstants.seekDuration;
        notifier.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
      },
      const SingleActivator(LogicalKeyboardKey.keyL): () {
        final newPos = state.position + AppConstants.seekDuration;
        notifier.seekTo(newPos > state.duration ? state.duration : newPos);
      },
      const SingleActivator(LogicalKeyboardKey.keyM): notifier.toggleMute,
      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        final newVol = (state.volume + AppConstants.volumeStep).clamp(0.0, 1.0);
        notifier.setVolume(newVol);
      },
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        final newVol = (state.volume - AppConstants.volumeStep).clamp(0.0, 1.0);
        notifier.setVolume(newVol);
      },
      // Number keys for seeking to percentage
      const SingleActivator(LogicalKeyboardKey.digit0): () =>
          _seekToPercent(0, state, notifier),
      const SingleActivator(LogicalKeyboardKey.digit1): () =>
          _seekToPercent(10, state, notifier),
      const SingleActivator(LogicalKeyboardKey.digit2): () =>
          _seekToPercent(20, state, notifier),
      const SingleActivator(LogicalKeyboardKey.digit3): () =>
          _seekToPercent(30, state, notifier),
      const SingleActivator(LogicalKeyboardKey.digit4): () =>
          _seekToPercent(40, state, notifier),
      const SingleActivator(LogicalKeyboardKey.digit5): () =>
          _seekToPercent(50, state, notifier),
      const SingleActivator(LogicalKeyboardKey.digit6): () =>
          _seekToPercent(60, state, notifier),
      const SingleActivator(LogicalKeyboardKey.digit7): () =>
          _seekToPercent(70, state, notifier),
      const SingleActivator(LogicalKeyboardKey.digit8): () =>
          _seekToPercent(80, state, notifier),
      const SingleActivator(LogicalKeyboardKey.digit9): () =>
          _seekToPercent(90, state, notifier),
    };
  }

  void _seekToPercent(int percent, PlayerState state, PlayerNotifier notifier) {
    if (state.duration.inMilliseconds > 0) {
      final targetMs = (state.duration.inMilliseconds * percent / 100).round();
      notifier.seekTo(Duration(milliseconds: targetMs));
    }
  }

  Widget _buildVideoLayer(
    Object? controller,
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    if (_isDisposing || controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    Widget videoWidget;
    if (state.playerBackend == 'fvp') {
      // FVP / VideoPlayer
      // Dynamic cast or check type if strictly needed, but Object? is passed
      // We assume controller is VideoPlayerController if backend is fvp
      // Import video_player package in file if needed, or use dynamic
      final videoPlayerController = controller as VideoPlayerController;
      videoWidget = AspectRatio(
        aspectRatio: videoPlayerController.value.aspectRatio,
        child: VideoPlayer(videoPlayerController),
      );
    } else {
      // MediaKit
      videoWidget = Video(
        controller: (controller as VideoController),
        controls: NoVideoControls,
      );
    }

    return GestureDetector(
      onTap: notifier.togglePlay,
      onDoubleTap: _handleToggleFullscreen,
      child: Center(child: videoWidget),
    );
  }

  Widget _buildNoVideoPlaceholder(PlayerNotifier notifier) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () {
          notifier.loadVideo(
            'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
            isNetwork: true,
          );
        },
        icon: const Icon(LucideIcons.fileVideo),
        label: const Text('Open Video'),
      ),
    );
  }
}
