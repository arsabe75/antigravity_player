import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/telegram_file_provider.dart';

class VideoCardThumbnail extends ConsumerWidget {
  final int? thumbnailFileId;
  final String? minithumbnailData;

  const VideoCardThumbnail({
    super.key,
    this.thumbnailFileId,
    this.minithumbnailData,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Build minithumbnail placeholder (immediate, from base64)
    Widget? placeholder;
    if (minithumbnailData != null && minithumbnailData!.isNotEmpty) {
      try {
        final bytes = base64Decode(minithumbnailData!);
        placeholder = Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              const SizedBox.shrink(),
        );
      } catch (_) {}
    }

    // Download full thumbnail via TDLib
    Widget? fullThumbnail;
    if (thumbnailFileId != null) {
      final fileState = ref.watch(telegramFileProvider(thumbnailFileId!));
      final hasImage =
          fileState.localPath != null && fileState.localPath!.isNotEmpty;
      if (hasImage) {
        fullThumbnail = Image.file(
          File(fileState.localPath!),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              const SizedBox.shrink(),
        );
      }
    }

    // Fallback: transparent (current look)
    final hasAnyThumbnail = placeholder != null || fullThumbnail != null;
    if (!hasAnyThumbnail) {
      return const SizedBox.expand();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ignore: use_null_aware_elements
        if (placeholder != null) placeholder,
        // ignore: use_null_aware_elements
        if (fullThumbnail != null) fullThumbnail,
        // Subtle dark overlay for badge readability over thumbnail
        Container(color: Colors.black.withValues(alpha: 0.2)),
      ],
    );
  }
}
