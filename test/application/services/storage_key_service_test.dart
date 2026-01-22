import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/application/services/storage_key_service.dart';

void main() {
  group('StorageKeyService.getStableKey', () {
    test(
      'should return telegram key when chat and message IDs are provided',
      () {
        final result = StorageKeyService.getStableKey(
          telegramChatId: -100123456,
          telegramMessageId: 789,
          proxyFileId: 999,
          fallbackPath: '/path/to/video.mp4',
        );

        expect(result, 'telegram_-100123456_789');
      },
    );

    test('should return file key when only proxy file ID is provided', () {
      final result = StorageKeyService.getStableKey(
        proxyFileId: 12345,
        fallbackPath: '/path/to/video.mp4',
      );

      expect(result, 'file_12345');
    });

    test('should return fallback path when no IDs are provided', () {
      final result = StorageKeyService.getStableKey(
        fallbackPath: '/path/to/video.mp4',
      );

      expect(result, '/path/to/video.mp4');
    });

    test('should prefer telegram key over file key', () {
      final result = StorageKeyService.getStableKey(
        telegramChatId: -100111111,
        telegramMessageId: 222,
        proxyFileId: 333,
        fallbackPath: '/fallback.mp4',
      );

      expect(result, 'telegram_-100111111_222');
    });

    test('should require both chat and message ID for telegram key', () {
      // Only chat ID provided
      var result = StorageKeyService.getStableKey(
        telegramChatId: -100123456,
        proxyFileId: 999,
        fallbackPath: '/path/to/video.mp4',
      );
      expect(result, 'file_999');

      // Only message ID provided
      result = StorageKeyService.getStableKey(
        telegramMessageId: 789,
        proxyFileId: 999,
        fallbackPath: '/path/to/video.mp4',
      );
      expect(result, 'file_999');
    });
  });

  group('StorageKeyService.extractProxyFileId', () {
    test('should extract file_id from valid URL', () {
      const url = 'http://localhost:8080/stream?file_id=12345&type=video';
      final result = StorageKeyService.extractProxyFileId(url);

      expect(result, 12345);
    });

    test('should return null when file_id is not present', () {
      const url = 'http://localhost:8080/stream?type=video';
      final result = StorageKeyService.extractProxyFileId(url);

      expect(result, isNull);
    });

    test('should return null for invalid file_id value', () {
      const url = 'http://localhost:8080/stream?file_id=not_a_number';
      final result = StorageKeyService.extractProxyFileId(url);

      expect(result, isNull);
    });

    test('should return null for malformed URL', () {
      const url = 'not a valid url with file_id=123';
      // The method checks for 'file_id=' first, then tries to parse
      // For malformed URLs, Uri.parse may throw or return unexpected results
      final result = StorageKeyService.extractProxyFileId(url);

      // Should gracefully handle and return null
      expect(result, isNull);
    });

    test('should handle URL without query parameters', () {
      const url = 'http://localhost:8080/stream';
      final result = StorageKeyService.extractProxyFileId(url);

      expect(result, isNull);
    });
  });
}
