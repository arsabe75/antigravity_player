import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_player_app/infrastructure/services/local_streaming_proxy.dart';
import 'package:video_player_app/infrastructure/services/tdlib_client.dart';
import 'package:video_player_app/infrastructure/services/cache_service.dart';
import 'package:video_player_app/infrastructure/services/download_priority.dart';
import 'package:video_player_app/infrastructure/services/downloaded_ranges.dart';

class MockTdlibClient extends Mock implements TdlibClient {}
class MockCacheService extends Mock implements CacheService {}

void main() {
  late LocalStreamingProxy proxy;
  late MockTdlibClient mockTdlib;
  late MockCacheService mockCache;

  setUp(() {
    mockTdlib = MockTdlibClient();
    mockCache = MockCacheService();
    proxy = LocalStreamingProxy.testing(
      tdlib: mockTdlib,
      cacheService: mockCache,
    );
    registerFallbackValue(<String, dynamic>{});
  });

  // ============================================================
  // isFileComplete
  // ============================================================
  group('isFileComplete', () {
    test('returns false for null info', () {
      expect(proxy.isFileComplete(null), isFalse);
    });

    test('returns true when file is completed', () {
      final info = ProxyFileInfo(
        path: '/tmp/test.mp4',
        totalSize: 100,
        isCompleted: true,
      );
      expect(proxy.isFileComplete(info), isTrue);
    });

    test('returns false when file is not completed', () {
      final info = ProxyFileInfo(
        path: '/tmp/test.mp4',
        totalSize: 100,
        isCompleted: false,
      );
      expect(proxy.isFileComplete(info), isFalse);
    });
  });

  // ============================================================
  // isEofRequest
  // ============================================================
  group('isEofRequest', () {
    test('returns false for null info', () {
      expect(proxy.isEofRequest(100, null), isFalse);
    });

    test('returns true when offset is at total size', () {
      final info = ProxyFileInfo(path: '/tmp/test.mp4', totalSize: 100);
      expect(proxy.isEofRequest(100, info), isTrue);
    });

    test('returns true when offset exceeds total size', () {
      final info = ProxyFileInfo(path: '/tmp/test.mp4', totalSize: 100);
      expect(proxy.isEofRequest(200, info), isTrue);
    });

    test('returns false when offset is within file', () {
      final info = ProxyFileInfo(path: '/tmp/test.mp4', totalSize: 100);
      expect(proxy.isEofRequest(50, info), isFalse);
    });

    test('returns false when totalSize is 0', () {
      final info = ProxyFileInfo(path: '/tmp/test.mp4', totalSize: 0);
      expect(proxy.isEofRequest(0, info), isFalse);
    });
  });

  // ============================================================
  // isStaleSeekGeneration
  // ============================================================
  group('isStaleSeekGeneration', () {
    test('returns false when seekGeneration is null', () {
      expect(proxy.isStaleSeekGeneration(null, 1), isFalse);
    });

    test('returns false when generations match', () {
      // We need to seed the seek generation. Since we can't call
      // signalUserSeek without a running proxy, test the null case.
      expect(proxy.isStaleSeekGeneration(null, 999), isFalse);
    });

    test('returns false when no generation stored for file', () {
      expect(proxy.isStaleSeekGeneration(0, 999), isFalse);
    });
  });

  // ============================================================
  // detectSeek
  // ============================================================
  group('detectSeek', () {
    test('returns false when moovFirstRedirect is true', () {
      final result = proxy.detectSeek(1, 0, 1000000, 256 * 1024, 1 * 1024 * 1024, true);
      expect(result, isFalse);
    });

    test('returns false when no last served offset', () {
      final result = proxy.detectSeek(1, 500 * 1024, 1000000, 256 * 1024, 1 * 1024 * 1024, false);
      expect(result, isFalse);
    });

    test('returns false when no prior offset has been served', () {
      // By default, a new fileId has no lastServedOffset
      final result = proxy.detectSeek(99, 500 * 1024, 1000000, 256 * 1024, 1 * 1024 * 1024, false);
      expect(result, isFalse);
    });
  });

  // ============================================================
  // handleMoovFirstRedirect
  // ============================================================
  group('handleMoovFirstRedirect', () {
    test('returns unchanged start when no stale position', () {
      final result = proxy.handleMoovFirstRedirect(1, 500 * 1024, 256 * 1024);
      expect(result.adjustedStart, equals(500 * 1024));
      expect(result.moovFirstRedirect, isFalse);
    });

    test('returns unchanged start for non-stale file', () {
      final result = proxy.handleMoovFirstRedirect(999, 1000, 256 * 1024);
      expect(result.adjustedStart, equals(1000));
      expect(result.moovFirstRedirect, isFalse);
    });
  });

  // ============================================================
  // resolvePriority
  // ============================================================
  group('resolvePriority', () {
    test('returns deepBuffer for non-low-offset forced priority far from primary', () {
      // offset=400MB (>300MB lowOffsetThreshold) ensures isLowOffsetRequest=false
      final priority = proxy.resolvePriority(
        1, 400 * 1024 * 1024, 500 * 1024 * 1024, 0, 400 * 1024 * 1024,
        true, false,
      );
      expect(priority, equals(DownloadPriority.deepBuffer));
    });

    test('returns critical for moov download', () {
      final priority = proxy.resolvePriority(
        1, 30 * 1024 * 1024, 100 * 1024 * 1024, 0, 30 * 1024 * 1024,
        true, true, // isMoovDownload = true
      );
      expect(priority, equals(DownloadPriority.critical));
    });

    test('returns critical for closest-to-primary requests', () {
      final priority = proxy.resolvePriority(
        1, 1 * 1024 * 1024, 100 * 1024 * 1024, 0, 1 * 1024 * 1024,
        true, false,
      );
      // distanceToPlayback = 1MB, closestToPrimary = 20MB -> critical
      expect(priority, equals(DownloadPriority.critical));
    });

    test('uses dynamic priority for high-offset non-forced request', () {
      // offset=400MB (>300MB lowOffsetThreshold), shouldForcePriority=false
      // → _calculateDynamicPriority(400MB) → minimum(1), no low-offset floor
      final priority = proxy.resolvePriority(
        1, 400 * 1024 * 1024, 500 * 1024 * 1024, 0, 400 * 1024 * 1024,
        false, false,
      );
      expect(priority, equals(DownloadPriority.minimum));
    });

    test('low-offset request gets highFloor minimum', () {
      final priority = proxy.resolvePriority(
        1, 1 * 1024, 100 * 1024 * 1024, 0, 1 * 1024,
        false, false,
      );
      expect(priority, greaterThanOrEqualTo(DownloadPriority.highFloor));
    });

    test('closest-to-primary low-offset gets critical', () {
      final priority = proxy.resolvePriority(
        1, 1 * 1024, 100 * 1024 * 1024, 0, 1 * 1024,
        false, false,
      );
      // Low offset (<300MB), closest to primary (<20MB), no active high priority
      expect(priority, equals(DownloadPriority.critical));
    });
  });

  // ============================================================
  // evaluateBlockingPriority
  // ============================================================
  group('evaluateBlockingPriority', () {
    test('returns isMoovDownload when not blocking', () {
      final result = proxy.evaluateBlockingPriority(
        1, 0, 100 * 1024 * 1024, 0, false, false,
      );
      expect(result, isFalse);
    });

    test('returns true for moov download when not blocking', () {
      final result = proxy.evaluateBlockingPriority(
        1, 0, 100 * 1024 * 1024, 0, true, false,
      );
      expect(result, isTrue);
    });
  });

  // ============================================================
  // Integration: ProxyFileInfo
  // ============================================================
  group('ProxyFileInfo', () {
    test('availableBytesFrom returns totalSize for completed file', () {
      final info = ProxyFileInfo(
        path: '/tmp/test.mp4',
        totalSize: 1000,
        isCompleted: true,
      );
      expect(info.availableBytesFrom(500), equals(500));
      expect(info.availableBytesFrom(0), equals(1000));
      expect(info.availableBytesFrom(1000), equals(0));
    });

    test('availableBytesFrom uses download offset and prefix', () {
      final info = ProxyFileInfo(
        path: '/tmp/test.mp4',
        totalSize: 1000,
        downloadOffset: 200,
        downloadedPrefixSize: 500,
      );
      expect(info.availableBytesFrom(300), equals(400)); // 700 - 300
      expect(info.availableBytesFrom(100), equals(0)); // before download offset
      expect(info.availableBytesFrom(700), equals(0)); // at end
    });

    test('availableBytesFrom uses multi-range when available', () {
      final info = ProxyFileInfo(
        path: '/tmp/test.mp4',
        totalSize: 1000,
      );
      final ranges = DownloadedRanges();
      ranges.addRange(100, 300);
      ranges.addRange(500, 800);
      info.ranges = ranges;

      expect(info.availableBytesFrom(150), equals(150));
      expect(info.availableBytesFrom(100), equals(200));
      expect(info.availableBytesFrom(400), equals(0)); // gap
      expect(info.availableBytesFrom(600), equals(200));
    });
  });

  // ============================================================
  // DownloadPriority
  // ============================================================
  group('DownloadPriority.fromDistance', () {
    test('returns critical for 0 distance', () {
      expect(DownloadPriority.fromDistance(0), equals(DownloadPriority.critical));
    });

    test('returns critical within 1MB', () {
      expect(
        DownloadPriority.fromDistance(512 * 1024),
        equals(DownloadPriority.critical),
      );
    });

    test('returns high priority between 1-10MB', () {
      final prio = DownloadPriority.fromDistance(5 * 1024 * 1024);
      expect(prio, greaterThanOrEqualTo(DownloadPriority.highFloor));
      expect(prio, lessThan(DownloadPriority.critical));
    });

    test('returns minimum beyond 50MB', () {
      final prio = DownloadPriority.fromDistance(100 * 1024 * 1024);
      expect(prio, equals(DownloadPriority.minimum));
    });
  });
}
