import 'dart:math';

/// Tracks retry attempts per file with adaptive limits based on network speed.
/// Prevents infinite retry loops while being patient with slow connections.
class RetryTracker {
  /// Default maximum retries (used when no per-file override is set)
  static const int defaultMaxRetries = 5;

  /// Time window for retry counting - retries older than this are forgotten
  static const Duration retryWindow = Duration(minutes: 5);

  /// History of retry timestamps per file
  final Map<int, List<DateTime>> _retryHistory = {};

  /// Per-file max retry overrides (set dynamically based on network speed)
  final Map<int, int> _maxRetriesPerFile = {};

  /// Callbacks to notify when max retries are exceeded
  final Map<int, void Function(int fileId)> _onMaxRetriesCallbacks = {};

  /// Set the max retry count for a specific file.
  /// Called by the proxy to adjust based on network speed:
  /// - Fast network (>2MB/s): lower count (aggressive fail-fast)
  /// - Slow network (<500KB/s): higher count (patient)
  void setMaxRetries(int fileId, int max) {
    _maxRetriesPerFile[fileId] = max;
  }

  /// Get the effective max retries for a file
  int _getMaxRetries(int fileId) {
    return _maxRetriesPerFile[fileId] ?? defaultMaxRetries;
  }

  /// Check if a file can still be retried
  bool canRetry(int fileId) {
    _cleanOldEntries(fileId);
    return (_retryHistory[fileId]?.length ?? 0) < _getMaxRetries(fileId);
  }

  /// Record a retry attempt for a file
  void recordRetry(int fileId) {
    _retryHistory.putIfAbsent(fileId, () => []);
    _retryHistory[fileId]!.add(DateTime.now());

    // Check if we just hit the limit
    if (!canRetry(fileId)) {
      _onMaxRetriesCallbacks[fileId]?.call(fileId);
    }
  }

  /// Get the number of remaining retries for a file
  int remainingRetries(int fileId) {
    _cleanOldEntries(fileId);
    return _getMaxRetries(fileId) - (_retryHistory[fileId]?.length ?? 0);
  }

  /// Get total retry attempts for a file
  int totalAttempts(int fileId) {
    return _retryHistory[fileId]?.length ?? 0;
  }

  /// Calculate exponential backoff delay based on attempt count.
  /// Attempt 1: 1s, Attempt 2: 2s, Attempt 3: 4s, ... capped at 15s.
  /// [baseMs] and [maxMs] can be overridden via ProxyConfig.
  Duration getBackoffDelay(
    int fileId, {
    int baseMs = 1000,
    int maxMs = 15000,
    double multiplier = 2.0,
  }) {
    final attempts = totalAttempts(fileId);
    if (attempts <= 0) return Duration.zero;

    // Exponential: base * multiplier^(attempts-1), capped at max
    final delayMs = (baseMs * pow(multiplier, attempts - 1)).round().clamp(
      baseMs,
      maxMs,
    );
    return Duration(milliseconds: delayMs);
  }

  /// Reset retry counter for a file (e.g., when switching videos)
  void reset(int fileId) {
    _retryHistory.remove(fileId);
    _maxRetriesPerFile.remove(fileId);
    _onMaxRetriesCallbacks.remove(fileId);
  }

  /// Reset all retry counters
  void resetAll() {
    _retryHistory.clear();
    _maxRetriesPerFile.clear();
    _onMaxRetriesCallbacks.clear();
  }

  /// Register a callback for when max retries are exceeded
  void onMaxRetries(int fileId, void Function(int fileId) callback) {
    _onMaxRetriesCallbacks[fileId] = callback;
  }

  /// Remove stale entries outside the retry window
  void _cleanOldEntries(int fileId) {
    final entries = _retryHistory[fileId];
    if (entries == null) return;

    final now = DateTime.now();
    entries.removeWhere((timestamp) => now.difference(timestamp) > retryWindow);

    if (entries.isEmpty) {
      _retryHistory.remove(fileId);
    }
  }
}
