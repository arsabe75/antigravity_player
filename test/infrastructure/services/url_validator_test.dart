import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/infrastructure/services/url_validator.dart';

void main() {
  group('UrlValidator', () {
    group('validateVideoUrl', () {
      test('returns valid for valid http URL', () {
        final result = UrlValidator.validateVideoUrl(
          'http://example.com/video.mp4',
        );
        expect(result.isValid, true);
        expect(result.errorMessage, null);
      });

      test('returns valid for valid https URL', () {
        final result = UrlValidator.validateVideoUrl(
          'https://example.com/video.mp4',
        );
        expect(result.isValid, true);
        expect(result.errorMessage, null);
      });

      test('returns invalid for invalid URL scheme', () {
        final result = UrlValidator.validateVideoUrl(
          'ftp://example.com/video.mp4',
        );
        expect(result.isValid, false);
        expect(result.errorMessage, contains('http'));
      });

      test('returns invalid for empty URL', () {
        final result = UrlValidator.validateVideoUrl('');
        expect(result.isValid, false);
        expect(result.errorMessage, contains('empty'));
      });

      test('returns invalid for malformed URL', () {
        final result = UrlValidator.validateVideoUrl('not-a-url');
        expect(result.isValid, false);
        expect(result.errorMessage, contains('Invalid URL'));
      });

      test('returns valid for URL without extension (streaming)', () {
        final result = UrlValidator.validateVideoUrl(
          'https://example.com/stream',
        );
        expect(result.isValid, true);
      });

      test('returns invalid for unsupported extension', () {
        final result = UrlValidator.validateVideoUrl(
          'https://example.com/document.pdf',
        );
        expect(result.isValid, false);
        expect(result.errorMessage, contains('Unsupported format'));
      });
    });

    group('validateFilePath', () {
      test('returns valid for valid mp4 path', () {
        final result = UrlValidator.validateFilePath('/home/user/video.mp4');
        expect(result.isValid, true);
      });

      test('returns valid for valid mkv path', () {
        final result = UrlValidator.validateFilePath('/home/user/movie.mkv');
        expect(result.isValid, true);
      });

      test('returns invalid for non-video file', () {
        final result = UrlValidator.validateFilePath('/home/user/document.pdf');
        expect(result.isValid, false);
        expect(result.errorMessage, contains('Unsupported format'));
      });

      test('returns invalid for empty path', () {
        final result = UrlValidator.validateFilePath('');
        expect(result.isValid, false);
        expect(result.errorMessage, contains('empty'));
      });

      test('returns invalid for file without extension', () {
        final result = UrlValidator.validateFilePath('/home/user/video');
        expect(result.isValid, false);
        expect(result.errorMessage, contains('must have a video extension'));
      });
    });

    group('getVideoExtension', () {
      test('returns extension for simple filename', () {
        expect(UrlValidator.getVideoExtension('video.mp4'), 'mp4');
      });

      test('returns extension for URL with query params', () {
        expect(
          UrlValidator.getVideoExtension(
            'https://example.com/video.mp4?token=123',
          ),
          'mp4',
        );
      });

      test('returns null for URL without extension', () {
        expect(
          UrlValidator.getVideoExtension('https://example.com/stream'),
          null,
        );
      });

      test('returns extension for path with multiple dots', () {
        expect(UrlValidator.getVideoExtension('my.video.file.mkv'), 'mkv');
      });

      test('returns lowercase extension', () {
        expect(UrlValidator.getVideoExtension('VIDEO.MP4'), 'mp4');
      });
    });

    group('isNetworkUrl', () {
      test('returns true for http', () {
        expect(UrlValidator.isNetworkUrl('http://example.com'), true);
      });

      test('returns true for https', () {
        expect(UrlValidator.isNetworkUrl('https://example.com'), true);
      });

      test('returns false for file path', () {
        expect(UrlValidator.isNetworkUrl('/home/user/video.mp4'), false);
      });
    });

    group('getDomain', () {
      test('returns domain for https URL', () {
        expect(
          UrlValidator.getDomain('https://www.example.com/video.mp4'),
          'www.example.com',
        );
      });

      test('returns domain for http URL', () {
        expect(
          UrlValidator.getDomain('http://streaming.example.org/live'),
          'streaming.example.org',
        );
      });

      test('returns null for invalid URL', () {
        expect(UrlValidator.getDomain('not-a-url'), null);
      });

      test('returns null for empty string', () {
        expect(UrlValidator.getDomain(''), null);
      });
    });
  });
}
