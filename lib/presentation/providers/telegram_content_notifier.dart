import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../infrastructure/services/telegram_service.dart';

class TelegramContentState {
  final List<Map<String, dynamic>> chats;
  final bool isLoading;
  final String? error;

  TelegramContentState({
    this.chats = const [],
    this.isLoading = false,
    this.error,
  });

  TelegramContentState copyWith({
    List<Map<String, dynamic>>? chats,
    bool? isLoading,
    String? error,
  }) {
    return TelegramContentState(
      chats: chats ?? this.chats,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class TelegramContentNotifier extends Notifier<TelegramContentState> {
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
    if (update['@type'] == 'updateNewChat') {
      final chat = update['chat'];
      final chatId = chat['id'];

      // Add to buffer
      _bufferedChats[chatId] = chat;

      // Schedule update if not already scheduled
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
        // Remove old entry for this list type
        positions.removeWhere(
          (p) => p['list']['@type'] == newPosition['list']['@type'],
        );

        // Add new position if order is not 0 (0 means removed from list)
        // order can be string or int from JSON
        final order = newPosition['order'];
        if (order != "0" && order != 0) {
          positions.add(newPosition);
        }

        chatToUpdate['positions'] = positions;
        _bufferedChats[chatId] = chatToUpdate;
        _scheduleFlush();
      }
    }
  }

  void _scheduleFlush() {
    if (_debounceTimer?.isActive != true) {
      _debounceTimer = Timer(const Duration(milliseconds: 200), _flushUpdates);
    }
  }

  void _flushUpdates() {
    if (_bufferedChats.isEmpty) return;

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
    currentChats.sort((a, b) {
      return _getChatOrder(b).compareTo(_getChatOrder(a));
    });

    state = state.copyWith(chats: currentChats);
    _bufferedChats.clear();
  }

  BigInt _getChatOrder(Map<String, dynamic> chat) {
    final positions = chat['positions'] as List<dynamic>? ?? [];
    for (final pos in positions) {
      if (pos['list']['@type'] == 'chatListMain') {
        final order = pos['order'];
        if (order is String) return BigInt.tryParse(order) ?? BigInt.zero;
        if (order is int) return BigInt.from(order);
      }
    }
    return BigInt.zero;
  }

  void loadChats() {
    state = state.copyWith(isLoading: true);
    print('TelegramContentNotifier: Loading chats...'); // DEBUG
    // Request getting chats. TDLib will send updates.
    // limiting to 50 for now
    _service.send({
      '@type': 'getChats',
      'chat_list': {'@type': 'chatListMain'}, // Main list object
      'limit': 50,
    });
  }

  // Method to start streaming a file
  // Returns the Proxy URL for the video player
  // fileId is the TDLib internal file ID
  Future<String> getStreamUrl(int fileId, int size) async {
    // Logic handled in Proxy, we just return the URL
    // But we need to make sure the file is "known" to TDLib (download started or at least file info loaded)
    // The Proxy calls downloadFile which triggers it.

    return 'http://127.0.0.1:0/stream?file_id=$fileId&size=$size'; // Port is dynamic, need access to Proxy singleton
  }
}

final telegramContentProvider =
    NotifierProvider<TelegramContentNotifier, TelegramContentState>(
      TelegramContentNotifier.new,
    );
