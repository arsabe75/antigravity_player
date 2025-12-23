import 'package:flutter/material.dart';

import '../../../config/constants/app_constants.dart';

/// Video progress slider with seek preview support.
/// Uses standard Slider callbacks for cross-platform compatibility.
class VideoProgressSlider extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  /// Called during slider drag for seek preview preloading (optional)
  final ValueChanged<Duration>? onSeekPreview;

  const VideoProgressSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.onSeekPreview,
  });

  @override
  State<VideoProgressSlider> createState() => _VideoProgressSliderState();
}

class _VideoProgressSliderState extends State<VideoProgressSlider> {
  // Track if user is currently dragging
  bool _isDragging = false;

  // Track the current drag position (separate from actual playback position)
  double _dragValue = 0;

  @override
  Widget build(BuildContext context) {
    final positionMs = widget.position.inMilliseconds.toDouble();
    final durationMs = widget.duration.inMilliseconds.toDouble();

    // Use drag value while dragging, otherwise use actual position
    final displayValue = _isDragging ? _dragValue : positionMs;
    final clampedValue = displayValue.clamp(
      0.0,
      durationMs > 0 ? durationMs : 1.0,
    );

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: AppConstants.sliderTrackHeight,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: AppConstants.progressThumbRadius,
        ),
        overlayShape: RoundSliderOverlayShape(
          overlayRadius: AppConstants.progressOverlayRadius,
        ),
        activeTrackColor: Colors.blue,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
      ),
      child: Slider(
        value: clampedValue,
        min: 0,
        max: durationMs > 0 ? durationMs : 1.0,
        onChanged: (value) {
          setState(() {
            _isDragging = true;
            _dragValue = value;
          });
          // Notify preview callback during drag
          widget.onSeekPreview?.call(Duration(milliseconds: value.toInt()));
        },
        onChangeStart: (value) {
          setState(() {
            _isDragging = true;
            _dragValue = value;
          });
        },
        onChangeEnd: (value) {
          // Perform actual seek on release
          widget.onSeek(Duration(milliseconds: value.toInt()));
          setState(() {
            _isDragging = false;
          });
        },
      ),
    );
  }
}
