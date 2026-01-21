/// Service for generating stable storage keys for playback progress persistence.
///
/// This centralizes the logic for creating unique, stable keys that survive:
/// - App restarts
/// - Telegram cache clears (when using message IDs)
/// - Proxy port changes
class StorageKeyService {
  const StorageKeyService._();

  /// Returns a stable storage key for progress persistence.
  ///
  /// Priority order:
  /// 1. Telegram message ID (most stable, survives cache clears)
  /// 2. Proxy file ID (session-stable)
  /// 3. File path (fallback for local files)
  ///
  /// Example keys:
  /// - `telegram_-100123456_789` for Telegram videos
  /// - `file_12345` for proxy file IDs
  /// - `/path/to/video.mp4` for local files
  static String getStableKey({
    int? telegramChatId,
    int? telegramMessageId,
    int? proxyFileId,
    required String fallbackPath,
  }) {
    // Best: Use stable Telegram message ID (survives cache clears)
    if (telegramChatId != null && telegramMessageId != null) {
      return 'telegram_${telegramChatId}_$telegramMessageId';
    }
    // Fallback: Use file_id (may change after cache clear, but works for session)
    if (proxyFileId != null) {
      return 'file_$proxyFileId';
    }
    // Default: Use path for local files
    return fallbackPath;
  }

  /// Extracts proxy file ID from a streaming URL.
  ///
  /// Returns null if the URL doesn't contain a file_id parameter.
  static int? extractProxyFileId(String url) {
    if (!url.contains('file_id=')) return null;
    try {
      final uri = Uri.parse(url);
      final fileIdStr = uri.queryParameters['file_id'];
      if (fileIdStr != null) {
        return int.tryParse(fileIdStr);
      }
    } catch (_) {}
    return null;
  }
}
