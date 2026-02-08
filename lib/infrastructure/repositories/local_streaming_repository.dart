import '../../domain/repositories/streaming_repository.dart';
import '../../domain/value_objects/loading_progress.dart';
import '../../domain/value_objects/streaming_error.dart';
import '../services/local_streaming_proxy.dart';

// Re-export LoadingProgress and StreamingError from domain
export '../../domain/value_objects/loading_progress.dart';
export '../../domain/value_objects/streaming_error.dart';

class LocalStreamingRepository implements StreamingRepository {
  final LocalStreamingProxy _proxy;

  LocalStreamingRepository() : _proxy = LocalStreamingProxy();

  @override
  void abortRequest(int fileId) {
    _proxy.abortRequest(fileId);
  }

  @override
  int get port => _proxy.port;

  @override
  void previewSeekTarget(int fileId, int estimatedOffset) {
    _proxy.previewSeekTarget(fileId, estimatedOffset);
  }

  @override
  Future<int> getByteOffsetForTime(
    int fileId,
    int timeMs,
    int totalDurationMs,
    int totalBytes,
  ) {
    return _proxy.getByteOffsetForTime(
      fileId,
      timeMs,
      totalDurationMs,
      totalBytes,
    );
  }

  @override
  bool isVideoNotOptimizedForStreaming(int fileId) {
    return _proxy.isVideoNotOptimizedForStreaming(fileId);
  }

  @Deprecated(
    'Preloading disabled due to TDLib limitations. Remove calls to this method.',
  )
  @override
  void preloadVideoStart(int fileId, int? totalSize, {bool isVisible = false}) {
    _proxy.preloadVideoStart(fileId, totalSize, isVisible: isVisible);
  }

  @override
  LoadingProgress? getLoadingProgress(int fileId) {
    return _proxy.getLoadingProgress(fileId);
  }

  @override
  StreamingError? getLastError(int fileId) {
    return _proxy.getLastError(fileId);
  }

  @override
  void clearError(int fileId) {
    _proxy.clearError(fileId);
  }

  @override
  void resetRetryCount(int fileId) {
    _proxy.resetRetryCount(fileId);
  }

  @override
  set onStreamingError(void Function(StreamingError error)? callback) {
    _proxy.onStreamingError = callback;
  }
}
