import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/domain/entities/player_error.dart';

void main() {
  group('PlayerError', () {
    group('NetworkError', () {
      test('creates with correct properties', () {
        final error = NetworkError('Connection failed');

        expect(error.message, 'Connection failed');
        expect(error.userFriendlyMessage, contains('connect'));
        expect(error.canRetry, true);
      });
    });

    group('FileNotFoundError', () {
      test('creates with path', () {
        final error = FileNotFoundError(
          'File not found',
          filePath: '/path/video.mp4',
        );

        expect(error.filePath, '/path/video.mp4');
        expect(error.canRetry, false);
      });
    });

    group('UnsupportedFormatError', () {
      test('creates with format', () {
        final error = UnsupportedFormatError('Bad format', format: '.xyz');

        expect(error.format, '.xyz');
        expect(error.canRetry, false);
      });
    });

    group('PlaybackError', () {
      test('creates with message', () {
        final error = PlaybackError('Codec error');

        expect(error.message, 'Codec error');
        expect(error.canRetry, true);
      });
    });

    group('PermissionError', () {
      test('creates correctly', () {
        final error = PermissionError('Access denied');

        expect(error.canRetry, false);
      });
    });

    group('UnknownError', () {
      test('creates with message', () {
        final error = UnknownError('Something went wrong');

        expect(error.message, 'Something went wrong');
        expect(error.canRetry, true);
      });
    });
  });

  group('PlayerErrorFactory', () {
    test('creates NetworkError from SocketException string', () {
      final error = PlayerErrorFactory.fromException(
        'SocketException: Connection refused',
      );

      expect(error, isA<NetworkError>());
    });

    test('creates FileNotFoundError from file not found message', () {
      final error = PlayerErrorFactory.fromException(
        'FileSystemException: No such file or directory, path = /missing.mp4',
      );

      expect(error, isA<FileNotFoundError>());
    });

    test('creates UnsupportedFormatError from codec message', () {
      final error = PlayerErrorFactory.fromException(
        'PlatformException: Video codec not supported',
      );

      expect(error, isA<UnsupportedFormatError>());
    });

    test('creates UnknownError for unknown exception type', () {
      final error = PlayerErrorFactory.fromException('Some random error');

      expect(error, isA<UnknownError>());
    });

    test('handles null input', () {
      final error = PlayerErrorFactory.fromException(null);

      expect(error, isA<UnknownError>());
    });

    test('handles dynamic object', () {
      final error = PlayerErrorFactory.fromException({'error': 'test'});

      expect(error, isA<UnknownError>());
    });
  });
}
