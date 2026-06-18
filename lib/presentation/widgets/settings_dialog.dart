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
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
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
            // About section — two columns
            Row(

              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column: App name + Licenses
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, snapshot) {
                          final version = snapshot.hasData
                              ? ' v${snapshot.data!.version}'
                              : '';
                          return Text(
                            '${AppConstants.appName}$version',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => showLicensePage(context: context),
                        icon: const Icon(Icons.article_outlined, size: 18),
                        label: Text(t.settingsLicenses),
                      ),
                    ],
                  ),
                ),
                // Right column: Developer + Telegram link
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
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
            const SizedBox(height: 16),
            Divider(height: 1, color: Colors.grey[700]),
            const SizedBox(height: 12),
            Text(
              t.settingsDisclaimer,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: Text(t.settingsClose)),
      ],
    );
  }
}
