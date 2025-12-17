import 'package:go_router/go_router.dart';
import '../../presentation/screens/player_screen.dart';
import '../../presentation/screens/home_screen.dart';
import '../../presentation/screens/telegram_screen.dart';

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
  ],
);
