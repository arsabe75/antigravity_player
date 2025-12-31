import 'package:freezed_annotation/freezed_annotation.dart';

part 'telegram_content_state.freezed.dart';

/// State for Telegram content (chat list)
@freezed
abstract class TelegramContentState with _$TelegramContentState {
  const factory TelegramContentState({
    @Default([]) List<Map<String, dynamic>> chats,
    @Default(false) bool isLoading,
    String? error,
  }) = _TelegramContentState;
}
