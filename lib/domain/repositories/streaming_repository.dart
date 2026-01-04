import '../../infrastructure/services/local_streaming_proxy.dart'
    show LoadingProgress;

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
  void preloadVideoStart(int fileId, int? totalSize, {bool isVisible = false});

  /// Get current loading progress for a file.
  /// Returns null if file is not being tracked.
  /// UI can use this to show loading indicators, progress bars, and MOOV fetching status.
  LoadingProgress? getLoadingProgress(int fileId);
}
