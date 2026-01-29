/// Progress information for video loading, exposed to UI.
/// Allows the UI to show loading indicators and progress.
class LoadingProgress {
  /// File ID being loaded
  final int fileId;

  /// Total bytes of the file
  final int totalBytes;

  /// Bytes currently loaded/available
  final int bytesLoaded;

  /// Whether we are currently fetching the MOOV atom (metadata)
  final bool isFetchingMoov;

  /// Whether the file is fully downloaded
  final bool isComplete;

  /// Current download speed in bytes per second (0 if unknown)
  final double bytesPerSecond;

  /// Current load state
  final FileLoadState loadState;

  const LoadingProgress({
    required this.fileId,
    required this.totalBytes,
    required this.bytesLoaded,
    this.isFetchingMoov = false,
    this.isComplete = false,
    this.bytesPerSecond = 0,
    this.loadState = FileLoadState.idle,
  });

  /// Progress as a value between 0.0 and 1.0
  double get progress =>
      totalBytes > 0 ? (bytesLoaded / totalBytes).clamp(0.0, 1.0) : 0.0;

  /// Estimated time remaining in seconds (0 if unknown)
  double get estimatedSecondsRemaining {
    if (bytesPerSecond <= 0 || isComplete) return 0;
    final remaining = totalBytes - bytesLoaded;
    return remaining / bytesPerSecond;
  }

  @override
  String toString() =>
      'LoadingProgress(fileId: $fileId, progress: ${(progress * 100).toStringAsFixed(1)}%, '
      'moov: $isFetchingMoov, speed: ${(bytesPerSecond / 1024).toStringAsFixed(0)}KB/s)';
}

/// Loading state machine for MOOV-first initialization.
/// Ensures proper sequence: MOOV loaded first, then seek to saved position.
enum FileLoadState {
  /// Initial state - no loading started
  idle,

  /// Loading MOOV atom (required for playback metadata)
  loadingMoov,

  /// MOOV is ready, file can be played
  moovReady,

  /// Seeking to a specific position
  seeking,

  /// Normal playback in progress
  playing,

  /// Recoverable error - can retry
  error,

  /// Timeout waiting for data
  timeout,

  /// Unrecoverable - video format not supported
  unsupported,
}

/// Position of MOOV atom in the MP4 file.
/// Used for optimizing streaming strategy.
enum MoovPosition {
  /// MOOV at start - optimized for streaming
  start,

  /// MOOV at end - requires additional download time
  end,

  /// Position unknown (not yet detected)
  unknown,
}
