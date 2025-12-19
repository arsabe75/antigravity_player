import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../infrastructure/services/telegram_service.dart';

part 'telegram_chat_notifier.g.dart';

class TelegramChatState {
  final List<Map<String, dynamic>> messages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  const TelegramChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  TelegramChatState copyWith({
    List<Map<String, dynamic>>? messages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
  }) {
    return TelegramChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

/// Parameters for TelegramChatNotifier
/// Supports both regular chats and forum topic threads
class TelegramChatParams {
  final int chatId;
  final int? messageThreadId; // For forum topics

  const TelegramChatParams({required this.chatId, this.messageThreadId});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TelegramChatParams &&
        other.chatId == chatId &&
        other.messageThreadId == messageThreadId;
  }

  @override
  int get hashCode => Object.hash(chatId, messageThreadId);

  @override
  String toString() =>
      'TelegramChatParams(chatId: $chatId, threadId: $messageThreadId)';
}

@Riverpod(keepAlive: true)
class TelegramChat extends _$TelegramChat {
  late final TelegramService _service;
  int _retryCount = 0;

  @override
  TelegramChatState build(TelegramChatParams params) {
    _service = TelegramService();
    final sub = _service.updates.listen(_handleUpdate);
    ref.onDispose(() => sub.cancel());

    // Defer loading to avoid modifying state during build
    Future.microtask(() => loadMessages());

    return const TelegramChatState(isLoading: true);
  }

  int get chatId => params.chatId;
  int? get messageThreadId => params.messageThreadId;

  void _handleUpdate(Map<String, dynamic> update) {
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
          error: update['message'] as String?,
        );
        return;
      }

      if (updateType == 'updateNewMessage') {
        final message = update['message'];
        if (message['chat_id'] == chatId) {
          // For thread messages, check message_thread_id
          if (messageThreadId != null) {
            final msgThreadId = message['message_thread_id'] as int?;
            if (msgThreadId != messageThreadId) return;
          }

          if (_isMessageExists(message['id'])) {
            return;
          }

          // Prepend new message (live update)
          final currentMessages = List<Map<String, dynamic>>.from(
            state.messages,
          );
          currentMessages.insert(0, message);
          state = state.copyWith(messages: currentMessages);
        }
      } else if (updateType == 'messages') {
        final msgs = (update['messages'] as List).cast<Map<String, dynamic>>();
        debugPrint(
          'TelegramChat[$chatId/${messageThreadId ?? "main"}]: Received ${msgs.length} messages',
        );
        if (msgs.isEmpty || msgs.length <= 1) {
          if (state.isLoadingMore) {
            state = state.copyWith(isLoadingMore: false, hasMore: false);
          } else if (state.isLoading) {
            if (_retryCount < 3) {
              _retryCount++;
              final delay = _retryCount * 2;
              debugPrint(
                'TelegramChat: Initial load empty, retry $_retryCount/3 in ${delay}s...',
              );
              Future.delayed(Duration(seconds: delay), () {
                loadMessages();
              });
              return;
            }
            state = state.copyWith(isLoading: false, hasMore: false);
          }
          return;
        }

        _retryCount = 0;

        if (msgs.first['chat_id'] != chatId) {
          return;
        }

        // Note: For forum topics, messages come via foundChatMessages response
        // This handler is for regular chats using getChatHistory

        // Merge messages
        final currentMessages = List<Map<String, dynamic>>.from(state.messages);

        for (final msg in msgs) {
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

        debugPrint(
          'TelegramChat: Loaded ${currentMessages.length} messages (hasMore: ${msgs.length >= 20})',
        );
        state = state.copyWith(
          messages: currentMessages,
          isLoading: false,
          isLoadingMore: false,
          hasMore: msgs.length >= 20,
        );
      } else if (updateType == 'foundChatMessages') {
        // Response from searchChatMessages
        final msgsList = update['messages'] as List?;

        if (msgsList == null || msgsList.isEmpty) {
          state = state.copyWith(
            isLoading: false,
            isLoadingMore: false,
            hasMore: false,
          );
          return;
        }

        final msgs = msgsList.cast<Map<String, dynamic>>();

        // Verify messages belong to this chat
        if (msgs.first['chat_id'] != chatId) {
          return; // Messages for different chat, ignore
        }

        // TDLib returns @extra in the response matching what we sent
        if (messageThreadId != null) {
          final extra = update['@extra'] as String?;
          final expectedExtra = 'topic_$messageThreadId';

          if (extra != expectedExtra) {
            return; // Response for different topic
          }
        }

        debugPrint('TelegramChat: Loaded ${msgs.length} messages');

        _retryCount = 0;

        final currentMessages = List<Map<String, dynamic>>.from(state.messages);

        for (final msg in msgs) {
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
          isLoading: false,
          isLoadingMore: false,
          hasMore: msgs.length >= 20,
        );
      }
    } catch (e) {
      debugPrint('TelegramChat Error: $e');
    }
  }

  bool _isMessageExists(int id, {List<Map<String, dynamic>>? list}) {
    final l = list ?? state.messages;
    return l.any((m) => m['id'] == id);
  }

  Future<void> loadMessages({bool forceRefresh = false}) async {
    try {
      if (forceRefresh) {
        state = state.copyWith(isLoading: true, messages: []);
      } else {
        state = state.copyWith(isLoading: true);
      }

      if (messageThreadId != null) {
        // For forum topics, use searchChatMessages with topic_id
        // Use @extra to identify this request when receiving the response
        debugPrint(
          'TelegramChat: Searching messages for forum topic chat=$chatId, topic=$messageThreadId',
        );
        _service.send({
          '@type': 'searchChatMessages',
          'chat_id': chatId,
          'topic_id': {
            '@type': 'messageTopicForum',
            'forum_topic_id': messageThreadId,
          },
          'query': '',
          'sender_id': null,
          'from_message_id': 0,
          'offset': 0,
          'limit': 100,
          'filter': null,
          '@extra': 'topic_$messageThreadId', // Identifier for this request
        });
      } else {
        _service.send({
          '@type': 'getChatHistory',
          'chat_id': chatId,
          'from_message_id': 0,
          'offset': 0,
          'limit': 100,
          'only_local': false,
        });
      }
    } catch (e) {
      if (e.toString().contains('StateError') ||
          e.toString().contains('disposed')) {
        return;
      }
      debugPrint('TelegramChat: Error loading messages: $e');
    }
  }

  Future<void> refreshMessages() async {
    _retryCount = 0;
    await loadMessages(forceRefresh: true);
  }

  Future<void> loadMoreMessages() async {
    if (state.isLoading ||
        state.isLoadingMore ||
        !state.hasMore ||
        state.messages.isEmpty) {
      return;
    }

    debugPrint('TelegramChat: Loading more messages...');
    state = state.copyWith(isLoadingMore: true);

    final lastMessageId = state.messages.last['id'];

    if (messageThreadId != null) {
      _service.send({
        '@type': 'getMessageThreadHistory',
        'chat_id': chatId,
        'message_id': messageThreadId,
        'from_message_id': lastMessageId,
        'offset': 0,
        'limit': 100,
      });
    } else {
      _service.send({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': lastMessageId,
        'offset': 0,
        'limit': 100,
        'only_local': false,
      });
    }
  }
}
