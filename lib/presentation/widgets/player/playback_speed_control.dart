import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../config/constants/app_constants.dart';

/// Control de velocidad de reproducción
class PlaybackSpeedControl extends StatelessWidget {
  final double currentSpeed;
  final ValueChanged<double> onSpeedChanged;

  const PlaybackSpeedControl({
    super.key,
    required this.currentSpeed,
    required this.onSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      initialValue: currentSpeed,
      onSelected: onSpeedChanged,
      tooltip: 'Playback Speed',
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.gauge,
            color: Colors.white,
            size: AppConstants.iconSize,
          ),
          const SizedBox(width: 4),
          Text(
            '${currentSpeed}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      color: Colors.black87,
      itemBuilder: (context) => AppConstants.playbackSpeeds.map((speed) {
        final isSelected = speed == currentSpeed;
        return PopupMenuItem<double>(
          value: speed,
          child: Row(
            children: [
              if (isSelected)
                const Icon(LucideIcons.check, color: Colors.blue, size: 16)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Text(
                '${speed}x',
                style: TextStyle(
                  color: isSelected ? Colors.blue : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
