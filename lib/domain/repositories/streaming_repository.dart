abstract class StreamingRepository {
  /// Aborts a specific file request to stop streaming data
  void abortRequest(int fileId);

  /// Gets the active port of the local streaming server
  int get port;
}
