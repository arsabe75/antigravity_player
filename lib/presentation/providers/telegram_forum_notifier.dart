import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../infrastructure/services/telegram_service.dart';

part 'telegram_forum_notifier.g.dart';

class TelegramForumState {
  final List<Map<String, dynamic>> topics;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  const TelegramForumState({
    this.topics = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  TelegramForumState copyWith({
    List<Map<String, dynamic>>? topics,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
  }) {
    return TelegramForumState(
      topics: topics ?? this.topics,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

@Riverpod(keepAlive: true)
class TelegramForum extends _$TelegramForum {
  late final TelegramService _service;

  // Pagination cursors - track server-side order
  int _lastOffsetDate = 0;
  int _lastOffsetMessageId = 0;
  int _lastOffsetMessageThreadId = 0;

  @override
  TelegramForumState build(int chatId) {
    _service = TelegramService();
    final sub = _service.updates.listen(_handleUpdate);
    ref.onDispose(() {
      sub.cancel();
      _service.send({'@type': 'closeChat', 'chat_id': chatId});
    });

    _service.send({'@type': 'openChat', 'chat_id': chatId});

    // Defer loading to avoid modifying state during build
    Future.microtask(() => loadTopics());

    return const TelegramForumState(isLoading: true);
  }

  // chatId getter is provided by generated code (_$TelegramForum)
  void _handleUpdate(Map<String, dynamic> update) {
    // Guard against disposed provider
    if (!ref.mounted) return;
    try {
      if (update['@type'] == 'forumTopics') {
        final topicsData = update['topics'] as List? ?? [];
        final totalCount = update['total_count'] as int? ?? 0;

        debugPrint(
          'TelegramForum: Received ${topicsData.length} topics (total: $totalCount)',
        );

        if (topicsData.isEmpty) {
          if (state.isLoadingMore) {
            state = state.copyWith(isLoadingMore: false, hasMore: false);
          } else if (state.isLoading) {
            state = state.copyWith(isLoading: false, hasMore: false);
          }
          return;
        }

        // UPDATE CURSORS from the LAST received topic (Server Order)
        final lastTopicInBatch = topicsData.last as Map<String, dynamic>;
        final lastInfo = lastTopicInBatch['info'] as Map<String, dynamic>?;
        final lastMsg =
            lastTopicInBatch['last_message'] as Map<String, dynamic>?;

        _lastOffsetDate = lastMsg?['date'] as int? ?? 0;
        _lastOffsetMessageId = lastMsg?['id'] as int? ?? 0;
        _lastOffsetMessageThreadId =
            lastInfo?['message_thread_id'] as int? ?? 0;

        final topics = topicsData
            .map((t) => t as Map<String, dynamic>)
            .toList();

        // Merge topics - handle both direct and nested info structures
        final currentTopics = List<Map<String, dynamic>>.from(state.topics);

        for (final topic in topics) {
          // TDLib forumTopic structure: { info: {...}, last_message: {...}, ... }
          final topicInfo = topic['info'] as Map<String, dynamic>?;
          if (topicInfo == null) {
            continue;
          }

          // TDLib uses 'forum_topic_id' as the thread identifier
          final topicId = topicInfo['forum_topic_id'];
          if (topicId == null) {
            continue;
          }

          final index = currentTopics.indexWhere((t) {
            final info = t['info'] as Map<String, dynamic>?;
            return info?['forum_topic_id'] == topicId;
          });

          if (index == -1) {
            currentTopics.add(topic);
          } else {
            currentTopics[index] = topic;
          }
        }

        debugPrint('TelegramForum: Loaded ${currentTopics.length} topics');

        // Sort by order (descending - higher order first)
        currentTopics.sort((a, b) {
          // Pinned topics first
          final aPinned = a['is_pinned'] == true ? 1 : 0;
          final bPinned = b['is_pinned'] == true ? 1 : 0;
          if (aPinned != bPinned) return bPinned - aPinned;

          // Then by order
          final aOrder =
              BigInt.tryParse(a['order']?.toString() ?? '0') ?? BigInt.zero;
          final bOrder =
              BigInt.tryParse(b['order']?.toString() ?? '0') ?? BigInt.zero;
          return bOrder.compareTo(aOrder);
        });

        state = state.copyWith(
          topics: currentTopics,
          isLoading: false,
          isLoadingMore: false,
          hasMore: topics.length >= 50,
        );
      } else if (update['@type'] == 'updateForumTopicInfo') {
        final chatIdUpdate = update['chat_id'];
        if (chatIdUpdate != chatId) return;

        final topicInfo = update['info'] as Map<String, dynamic>?;
        if (topicInfo == null) return;

        final topicId = topicInfo['forum_topic_id'];
        final currentTopics = List<Map<String, dynamic>>.from(state.topics);
        final index = currentTopics.indexWhere((t) {
          final info = t['info'] as Map<String, dynamic>?;
          return info?['forum_topic_id'] == topicId;
        });

        if (index != -1) {
          currentTopics[index] = {...currentTopics[index], 'info': topicInfo};
          state = state.copyWith(topics: currentTopics);
        }
      } else if (update['@type'] == 'updateNewMessage') {
        final message = update['message'] as Map<String, dynamic>?;
        if (message == null || message['chat_id'] != chatId) return;

        int? topicId = message['message_thread_id'] as int?;
        if (topicId == null && message.containsKey('topic_id')) {
          final topicObj = message['topic_id'];
          if (topicObj is Map) {
            topicId = topicObj['forum_topic_id'] as int?;
          } else if (topicObj is int) {
            topicId = topicObj;
          }
        }

        // debugPrint('Forum LiveUpdate: extracted topicId=$topicId');
        if (topicId == null || topicId == 0) return;

        final currentTopics = List<Map<String, dynamic>>.from(state.topics);
        final index = currentTopics.indexWhere((t) {
          final info = t['info'] as Map<String, dynamic>?;
          return info?['forum_topic_id'] == topicId;
        });

        if (index != -1) {
          final topic = Map<String, dynamic>.from(currentTopics[index]);
          topic['last_message'] = message;

          // Find max order among unpinned topics to bump this topic to the top
          BigInt maxOrder = BigInt.zero;
          for (final t in currentTopics) {
            if (t['is_pinned'] == true) continue;
            final orderStr = t['order']?.toString() ?? '0';
            final order = BigInt.tryParse(orderStr) ?? BigInt.zero;
            if (order > maxOrder) maxOrder = order;
          }

          // Increment the order
          topic['order'] = (maxOrder + BigInt.one).toString();

          currentTopics[index] = topic;

          // Re-sort currentTopics
          currentTopics.sort((a, b) {
            final aPinned = a['is_pinned'] == true ? 1 : 0;
            final bPinned = b['is_pinned'] == true ? 1 : 0;
            if (aPinned != bPinned) return bPinned - aPinned;

            final aOrderStr = a['order']?.toString() ?? '0';
            final bOrderStr = b['order']?.toString() ?? '0';
            final aOrder = BigInt.tryParse(aOrderStr) ?? BigInt.zero;
            final bOrder = BigInt.tryParse(bOrderStr) ?? BigInt.zero;
            return bOrder.compareTo(aOrder);
          });

          state = state.copyWith(topics: currentTopics);
        }
      } else if (update['@type'] == 'updateDeleteMessages') {
        if (update['chat_id'] == chatId) {
          final messageIdsList = update['message_ids'] as List?;
          if (messageIdsList != null && messageIdsList.isNotEmpty) {
            final deletedIds = messageIdsList.cast<int>().toSet();
            final updatedTopics = state.topics.where((t) {
              final info = t['info'] as Map<String, dynamic>?;
              final topicId = info?['forum_topic_id'] as int?;
              if (topicId == null) return true;
              // In TDLib for supergroups, the message ID of a topic is its topicId * 2^20
              final topicMessageId = topicId * 1048576;
              return !deletedIds.contains(topicId) &&
                  !deletedIds.contains(topicMessageId);
            }).toList();

            if (updatedTopics.length != state.topics.length) {
              state = state.copyWith(topics: updatedTopics);
            }
          }
        }
      }
    } catch (e, st) {
      debugPrint('TelegramForum Error: $e\n$st');
    }
  }

  Future<void> loadTopics() async {
    try {
      // Reset cursors
      _lastOffsetDate = 0;
      _lastOffsetMessageId = 0;
      _lastOffsetMessageThreadId = 0;

      state = state.copyWith(
        isLoading: true,
        topics: [],
      ); // Clear prev topics on fresh load
      debugPrint('TelegramForum: Loading topics for chat $chatId');

      _service.send({
        '@type': 'getForumTopics',
        'chat_id': chatId,
        'query': '',
        'offset_date': 0,
        'offset_message_id': 0,
        'offset_message_thread_id': 0,
        'limit': 50,
      });

      // Safety timeout
      Future.delayed(const Duration(seconds: 10), () {
        try {
          if (state.isLoading) {
            state = state.copyWith(isLoading: false, hasMore: false);
          }
        } catch (_) {
          // Notifier disposed
        }
      });
    } catch (e) {
      debugPrint('TelegramForum: Error loading topics: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refreshTopics() async {
    state = const TelegramForumState(isLoading: true);
    await loadTopics();
  }

  Future<void> loadMoreTopics() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) {
      return;
    }

    state = state.copyWith(isLoadingMore: true);
    debugPrint('TelegramForum: Loading more topics...');

    _service.send({
      '@type': 'getForumTopics',
      'chat_id': chatId,
      'query': '',
      'offset_date': _lastOffsetDate,
      'offset_message_id': _lastOffsetMessageId,
      'offset_message_thread_id': _lastOffsetMessageThreadId,
      'limit': 50,
    });
  }
}
