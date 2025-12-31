import 'package:freezed_annotation/freezed_annotation.dart';

part 'telegram_auth_state.freezed.dart';

/// Authentication states for Telegram
enum AuthState {
  initial,
  waitPhoneNumber,
  waitCode,
  waitPassword,
  ready,
  closed,
  error,
}

/// State for Telegram authentication process
@freezed
abstract class TelegramAuthState with _$TelegramAuthState {
  const factory TelegramAuthState({
    @Default(AuthState.initial) AuthState list,
    String? error,
    @Default(false) bool isLoading,
  }) = _TelegramAuthState;
}
