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

  /// OPTIMIZATION 2: Preload first 2MB of video when it appears in list view
  /// Call this when a video thumbnail becomes visible to pre-download data
  void preloadVideoStart(int fileId, int? totalSize);
}
