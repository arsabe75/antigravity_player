import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../infrastructure/services/telegram_service.dart';

part 'telegram_chat_notifier.g.dart';

class TelegramChatState {
  final List<Map<String, dynamic>> messages;
  final bool isLoading;
  final String? error;

  TelegramChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  TelegramChatState copyWith({
    List<Map<String, dynamic>>? messages,
    bool? isLoading,
    String? error,
  }) {
    return TelegramChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

@riverpod
class TelegramChatNotifier extends _$TelegramChatNotifier {
  late final TelegramService _service;

  @override
  TelegramChatState build(int chatId) {
    _service = TelegramService();
    _service.updates.listen(_handleUpdate);
    loadMessages();
    return TelegramChatState(isLoading: true);
  }

  void _handleUpdate(Map<String, dynamic> update) {
    if (update['@type'] == 'updateNewMessage') {
      final message = update['message'];
      if (message['chat_id'] == chatId) {
        // Prepend new message
        final currentMessages = List<Map<String, dynamic>>.from(state.messages);
        if (!currentMessages.any((m) => m['id'] == message['id'])) {
          currentMessages.insert(0, message);
          state = state.copyWith(messages: currentMessages);
        }
      }
    } else if (update['@type'] == 'messages') {
      final msgs = (update['messages'] as List).cast<Map<String, dynamic>>();
      if (msgs.isNotEmpty && msgs.first['chat_id'] == chatId) {
        state = state.copyWith(messages: msgs, isLoading: false);
      }
    }
  }

  Future<void> loadMessages() async {
    _service.send({
      '@type': 'getChatHistory',
      'chat_id': chatId,
      'from_message_id': 0,
      'offset': 0,
      'limit': 50,
      'only_local': false,
    });
  }
}
