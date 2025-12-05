import 'package:flutter/material.dart';

import '../../../config/constants/app_constants.dart';

/// Slider de progreso del video con estilo personalizado
class VideoProgressSlider extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const VideoProgressSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final positionMs = position.inMilliseconds.toDouble();
    final durationMs = duration.inMilliseconds.toDouble();

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
        value: positionMs.clamp(0, durationMs),
        min: 0,
        max: durationMs > 0 ? durationMs : 1.0,
        onChanged: (value) {
          onSeek(Duration(milliseconds: value.toInt()));
        },
      ),
    );
  }
}
