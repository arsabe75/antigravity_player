import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_player_app/application/use_cases/clear_finished_progress_use_case.dart';
import 'package:video_player_app/infrastructure/services/playback_storage_service.dart';

// Mocks
class MockPlaybackStorageService extends Mock
    implements PlaybackStorageService {}

void main() {
  late ClearFinishedProgressUseCase useCase;
  late MockPlaybackStorageService mockStorageService;

  setUp(() {
    mockStorageService = MockPlaybackStorageService();

    useCase = ClearFinishedProgressUseCase(storageService: mockStorageService);
  });

  group('ClearFinishedProgressUseCase', () {
    test('should clear progress when video is at the end', () async {
      // Arrange
      const duration = Duration(minutes: 10);
      // Position is within 500ms threshold of end
      final position = duration - const Duration(milliseconds: 300);
      const storageKey = 'video_key';

      final params = ClearFinishedProgressParams(
        storageKey: storageKey,
        position: position,
        duration: duration,
      );

      when(
        () => mockStorageService.clearPosition(any()),
      ).thenAnswer((_) async {});

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result, true);
      verify(() => mockStorageService.clearPosition(storageKey)).called(1);
    });

    test('should not clear progress when video is not at the end', () async {
      // Arrange
      const duration = Duration(minutes: 10);
      // Position is 1 second before end (outside 500ms threshold)
      final position = duration - const Duration(seconds: 1);
      const storageKey = 'video_key';

      final params = ClearFinishedProgressParams(
        storageKey: storageKey,
        position: position,
        duration: duration,
      );

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result, false);
      verifyNever(() => mockStorageService.clearPosition(any()));
    });

    test('should not clear progress when duration is zero', () async {
      // Arrange
      const params = ClearFinishedProgressParams(
        storageKey: 'video_key',
        position: Duration.zero,
        duration: Duration.zero,
      );

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result, false);
      verifyNever(() => mockStorageService.clearPosition(any()));
    });

    test('should clear progress exactly at 500ms threshold', () async {
      // Arrange
      const duration = Duration(minutes: 5);
      // Position is exactly at the 500ms threshold
      final position = duration - const Duration(milliseconds: 500);
      const storageKey = 'telegram_-100123_456';

      final params = ClearFinishedProgressParams(
        storageKey: storageKey,
        position: position,
        duration: duration,
      );

      when(
        () => mockStorageService.clearPosition(any()),
      ).thenAnswer((_) async {});

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result, true);
      verify(() => mockStorageService.clearPosition(storageKey)).called(1);
    });

    test('should not clear progress just outside threshold', () async {
      // Arrange
      const duration = Duration(minutes: 5);
      // Position is 501ms before end (just outside threshold)
      final position = duration - const Duration(milliseconds: 501);
      const storageKey = 'file_12345';

      final params = ClearFinishedProgressParams(
        storageKey: storageKey,
        position: position,
        duration: duration,
      );

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result, false);
      verifyNever(() => mockStorageService.clearPosition(any()));
    });

    test('should clear progress when position exceeds duration', () async {
      // Arrange - this can happen with imprecise seeking/buffering
      const duration = Duration(minutes: 10);
      final position = duration + const Duration(milliseconds: 100);
      const storageKey = 'video_key';

      final params = ClearFinishedProgressParams(
        storageKey: storageKey,
        position: position,
        duration: duration,
      );

      when(
        () => mockStorageService.clearPosition(any()),
      ).thenAnswer((_) async {});

      // Act
      final result = await useCase.call(params);

      // Assert
      expect(result, true);
      verify(() => mockStorageService.clearPosition(storageKey)).called(1);
    });
  });
}
