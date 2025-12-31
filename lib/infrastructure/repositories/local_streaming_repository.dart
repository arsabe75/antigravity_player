import '../../domain/repositories/streaming_repository.dart';
import '../services/local_streaming_proxy.dart';

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

  @override
  void preloadVideoStart(int fileId, int? totalSize, {bool isVisible = false}) {
    _proxy.preloadVideoStart(fileId, totalSize, isVisible: isVisible);
  }
}
