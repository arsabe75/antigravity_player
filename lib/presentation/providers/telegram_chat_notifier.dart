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

  TelegramChatState({
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

@Riverpod(keepAlive: true)
class TelegramChatNotifier extends _$TelegramChatNotifier {
  late final TelegramService _service;
  int _retryCount = 0;
  // Track the last request to avoid race conditions or interpret responses correctly?
  // Since we rely on the stream, we just assume incoming 'messages' for this chat are relevant.

  @override
  TelegramChatState build(int chatId) {
    _service = TelegramService();
    // subscription is managed by Riverpod's ref.onDispose if we returned a stream,
    // but here we listen manually. We should cancel it.
    final sub = _service.updates.listen(_handleUpdate);
    ref.onDispose(() => sub.cancel());

    // Defer loading to avoid modifying state during build
    Future.microtask(() => loadMessages());

    return TelegramChatState(isLoading: true);
  }

  void _handleUpdate(Map<String, dynamic> update) {
    // Trace update type for debugging flow
    // debugPrint('TelegramChatNotifier: Update received: ${update['@type']}');
    try {
      if (update['@type'] == 'updateNewMessage') {
        final message = update['message'];
        if (message['chat_id'] == chatId) {
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
      } else if (update['@type'] == 'messages') {
        final msgs = (update['messages'] as List).cast<Map<String, dynamic>>();
        if (msgs.isEmpty || msgs.length <= 1) {
          // If we were loading more and got 0 (or just 1 dummy), then no more messages.
          if (state.isLoadingMore) {
            state = state.copyWith(isLoadingMore: false, hasMore: false);
          } else if (state.isLoading) {
            // Initial load empty OR very few messages (likely just "created" date or service message)
            // This might be because TDLib hasn't synced yet.
            // We'll try up to 3 retries (2s, 4s, 6s)
            if (_retryCount < 3) {
              _retryCount++;
              final delay = _retryCount * 2;
              debugPrint(
                'TelegramChatNotifier: Initial load empty, retry $_retryCount/3 in ${delay}s...',
              );
              Future.delayed(Duration(seconds: delay), () {
                loadMessages();
              });
              return; // Maintain loading state
            }
            state = state.copyWith(isLoading: false, hasMore: false);
          }
          return;
        }

        // If we got messages, reset retry count
        _retryCount = 0;

        // Check if these messages belong to this chat
        if (msgs.first['chat_id'] != chatId) {
          return;
        }

        // Merge messages
        final currentMessages = List<Map<String, dynamic>>.from(state.messages);

        for (final msg in msgs) {
          if (!_isMessageExists(msg['id'], list: currentMessages)) {
            currentMessages.add(msg);
          }
        }

        // Sort by id descending (assuming larger ID is newer, which is generally true for TG,
        // but date is safer. However, standard TG id is sortable).
        // Actually, let's sort by date then ID to be safe.
        currentMessages.sort((a, b) {
          final dateA = a['date'] as int;
          final dateB = b['date'] as int;
          if (dateB != dateA) return dateB.compareTo(dateA);
          return (b['id'] as int).compareTo(a['id'] as int);
        });

        debugPrint(
          'TelegramChatNotifier: Loaded ${currentMessages.length} messages (hasMore: ${msgs.length >= 20})',
        );
        state = state.copyWith(
          messages: currentMessages,
          isLoading: false,
          isLoadingMore: false,
          hasMore:
              msgs.length >= 20, // If we got fewer than limit, probably end.
        );
      }
    } catch (e) {
      debugPrint('TelegramChatNotifier Error: $e');
    }
  }

  bool _isMessageExists(int id, {List<Map<String, dynamic>>? list}) {
    final l = list ?? state.messages;
    return l.any((m) => m['id'] == id);
  }

  /// Loads messages from chat history.
  /// Set [forceRefresh] to true to clear existing messages before loading.
  Future<void> loadMessages({bool forceRefresh = false}) async {
    try {
      // Only clear messages if explicitly requested (manual refresh)
      if (forceRefresh) {
        state = state.copyWith(isLoading: true, messages: []);
      } else {
        state = state.copyWith(isLoading: true);
      }
      _service.send({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': 0,
        'offset': 0,
        'limit': 100,
        'only_local': false,
      });
    } catch (e) {
      if (e.toString().contains('StateError') ||
          e.toString().contains('disposed')) {
        // Ignore state errors if notifier is disposed
        return;
      }
      debugPrint('TelegramChatNotifier: Error loading messages: $e');
    }
  }

  /// Forces a full refresh, clearing cached messages first.
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

    debugPrint('TelegramChatNotifier: Loading more messages...');
    state = state.copyWith(isLoadingMore: true);

    final lastMessageId = state.messages.last['id'];

    _service.send({
      '@type': 'getChatHistory',
      'chat_id': chatId,
      'from_message_id': lastMessageId,
      'offset': 0,
      'limit': 100, // Increased limit
      'only_local': false,
    });
  }
}
