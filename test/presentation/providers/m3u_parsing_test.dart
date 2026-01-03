import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:video_player_app/domain/entities/playlist_entity.dart';

/// Utility function to parse M3U content (mirrors playlist_manager_screen logic)
List<PlaylistItem> parseM3UContent(String content) {
  final lines = content.split('\n');
  final items = <PlaylistItem>[];
  String? pendingTitle;
  int? pendingDurationSecs;

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    // Parse M3U EXTINF metadata line
    if (trimmed.startsWith('#EXTINF:')) {
      final extinf = trimmed.substring(8);
      final commaIndex = extinf.indexOf(',');
      if (commaIndex > 0) {
        pendingDurationSecs = int.tryParse(extinf.substring(0, commaIndex));
        pendingTitle = extinf.substring(commaIndex + 1).trim();
      }
      continue;
    }

    // Skip other M3U directives
    if (trimmed.startsWith('#')) continue;

    // This is a path line
    items.add(
      PlaylistItem(
        path: trimmed,
        isNetwork: trimmed.startsWith('http'),
        title: pendingTitle ?? path.basename(trimmed),
        duration: pendingDurationSecs != null && pendingDurationSecs > 0
            ? Duration(seconds: pendingDurationSecs)
            : null,
      ),
    );
    pendingTitle = null;
    pendingDurationSecs = null;
  }

  return items;
}

/// Utility function to generate M3U content (mirrors playlist_manager_screen logic)
String generateM3UContent(List<PlaylistItem> items) {
  final buffer = StringBuffer('#EXTM3U\n');
  for (final item in items) {
    final durationSecs = item.duration?.inSeconds ?? -1;
    final title = item.title ?? path.basename(item.path);
    buffer.writeln('#EXTINF:$durationSecs,$title');
    buffer.writeln(item.path);
  }
  return buffer.toString();
}

