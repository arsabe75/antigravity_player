import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            LucideIcons.minus,
            color: theme.colorScheme.onSurface,
            size: 20,
          ),
          onPressed: () => windowManager.minimize(),
          tooltip: 'Minimize',
        ),
        IconButton(
          icon: Icon(
            LucideIcons.maximize,
            color: theme.colorScheme.onSurface,
            size: 20,
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
          icon: Icon(
            LucideIcons.x,
            color: theme.colorScheme.onSurface,
            size: 20,
          ),
          onPressed: () => windowManager.close(),
          tooltip: 'Close',
        ),
      ],
    );
  }
}
