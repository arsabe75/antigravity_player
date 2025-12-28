import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../../domain/entities/playlist_entity.dart';
import '../providers/playlist_notifier.dart';
import '../providers/theme_provider.dart';
import '../widgets/dialogs/url_input_dialog.dart';
import '../widgets/home/recent_videos_widget.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/window_controls.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      if (context.mounted) {
        // Create playlist items
        final items = result.files
            .where((file) => file.path != null)
            .map(
              (file) => PlaylistItem(
                path: file.path!,
                isNetwork: false,
                title: file.name,
              ),
            )
            .toList();

        if (items.isNotEmpty) {
          // Set playlist and start playing first item
          ref.read(playlistProvider.notifier).setPlaylist(items);
          context.go('/player', extra: items.first.path);
        }
      }
    }
  }

  Future<void> _enterUrl(BuildContext context) async {
    final url = await UrlInputDialog.show(context);

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
          Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60), // Space for top bar
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
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          alignment: WrapAlignment.center,
                          children: [
                            SizedBox(
                              width: 200,
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: () => _pickFile(context, ref),
                                icon: const Icon(LucideIcons.folderOpen),
                                label: const Text('Open Local File(s)'),
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: () => _enterUrl(context),
                                icon: const Icon(LucideIcons.globe),
                                label: const Text('Open Network URL'),
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: () => context.push('/telegram'),
                                icon: const Icon(LucideIcons.send),
                                label: const Text('Telegram'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Recent Videos pinned to bottom
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: RecentVideosWidget(
                  // showTelegramVideos: false (default) - only local/network videos
                  onVideoSelected: (video) {
                    context.go('/player', extra: video.path);
                  },
                ),
              ),
            ],
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
                    colors: [
                      isDarkMode ? Colors.black54 : Colors.transparent,
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Text(
                      'Antigravity Player',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Theme Toggle Button
                    IconButton(
                      icon: Icon(
                        isDarkMode ? LucideIcons.sun : LucideIcons.moon,
                        color: Theme.of(context).colorScheme.onSurface,
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
                      icon: Icon(
                        LucideIcons.settings,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: 20,
                      ),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => const SettingsDialog(),
                        );
                      },
                      tooltip: 'Settings',
                    ),
                    const WindowControls(),
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
