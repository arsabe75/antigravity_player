/// Centralized download priority management for LocalStreamingProxy.
///
/// TDLib uses priorities 1-32 where 32 is highest priority.
/// This class provides a unified API for priority calculation with
/// clear documentation of priority levels and their use cases.
///
/// ## Priority Levels:
/// - **32 (Critical)**: Immediate playback data, MOOV atoms
/// - **28-31 (Urgent)**: Near-playback buffer, interruptible by Critical
/// - **20-27 (High)**: Pre-buffering, seek preview
/// - **10-19 (Medium)**: Background prefetch
/// - **1-9 (Low)**: Far-ahead background loading
class DownloadPriority {
  // ============================================================
  // PRIORITY LEVEL CONSTANTS
  // ============================================================

  /// Critical priority - used for immediate playback and MOOV downloads
  static const int critical = 32;

  /// Deep buffering - high priority but can be interrupted by critical
  static const int deepBuffer = 28;

  /// High priority floor - minimum for active playback-related requests
  static const int highFloor = 20;

  /// Medium priority - for seek previews and preloading
  static const int medium = 16;

  /// Low priority - background prefetch
  static const int low = 10;

  /// Minimum priority - far-ahead background loading
  static const int minimum = 1;

  // ============================================================
  // DISTANCE THRESHOLDS (in bytes)
  // ============================================================

  /// Distance threshold for critical priority (0-1MB from playback)
  static const int criticalDistanceBytes = 1 * 1024 * 1024;

  /// Distance threshold for high priority (1-10MB from playback)
  static const int highDistanceBytes = 10 * 1024 * 1024;

  /// Distance threshold for low priority (10-50MB from playback)
  static const int lowDistanceBytes = 50 * 1024 * 1024;

  /// Maximum distance to consider a blocking request valid
  static const int maxBlockingDistanceBytes = 500 * 1024 * 1024;

  /// Distance behind primary to allow blocking (resume scenarios)
  static const int maxBehindPrimaryBytes = 100 * 1024 * 1024;

  /// Threshold for "low offset" requests (early file data)
  static const int lowOffsetThresholdBytes = 300 * 1024 * 1024;

  /// Distance to cache edge that is considered "continuation"
  static const int cacheEdgeDistanceBytes = 5 * 1024 * 1024;

  /// Distance difference needed to protect active download
  static const int priorityProtectionGap = 5;

  /// Distance from primary to be considered "closest"
  static const int closestToPrimaryBytes = 20 * 1024 * 1024;

  // ============================================================
  // PRIORITY CALCULATION
  // ============================================================

  /// Calculate priority based on distance from playback position.
  ///
  /// Returns priority from 1 (lowest) to 32 (highest) based on:
  /// - distanceBytes: Distance from current playback position
  ///
  /// Priority ranges:
  /// - 32: Critical (0-1MB ahead)
  /// - 20-31: High (1-10MB ahead) - linear interpolation
  /// - 1-10: Low (>10MB ahead) - linear interpolation
  static int fromDistance(int distanceBytes) {
    // Critical: 0-1MB
    if (distanceBytes < criticalDistanceBytes) {
      return critical;
    }

    // High: 1-10MB -> Priority 31-20
    if (distanceBytes < highDistanceBytes) {
      return _interpolate(
        distanceBytes,
        criticalDistanceBytes,
        highDistanceBytes,
        31,
        highFloor,
      );
    }

    // Low: 10-50MB -> Priority 10-1
    if (distanceBytes < lowDistanceBytes) {
      return _interpolate(
        distanceBytes,
        highDistanceBytes,
        lowDistanceBytes,
        low,
        minimum,
      );
    }

    // Beyond 50MB: minimum priority
    return minimum;
  }

  /// Linear interpolation helper for priority calculation.
  static int _interpolate(
    int value,
    int minValue,
    int maxValue,
    int maxPrio,
    int minPrio,
  ) {
    final range = maxValue - minValue;
    if (range <= 0) return maxPrio;

    final progress = (value - minValue) / range;
    final prio = maxPrio - (progress * (maxPrio - minPrio)).round();
    return prio.clamp(minPrio, maxPrio);
  }

  /// Determine if a blocking request should receive forced high priority.
  ///
  /// Returns true if the request is:
  /// - A MOOV download request
  /// - Within valid distance of primary playback position
  /// - Near cache edge (continuation scenario)
  /// - Early file data (<300MB)
  static bool shouldForceHighPriority({
    required bool isMoovDownload,
    required bool isBlocking,
    required int requestedOffset,
    int? primaryOffset,
    int? cacheEnd,
  }) {
    // MOOV downloads always get priority
    if (isMoovDownload) return true;

    // Non-blocking requests don't get forced priority
    if (!isBlocking) return false;

    // No primary yet - trust blocking flag
    if (primaryOffset == null) return true;

    final distToPrimary = requestedOffset - primaryOffset;

    // Forward buffering within 500MB
    if (distToPrimary >= 0 && distToPrimary < maxBlockingDistanceBytes) {
      return true;
    }

    // Backward (resume) within 100MB
    if (distToPrimary < 0 && distToPrimary.abs() < maxBehindPrimaryBytes) {
      return true;
    }

    // Cache edge continuation
    if (cacheEnd != null) {
      final distToCacheEnd = (requestedOffset - cacheEnd).abs();
      if (distToCacheEnd < cacheEdgeDistanceBytes) {
        return true;
      }
    }

    // Early file data (< 300MB)
    if (requestedOffset < lowOffsetThresholdBytes) {
      return true;
    }

    return false;
  }

  /// Check if an incoming request should be blocked to protect
  /// an existing high-priority active download.
  ///
  /// Returns true if the request should be rejected.
  static bool shouldProtectActiveDownload({
    required int incomingPriority,
    required int activePriority,
    required int requestedOffset,
    required int activeOffset,
    required bool isBlocking,
  }) {
    // Blocking requests are never rejected
    if (isBlocking) return false;

    // Only protect high-priority downloads
    if (activePriority < highFloor) return false;

    // Allow if priority difference is small
    if (incomingPriority >= activePriority - priorityProtectionGap) {
      return false;
    }

    // Allow if offsets are close
    if ((requestedOffset - activeOffset).abs() < cacheEdgeDistanceBytes) {
      return false;
    }

    // Block low-priority request that would displace high-priority
    return true;
  }
}
