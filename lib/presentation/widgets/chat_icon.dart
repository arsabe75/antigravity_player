import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'custom_emoji_icon.dart';
import '../providers/telegram_file_provider.dart';

class ChatIcon extends ConsumerWidget {
  final Map<String, dynamic> chat;
  final IconData fallbackIcon;
  final double size;

  const ChatIcon({
    super.key,
    required this.chat,
    required this.fallbackIcon,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Icon size is usually smaller than the full avatar size
    final double iconSize = size * 0.6;
    // 1. Check for Custom Emoji
    final customEmojiId = _getCustomEmojiId(chat);
    if (customEmojiId != 0) {
      return CustomEmojiIcon(
        customEmojiId: customEmojiId,
        fallbackIcon: fallbackIcon,
        size: iconSize,
      );
    }

    // 2. Check for Chat Photo
    final photo = chat['photo'];
    if (photo != null) {
      final smallFile = photo['small'];
      if (smallFile != null) {
        final fileId = smallFile['id'] as int;
        // Check if path is already available in the chat object to avoid flicker/wait
        final localPath = smallFile['local']?['path'] as String?;
        final isCompleted =
            smallFile['local']?['is_downloading_completed'] == true;

        if (isCompleted && localPath != null && localPath.isNotEmpty) {
          return ClipOval(
            child: Image.file(
              File(localPath),
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return Icon(fallbackIcon, size: iconSize);
              },
            ),
          );
        }

        // Check for minithumbnail to show while loading
        final minithumbnail = photo['minithumbnail'];
        Widget? placeholder;
        if (minithumbnail != null && minithumbnail['data'] != null) {
          try {
            final String base64Data = minithumbnail['data'] as String;
            placeholder = Image.memory(
              base64Decode(base64Data),
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            );
          } catch (_) {
            // Error decoding minithumbnail
          }
        }

        // Use provider to download/track
        final fileState = ref.watch(telegramFileProvider(fileId));
        final hasHighRes =
            fileState.localPath != null && fileState.localPath!.isNotEmpty;

        return ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (placeholder != null) placeholder,
                if (hasHighRes)
                  Image.file(
                    File(fileState.localPath!),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink();
                    },
                  ),
              ],
            ),
          ),
        );
      }
    }

    // 3. Fallback
    return Icon(fallbackIcon, size: iconSize);
  }

  /// Get custom emoji ID for channels/groups.
  /// Uses profile_background_custom_emoji_id (for avatar backgrounds) or
  /// background_custom_emoji_id (for message headers) as fallback.
  int _getCustomEmojiId(Map<String, dynamic> chat) {
    // For channels/groups: use profile_background_custom_emoji_id
    final profileEmojiId = chat['profile_background_custom_emoji_id'];
    if (profileEmojiId != null && profileEmojiId != 0) {
      return profileEmojiId is int
          ? profileEmojiId
          : int.tryParse(profileEmojiId.toString()) ?? 0;
    }

    // Fallback to background_custom_emoji_id (for message headers)
    final bgEmojiId = chat['background_custom_emoji_id'];
    if (bgEmojiId != null && bgEmojiId != 0) {
      return bgEmojiId is int
          ? bgEmojiId
          : int.tryParse(bgEmojiId.toString()) ?? 0;
    }

    return 0;
  }

  /// Get accent color for channel/group avatar background.
  /// Uses profile_accent_color_id with built-in color palette.
  static Color? getAccentColor(Map<String, dynamic> chat) {
    final accentColorId = chat['profile_accent_color_id'] as int?;
    if (accentColorId == null || accentColorId < 0) {
      // Fallback to accent_color_id (for message headers)
      final msgAccentColorId = chat['accent_color_id'] as int?;
      if (msgAccentColorId == null || msgAccentColorId < 0) return null;
      return _getBuiltInColor(msgAccentColorId);
    }
    return _getBuiltInColor(accentColorId);
  }

  /// Get built-in accent color by ID.
  /// These are the 8 standard Telegram accent colors (IDs 0-7).
  static Color? _getBuiltInColor(int colorId) {
    const builtInColors = [
      Color(0xFFE17076), // 0 - Red
      Color(0xFFF5A623), // 1 - Orange
      Color(0xFF9B59B6), // 2 - Purple
      Color(0xFF27AE60), // 3 - Green
      Color(0xFF3498DB), // 4 - Blue
      Color(0xFF00BCD4), // 5 - Cyan
      Color(0xFFE91E63), // 6 - Pink
      Color(0xFF607D8B), // 7 - Grey
    ];

    if (colorId >= 0 && colorId < builtInColors.length) {
      return builtInColors[colorId];
    }
    return null; // Custom colors would need TDLib lookup
  }
}
