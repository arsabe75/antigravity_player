/// Minimal abstraction over Telegram cache management used by [LocalStreamingProxy].
///
/// Enables unit testing of the proxy without real disk operations.
/// [TelegramCacheService] is the production implementation.
abstract class CacheService {
  Future<bool> checkDiskSafety();
  Future<void> enforceVideoSizeLimit();
}
