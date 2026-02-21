import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../use_case.dart';
import '../../../infrastructure/services/secure_storage_service.dart';
import '../../../infrastructure/services/recent_videos_service.dart';
import '../../../infrastructure/services/playback_storage_service.dart';
import '../../../infrastructure/services/telegram_cache_service.dart';
import '../../../infrastructure/services/telegram_service.dart';

part 'telegram_logout_use_case.g.dart';

class TelegramLogoutUseCase implements UseCase<void, void> {
  final TelegramService _telegramService;

  TelegramLogoutUseCase(this._telegramService);

  @override
  Future<void> call([void params]) async {
    try {
      // 1. Clear Favorites and Settings
      final prefs = SecureStorageService.instance;
      await prefs.remove('telegram_favorites');

      // 2. Clear Recent Videos (Telegram only)
      await RecentVideosService().clearTelegramVideos();

      // 3. Clear Playback Progress
      await PlaybackStorageService().clearAllPositions();

      // 4. Clear Cache (Force all, including avatars/headers)
      await TelegramCacheService().clearCache(forceAll: true);
    } catch (e) {
      // Catch exceptions silently or rethrow depending on requirement
    }

    // 5. Send logout command to TDLib
    _telegramService.send({'@type': 'logOut'});
  }
}

@riverpod
TelegramLogoutUseCase telegramLogoutUseCase(Ref ref) {
  return TelegramLogoutUseCase(TelegramService());
}
