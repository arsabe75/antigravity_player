/// Metrics for tracking download speed per file.
/// Used for adaptive buffer decisions inspired by Telegram Android's approach.
class DownloadMetrics {
  DateTime _lastUpdateTime = DateTime.now();
  int _bytesInWindow = 0;
  int _totalBytesDownloaded = 0;
  double _averageBytesPerSecond = 0;

  /// Total bytes downloaded since tracking started
  int get totalBytesDownloaded => _totalBytesDownloaded;

  void recordBytes(int bytes) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastUpdateTime).inMilliseconds;

    _bytesInWindow += bytes;
    _totalBytesDownloaded += bytes;

    // Update average every 500ms
    if (elapsed >= 500) {
      final currentSpeed = _bytesInWindow / (elapsed / 1000);
      // Exponential moving average
      _averageBytesPerSecond = _averageBytesPerSecond == 0
          ? currentSpeed
          : (_averageBytesPerSecond * 0.7 + currentSpeed * 0.3);
      _bytesInWindow = 0;
      _lastUpdateTime = now;
    }
  }

  /// Current download speed in bytes/second
  double get bytesPerSecond => _averageBytesPerSecond;

  /// Is the network considered "fast"? (> 2 MB/s)
  bool get isFastNetwork => _averageBytesPerSecond > 2 * 1024 * 1024;

  /// Is download stalled? (< 50 KB/s for more than 2s)
  bool get isStalled {
    final elapsed = DateTime.now().difference(_lastUpdateTime).inMilliseconds;
    return elapsed > 2000 && _averageBytesPerSecond < 50 * 1024;
  }

  // ============================================================
  // STALL TRACKING FOR ADAPTIVE POST-SEEK BUFFER
  // ============================================================

  int _recentStallCount = 0;
  DateTime? _lastStallTime;

  /// Record a stall event
  void recordStall() {
    _recentStallCount++;
    _lastStallTime = DateTime.now();
  }

  /// Returns stall count in last 30 seconds
  int get recentStallCount {
    final now = DateTime.now();
    if (_lastStallTime != null &&
        now.difference(_lastStallTime!).inSeconds > 30) {
      _recentStallCount = 0; // Reset after 30s without stalls
    }
    return _recentStallCount;
  }

  /// Reset stall count (e.g., after successful playback)
  void resetStallCount() {
    _recentStallCount = 0;
  }
}
