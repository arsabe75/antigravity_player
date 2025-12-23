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
}
