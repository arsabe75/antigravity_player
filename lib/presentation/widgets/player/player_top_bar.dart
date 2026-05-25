import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../l10n/l10n.dart';
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
    return videoTitle ?? AppConstants.appName;
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
          height: 56.0,
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
                  size: 24.0,
                ),
                onPressed: onBack,
                tooltip: AppLocalizations.of(context).controlBack,
              ),
              const SizedBox(width: 8),
              // Video title
              Expanded(
                child: Text(
                  _getDisplayTitle(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Window controls
              IconButton(
                icon: const Icon(
                  LucideIcons.minus,
                  color: Colors.white,
                  size: 24.0,
                ),
                onPressed: () => windowManager.minimize(),
                tooltip: AppLocalizations.of(context).controlMinimize,
              ),
              IconButton(
                icon: const Icon(
                  LucideIcons.square,
                  color: Colors.white,
                  size: 24.0,
                ),
                onPressed: () async {
                  if (await windowManager.isMaximized()) {
                    windowManager.unmaximize();
                  } else {
                    windowManager.maximize();
                  }
                },
                tooltip: AppLocalizations.of(context).controlMaximize,
              ),
              IconButton(
                icon: const Icon(
                  LucideIcons.x,
                  color: Colors.white,
                  size: 24.0,
                ),
                onPressed: onClose,
                tooltip: AppLocalizations.of(context).controlClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
