import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/video_repository_provider.dart';
import '../providers/player_notifier.dart';
import '../../infrastructure/services/player_settings_service.dart';
import '../../config/constants/app_constants.dart';
import '../../l10n/l10n.dart';
import 'subtitle_config_dialog.dart';

class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  Future<void> _openUrl(String url) async {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', url]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(t.settingsTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.settingsPlayerEngine,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Consumer(
              builder: (context, ref, child) {
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
                            title: Text(t.settingsMediaKit),
                            subtitle: Text(
                              t.settingsMediaKitSubtitle,
                            ),
                            value: PlayerSettingsService.engineMediaKit,
                          ),
                          RadioListTile<String>(
                            title: Text(t.settingsFvp),
                            subtitle: Text(
                              t.settingsFvpSubtitle,
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
            const SizedBox(height: 16),
            FutureBuilder<String>(
              future: PlayerSettingsService().getPlayerEngine(),
              builder: (context, snapshot) {
                final isMediaKit = snapshot.data == PlayerSettingsService.engineMediaKit;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.subtitleConfigTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isMediaKit
                          ? t.settingsMediaKitSubtitle
                          : t.settingsFvpSubtitle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: isMediaKit
                          ? () {
                              final notifier = ref.read(playerProvider.notifier);
                              showDialog(
                                context: context,
                                builder: (_) => SubtitleConfigDialog(
                                  onSettingsChanged: () =>
                                      notifier.applySubtitleSettings(),
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.subtitles, size: 18),
                      label: Text(t.subtitleConfigButton),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            // About section
            Center(
              child: Column(
                children: [
                  Image.asset(
                    'assets/icon/app_icon_v2.png',
                    width: 48,
                    height: 48,
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version =
                          snapshot.hasData ? ' v${snapshot.data!.version}' : '';
                      return Text(
                        '${AppConstants.appName}$version',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(t.settingsDevelopedBy),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _openUrl('https://t.me/asbSoftware'),
                    child: Text(
                      't.me/asbSoftware',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: Text(t.settingsClose)),
      ],
    );
  }
}
