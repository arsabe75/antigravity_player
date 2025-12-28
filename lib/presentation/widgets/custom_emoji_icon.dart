import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/custom_emoji_provider.dart';

class CustomEmojiIcon extends ConsumerWidget {
  final int customEmojiId;
  final double size;
  final IconData? fallbackIcon;
  final Color? color;

  const CustomEmojiIcon({
    super.key,
    required this.customEmojiId,
    this.size = 24,
    this.fallbackIcon,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (customEmojiId == 0) {
      return Icon(
        fallbackIcon ?? LucideIcons.messageSquare,
        size: size,
        color: color,
      );
    }

    final emojiState = ref.watch(customEmojiProvider(customEmojiId));

    if (emojiState.localPath != null) {
      return Image.file(
        File(emojiState.localPath!),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            fallbackIcon ?? LucideIcons.helpCircle,
            size: size,
            color: color,
          );
        },
      );
    } else if (emojiState.isLoading) {
      // Show a placeholder or the fallback with low opacity
      return SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Icon(
      fallbackIcon ?? LucideIcons.messageSquare,
      size: size,
      color: color,
    );
  }
}
