import 'package:go_router/go_router.dart';
import '../../presentation/screens/player_screen.dart';
import '../../presentation/screens/home_screen.dart';
import '../../presentation/screens/telegram_screen.dart';
import '../../presentation/screens/telegram_selection_screen.dart';
import '../../presentation/screens/telegram_storage_screen.dart';
import '../../presentation/screens/telegram_topics_screen.dart';
import '../../presentation/screens/telegram_chat_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/player',
      builder: (context, state) {
        String? url;
        String? title;
        int? telegramChatId;
        int? telegramMessageId;
        int? telegramFileSize;

        if (state.extra is Map) {
          final map = state.extra as Map;
          url = map['url'] as String?;
          title = map['title'] as String?;
          telegramChatId = map['telegramChatId'] as int?;
          telegramMessageId = map['telegramMessageId'] as int?;
          telegramFileSize = map['telegramFileSize'] as int?;
        } else if (state.extra is String) {
          url = state.extra as String?;
        }

        return PlayerScreen(
          videoUrl: url,
          title: title,
          telegramChatId: telegramChatId,
          telegramMessageId: telegramMessageId,
          telegramFileSize: telegramFileSize,
        );
      },
    ),
    GoRoute(
      path: '/telegram',
      builder: (context, state) => const TelegramScreen(),
    ),
    GoRoute(
      path: '/telegram/selection',
      builder: (context, state) => const TelegramSelectionScreen(),
    ),
    GoRoute(
      path: '/telegram/storage',
      builder: (context, state) => const TelegramStorageScreen(),
    ),
    GoRoute(
      path: '/telegram/topics/:chatId',
      builder: (context, state) {
        final chatId = int.parse(state.pathParameters['chatId']!);
        final title = state.extra as String? ?? 'Topics';
        return TelegramTopicsScreen(chatId: chatId, title: title);
      },
    ),
    GoRoute(
      path: '/telegram/chat/:chatId',
      builder: (context, state) {
        final chatId = int.parse(state.pathParameters['chatId']!);
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return TelegramChatScreen(
          chatId: chatId,
          title: extra['title'] as String? ?? 'Chat',
          messageThreadId: extra['messageThreadId'] as int?,
        );
      },
    ),
  ],
);
