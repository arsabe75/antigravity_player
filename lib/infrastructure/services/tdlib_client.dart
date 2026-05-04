/// Minimal abstraction over TDLib's FFI API used by [LocalStreamingProxy].
///
/// Enables unit testing of the proxy without a real TDLib client.
/// [TelegramService] is the production implementation.
abstract class TdlibClient {
  bool get isClientReady;
  Stream<Map<String, dynamic>> get updates;
  void send(Map<String, dynamic> request);
  Future<Map<String, dynamic>> sendWithResult(Map<String, dynamic> request);
}
