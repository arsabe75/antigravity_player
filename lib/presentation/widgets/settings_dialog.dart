import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/video_repository_provider.dart';
import '../../infrastructure/services/player_settings_service.dart';

class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We can read current backend from PlayerState or SettingsService.
    // Reading from ref.read(initialPlayerBackendProvider) gives the STARTUP value,
    // but if we change it, we want to know.
    // Actually, we don't have a provider that updates on change yet besides simple state.
    // For now, let's just let the user pick, and on selection, save and notify/restart hint.

    return AlertDialog(
      title: const Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Player Engine'),
          const SizedBox(height: 10),
          Consumer(
            builder: (context, ref, child) {
              // We'll read the setting asynchronously or use the one in PlayerState if we trust it
              // For simplicity, let's use a FutureBuilder to get the current stored setting
              return FutureBuilder<String>(
                future: PlayerSettingsService().getPlayerEngine(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }

                  final currentEngine = snapshot.data!;

                  return RadioGroup<String>(
                    groupValue: currentEngine,
                    onChanged: (value) async {
                      if (value != null) {
                        await PlayerSettingsService().savePlayerEngine(value);
                        ref
                            .read(playerBackendProvider.notifier)
                            .setBackend(value);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      }
                    },
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text('MediaKit (Default)'),
                          subtitle: const Text(
                            'Supports tracks, hardware acceleration',
                          ),
                          value: PlayerSettingsService.engineMediaKit,
                        ),
                        RadioListTile<String>(
                          title: const Text('FVP (VideoPlayer)'),
                          subtitle: const Text(
                            'Alternative engine. No subtitles/audio selection.',
                          ),
                          value: PlayerSettingsService.engineFvp,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: const Text('Close')),
      ],
    );
  }
}
