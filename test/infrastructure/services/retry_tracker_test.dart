import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/infrastructure/services/retry_tracker.dart';

void main() {
  group('RetryTracker', () {
    late RetryTracker tracker;

    setUp(() {
      tracker = RetryTracker();
    });

    group('default behavior', () {
      test('canRetry returns true initially', () {
        expect(tracker.canRetry(1), isTrue);
      });

      test('totalAttempts is 0 initially', () {
        expect(tracker.totalAttempts(1), equals(0));
      });

      test('remainingRetries equals defaultMaxRetries initially', () {
        expect(
          tracker.remainingRetries(1),
          equals(RetryTracker.defaultMaxRetries),
        );
      });

      test('exhausts after defaultMaxRetries attempts', () {
        for (var i = 0; i < RetryTracker.defaultMaxRetries; i++) {
          expect(tracker.canRetry(1), isTrue);
          tracker.recordRetry(1);
        }
        expect(tracker.canRetry(1), isFalse);
      });

      test('remainingRetries decrements correctly', () {
        tracker.recordRetry(1);
        tracker.recordRetry(1);
        expect(
          tracker.remainingRetries(1),
          equals(RetryTracker.defaultMaxRetries - 2),
        );
      });
    });

    group('setMaxRetries (adaptive)', () {
      test('overrides default max for a specific file', () {
        tracker.setMaxRetries(1, 3);
        tracker.recordRetry(1);
        tracker.recordRetry(1);
        tracker.recordRetry(1);
        expect(tracker.canRetry(1), isFalse);
      });

      test('different files can have different limits', () {
        tracker.setMaxRetries(1, 3); // fast network
        tracker.setMaxRetries(2, 10); // slow network

        for (var i = 0; i < 3; i++) {
          tracker.recordRetry(1);
          tracker.recordRetry(2);
        }

        expect(tracker.canRetry(1), isFalse); // file 1 exhausted at 3
        expect(tracker.canRetry(2), isTrue); // file 2 still has 7 left
      });

      test('can increase max after initial retries', () {
        // Start with default (5), use 4 retries
        for (var i = 0; i < 4; i++) {
          tracker.recordRetry(1);
        }
        expect(tracker.remainingRetries(1), equals(1));

        // Network slowed down, increase max to 10
        tracker.setMaxRetries(1, 10);
        expect(tracker.remainingRetries(1), equals(6));
        expect(tracker.canRetry(1), isTrue);
      });

      test('remainingRetries reflects per-file max', () {
        tracker.setMaxRetries(1, 8);
        tracker.recordRetry(1);
        expect(tracker.remainingRetries(1), equals(7));
      });
    });

    group('getBackoffDelay', () {
      test('returns zero when no attempts recorded', () {
        expect(tracker.getBackoffDelay(1), equals(Duration.zero));
      });

      test('returns base delay after first attempt', () {
        tracker.recordRetry(1);
        final delay = tracker.getBackoffDelay(1, baseMs: 1000);
        expect(delay.inMilliseconds, equals(1000));
      });

      test('grows exponentially with attempts', () {
        tracker.recordRetry(1);
        final delay1 = tracker.getBackoffDelay(1, baseMs: 1000, multiplier: 2.0);

        tracker.recordRetry(1);
        final delay2 = tracker.getBackoffDelay(1, baseMs: 1000, multiplier: 2.0);

        tracker.recordRetry(1);
        final delay3 = tracker.getBackoffDelay(1, baseMs: 1000, multiplier: 2.0);

        expect(delay1.inMilliseconds, equals(1000)); // 1000 * 2^0
        expect(delay2.inMilliseconds, equals(2000)); // 1000 * 2^1
        expect(delay3.inMilliseconds, equals(4000)); // 1000 * 2^2
      });

      test('caps at maxMs', () {
        // Record many retries
        for (var i = 0; i < 20; i++) {
          tracker.recordRetry(1);
        }
        final delay = tracker.getBackoffDelay(
          1,
          baseMs: 1000,
          maxMs: 15000,
          multiplier: 2.0,
        );
        expect(delay.inMilliseconds, equals(15000));
      });

      test('never goes below baseMs', () {
        tracker.recordRetry(1);
        final delay = tracker.getBackoffDelay(1, baseMs: 500);
        expect(delay.inMilliseconds, greaterThanOrEqualTo(500));
      });
    });

    group('reset', () {
      test('clears retries for a specific file', () {
        tracker.recordRetry(1);
        tracker.recordRetry(1);
        tracker.setMaxRetries(1, 3);

        tracker.reset(1);

        expect(tracker.totalAttempts(1), equals(0));
        expect(tracker.canRetry(1), isTrue);
        // After reset, max reverts to default
        expect(
          tracker.remainingRetries(1),
          equals(RetryTracker.defaultMaxRetries),
        );
      });

      test('does not affect other files', () {
        tracker.recordRetry(1);
        tracker.recordRetry(2);

        tracker.reset(1);

        expect(tracker.totalAttempts(1), equals(0));
        expect(tracker.totalAttempts(2), equals(1));
      });
    });

    group('resetAll', () {
      test('clears everything', () {
        tracker.recordRetry(1);
        tracker.recordRetry(2);
        tracker.setMaxRetries(1, 3);
        tracker.setMaxRetries(2, 10);

        tracker.resetAll();

        expect(tracker.totalAttempts(1), equals(0));
        expect(tracker.totalAttempts(2), equals(0));
        expect(tracker.canRetry(1), isTrue);
        expect(tracker.canRetry(2), isTrue);
      });
    });

    group('onMaxRetries callback', () {
      test('fires when max retries exceeded', () {
        int? calledWith;
        tracker.setMaxRetries(1, 2);
        tracker.onMaxRetries(1, (fileId) => calledWith = fileId);

        tracker.recordRetry(1);
        expect(calledWith, isNull); // not yet

        tracker.recordRetry(1);
        expect(calledWith, equals(1)); // triggered
      });

      test('callback cleared on reset', () {
        int callCount = 0;
        tracker.setMaxRetries(1, 1);
        tracker.onMaxRetries(1, (_) => callCount++);

        tracker.reset(1);
        tracker.setMaxRetries(1, 1);
        tracker.recordRetry(1);

        // Callback was cleared by reset, so should not fire
        expect(callCount, equals(0));
      });
    });
  });
}
