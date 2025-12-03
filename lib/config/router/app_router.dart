import 'package:go_router/go_router.dart';
import '../../presentation/screens/player_screen.dart';
import '../../presentation/screens/home_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/player',
      builder: (context, state) {
        final url = state.extra as String?;
        return PlayerScreen(videoUrl: url);
      },
    ),
  ],
);
