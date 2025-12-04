import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/theme_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _pickFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      if (context.mounted) {
        context.go('/player', extra: result.files.single.path);
      }
    }
  }

  Future<void> _enterUrl(BuildContext context) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Network URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://example.com/video.mp4',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );

    if (url != null && url.isNotEmpty) {
      if (context.mounted) {
        context.go('/player', extra: url);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.clapperboard,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 32),
                Text(
                  'Antigravity Player',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 250,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => _pickFile(context),
                    icon: const Icon(LucideIcons.folderOpen),
                    label: const Text('Open Local File'),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 250,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () => _enterUrl(context),
                    icon: const Icon(LucideIcons.globe),
                    label: const Text('Open Network URL'),
                  ),
                ),
              ],
            ),
          ),
          // Top bar with window controls
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              onPanStart: (_) => windowManager.startDragging(),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Text(
                      'Antigravity Player',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Theme Toggle Button
                    IconButton(
                      icon: Icon(
                        isDarkMode ? LucideIcons.sun : LucideIcons.moon,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () {
                        ref.read(themeProvider.notifier).toggleTheme();
                      },
                      tooltip: isDarkMode
                          ? 'Switch to Light Mode'
                          : 'Switch to Dark Mode',
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.minus,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => windowManager.minimize(),
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.maximize,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () async {
                        if (await windowManager.isMaximized()) {
                          windowManager.unmaximize();
                        } else {
                          windowManager.maximize();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.x,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => windowManager.close(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
