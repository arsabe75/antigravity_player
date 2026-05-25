import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/l10n.dart';

class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            LucideIcons.minus,
            color: theme.colorScheme.onSurface,
            size: 24,
          ),
          onPressed: () => windowManager.minimize(),
          tooltip: t.controlMinimize,
        ),
        IconButton(
          icon: Icon(
            LucideIcons.square,
            color: theme.colorScheme.onSurface,
            size: 24,
          ),
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
          tooltip: t.controlMaximize,
        ),
        IconButton(
          icon: Icon(
            LucideIcons.x,
            color: theme.colorScheme.onSurface,
            size: 24,
          ),
          onPressed: () => windowManager.close(),
          tooltip: t.controlClose,
        ),
      ],
    );
  }
}
