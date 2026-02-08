import '../value_objects/loading_progress.dart';
import '../value_objects/streaming_error.dart';

abstract class StreamingRepository {
  /// Aborts a specific file request to stop streaming data
  void abortRequest(int fileId);

  /// Gets the active port of the local streaming server
  int get port;

  /// Preview seek target - start downloading at estimated offset with lower priority
  /// This is called during slider drag to preload data before user releases
  void previewSeekTarget(int fileId, int estimatedOffset);

  /// Get accurate byte offset for a time position using MP4 sample table
  /// Falls back to linear estimation if sample table unavailable
  Future<int> getByteOffsetForTime(
    int fileId,
    int timeMs,
    int totalDurationMs,
    int totalBytes,
  );

  /// Check if a video is NOT optimized for streaming (moov atom at end of file)
  /// Returns true if the video requires extra loading time due to metadata placement
  bool isVideoNotOptimizedForStreaming(int fileId);

  /// P1: Two-tier preloading when videos appear in list view
  /// isVisible=true: Priority 5, 2MB + MOOV | isVisible=false: Priority 1, 512KB only
  @Deprecated(
    'Preloading disabled due to TDLib limitations. Remove calls to this method.',
  )
  void preloadVideoStart(int fileId, int? totalSize, {bool isVisible = false});

  /// Get current loading progress for a file.
  /// Returns null if file is not being tracked.
  /// UI can use this to show loading indicators, progress bars, and MOOV fetching status.
  LoadingProgress? getLoadingProgress(int fileId);

  /// Get the last streaming error for a file, or null if no error.
  /// UI can use this to show error messages.
  StreamingError? getLastError(int fileId);

  /// Clear error state for a file and reset retry counter.
  /// Call this when user wants to manually retry a failed video.
  void clearError(int fileId);

  /// Reset retry counter without clearing error state.
  /// Call this when playback recovers successfully to prevent
  /// cascading MAX_RETRIES_EXCEEDED errors.
  void resetRetryCount(int fileId);

  /// Register a callback for streaming errors.
  /// This callback is invoked when an unrecoverable error occurs.
  set onStreamingError(void Function(StreamingError error)? callback);

  /// Report a player-detected error (e.g. unsupported codec, corrupt file).
  /// Marks the file as unrecoverable in the proxy and invokes [onStreamingError].
  void reportPlayerError(StreamingError error);
}
