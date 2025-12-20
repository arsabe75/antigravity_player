import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_player_app/application/use_cases/load_video_use_case.dart';
import 'package:video_player_app/domain/entities/video_entity.dart';
import 'package:video_player_app/domain/repositories/video_repository.dart';
import 'package:video_player_app/domain/repositories/streaming_repository.dart';
import 'package:video_player_app/infrastructure/services/playback_storage_service.dart';
import 'package:video_player_app/infrastructure/services/recent_videos_service.dart';

// Mocks
class MockVideoRepository extends Mock implements VideoRepository {}

class MockStreamingRepository extends Mock implements StreamingRepository {}

class MockPlaybackStorageService extends Mock
    implements PlaybackStorageService {}

class MockRecentVideosService extends Mock implements RecentVideosService {}

class FakeVideoEntity extends Fake implements VideoEntity {}

void main() {
  late LoadVideoUseCase useCase;
  late MockVideoRepository mockVideoRepository;
  late MockStreamingRepository mockStreamingRepository;
  late MockPlaybackStorageService mockStorageService;
  late MockRecentVideosService mockRecentVideosService;

  setUpAll(() {
    registerFallbackValue(FakeVideoEntity());
  });

  setUp(() {
    mockVideoRepository = MockVideoRepository();
    mockStreamingRepository = MockStreamingRepository();
    mockStorageService = MockPlaybackStorageService();
    mockRecentVideosService = MockRecentVideosService();

    useCase = LoadVideoUseCase(
      videoRepository: mockVideoRepository,
      streamingRepository: mockStreamingRepository,
      storageService: mockStorageService,
      recentVideosService: mockRecentVideosService,
    );
  });

  group('LoadVideoUseCase', () {
    test(
      'should play video and save to recent videos for network video',
      () async {
        // Arrange
        const params = LoadVideoParams(
          path: 'https://example.com/video.mp4',
          isNetwork: true,
          title: 'Test Video',
        );

        when(() => mockVideoRepository.play(any())).thenAnswer((_) async {});
        when(
          () => mockRecentVideosService.addVideo(
            any(),
            isNetwork: any(named: 'isNetwork'),
            title: any(named: 'title'),
            telegramChatId: any(named: 'telegramChatId'),
            telegramMessageId: any(named: 'telegramMessageId'),
            telegramFileSize: any(named: 'telegramFileSize'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => mockStorageService.getPosition(any()),
        ).thenAnswer((_) async => null);

        // Act
        final result = await useCase.call(params);

        // Assert
        expect(result.correctedPath, params.path);
        expect(result.proxyFileId, isNull);
        expect(result.savedPosition, isNull);

        verify(() => mockVideoRepository.play(any())).called(1);
        verify(
          () => mockRecentVideosService.addVideo(
            params.path,
            isNetwork: true,
            title: 'Test Video',
            telegramChatId: null,
            telegramMessageId: null,
            telegramFileSize: null,
          ),
        ).called(1);
      },
    );

    test('should correct port for local proxy URL', () async {
      // Arrange
      const oldPort = 8080;
      const newPort = 9090;
      final params = LoadVideoParams(
        path: 'http://127.0.0.1:$oldPort/stream?file_id=123',
        isNetwork: true,
      );

      when(() => mockStreamingRepository.port).thenReturn(newPort);
      when(() => mockVideoRepository.play(any())).thenAnswer((_) async {});
      when(
        () => mockRecentVideosService.addVideo(
          any(),
          isNetwork: any(named: 'isNetwork'),
          title: any(named: 'title'),
          telegramChatId: any(named: 'telegramChatId'),
          telegramMessageId: any(named: 'telegramMessageId'),
          telegramFileSize: any(named: 'telegramFileSize'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockStorageService.getPosition(any()),
      ).thenAnswer((_) async => null);

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result.correctedPath, contains(':$newPort/'));
      expect(result.proxyFileId, 123);
    });

    test('should return saved position when available', () async {
      // Arrange
      const savedMs = 30000; // 30 seconds
      const params = LoadVideoParams(
        path: 'https://example.com/video.mp4',
        isNetwork: true,
      );

      when(() => mockVideoRepository.play(any())).thenAnswer((_) async {});
      when(
        () => mockRecentVideosService.addVideo(
          any(),
          isNetwork: any(named: 'isNetwork'),
          title: any(named: 'title'),
          telegramChatId: any(named: 'telegramChatId'),
          telegramMessageId: any(named: 'telegramMessageId'),
          telegramFileSize: any(named: 'telegramFileSize'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockStorageService.getPosition(any()),
      ).thenAnswer((_) async => savedMs);

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result.savedPosition, const Duration(milliseconds: savedMs));
    });

    test('should use telegram message ID for storage key', () async {
      // Arrange
      const params = LoadVideoParams(
        path: 'http://127.0.0.1:8080/stream?file_id=456',
        isNetwork: true,
        telegramChatId: -100123456,
        telegramMessageId: 789,
      );

      when(() => mockStreamingRepository.port).thenReturn(8080);
      when(() => mockVideoRepository.play(any())).thenAnswer((_) async {});
      when(
        () => mockRecentVideosService.addVideo(
          any(),
          isNetwork: any(named: 'isNetwork'),
          title: any(named: 'title'),
          telegramChatId: any(named: 'telegramChatId'),
          telegramMessageId: any(named: 'telegramMessageId'),
          telegramFileSize: any(named: 'telegramFileSize'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockStorageService.getPosition('telegram_-100123456_789'),
      ).thenAnswer((_) async => 5000);

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result.savedPosition, const Duration(milliseconds: 5000));
      verify(
        () => mockStorageService.getPosition('telegram_-100123456_789'),
      ).called(1);
    });

    test(
      'should throw FileSystemException for non-existent local file',
      () async {
        // Arrange
        const params = LoadVideoParams(
          path: '/non/existent/path/video.mp4',
          isNetwork: false,
        );

        // Act & Assert
        expect(() => useCase.call(params), throwsA(isA<FileSystemException>()));
      },
    );
  });
}
