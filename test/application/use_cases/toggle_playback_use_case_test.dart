import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_player_app/application/use_cases/toggle_playback_use_case.dart';
import 'package:video_player_app/domain/repositories/video_repository.dart';
import 'package:video_player_app/infrastructure/services/playback_storage_service.dart';

// Mocks
class MockVideoRepository extends Mock implements VideoRepository {}

class MockPlaybackStorageService extends Mock
    implements PlaybackStorageService {}

void main() {
  late TogglePlaybackUseCase useCase;
  late MockVideoRepository mockVideoRepository;
  late MockPlaybackStorageService mockStorageService;

  setUp(() {
    mockVideoRepository = MockVideoRepository();
    mockStorageService = MockPlaybackStorageService();

    useCase = TogglePlaybackUseCase(
      videoRepository: mockVideoRepository,
      storageService: mockStorageService,
    );
  });

  group('TogglePlaybackUseCase', () {
    test('should pause and save position when currently playing', () async {
      // Arrange
      const currentPosition = Duration(minutes: 5);
      const storageKey = 'video_key';
      const params = TogglePlaybackParams(
        isCurrentlyPlaying: true,
        currentPosition: currentPosition,
        storageKey: storageKey,
      );

      when(() => mockVideoRepository.pause()).thenAnswer((_) async {});
      when(
        () => mockStorageService.savePosition(
          storageKey,
          currentPosition.inMilliseconds,
        ),
      ).thenAnswer((_) async {});

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result.isNowPlaying, false);
      verify(() => mockVideoRepository.pause()).called(1);
      verify(
        () => mockStorageService.savePosition(
          storageKey,
          currentPosition.inMilliseconds,
        ),
      ).called(1);
    });

    test('should resume without saving when currently paused', () async {
      // Arrange
      const params = TogglePlaybackParams(
        isCurrentlyPlaying: false,
        currentPosition: Duration(seconds: 30),
        storageKey: 'video_key',
      );

      when(() => mockVideoRepository.resume()).thenAnswer((_) async {});

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result.isNowPlaying, true);
      verify(() => mockVideoRepository.resume()).called(1);
      verifyNever(() => mockStorageService.savePosition(any(), any()));
    });

    test('should not save position on pause if no storage key', () async {
      // Arrange
      const params = TogglePlaybackParams(
        isCurrentlyPlaying: true,
        currentPosition: Duration(minutes: 10),
      );

      when(() => mockVideoRepository.pause()).thenAnswer((_) async {});

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result.isNowPlaying, false);
      verify(() => mockVideoRepository.pause()).called(1);
      verifyNever(() => mockStorageService.savePosition(any(), any()));
    });
  });
}
