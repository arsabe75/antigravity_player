import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../infrastructure/services/telegram_service.dart';

part 'custom_emoji_provider.g.dart';

class CustomEmojiState {
  final String? localPath;
  final bool isLoading;

  const CustomEmojiState({this.localPath, this.isLoading = false});
}

@Riverpod(keepAlive: true)
class CustomEmoji extends _$CustomEmoji {
  late final TelegramService _service;
  int? _pendingFileId;

  @override
  CustomEmojiState build(int customEmojiId) {
    _service = TelegramService();

    // Listen for file updates universally for this provider
    // Using ref.onDispose to clean up is good, but for streaming updates
    // where we might not get the update immediately, we rely on the stream.
    // Note: listening to the global stream for EVERY emoji instance might be heavy if many exist.
    // However, Riverpod handles disposals.

    final sub = _service.updates.listen((update) {
      if (_pendingFileId != null && update['@type'] == 'updateFile') {
        final file = update['file'];
        if (file['id'] == _pendingFileId &&
            file['local']['is_downloading_completed'] == true) {
          state = CustomEmojiState(localPath: file['local']['path']);
        }
      }
    });

    ref.onDispose(() {
      sub.cancel();
    });

    // Load emoji data
    _loadCustomEmoji(customEmojiId);

    return const CustomEmojiState(isLoading: true);
  }

  Future<void> _loadCustomEmoji(int customEmojiId) async {
    try {
      final result = await _service.sendWithResult({
        '@type': 'getCustomEmojiStickers',
        'custom_emoji_ids': [customEmojiId],
      });

      if (result['@type'] == 'stickers') {
        final stickers = result['stickers'] as List;
        if (stickers.isNotEmpty) {
          final sticker = stickers.first as Map<String, dynamic>;
          // Prefer thumbnail, then sticker itself
          final thumbnail = sticker['thumbnail'] as Map<String, dynamic>?;
          final Map<String, dynamic> fileObj;

          if (thumbnail != null) {
            fileObj = thumbnail['file'] as Map<String, dynamic>;
          } else {
            fileObj = sticker['sticker'] as Map<String, dynamic>;
          }

          final local = fileObj['local'] as Map<String, dynamic>;
          final fileId = fileObj['id'] as int;

          if (local['is_downloading_completed'] == true &&
              local['path'] != null) {
            state = CustomEmojiState(localPath: local['path']);
          } else {
            _pendingFileId = fileId;
            await _downloadFile(fileId);
          }
        } else {
          state = const CustomEmojiState(isLoading: false);
        }
      }
    } catch (e) {
      debugPrint('Error loading custom emoji $customEmojiId: $e');
      state = const CustomEmojiState(isLoading: false);
    }
  }

  Future<void> _downloadFile(int fileId) async {
    _service.send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': 32,
      'synchronous': false,
    });
  }
}
