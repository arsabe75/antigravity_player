import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/playlist_entity.dart';
import '../../presentation/providers/playlist_notifier.dart';
import '../../config/router/routes.dart';

class ExternalFileHandler {
  static const _supportedVideoExtensions = [
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.flv',
    '.wmv',
    '.webm',
    '.m4v',
  ];

  static final String _linuxTempFilePath = p.join(Directory.systemTemp.path, 'antigravity_player_ipc.txt');

  /// Handles an incoming file path from the OS.
  static Future<void> handleExternalFile(
    String path,
    ProviderContainer container,
    BuildContext? context,
  ) async {
    final lowerPath = path.toLowerCase();
    final isValidVideo = _supportedVideoExtensions.any(
      (ext) => lowerPath.endsWith(ext),
    );

    if (!isValidVideo) {
      debugPrint('ExternalFileHandler: No es un video válido -> $path');
      return;
    }

    final item = PlaylistItem(
      path: path,
      isNetwork: false,
      title: p.basename(path),
    );

    // Update playlist without startFromBeginning to ensure progress persistence
    container.read(playlistProvider.notifier).setPlaylist([item]);

    // If context is available (app already running), perform navigation
    if (context != null && context.mounted) {
      PlayerRoute($extra: PlayerRouteExtra(url: path)).go(context);
    }
  }

  /// Writes the file path to a temp file for Linux IPC
  static Future<void> writeLinuxIpcFile(String path) async {
    try {
      final file = File(_linuxTempFilePath);
      await file.writeAsString(path);
      debugPrint('ExternalFileHandler: IPC file written -> $path');
    } catch (e) {
      debugPrint('ExternalFileHandler: Error writing IPC file: $e');
    }
  }

  /// Reads and processes the Linux IPC file if it exists, then deletes it
  static Future<void> processLinuxIpcFile(
    ProviderContainer container,
    BuildContext context,
  ) async {
    try {
      final file = File(_linuxTempFilePath);
      if (await file.exists()) {
        final path = await file.readAsString();
        await file.delete(); // Clean up immediately
        debugPrint('ExternalFileHandler: Processed IPC file -> $path');
        if (path.isNotEmpty) {
          if (!context.mounted) return;
          await handleExternalFile(path.trim(), container, context);
        }
      }
    } catch (e) {
      debugPrint('ExternalFileHandler: Error processing IPC file: $e');
    }
  }
}
