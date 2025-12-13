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
}
