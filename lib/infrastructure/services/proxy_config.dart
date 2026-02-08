/// Centralized configuration for LocalStreamingProxy.
/// Adjust these values to tune streaming behavior.
class ProxyConfig {
  ProxyConfig._();

  // ============================================================
  // BUFFER SIZES
  // ============================================================

  /// Minimum bytes to preload before serving to player (default).
  static const int minPreloadBytes = 2 * 1024 * 1024; // 2MB

  /// Preload size for fast network connections (>5MB/s).
  static const int fastNetworkPreload = 1 * 1024 * 1024; // 1MB

  /// Preload size for slow network connections (<1MB/s).
  static const int slowNetworkPreload = 4 * 1024 * 1024; // 4MB

  // ============================================================
  // TIMEOUTS
  // ============================================================

  /// Grace period for video initialization.
  /// Prevents false stalls during MOOV-at-end video loading.
  static const Duration initializationGracePeriod = Duration(seconds: 30);

  /// Timeout for normal data requests.
  static const Duration normalDataTimeout = Duration(seconds: 5);

  /// Extended timeout for MOOV atom requests (near end of file).
  static const Duration moovDataTimeout = Duration(seconds: 15);

  /// Interval for stall detection checks.
  static const Duration stallCheckInterval = Duration(seconds: 2);

  // ============================================================
  // THROTTLING
  // ============================================================

  /// Throttle TDLib updateFile events processing (milliseconds).
  /// Higher values reduce Windows message queue overflow risk.
  static const int updateThrottleMs = 500;

  /// Debounce rapid seeks to prevent TDLib flooding (milliseconds).
  static const int seekDebounceMs = 500;

  /// "Waiting for data" log throttle duration.
  static const Duration waitingLogThrottle = Duration(seconds: 2);

  /// "Protected region" log throttle duration.
  static const Duration protectedLogThrottle = Duration(seconds: 5);

  // ============================================================
  // CACHE ENFORCEMENT
  // ============================================================

  /// Bytes downloaded before triggering cache limit enforcement.
  static const int enforcementThresholdBytes = 500 * 1024 * 1024; // 500MB

  /// Minimum time between cache enforcement runs (milliseconds).
  static const int enforcementDebounceMs = 10000; // 10 seconds

  /// Cache disk safety check validity (milliseconds).
  static const int diskCheckCacheMs = 5000; // 5 seconds

  // ============================================================
  // MOOV DETECTION
  // ============================================================

  /// Minimum prefix bytes needed for MOOV detection.
  static const int moovDetectionMinPrefix = 1024; // 1KB

  /// Threshold to infer MOOV-at-end based on offset pattern.
  static const int moovAtEndInferenceThreshold = 100 * 1024 * 1024; // 100MB
}
