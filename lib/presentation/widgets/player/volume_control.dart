import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../config/constants/app_constants.dart';
import '../../../../l10n/l10n.dart';

/// Control de volumen con icono y slider
class VolumeControl extends StatelessWidget {
  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;

  const VolumeControl({
    super.key,
    required this.volume,
    required this.onVolumeChanged,
    required this.onToggleMute,
  });

  IconData _getVolumeIcon() {
    if (volume <= 0) return LucideIcons.volumeX;
    if (volume < 0.3) return LucideIcons.volume;
    if (volume < 0.7) return LucideIcons.volume1;
    return LucideIcons.volume2;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _getVolumeIcon(),
            color: Colors.white,
            size: AppConstants.iconSize,
          ),
          onPressed: onToggleMute,
          tooltip: volume > 0 ? AppLocalizations.of(context).controlMute : AppLocalizations.of(context).controlUnmute,
        ),
        SizedBox(
          width: AppConstants.volumeSliderWidth,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: AppConstants.sliderTrackHeight,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: AppConstants.volumeThumbRadius,
              ),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: volume,
              min: AppConstants.minVolume,
              max: AppConstants.maxVolume,
              onChanged: onVolumeChanged,
            ),
          ),
        ),
      ],
    );
  }
}
