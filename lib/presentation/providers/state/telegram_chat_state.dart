import 'package:freezed_annotation/freezed_annotation.dart';

part 'telegram_chat_state.freezed.dart';

/// State for Telegram chat messages
@freezed
abstract class TelegramChatState with _$TelegramChatState {
  const factory TelegramChatState({
    @Default([]) List<Map<String, dynamic>> messages,
    @Default(false) bool isLoading,
    @Default(false) bool isLoadingMore,
    @Default(true) bool hasMore,
    String? error,
  }) = _TelegramChatState;
}

/// Parameters for TelegramChat provider (used as family key)
@freezed
abstract class TelegramChatParams with _$TelegramChatParams {
  const factory TelegramChatParams({
    required int chatId,
    int? messageThreadId,
  }) = _TelegramChatParams;
}
