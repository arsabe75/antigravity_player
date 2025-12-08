import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'video_progress_slider.dart';
import 'volume_control.dart';
import 'playback_speed_control.dart';

/// Barra inferior del reproductor con controles de reproducción
class PlayerBottomBar extends StatelessWidget {
  // Estado de reproducción
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double volume;
  final double playbackSpeed;
  final bool isFullscreen;
  final bool isAlwaysOnTop;
  final bool showPlaylist;
  final bool hasNext;
  final bool hasPrevious;
  final bool isPlaylistEmpty;

  // Callbacks
  final VoidCallback onTogglePlay;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleAlwaysOnTop;
  final VoidCallback onTogglePlaylist;
  final VoidCallback? onToggleTracks;

  const PlayerBottomBar({
    super.key,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.volume,
    required this.playbackSpeed,
    required this.isFullscreen,
    required this.isAlwaysOnTop,
    required this.showPlaylist,
    required this.hasNext,
    required this.hasPrevious,
    required this.isPlaylistEmpty,
    required this.onTogglePlay,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    required this.onVolumeChanged,
    required this.onToggleMute,
    required this.onSpeedChanged,
    required this.onToggleFullscreen,
    required this.onToggleAlwaysOnTop,
    required this.onTogglePlaylist,
    this.onToggleTracks,
  });

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
            VideoProgressSlider(
              position: position,
              duration: duration,
              onSeek: onSeek,
            ),
            // Controls Row
            Row(
              children: [
                // Previous button
                if (!isPlaylistEmpty)
                  IconButton(
                    icon: Icon(
                      LucideIcons.skipBack,
                      color: hasPrevious ? Colors.white : Colors.white30,
                    ),
                    onPressed: hasPrevious ? onPrevious : null,
                    tooltip: 'Previous',
                  ),
                // Play/Pause button
                IconButton(
                  icon: Icon(
                    isPlaying ? LucideIcons.pause : LucideIcons.play,
                    color: Colors.white,
                  ),
                  onPressed: onTogglePlay,
                  tooltip: isPlaying ? 'Pause' : 'Play',
                ),
                // Next button
                if (!isPlaylistEmpty)
                  IconButton(
                    icon: Icon(
                      LucideIcons.skipForward,
                      color: hasNext ? Colors.white : Colors.white30,
                    ),
                    onPressed: hasNext ? onNext : null,
                    tooltip: 'Next',
                  ),
                if (!isPlaylistEmpty) const SizedBox(width: 8),
                // Time display
                Text(
                  '${_formatDuration(position)} / ${_formatDuration(duration)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const Spacer(),
                // Playback speed
                PlaybackSpeedControl(
                  currentSpeed: playbackSpeed,
                  onSpeedChanged: onSpeedChanged,
                ),
                // Volume control
                VolumeControl(
                  volume: volume,
                  onVolumeChanged: onVolumeChanged,
                  onToggleMute: onToggleMute,
                ),
                // Tracks button
                if (onToggleTracks != null)
                  IconButton(
                    icon: const Icon(
                      LucideIcons.subtitles,
                      color: Colors.white,
                    ),
                    onPressed: onToggleTracks!,
                    tooltip: 'Audio & Subtitles',
                  ),
                // Always on top button
                IconButton(
                  icon: Icon(
                    LucideIcons.pin,
                    color: isAlwaysOnTop ? Colors.blue : Colors.white,
                  ),
                  onPressed: onToggleAlwaysOnTop,
                  tooltip: isAlwaysOnTop
                      ? 'Disable Always on Top'
                      : 'Enable Always on Top',
                ),
                // Playlist button
                IconButton(
                  icon: Icon(
                    LucideIcons.listVideo,
                    color: showPlaylist ? Colors.blue : Colors.white,
                  ),
                  onPressed: onTogglePlaylist,
                  tooltip: 'Playlist',
                ),
                // Fullscreen button
                IconButton(
                  icon: Icon(
                    isFullscreen ? LucideIcons.minimize : LucideIcons.maximize,
                    color: Colors.white,
                  ),
                  onPressed: onToggleFullscreen,
                  tooltip: isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
