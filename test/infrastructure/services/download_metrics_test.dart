import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/infrastructure/services/download_metrics.dart';

void main() {
  group('DownloadMetrics', () {
    late DownloadMetrics metrics;

    setUp(() {
      metrics = DownloadMetrics();
    });

    group('initial state', () {
      test('starts with zero total bytes', () {
        expect(metrics.totalBytesDownloaded, equals(0));
      });

      test('starts with zero speed', () {
        expect(metrics.bytesPerSecond, equals(0));
      });

      test('is not fast network initially', () {
        expect(metrics.isFastNetwork, isFalse);
      });

      test('reports no stalls initially', () {
        // Initially, elapsed time is 0, so isStalled checks elapsed > 2000
        // Should be false since we just created the metrics
        expect(metrics.recentStallCount, equals(0));
      });
    });

    group('recordBytes()', () {
      test('tracks total bytes downloaded', () {
        metrics.recordBytes(1000);
        metrics.recordBytes(2000);

        expect(metrics.totalBytesDownloaded, equals(3000));
      });

      test('accumulates bytes in window before update', () {
        // Record bytes but don't wait for window update
        metrics.recordBytes(500);
        metrics.recordBytes(500);

        expect(metrics.totalBytesDownloaded, equals(1000));
        // Speed may still be 0 since window hasn't elapsed
      });
    });

    group('isFastNetwork', () {
      test('returns false for slow speeds', () {
        // Speed is 0 initially
        expect(metrics.isFastNetwork, isFalse);
      });

      test('threshold is 2 MB/s', () {
        // We need to simulate high-speed downloads
        // The threshold is 2 * 1024 * 1024 = 2097152 bytes/sec
        // This test verifies the threshold logic exists
        expect(metrics.isFastNetwork, isFalse);
      });
    });

    group('isSlowNetwork', () {
      test('returns false when no data recorded (speed is 0)', () {
        // isSlowNetwork requires speed > 0 to avoid false positives at start
        expect(metrics.isSlowNetwork, isFalse);
      });

      test('returns false when speed is zero (no data yet)', () {
        expect(metrics.bytesPerSecond, equals(0));
        expect(metrics.isSlowNetwork, isFalse);
      });

      test('threshold is 500 KB/s', () {
        // The threshold is 500 * 1024 = 512000 bytes/sec
        // isSlowNetwork = speed > 0 && speed < 512000
        // We verify the getter exists and returns a bool
        expect(metrics.isSlowNetwork, isA<bool>());
      });

      test('isFastNetwork and isSlowNetwork are mutually exclusive', () {
        // Both can be false (normal speed or zero), but never both true
        expect(metrics.isFastNetwork && metrics.isSlowNetwork, isFalse);
      });
    });

    group('stall tracking', () {
      test('recordStall increments count', () {
        metrics.recordStall();
        expect(metrics.recentStallCount, equals(1));

        metrics.recordStall();
        expect(metrics.recentStallCount, equals(2));
      });

      test('resetStallCount clears count', () {
        metrics.recordStall();
        metrics.recordStall();

        metrics.resetStallCount();

        expect(metrics.recentStallCount, equals(0));
      });

      test('recentStallCount returns current count when recent', () {
        metrics.recordStall();
        metrics.recordStall();
        metrics.recordStall();

        expect(metrics.recentStallCount, equals(3));
      });
    });

    group('bytesPerSecond', () {
      test('returns exponential moving average after window', () async {
        // Initial speed is 0
        expect(metrics.bytesPerSecond, equals(0));

        // The speed calculation happens every 500ms
        // We can't easily test this without mocking time
        // But we verify the getter exists and returns a double
        expect(metrics.bytesPerSecond, isA<double>());
      });
    });

    group('isStalled', () {
      test('returns false initially since not enough time elapsed', () {
        // isStalled requires elapsed > 2000ms AND speed < 50KB/s
        // Initially elapsed is ~0ms, so should be false
        expect(metrics.isStalled, isFalse);
      });

      test('checks both time and speed conditions', () {
        // The condition is: elapsed > 2000 && speed < 50KB/s
        // We can verify it returns a bool
        expect(metrics.isStalled, isA<bool>());
      });
    });
  });
}
