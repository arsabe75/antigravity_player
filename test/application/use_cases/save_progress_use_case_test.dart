import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_player_app/application/use_cases/save_progress_use_case.dart';
import 'package:video_player_app/infrastructure/services/playback_storage_service.dart';
import 'package:video_player_app/infrastructure/services/recent_videos_service.dart';

// Mocks
class MockPlaybackStorageService extends Mock
    implements PlaybackStorageService {}

class MockRecentVideosService extends Mock implements RecentVideosService {}

void main() {
  late SaveProgressUseCase useCase;
  late MockPlaybackStorageService mockStorageService;
  late MockRecentVideosService mockRecentVideosService;

  setUp(() {
    mockStorageService = MockPlaybackStorageService();
    mockRecentVideosService = MockRecentVideosService();

    useCase = SaveProgressUseCase(
      storageService: mockStorageService,
      recentVideosService: mockRecentVideosService,
    );

    // Register fallback values for any() matchers
    registerFallbackValue(Duration.zero);
  });

  group('SaveProgressUseCase', () {
    test(
      'should save position and update recent videos for normal playback',
      () async {
        // Arrange
        const videoPath = 'http://localhost:8080/stream?file_id=123';
        const position = Duration(minutes: 5);
        const duration = Duration(minutes: 30);

        const params = SaveProgressParams(
          videoPath: videoPath,
          position: position,
          duration: duration,
          proxyFileId: 123,
        );

        when(
          () => mockStorageService.savePosition(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => mockRecentVideosService.updatePosition(any(), any()),
        ).thenAnswer((_) async {});

        // Act
        final result = await useCase.call(params);

        // Assert
        expect(result.wasCleared, false);
        expect(result.storageKey, 'file_123');
        verify(
          () => mockStorageService.savePosition(
            'file_123',
            position.inMilliseconds,
          ),
        ).called(1);
        verify(
          () => mockRecentVideosService.updatePosition(videoPath, position),
        ).called(1);
      },
    );

    test('should clear progress when video reaches the end', () async {
      // Arrange
      const duration = Duration(minutes: 10);
      // Position is within 500ms of end (threshold)
      final position = duration - const Duration(milliseconds: 400);

      final params = SaveProgressParams(
        videoPath: '/local/video.mp4',
        position: position,
        duration: duration,
      );

      when(
        () => mockStorageService.clearPosition(any()),
      ).thenAnswer((_) async {});

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result.wasCleared, true);
      verify(
        () => mockStorageService.clearPosition('/local/video.mp4'),
      ).called(1);
      verifyNever(() => mockStorageService.savePosition(any(), any()));
      verifyNever(() => mockRecentVideosService.updatePosition(any(), any()));
    });

    test(
      'should use telegram key when chat and message IDs are provided',
      () async {
        // Arrange
        const params = SaveProgressParams(
          videoPath: 'http://localhost/stream',
          position: Duration(seconds: 30),
          duration: Duration(minutes: 5),
          telegramChatId: -100123456,
          telegramMessageId: 789,
          proxyFileId: 999,
        );

        when(
          () => mockStorageService.savePosition(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => mockRecentVideosService.updatePosition(any(), any()),
        ).thenAnswer((_) async {});

        // Act
        final result = await useCase.call(params);

        // Assert
        expect(result.storageKey, 'telegram_-100123456_789');
        verify(
          () =>
              mockStorageService.savePosition('telegram_-100123456_789', 30000),
        ).called(1);
      },
    );

    test('should not clear progress if not at end threshold', () async {
      // Arrange
      const duration = Duration(minutes: 10);
      // Position is 1 second before end (outside 500ms threshold)
      final position = duration - const Duration(seconds: 1);

      final params = SaveProgressParams(
        videoPath: '/video.mp4',
        position: position,
        duration: duration,
      );

      when(
        () => mockStorageService.savePosition(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => mockRecentVideosService.updatePosition(any(), any()),
      ).thenAnswer((_) async {});

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result.wasCleared, false);
      verifyNever(() => mockStorageService.clearPosition(any()));
    });

    test('should not consider video finished if duration is zero', () async {
      // Arrange
      const params = SaveProgressParams(
        videoPath: '/video.mp4',
        position: Duration.zero,
        duration: Duration.zero,
      );

      when(
        () => mockStorageService.savePosition(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => mockRecentVideosService.updatePosition(any(), any()),
      ).thenAnswer((_) async {});

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result.wasCleared, false);
      verify(() => mockStorageService.savePosition('/video.mp4', 0)).called(1);
    });

    test(
      'should use fallback path as storage key when no IDs provided',
      () async {
        // Arrange
        const params = SaveProgressParams(
          videoPath: '/local/video.mp4',
          position: Duration(minutes: 2),
          duration: Duration(minutes: 10),
        );

        when(
          () => mockStorageService.savePosition(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => mockRecentVideosService.updatePosition(any(), any()),
        ).thenAnswer((_) async {});

        // Act
        final result = await useCase.call(params);

        // Assert
        expect(result.storageKey, '/local/video.mp4');
      },
    );
  });
}
