import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_player_app/application/use_cases/seek_video_use_case.dart';
import 'package:video_player_app/domain/repositories/video_repository.dart';
import 'package:video_player_app/infrastructure/services/playback_storage_service.dart';

// Mocks
class MockVideoRepository extends Mock implements VideoRepository {}

class MockPlaybackStorageService extends Mock
    implements PlaybackStorageService {}

void main() {
  late SeekVideoUseCase useCase;
  late MockVideoRepository mockVideoRepository;
  late MockPlaybackStorageService mockStorageService;

  setUp(() {
    mockVideoRepository = MockVideoRepository();
    mockStorageService = MockPlaybackStorageService();

    useCase = SeekVideoUseCase(
      videoRepository: mockVideoRepository,
      storageService: mockStorageService,
    );
  });

  group('SeekVideoUseCase', () {
    test(
      'should seek to position and save when storage key provided',
      () async {
        // Arrange
        const position = Duration(seconds: 30);
        const storageKey = 'test_video_key';
        const params = SeekVideoParams(
          position: position,
          storageKey: storageKey,
        );

        when(
          () => mockVideoRepository.seekTo(position),
        ).thenAnswer((_) async {});
        when(
          () => mockStorageService.savePosition(
            storageKey,
            position.inMilliseconds,
          ),
        ).thenAnswer((_) async {});

        // Act
        await useCase.call(params);

        // Assert
        verify(() => mockVideoRepository.seekTo(position)).called(1);
        verify(
          () => mockStorageService.savePosition(
            storageKey,
            position.inMilliseconds,
          ),
        ).called(1);
      },
    );

    test('should seek to position using video path as fallback key', () async {
      // Arrange
      const position = Duration(minutes: 2);
      const videoPath = '/path/to/video.mp4';
      const params = SeekVideoParams(position: position, videoPath: videoPath);

      when(() => mockVideoRepository.seekTo(position)).thenAnswer((_) async {});
      when(
        () =>
            mockStorageService.savePosition(videoPath, position.inMilliseconds),
      ).thenAnswer((_) async {});

      // Act
      await useCase.call(params);

      // Assert
      verify(() => mockVideoRepository.seekTo(position)).called(1);
      verify(
        () =>
            mockStorageService.savePosition(videoPath, position.inMilliseconds),
      ).called(1);
    });

    test('should seek without saving if no key provided', () async {
      // Arrange
      const position = Duration(seconds: 45);
      const params = SeekVideoParams(position: position);

      when(() => mockVideoRepository.seekTo(position)).thenAnswer((_) async {});

      // Act
      await useCase.call(params);

      // Assert
      verify(() => mockVideoRepository.seekTo(position)).called(1);
      verifyNever(() => mockStorageService.savePosition(any(), any()));
    });

    test('should prefer storage key over video path', () async {
      // Arrange
      const position = Duration(seconds: 60);
      const storageKey = 'preferred_key';
      const videoPath = '/fallback/path.mp4';
      const params = SeekVideoParams(
        position: position,
        storageKey: storageKey,
        videoPath: videoPath,
      );

      when(() => mockVideoRepository.seekTo(position)).thenAnswer((_) async {});
      when(
        () => mockStorageService.savePosition(
          storageKey,
          position.inMilliseconds,
        ),
      ).thenAnswer((_) async {});

      // Act
      await useCase.call(params);

      // Assert
      verify(
        () => mockStorageService.savePosition(
          storageKey,
          position.inMilliseconds,
        ),
      ).called(1);
      verifyNever(() => mockStorageService.savePosition(videoPath, any()));
    });
  });
}
