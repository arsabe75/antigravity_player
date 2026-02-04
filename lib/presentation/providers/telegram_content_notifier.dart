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

  // Pagination Cursors
  BigInt _lastMainOrder = BigInt.from(9223372036854775807); // Max int64
  BigInt _lastArchiveOrder = BigInt.from(9223372036854775807); // Max int64
  bool _hasMoreMain = true;
  bool _hasMoreArchive = true;

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
    // Guard against disposed provider
    if (!ref.mounted) return;
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
          // No chats, stop loading for this specific list?
          // We don't know WHICH list was empty from just 'chats' update unless we track requests.
          // But usually empty means end of list.
          // Since we request both, we might need a better way.
          // For now, if we receive 0 chats, we assume NO MORE for that direction.
          // Ideally we would inspect the request ID if TDLib passed it back, but it doesn't in update.

          // Heuristic: If we were loading more, and got 0, stop loading more.
          if (state.isLoadingMore) {
            // We can't distinguish Main vs Archive easily here without complex tracking.
            // But usually if one runs out, we might still have the other.
            // We'll rely on the flush update heuristic or timeout.
          } else {
            state = state.copyWith(isLoading: false);
          }
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
    // Guard against disposed provider
    if (!ref.mounted) return;
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

    // Sort chats by order: Main List first, then Archive
    try {
      currentChats.sort((a, b) {
        final orderMainA = _getChatOrder(a, 'chatListMain');
        final orderMainB = _getChatOrder(b, 'chatListMain');

        final inMainA = orderMainA != BigInt.zero;
        final inMainB = orderMainB != BigInt.zero;

        // 1. Both in Main: Sort by Main order
        if (inMainA && inMainB) {
          return orderMainB.compareTo(orderMainA);
        }

        // 2. A in Main, B not: A comes first
        if (inMainA && !inMainB) {
          return -1;
        }

        // 3. B in Main, A not: B comes first
        if (!inMainA && inMainB) {
          return 1;
        }

        // 4. Neither in Main (Both likely Archive): Sort by Archive order
        final orderArchA = _getChatOrder(a, 'chatListArchive');
        final orderArchB = _getChatOrder(b, 'chatListArchive');
        return orderArchB.compareTo(orderArchA);
      });
    } catch (_) {}

    // Filter out chats that are not in either list (order 0 in both)
    final filteredChats = currentChats.where((chat) {
      final orderMain = _getChatOrder(chat, 'chatListMain');
      final orderArch = _getChatOrder(chat, 'chatListArchive');
      return orderMain != BigInt.zero || orderArch != BigInt.zero;
    }).toList();

    // Update Pagination Cursors based on the LAST chat in each list found
    // This is an approximation. Ideally we track what getChats returns.
    // However, getChats returns IDs via updates. We can scan the sorted list.

    // Find last Main order
    BigInt lowestMain = _lastMainOrder;
    BigInt lowestArch = _lastArchiveOrder;

    for (var c in filteredChats.reversed) {
      final om = _getChatOrder(c, 'chatListMain');
      if (om != BigInt.zero && om < lowestMain) lowestMain = om;

      final oa = _getChatOrder(c, 'chatListArchive');
      if (oa != BigInt.zero && oa < lowestArch) lowestArch = oa;
    }

    // Only update if we received new items (simple heuristic since TDLib doesn't signal "end of page" easily in update stream)
    // Actually, getChats sends a 'chats' update. Using that to detect end is safer.
    // See _handleUpdate 'chats' section.

    if (_bufferedChats.isEmpty) {
      // Flush complete
      _lastMainOrder = lowestMain;
      _lastArchiveOrder = lowestArch;
    }

    state = state.copyWith(
      chats: filteredChats,
      isLoading: false,
      isLoadingMore: false,
    );
    _bufferedChats.clear();
  }

  BigInt _getChatOrder(Map<String, dynamic> chat, String listType) {
    try {
      final positions = chat['positions'] as List<dynamic>? ?? [];
      for (final pos in positions) {
        if (pos['list'] != null && pos['list']['@type'] == listType) {
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
    // Reset Pagination
    _lastMainOrder = BigInt.from(9223372036854775807);
    _lastArchiveOrder = BigInt.from(9223372036854775807);
    _hasMoreMain = true;
    _hasMoreArchive = true;

    state = state.copyWith(isLoading: true, hasMore: true, chats: []);
    debugPrint(
      'TelegramContentNotifier: Loading chats (attempt ${_loadRetryCount + 1})...',
    );

    // Request getting chats with higher limit
    // TDLib will send updates via updateNewChat for each chat

    // 1. Request Main List
    _service.send({
      '@type': 'getChats',
      'chat_list': {'@type': 'chatListMain'},
      'limit': 50, // Initial batch
    });

    // 2. Request Archive List
    _service.send({
      '@type': 'getChats',
      'chat_list': {'@type': 'chatListArchive'},
      'limit': 50, // Initial batch
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

  /// Load next page of chats
  void loadMoreChats() {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);
    debugPrint('TelegramContentNotifier: Loading MORE chats...');

    // 1. Request Main List (Next Batch)
    if (_hasMoreMain) {
      _service.send({
        '@type': 'getChats',
        'chat_list': {'@type': 'chatListMain'},
        'offset_order': _lastMainOrder.toString(),
        'limit': 50,
      });
    }

    // 2. Request Archive List (Next Batch)
    if (_hasMoreArchive) {
      // NOTE: Archive often starts after Main is done, but we load concurrently for now
      _service.send({
        '@type': 'getChats',
        'chat_list': {'@type': 'chatListArchive'},
        'offset_order': _lastArchiveOrder.toString(),
        'limit': 50,
      });
    }

    // If no more in both, set hasMore = false
    if (!_hasMoreMain && !_hasMoreArchive) {
      state = state.copyWith(isLoadingMore: false, hasMore: false);
    }
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
