import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../infrastructure/services/telegram_service.dart';
import '../../application/use_cases/load_chat_messages_use_case.dart';

import 'state/telegram_chat_state.dart';
export 'state/telegram_chat_state.dart';

part 'telegram_chat_notifier.g.dart';

@Riverpod(keepAlive: true)
class TelegramChat extends _$TelegramChat {
  late final TelegramService _service;

  // Pagination State
  int _nextVideoFromId = 0;
  int _nextDocFromId = 0;
  bool _hasMoreVideos = true;
  bool _hasMoreDocs = true;

  @override
  TelegramChatState build(TelegramChatParams params) {
    _service = TelegramService();
    final sub = _service.updates.listen(_handleUpdate);
    ref.onDispose(() {
      sub.cancel();
      // Inform TDLib we are no longer viewing this chat/topic
      _service.send({'@type': 'closeChat', 'chat_id': params.chatId});
    });

    // Inform TDLib we are viewing this chat/topic to ensure live updates
    _service.send({'@type': 'openChat', 'chat_id': params.chatId});

    // Defer loading to avoid modifying state during build
    Future.microtask(() => loadMessages());

    return const TelegramChatState(isLoading: true);
  }

  int get chatId => params.chatId;
  int? get messageThreadId => params.messageThreadId;

  // Handle ONLY live updates here (new messages arriving in real-time)
  void _handleUpdate(Map<String, dynamic> update) {
    // Guard against disposed provider
    if (!ref.mounted) return;
    try {
      final updateType = update['@type'];

      // Handle TDLib errors
      if (updateType == 'error') {
        debugPrint(
          'TelegramChat: TDLib error: ${update['code']} - ${update['message']}',
        );
        state = state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          hasMore: false,
          error: update['message'] as String?,
        );
        return;
      }

      if (updateType == 'updateNewMessage') {
        final message = update['message'];

        if (message['chat_id'] == chatId) {
          // For thread messages, check message_thread_id
          if (messageThreadId != null) {
            int? msgThreadId = message['message_thread_id'] as int?;
            if (msgThreadId == null && message.containsKey('topic_id')) {
              final topicObj = message['topic_id'];
              if (topicObj is Map) {
                msgThreadId = topicObj['forum_topic_id'] as int?;
              } else if (topicObj is int) {
                msgThreadId = topicObj;
              }
            }
            final finalThreadId = msgThreadId ?? 0;
            if (finalThreadId != messageThreadId) return;
          }

          if (_isMessageExists(message['id'])) {
            return;
          }

          // ONLY add if it is a video (Smart Filter)
          if (!_isVideoMessage(message)) {
            return;
          }

          // Prepend new message (live update)
          final currentMessages = List<Map<String, dynamic>>.from(
            state.messages,
          );
          currentMessages.insert(0, message);
          state = state.copyWith(messages: currentMessages);
        }
      } else if (updateType == 'updateDeleteMessages') {
        if (update['chat_id'] == chatId) {
          final messageIdsList = update['message_ids'] as List?;
          if (messageIdsList != null && messageIdsList.isNotEmpty) {
            final deletedIds = messageIdsList.cast<int>().toSet();
            final updatedMessages = state.messages
                .where((msg) => !deletedIds.contains(msg['id'] as int))
                .toList();

            if (updatedMessages.length != state.messages.length) {
              state = state.copyWith(messages: updatedMessages);
            }
          }
        }
      }
      // Note: We no longer handle 'foundChatMessages' here because we use sendWithResult
    } catch (e) {
      debugPrint('TelegramChat Error: $e');
    }
  }

  bool _isMessageExists(int id, {List<Map<String, dynamic>>? list}) {
    final l = list ?? state.messages;
    return l.any((m) => m['id'] == id);
  }

  /// Check if message is a video or video-document
  bool _isVideoMessage(Map<String, dynamic> message) {
    final content = message['content'];
    if (content == null) return false;

    // Standard video
    if (content['@type'] == 'messageVideo') return true;

    // MKV/AVI/others as Document
    if (content['@type'] == 'messageDocument') {
      final document = content['document'];
      final mimeType = (document['mime_type'] as String? ?? '').toLowerCase();
      final fileName = (document['file_name'] as String? ?? '').toLowerCase();

      if (mimeType.startsWith('video/')) return true;
      if (mimeType == 'application/x-matroska' ||
          mimeType == 'application/matroska') {
        return true;
      }

      const videoExtensions = [
        '.mkv',
        '.avi',
        '.mp4',
        '.mov',
        '.webm',
        '.flv',
        '.wmv',
        '.ts',
        '.m2ts',
        '.m4v',
        '.mpg',
        '.mpeg',
        '.3gp',
      ];

      for (final ext in videoExtensions) {
        if (fileName.endsWith(ext)) return true;
      }

      // If no valid extension and Linux failed to parse a video MIME type,
      // we can do a heuristic check: if it's a large file (>50MB) and we're
      // explicitly keeping videos, we might want to include it, but to be
      // safe we just check if it literally has no extension and size > 20MB.
      final size = document['document']['size'] ?? 0;
      if (size > 20 * 1024 * 1024 && !fileName.contains('.')) {
        return true;
      }
    }
    return false;
  }

  Future<void> loadMessages({bool forceRefresh = false}) async {
    try {
      if (forceRefresh) {
        state = state.copyWith(isLoading: true, messages: []);
      } else {
        if (!state.isLoading) {
          state = state.copyWith(isLoading: true);
        }
      }

      debugPrint(
        'TelegramChat: Searching video+docs for chat=$chatId thread=$messageThreadId...',
      );

      // Reset Cursors
      _nextVideoFromId = 0;
      _nextDocFromId = 0;
      _hasMoreVideos = true;
      _hasMoreDocs = true;

      final loadUseCase = ref.read(loadChatMessagesUseCaseProvider);
      final result = await loadUseCase(
        LoadChatMessagesParams(
          chatId: chatId,
          messageThreadId: messageThreadId,
          nextVideoFromId: _nextVideoFromId,
          nextDocFromId: _nextDocFromId,
        ),
      );

      _nextVideoFromId = result.nextVideoFromId;
      _nextDocFromId = result.nextDocFromId;
      _hasMoreVideos = result.hasMoreVideos;
      _hasMoreDocs = result.hasMoreDocs;

      final validMsgs = result.messages;

      debugPrint('TelegramChat: Loaded ${validMsgs.length} valid video items');

      // Dedupe & Merge with empty state (since it's initial load)
      final messageMap = <int, Map<String, dynamic>>{};
      for (final m in validMsgs) {
        messageMap[m['id'] as int] = m;
      }

      final sortedMessages = messageMap.values.toList()
        ..sort((a, b) {
          final dateA = a['date'] as int;
          final dateB = b['date'] as int;
          if (dateB != dateA) return dateB.compareTo(dateA);
          return (b['id'] as int).compareTo(a['id'] as int);
        });

      state = state.copyWith(
        messages: sortedMessages,
        isLoading: false,
        isLoadingMore: false,
        hasMore: _hasMoreVideos || _hasMoreDocs,
      );
    } catch (e) {
      debugPrint('TelegramChat: Error loading messages: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refreshMessages() async {
    await loadMessages(forceRefresh: true);
  }

  Future<void> loadMoreMessages() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) {
      return;
    }

    // Debounce/Protection against multiple calls
    if (state.isLoadingMore) return;

    debugPrint('TelegramChat: Loading more messages...');
    state = state.copyWith(isLoadingMore: true);

    try {
      final loadUseCase = ref.read(loadChatMessagesUseCaseProvider);

      // If we don't need to load more of anything, return early
      if (!_hasMoreVideos && !_hasMoreDocs) {
        state = state.copyWith(isLoadingMore: false, hasMore: false);
        return;
      }

      final result = await loadUseCase(
        LoadChatMessagesParams(
          chatId: chatId,
          messageThreadId: messageThreadId,
          // If a stream is exhausted, pass -1 to kill fetching that type
          nextVideoFromId: _hasMoreVideos ? _nextVideoFromId : -1,
          nextDocFromId: _hasMoreDocs ? _nextDocFromId : -1,
        ),
      );

      // Only update cursors if we requested them
      if (_hasMoreVideos) {
        _nextVideoFromId = result.nextVideoFromId;
        _hasMoreVideos = result.hasMoreVideos;
      }

      if (_hasMoreDocs) {
        _nextDocFromId = result.nextDocFromId;
        _hasMoreDocs = result.hasMoreDocs;
      }

      final validMsgs = result.messages;

      debugPrint('TelegramChat: Loaded ${validMsgs.length} more valid items');

      // Merge with existing
      final currentMessages = List<Map<String, dynamic>>.from(state.messages);
      for (final msg in validMsgs) {
        if (!_isMessageExists(msg['id'], list: currentMessages)) {
          currentMessages.add(msg);
        }
      }

      currentMessages.sort((a, b) {
        final dateA = a['date'] as int;
        final dateB = b['date'] as int;
        if (dateB != dateA) return dateB.compareTo(dateA);
        return (b['id'] as int).compareTo(a['id'] as int);
      });

      state = state.copyWith(
        messages: currentMessages,
        isLoadingMore: false,
        hasMore: _hasMoreVideos || _hasMoreDocs,
      );
    } catch (e) {
      debugPrint('TelegramChat: Error loading more: $e');
      state = state.copyWith(isLoadingMore: false, hasMore: false);
    }
  }
}
