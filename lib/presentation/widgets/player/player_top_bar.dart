import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../../../config/constants/app_constants.dart';

/// Barra superior del reproductor con controles de ventana
class PlayerTopBar extends StatelessWidget {
  final String? videoTitle;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final bool isVisible;

  const PlayerTopBar({
    super.key,
    this.videoTitle,
    required this.onBack,
    required this.onClose,
    this.isVisible = true,
  });

  String _getDisplayTitle() {
    if (videoTitle == null) return AppConstants.appName;
    // Extract filename from path
    final parts = videoTitle!.split('/');
    return parts.isNotEmpty ? parts.last : AppConstants.appName;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Container(
          height: AppConstants.topBarHeight,
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
              // Back button
              IconButton(
                icon: const Icon(
                  LucideIcons.arrowLeft,
                  color: Colors.white,
                  size: AppConstants.iconSize,
                ),
                onPressed: onBack,
                tooltip: 'Back',
              ),
              const SizedBox(width: 8),
              // Video title
              Expanded(
                child: Text(
                  _getDisplayTitle(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Window controls
              IconButton(
                icon: const Icon(
                  LucideIcons.minus,
                  color: Colors.white,
                  size: AppConstants.iconSize,
                ),
                onPressed: () => windowManager.minimize(),
                tooltip: 'Minimize',
              ),
              IconButton(
                icon: const Icon(
                  LucideIcons.maximize,
                  color: Colors.white,
                  size: AppConstants.iconSize,
                ),
                onPressed: () async {
                  if (await windowManager.isMaximized()) {
                    windowManager.unmaximize();
                  } else {
                    windowManager.maximize();
                  }
                },
                tooltip: 'Maximize',
              ),
              IconButton(
                icon: const Icon(
                  LucideIcons.x,
                  color: Colors.white,
                  size: AppConstants.iconSize,
                ),
                onPressed: onClose,
                tooltip: 'Close',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