void main() {
  group('M3U Format Parsing', () {
    group('parseM3UContent', () {
      test('parses basic M3U with EXTINF metadata', () {
        const content = '''
#EXTM3U
#EXTINF:120,Video One
/path/to/video1.mp4
#EXTINF:180,Video Two
/path/to/video2.mp4
''';
        final items = parseM3UContent(content);

        expect(items.length, 2);
        expect(items[0].path, '/path/to/video1.mp4');
        expect(items[0].title, 'Video One');
        expect(items[0].duration, const Duration(seconds: 120));
        expect(items[1].path, '/path/to/video2.mp4');
        expect(items[1].title, 'Video Two');
        expect(items[1].duration, const Duration(seconds: 180));
      });

      test('parses M3U with network URLs', () {
        const content = '''
#EXTM3U
#EXTINF:300,Online Video
https://example.com/video.mp4
''';
        final items = parseM3UContent(content);

        expect(items.length, 1);
        expect(items[0].isNetwork, true);
        expect(items[0].path, 'https://example.com/video.mp4');
      });

      test('parses M3U without EXTINF (path only)', () {
        const content = '''
#EXTM3U
/path/to/video1.mp4
/path/to/video2.mp4
''';
        final items = parseM3UContent(content);

        expect(items.length, 2);
        expect(items[0].path, '/path/to/video1.mp4');
        expect(items[0].title, 'video1.mp4'); // Basename fallback
        expect(items[0].duration, null);
      });

      test('parses simple TXT format (no header)', () {
        const content = '''
/path/to/video1.mp4
/path/to/video2.mp4
''';
        final items = parseM3UContent(content);

        expect(items.length, 2);
        expect(items[0].path, '/path/to/video1.mp4');
        expect(items[1].path, '/path/to/video2.mp4');
      });

      test('handles -1 duration (unknown duration)', () {
        const content = '''
#EXTM3U
#EXTINF:-1,Unknown Duration
/path/to/video.mp4
''';
        final items = parseM3UContent(content);

        expect(items.length, 1);
        expect(items[0].duration, null);
      });

      test('skips empty lines', () {
        const content = '''
#EXTM3U

#EXTINF:120,Video

/path/to/video.mp4

''';
        final items = parseM3UContent(content);

        expect(items.length, 1);
      });

      test('skips unknown directives', () {
        const content = '''
#EXTM3U
#EXT-X-VERSION:3
#PLAYLIST:My Playlist
#EXTINF:60,Video
/path/to/video.mp4
''';
        final items = parseM3UContent(content);

        expect(items.length, 1);
        expect(items[0].title, 'Video');
      });

      test('handles mixed local and network paths', () {
        const content = '''
#EXTM3U
#EXTINF:100,Local Video
C:\\Videos\\local.mp4
#EXTINF:200,Remote Video
http://example.com/remote.mp4
''';
        final items = parseM3UContent(content);

        expect(items.length, 2);
        expect(items[0].isNetwork, false);
        expect(items[1].isNetwork, true);
      });
    });

    group('generateM3UContent', () {
      test('generates valid M3U with header', () {
        final items = [
          const PlaylistItem(
            path: '/path/to/video.mp4',
            isNetwork: false,
            title: 'My Video',
            duration: Duration(seconds: 120),
          ),
        ];

        final content = generateM3UContent(items);

        expect(content, contains('#EXTM3U'));
        expect(content, contains('#EXTINF:120,My Video'));
        expect(content, contains('/path/to/video.mp4'));
      });

      test('generates -1 duration for unknown', () {
        final items = [
          const PlaylistItem(
            path: '/path/to/video.mp4',
            isNetwork: false,
            title: 'No Duration',
          ),
        ];

        final content = generateM3UContent(items);

        expect(content, contains('#EXTINF:-1,No Duration'));
      });

      test('uses path basename as fallback title', () {
        final items = [
          const PlaylistItem(path: '/path/to/MyVideo.mp4', isNetwork: false),
        ];

        final content = generateM3UContent(items);

        expect(content, contains('#EXTINF:-1,MyVideo.mp4'));
      });

      test('generates multiple entries', () {
        final items = [
          const PlaylistItem(
            path: '/path/to/video1.mp4',
            isNetwork: false,
            title: 'V1',
            duration: Duration(seconds: 60),
          ),
          const PlaylistItem(
            path: '/path/to/video2.mp4',
            isNetwork: false,
            title: 'V2',
            duration: Duration(seconds: 90),
          ),
        ];

        final content = generateM3UContent(items);

        expect(content, contains('#EXTINF:60,V1'));
        expect(content, contains('#EXTINF:90,V2'));
        expect(content, contains('/path/to/video1.mp4'));
        expect(content, contains('/path/to/video2.mp4'));
      });
    });

    group('roundtrip', () {
      test('parse and generate produces consistent result', () {
        final original = [
          const PlaylistItem(
            path: '/path/to/video1.mp4',
            isNetwork: false,
            title: 'Video One',
            duration: Duration(seconds: 120),
          ),
          const PlaylistItem(
            path: 'https://example.com/video2.mp4',
            isNetwork: true,
            title: 'Video Two',
            duration: Duration(seconds: 180),
          ),
        ];

        final content = generateM3UContent(original);
        final parsed = parseM3UContent(content);

        expect(parsed.length, original.length);
        expect(parsed[0].path, original[0].path);
        expect(parsed[0].title, original[0].title);
        expect(parsed[0].duration, original[0].duration);
        expect(parsed[1].path, original[1].path);
        expect(parsed[1].isNetwork, original[1].isNetwork);
      });
    });
  });

  group('M3U File Operations', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('playlist_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writes and reads M3U file', () async {
      final items = [
        const PlaylistItem(
          path: '/path/to/video.mp4',
          isNetwork: false,
          title: 'Test Video',
          duration: Duration(seconds: 60),
        ),
      ];

      final content = generateM3UContent(items);
      final file = File(path.join(tempDir.path, 'test.m3u'));
      await file.writeAsString(content);

      final readContent = await file.readAsString();
      final parsed = parseM3UContent(readContent);

      expect(parsed.length, 1);
      expect(parsed[0].title, 'Test Video');
    });

    test('writes and reads TXT file', () async {
      final items = [
        const PlaylistItem(path: '/video1.mp4', isNetwork: false),
        const PlaylistItem(path: '/video2.mp4', isNetwork: false),
      ];

      // Simple TXT format
      final content = items.map((i) => i.path).join('\n');
      final file = File(path.join(tempDir.path, 'test.txt'));
      await file.writeAsString(content);

      final readContent = await file.readAsString();
      final parsed = parseM3UContent(readContent);

      expect(parsed.length, 2);
      expect(parsed[0].path, '/video1.mp4');
    });
  });
}
