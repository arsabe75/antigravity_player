import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../infrastructure/services/telegram_service.dart';
import '../../infrastructure/services/local_streaming_proxy.dart';

import 'state/telegram_content_state.dart';
export 'state/telegram_content_state.dart';

part 'telegram_content_notifier.g.dart';

@Riverpod(keepAlive: true)
class TelegramContent extends _$TelegramContent {
  late final TelegramService _service;
  final Map<int, Map<String, dynamic>> _bufferedChats = {}; // Buffer by Chat ID
  Timer? _debounceTimer;

  @override
  TelegramContentState build() {
    _service = TelegramService();
    // Use a broadcast stream or ensure single subscription appropriately
    final sub = _service.updates.listen(_handleUpdate);

    // Ensure we clean up the timer and subscription when the notifier is disposed
    ref.onDispose(() {
      _debounceTimer?.cancel();
      sub.cancel();
    });

    return TelegramContentState();
  }

  void _handleUpdate(Map<String, dynamic> update) {
    try {
      if (update['@type'] == 'updateNewChat') {
        final chat = update['chat'];
        final chatId = chat['id'];
        final photoId = chat['photo']?['small']?['id'];
        debugPrint(
          'TelegramContentNotifier: New Chat $chatId, PhotoID: $photoId',
        );

        // Add to buffer
        _bufferedChats[chatId] = chat;

        // Schedule update if not already scheduled
        _scheduleFlush();
      } else if (update['@type'] == 'chats') {
        // Response from getChats - contains list of chat_ids
        final chatIds = update['chat_ids'] as List? ?? [];
        debugPrint(
          'TelegramContentNotifier: getChats returned ${chatIds.length} chat IDs',
        );

        if (chatIds.isEmpty) {
          // No chats, stop loading
          state = state.copyWith(isLoading: false);
          _loadRetryCount = 0;
          return;
        }

        // Request full info for each chat
        for (final chatId in chatIds) {
          _service.send({'@type': 'getChat', 'chat_id': chatId});
        }
      } else if (update['@type'] == 'chat') {
        // Response from getChat - full chat object
        final chatId = update['id'];
        final photoId = update['photo']?['small']?['id'];
        debugPrint(
          'TelegramContentNotifier: Full Chat $chatId, PhotoID: $photoId',
        );
        _bufferedChats[chatId] = update;
        _scheduleFlush();
      } else if (update['@type'] == 'updateChatPosition') {
        final chatId = update['chat_id'];
        final newPosition = update['position'];

        Map<String, dynamic>? chatToUpdate;

        // Check buffer first
        if (_bufferedChats.containsKey(chatId)) {
          chatToUpdate = Map<String, dynamic>.from(_bufferedChats[chatId]!);
        } else {
          // Check current state
          try {
            final existing = state.chats.firstWhere((c) => c['id'] == chatId);
            chatToUpdate = Map<String, dynamic>.from(existing);
          } catch (_) {}
        }

        if (chatToUpdate != null) {
          // Update positions
          List<dynamic> positions = List.from(chatToUpdate['positions'] ?? []);

          if (newPosition['list'] != null) {
            // Remove old entry for this list type
            positions.removeWhere(
              (p) =>
                  p['list'] != null &&
                  p['list']['@type'] == newPosition['list']['@type'],
            );

            // Add new position if order is not 0
            final order = newPosition['order'];
            if (order != "0" && order != 0 && order != null) {
              positions.add(newPosition);
            }

            chatToUpdate['positions'] = positions;
            _bufferedChats[chatId] = chatToUpdate;
            _scheduleFlush();
          }
        }
      }
    } catch (e, st) {
      debugPrint('TelegramContentNotifier Error: $e\n$st');
    }
  }

  void _scheduleFlush() {
    if (_debounceTimer?.isActive != true) {
      _debounceTimer = Timer(const Duration(milliseconds: 200), _flushUpdates);
    }
  }

  void _flushUpdates() {
    if (_bufferedChats.isEmpty) {
      // Even if no updates, if we were loading and time passed, maybe stop loading?
      // But usually flush is only called if buffered chats exist.
      return;
    }

    final currentChats = List<Map<String, dynamic>>.from(state.chats);

    for (final chat in _bufferedChats.values) {
      final index = currentChats.indexWhere((c) => c['id'] == chat['id']);
      if (index == -1) {
        currentChats.add(chat);
      } else {
        currentChats[index] = chat;
      }
    }

    // Sort chats by order in Main List
    try {
      currentChats.sort((a, b) {
        return _getChatOrder(b).compareTo(_getChatOrder(a));
      });
    } catch (_) {}

    state = state.copyWith(chats: currentChats, isLoading: false);
    _bufferedChats.clear();
  }

  BigInt _getChatOrder(Map<String, dynamic> chat) {
    try {
      final positions = chat['positions'] as List<dynamic>? ?? [];
      for (final pos in positions) {
        if (pos['list'] != null && pos['list']['@type'] == 'chatListMain') {
          final order = pos['order'];
          if (order is String) return BigInt.tryParse(order) ?? BigInt.zero;
          if (order is int) return BigInt.from(order);
        }
      }
    } catch (_) {}
    return BigInt.zero;
  }

  int _loadRetryCount = 0;
  static const int _maxLoadRetries = 3;

  void loadChats() {
    state = state.copyWith(isLoading: true);
    debugPrint(
      'TelegramContentNotifier: Loading chats (attempt ${_loadRetryCount + 1})...',
    );

    // Request getting chats with higher limit
    // TDLib will send updates via updateNewChat for each chat
    _service.send({
      '@type': 'getChats',
      'chat_list': {'@type': 'chatListMain'},
      'limit': 200, // Increased limit to get more chats
    });

    // Safety timeout - if no chats arrived, retry
    Future.delayed(const Duration(seconds: 5), () {
      try {
        if (state.isLoading &&
            state.chats.isEmpty &&
            _loadRetryCount < _maxLoadRetries) {
          _loadRetryCount++;
          debugPrint(
            'TelegramContentNotifier: No chats received, retrying ($_loadRetryCount/$_maxLoadRetries)...',
          );
          loadChats();
        } else if (state.isLoading) {
          // Final timeout - stop loading even if no chats
          state = state.copyWith(isLoading: false);
          _loadRetryCount = 0;
        }
      } catch (_) {
        // Notifier likely disposed
      }
    });
  }

  /// Force reload chats from server, clearing the current state
  void reloadChats() {
    _loadRetryCount = 0;
    _bufferedChats.clear();
    state = TelegramContentState(isLoading: true);
    loadChats();
  }

  // Method to start streaming a file
  // Returns the Proxy URL for the video player
  // fileId is the TDLib internal file ID
  Future<String> getStreamUrl(int fileId, int size) async {
    // Logic handled in Proxy, we just return the URL
    // But we need to make sure the file is "known" to TDLib (download started or at least file info loaded)
    // The Proxy calls downloadFile which triggers it.

    return LocalStreamingProxy().getUrl(fileId, size);
  }
}
