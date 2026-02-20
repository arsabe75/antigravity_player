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

  /// Initial timeout for normal data requests (grows with backoff on retries).
  static const Duration normalDataTimeoutInitial = Duration(seconds: 5);

  /// Maximum timeout for normal data requests after exponential backoff.
  static const Duration normalDataTimeoutMax = Duration(seconds: 30);

  /// Backoff multiplier for timeout growth per retry attempt.
  static const double timeoutBackoffMultiplier = 1.5;

  /// Extended timeout for MOOV atom requests (near end of file).
  static const Duration moovDataTimeout = Duration(seconds: 20);

  // ============================================================
  // ADAPTIVE RETRY
  // ============================================================

  /// Max retries for fast networks (>2MB/s): fail fast, likely a real problem.
  static const int retryMinCount = 3;

  /// Max retries for normal network speed.
  static const int retryDefaultCount = 5;

  /// Max retries for slow networks (<500KB/s): be patient.
  static const int retryMaxCount = 10;

  /// Base delay for exponential backoff between retries (ms).
  static const int retryBackoffBaseMs = 1000;

  /// Maximum delay between retries (ms).
  static const int retryBackoffMaxMs = 15000;

  /// Multiplier for exponential backoff between retries.
  static const double retryBackoffMultiplier = 2.0;

  /// Interval for stall detection checks.
  static const Duration stallCheckInterval = Duration(seconds: 2);

  // ============================================================
  // THROTTLING
  // ============================================================

  /// Throttle TDLib updateFile events processing (milliseconds).
  /// Active waiters bypass this entirely; this only affects background updates.
  static const int updateThrottleMs = 100;

  /// Debounce rapid seeks to prevent TDLib flooding (milliseconds).
  static const int seekDebounceMs = 500;

  /// Minimum interval between downloadFile TDLib calls for the same file (ms).
  static const int minDownloadCallIntervalMs = 300;

  /// Maximum concurrent HTTP connections per file.
  static const int maxConnectionsPerFile = 6;

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
  // MOOV DETECTION & DOWNLOAD
  // ============================================================

  /// Minimum prefix bytes needed for MOOV atom parsing at file start.
  static const int moovDetectionMinPrefix = 1024; // 1KB

  /// Prefix threshold to infer MOOV-at-end when moov not found at start.
  static const int moovAtEndInferenceThreshold = 5 * 1024 * 1024; // 5MB

  /// Minimum file size to attempt early MOOV detection.
  static const int moovDetectionMinFileSize = 10 * 1024 * 1024; // 10MB

  /// Maximum cap for MOOV atom download size.
  static const int moovDownloadMaxBytes = 20 * 1024 * 1024; // 20MB

  /// Max MOOV region clamp for isMoovRequest detection (broad check).
  static const int moovRegionClampMaxBytes = 100 * 1024 * 1024; // 100MB

  /// Max MOOV region clamp for isMoovDownload detection (tighter check).
  static const int moovDownloadRegionMaxBytes = 50 * 1024 * 1024; // 50MB

  /// Delay before scheduling async MOOV position detection (ms).
  static const int moovDetectScheduleDelayMs = 500;

  // ============================================================
  // SCALED THRESHOLDS (file-size-proportional)
  // ============================================================

  /// Minimum bytes for MOOV region detection.
  static const int moovRegionMinBytes = 5 * 1024 * 1024; // 5MB

  /// Minimum bytes served to consider active playback (small files).
  static const int activePlaybackMinBytes = 1 * 1024 * 1024; // 1MB

  /// Minimum MOOV preload clamp (small files).
  static const int moovPreloadMinBytes = 512 * 1024; // 512KB

  /// Minimum significant jump threshold (small files).
  static const int significantJumpMinBytes = 2 * 1024 * 1024; // 2MB

  // ============================================================
  // SCALED THRESHOLD PERCENTAGES & LIMITS
  // ============================================================

  static const double seekDetectionThresholdPercent = 0.05;
  static const double sequentialReadThresholdPercent = 0.05;

  static const double moovPreloadThresholdPercent = 0.05;
  static const int moovPreloadMaxBytes = 5 * 1024 * 1024; // 5MB

  static const double activePlaybackThresholdPercent = 0.10;
  static const int activePlaybackMaxBytes = 10 * 1024 * 1024; // 10MB

  static const double significantJumpThresholdPercent = 0.10;
  static const int significantJumpMaxBytes = 50 * 1024 * 1024; // 50MB

  static const double frontierProximityThresholdPercent = 0.05;
  static const int frontierProximityMinBytes = 1 * 1024 * 1024; // 1MB
  static const int frontierProximityMaxBytes = 5 * 1024 * 1024; // 5MB

  static const double moovRegionThresholdPercent = 0.005;
  static const int moovRegionMaxBytes = 10 * 1024 * 1024; // 10MB

  static const double moovDownloadThresholdPercent = 0.01;

  static const double scrubMoovDetectionThresholdPercent = 0.05;

  static const double moovReadyThresholdPercent = 0.05;

  static const double primaryProgressBaseThresholdPercent = 0.10;

  static const int streamChunkSize = 512 * 1024; // 512KB

  static const double maxForwardBufferPercent = 0.80;
  static const int maxForwardBufferMinBytes = 50 * 1024 * 1024; // 50MB
  static const int maxForwardBufferMaxBytes = 500 * 1024 * 1024; // 500MB

  static const double maxBackwardOverlapPercent = 0.50;
  static const int maxBackwardOverlapMinBytes = 10 * 1024 * 1024; // 10MB
  static const int maxBackwardOverlapMaxBytes = 100 * 1024 * 1024; // 100MB

  static const double earlyFileThresholdPercent = 0.50;
  static const int earlyFileThresholdMinBytes = 10 * 1024 * 1024; // 10MB
  static const int earlyFileThresholdMaxBytes = 300 * 1024 * 1024; // 300MB

  static const double cacheEdgeProximityPercent = 0.05;
  static const int cacheEdgeProximityMinBytes = 1 * 1024 * 1024; // 1MB
  static const int cacheEdgeProximityMaxBytes = 5 * 1024 * 1024; // 5MB

  // ============================================================
  // PREFETCH BUFFER
  // ============================================================

  /// Minimum prefetch buffer target (bytes).
  static const int prefetchMinBytes = 2 * 1024 * 1024; // 2MB

  /// Maximum prefetch buffer target (bytes).
  static const int prefetchMaxBytes = 50 * 1024 * 1024; // 50MB

  /// Default prefetch buffer when no speed data available (bytes).
  static const int prefetchDefaultBytes = 5 * 1024 * 1024; // 5MB

  /// Seconds of video to buffer ahead on fast networks (>2MB/s).
  static const double prefetchSecondsFast = 5.0;

  /// Seconds of video to buffer ahead on normal networks.
  static const double prefetchSecondsNormal = 10.0;

  /// Seconds of video to buffer ahead on slow networks (<500KB/s).
  static const double prefetchSecondsSlow = 15.0;

  /// Prefetch triggers when buffer ahead < this fraction of target.
  static const double prefetchTriggerRatio = 0.5;

  /// Debounce after TDLib goes idle before evaluating prefetch (ms).
  static const int prefetchDebounceMs = 500;

  /// Periodic fallback timer for prefetch evaluation (ms).
  static const int prefetchPeriodicCheckMs = 3000;

  /// Minimum gap size worth prefetching (skip tiny gaps).
  static const int prefetchMinGapBytes = 256 * 1024; // 256KB

  // ============================================================
  // SEEK & PLAYBACK TRACKING (scaled for small files)
  // ============================================================

  /// Min seek detection threshold (small files). Jumps larger than this
  /// are treated as a "seek" rather than sequential read.
  static const int seekDetectionMinBytes = 256 * 1024; // 256KB

  /// Max seek detection threshold (large files).
  static const int seekDetectionMaxBytes = 1 * 1024 * 1024; // 1MB

  /// Min sequential read window (small files).
  static const int sequentialReadMinBytes = 128 * 1024; // 128KB

  /// Max sequential read window (large files).
  static const int sequentialReadMaxBytes = 2 * 1024 * 1024; // 2MB

  /// Min MOOV-ready bytes before declaring MOOV loaded (small files).
  static const int moovReadyMinBytes = 128 * 1024; // 128KB

  /// Max MOOV-ready threshold (large files).
  static const int moovReadyMaxBytes = 2 * 1024 * 1024; // 2MB

  /// Min base bytes for instant primary offset progress (small files).
  static const int primaryProgressBaseMinBytes = 256 * 1024; // 256KB

  /// Max base bytes for instant primary offset progress (large files).
  static const int primaryProgressBaseMaxBytes = 2 * 1024 * 1024; // 2MB

  /// Rate limit for primary offset advance (bytes/sec).
  static const int primaryProgressRateBytesPerSec = 3 * 1024 * 1024; // 3MB/s

  /// Min post-seek preload size (small files).
  static const int postSeekPreloadMinBytes = 128 * 1024; // 128KB

  /// Max post-seek preload size (large files).
  static const int postSeekPreloadMaxBytes = 1 * 1024 * 1024; // 1MB

  // ============================================================
  // PRIMARY TRACKING TIMING
  // ============================================================

  /// Duration (ms) before considering primary offset "stagnant".
  static const int stagnantPrimaryMs = 2000;

  /// Throttle interval (ms) for primary offset map updates.
  static const int primaryUpdateThrottleMs = 200;

  /// Window (ms) for detecting divergent rapid seeks.
  static const int rapidDivergenceWindowMs = 1000;

  // ============================================================
  // OPERATIONAL DELAYS & LIMITS
  // ============================================================

  /// TDLib stabilization delay after aborting this file (ms).
  static const int abortStabilizationAbortedMs = 500;

  /// TDLib stabilization delay after aborting other files (ms).
  static const int abortStabilizationOtherMs = 200;

  /// TDLib stabilization delay after deleteFile (ms).
  static const int tdlibDeleteStabilizationMs = 300;

  /// TDLib stabilization delay after stale partial cleanup (ms).
  static const int tdlibStaleCleanupDelayMs = 200;

  /// TDLib initialization: max wait attempts.
  static const int tdlibInitMaxAttempts = 100;

  /// TDLib initialization: wait interval per attempt (ms).
  static const int tdlibInitWaitMs = 100;

  /// Cooldown for sequential reads (ms).
  static const int cooldownSequentialMs = 50;

  /// Cooldown for non-sequential reads (ms).
  static const int cooldownNonSequentialMs = 100;

  /// Min distance for sequential cooldown bypass.
  static const int minDistanceSequentialBytes = 256 * 1024; // 256KB

  /// Min distance for non-sequential cooldown bypass.
  static const int minDistanceNonSequentialBytes = 512 * 1024; // 512KB

  /// Debounce for rapid offset switches (ms).
  static const int rapidSwitchDebounceMs = 100;

  /// Deadlock detection: time before phantom-active check (ms).
  static const int deadlockCheckMs = 1000;

  /// Retry delay on empty data read (ms).
  static const int emptyDataRetryMs = 50;

  /// File open retry: max attempts.
  static const int fileOpenMaxRetries = 5;

  /// File open retry: base delay (ms), exponentially backed off.
  static const int fileOpenRetryBaseMs = 50;

  /// Seek preview cooldown (ms).
  static const int previewCooldownMs = 100;

  /// Seek preview preload size.
  static const int previewPreloadBytes = 2 * 1024 * 1024; // 2MB

  /// Fetch file info: wait interval per attempt (ms).
  static const int fetchWaitIntervalMs = 200;

  /// Fetch file info: max attempts.
  static const int fetchMaxAttempts = 50;

  // ============================================================
  // UTILITY
  // ============================================================

  /// Calculates a file-size-proportional threshold.
  /// Returns (fileSize * percent).round().clamp(absoluteMin, absoluteMax).
  /// Ensures thresholds scale down for small files while maintaining
  /// existing behavior for large files (>= 500MB).
  static int scaled(
    int fileSize,
    double percent,
    int absoluteMin,
    int absoluteMax,
  ) {
    return (fileSize * percent).round().clamp(absoluteMin, absoluteMax);
  }
}
