import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/infrastructure/services/proxy_config.dart';

void main() {
  group('ProxyConfig', () {
    group('buffer sizes', () {
      test('minPreloadBytes is 2MB', () {
        expect(ProxyConfig.minPreloadBytes, equals(2 * 1024 * 1024));
      });

      test('fastNetworkPreload is 1MB', () {
        expect(ProxyConfig.fastNetworkPreload, equals(1 * 1024 * 1024));
      });

      test('slowNetworkPreload is 4MB', () {
        expect(ProxyConfig.slowNetworkPreload, equals(4 * 1024 * 1024));
      });

      test('slow network has larger preload than fast', () {
        expect(
          ProxyConfig.slowNetworkPreload,
          greaterThan(ProxyConfig.fastNetworkPreload),
        );
      });
    });

    group('timeouts', () {
      test('initializationGracePeriod is 30 seconds', () {
        expect(
          ProxyConfig.initializationGracePeriod,
          equals(const Duration(seconds: 30)),
        );
      });

      test('normalDataTimeoutInitial is 5 seconds', () {
        expect(
          ProxyConfig.normalDataTimeoutInitial,
          equals(const Duration(seconds: 5)),
        );
      });

      test('normalDataTimeoutMax is 30 seconds', () {
        expect(
          ProxyConfig.normalDataTimeoutMax,
          equals(const Duration(seconds: 30)),
        );
      });

      test('moovDataTimeout is 20 seconds', () {
        expect(
          ProxyConfig.moovDataTimeout,
          equals(const Duration(seconds: 20)),
        );
      });

      test('moov timeout is longer than initial normal timeout', () {
        expect(
          ProxyConfig.moovDataTimeout,
          greaterThan(ProxyConfig.normalDataTimeoutInitial),
        );
      });

      test('adaptive retry constants are consistent', () {
        expect(ProxyConfig.retryMinCount, lessThan(ProxyConfig.retryDefaultCount));
        expect(ProxyConfig.retryDefaultCount, lessThan(ProxyConfig.retryMaxCount));
        expect(ProxyConfig.retryBackoffBaseMs, lessThan(ProxyConfig.retryBackoffMaxMs));
      });

      test('stallCheckInterval is 2 seconds', () {
        expect(
          ProxyConfig.stallCheckInterval,
          equals(const Duration(seconds: 2)),
        );
      });
    });

    group('throttling', () {
      test('updateThrottleMs is 100', () {
        expect(ProxyConfig.updateThrottleMs, equals(100));
      });

      test('seekDebounceMs is 500', () {
        expect(ProxyConfig.seekDebounceMs, equals(500));
      });

      test('waitingLogThrottle is 2 seconds', () {
        expect(
          ProxyConfig.waitingLogThrottle,
          equals(const Duration(seconds: 2)),
        );
      });

      test('protectedLogThrottle is 5 seconds', () {
        expect(
          ProxyConfig.protectedLogThrottle,
          equals(const Duration(seconds: 5)),
        );
      });
    });

    group('cache enforcement', () {
      test('enforcementThresholdBytes is 500MB', () {
        expect(
          ProxyConfig.enforcementThresholdBytes,
          equals(500 * 1024 * 1024),
        );
      });

      test('enforcementDebounceMs is 10 seconds', () {
        expect(ProxyConfig.enforcementDebounceMs, equals(10000));
      });

      test('diskCheckCacheMs is 5 seconds', () {
        expect(ProxyConfig.diskCheckCacheMs, equals(5000));
      });
    });

    group('prefetch buffer', () {
      test('prefetchMinBytes is 2MB', () {
        expect(ProxyConfig.prefetchMinBytes, equals(2 * 1024 * 1024));
      });

      test('prefetchMaxBytes is 50MB', () {
        expect(ProxyConfig.prefetchMaxBytes, equals(50 * 1024 * 1024));
      });

      test('prefetchDefaultBytes is 5MB', () {
        expect(ProxyConfig.prefetchDefaultBytes, equals(5 * 1024 * 1024));
      });

      test('prefetch seconds: slow > normal > fast', () {
        expect(
          ProxyConfig.prefetchSecondsSlow,
          greaterThan(ProxyConfig.prefetchSecondsNormal),
        );
        expect(
          ProxyConfig.prefetchSecondsNormal,
          greaterThan(ProxyConfig.prefetchSecondsFast),
        );
      });

      test('prefetchTriggerRatio is between 0 and 1', () {
        expect(ProxyConfig.prefetchTriggerRatio, greaterThan(0));
        expect(ProxyConfig.prefetchTriggerRatio, lessThanOrEqualTo(1.0));
      });

      test('prefetchDebounceMs is 500', () {
        expect(ProxyConfig.prefetchDebounceMs, equals(500));
      });

      test('prefetchPeriodicCheckMs is 3000', () {
        expect(ProxyConfig.prefetchPeriodicCheckMs, equals(3000));
      });

      test('prefetchMinGapBytes is 256KB', () {
        expect(ProxyConfig.prefetchMinGapBytes, equals(256 * 1024));
      });
    });

    group('MOOV detection', () {
      test('moovDetectionMinPrefix is 1KB', () {
        expect(ProxyConfig.moovDetectionMinPrefix, equals(1024));
      });

      test('moovAtEndInferenceThreshold is 5MB', () {
        expect(
          ProxyConfig.moovAtEndInferenceThreshold,
          equals(5 * 1024 * 1024),
        );
      });
    });
  });
}
