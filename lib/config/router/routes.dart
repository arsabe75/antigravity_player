import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/screens/home_screen.dart';
import '../../presentation/screens/player_screen.dart';
import '../../presentation/screens/telegram_screen.dart';
import '../../presentation/screens/telegram_selection_screen.dart';
import '../../presentation/screens/telegram_storage_screen.dart';
import '../../presentation/screens/telegram_topics_screen.dart';
import '../../presentation/screens/telegram_chat_screen.dart';
import '../../presentation/screens/playlist_manager_screen.dart';

part 'routes.g.dart';

// ============================================================================
// Type-Safe Routes using go_router_builder 4.x
// Each class must use the generated mixin (e.g., with $HomeRoute)
// ============================================================================

/// Home Route - Main entry point
@TypedGoRoute<HomeRoute>(path: '/')
class HomeRoute extends GoRouteData with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const HomeScreen();
  }
}

/// Player Route Data - passed via $extra to avoid URL encoding issues
class PlayerRouteExtra {
  const PlayerRouteExtra({
    this.url,
    this.title,
    this.telegramChatId,
    this.telegramMessageId,
    this.telegramFileSize,
    this.telegramTopicId,
    this.telegramTopicName,
  });

  final String? url;
  final String? title;
  final int? telegramChatId;
  final int? telegramMessageId;
  final int? telegramFileSize;
  final int? telegramTopicId;
  final String? telegramTopicName;

  /// Serialization for GoRouter codec
  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'telegramChatId': telegramChatId,
    'telegramMessageId': telegramMessageId,
    'telegramFileSize': telegramFileSize,
    'telegramTopicId': telegramTopicId,
    'telegramTopicName': telegramTopicName,
  };

  /// Deserialization for GoRouter codec
  factory PlayerRouteExtra.fromJson(Map<String, dynamic> json) {
    return PlayerRouteExtra(
      url: json['url'] as String?,
      title: json['title'] as String?,
      telegramChatId: json['telegramChatId'] as int?,
      telegramMessageId: json['telegramMessageId'] as int?,
      telegramFileSize: json['telegramFileSize'] as int?,
      telegramTopicId: json['telegramTopicId'] as int?,
      telegramTopicName: json['telegramTopicName'] as String?,
    );
  }
}

/// Player Route - Video playback
/// Uses $extra to pass PlayerRouteExtra because video URLs contain
/// query parameters that would conflict with route query strings.
@TypedGoRoute<PlayerRoute>(path: '/player')
class PlayerRoute extends GoRouteData with $PlayerRoute {
  const PlayerRoute({this.$extra});

  final PlayerRouteExtra? $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final extra = $extra;
    return PlayerScreen(
      videoUrl: extra?.url,
      title: extra?.title,
      telegramChatId: extra?.telegramChatId,
      telegramMessageId: extra?.telegramMessageId,
      telegramFileSize: extra?.telegramFileSize,
      telegramTopicId: extra?.telegramTopicId,
      telegramTopicName: extra?.telegramTopicName,
    );
  }
}

/// Telegram Main Route
@TypedGoRoute<TelegramRoute>(path: '/telegram')
class TelegramRoute extends GoRouteData with $TelegramRoute {
  const TelegramRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const TelegramScreen();
  }
}

/// Telegram Selection Route
@TypedGoRoute<TelegramSelectionRoute>(path: '/telegram/selection')
class TelegramSelectionRoute extends GoRouteData with $TelegramSelectionRoute {
  const TelegramSelectionRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const TelegramSelectionScreen();
  }
}

/// Telegram Storage Route
@TypedGoRoute<TelegramStorageRoute>(path: '/telegram/storage')
class TelegramStorageRoute extends GoRouteData with $TelegramStorageRoute {
  const TelegramStorageRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const TelegramStorageScreen();
  }
}

/// Telegram Topics Route - Shows forum topics for a chat
@TypedGoRoute<TelegramTopicsRoute>(path: '/telegram/topics/:chatId')
class TelegramTopicsRoute extends GoRouteData with $TelegramTopicsRoute {
  const TelegramTopicsRoute({required this.chatId, this.title});

  final int chatId;
  final String? title;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return TelegramTopicsScreen(chatId: chatId, title: title ?? 'Topics');
  }
}

/// Telegram Chat Route - Shows messages in a chat/topic
@TypedGoRoute<TelegramChatRoute>(path: '/telegram/chat/:chatId')
class TelegramChatRoute extends GoRouteData with $TelegramChatRoute {
  const TelegramChatRoute({
    required this.chatId,
    this.title,
    this.messageThreadId,
  });

  final int chatId;
  final String? title;
  final int? messageThreadId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return TelegramChatScreen(
      chatId: chatId,
      title: title ?? 'Chat',
      messageThreadId: messageThreadId,
    );
  }
}

/// Playlist Manager Route
@TypedGoRoute<PlaylistManagerRoute>(path: '/playlist-manager')
class PlaylistManagerRoute extends GoRouteData with $PlaylistManagerRoute {
  const PlaylistManagerRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const PlaylistManagerScreen();
  }
}
