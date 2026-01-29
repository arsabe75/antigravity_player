/// Tracks retry attempts per file with configurable limits.
/// Prevents infinite retry loops by enforcing maximum attempts.
class RetryTracker {
  /// Maximum number of retry attempts per file
  static const int maxRetries = 5;

  /// Time window for retry counting - retries older than this are forgotten
  static const Duration retryWindow = Duration(minutes: 5);

  /// History of retry timestamps per file
  final Map<int, List<DateTime>> _retryHistory = {};

  /// Callbacks to notify when max retries are exceeded
  final Map<int, void Function(int fileId)> _onMaxRetriesCallbacks = {};

  /// Check if a file can still be retried
  bool canRetry(int fileId) {
    _cleanOldEntries(fileId);
    return (_retryHistory[fileId]?.length ?? 0) < maxRetries;
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
    return maxRetries - (_retryHistory[fileId]?.length ?? 0);
  }

  /// Get total retry attempts for a file
  int totalAttempts(int fileId) {
    return _retryHistory[fileId]?.length ?? 0;
  }

  /// Reset retry counter for a file (e.g., when switching videos)
  void reset(int fileId) {
    _retryHistory.remove(fileId);
    _onMaxRetriesCallbacks.remove(fileId);
  }

  /// Reset all retry counters
  void resetAll() {
    _retryHistory.clear();
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
