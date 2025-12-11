import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef TdJsonClientCreate = ffi.Pointer<ffi.Void> Function();
typedef TdJsonClientReceive =
    ffi.Pointer<ffi.Int8> Function(
      ffi.Pointer<ffi.Void> client,
      double timeout,
    );
typedef TdJsonClientSend =
    void Function(ffi.Pointer<ffi.Void> client, ffi.Pointer<ffi.Int8> request);
typedef TdJsonClientExecute =
    ffi.Pointer<ffi.Int8> Function(
      ffi.Pointer<ffi.Void> client,
      ffi.Pointer<ffi.Int8> request,
    );

typedef TdJsonClientCreateC = ffi.Pointer<ffi.Void> Function();
typedef TdJsonClientReceiveC =
    ffi.Pointer<ffi.Int8> Function(
      ffi.Pointer<ffi.Void> client,
      ffi.Double timeout,
    );
typedef TdJsonClientSendC =
    ffi.Void Function(
      ffi.Pointer<ffi.Void> client,
      ffi.Pointer<ffi.Int8> request,
    );
typedef TdJsonClientExecuteC =
    ffi.Pointer<ffi.Int8> Function(
      ffi.Pointer<ffi.Void> client,
      ffi.Pointer<ffi.Int8> request,
    );

class TelegramService {
  static final TelegramService _instance = TelegramService._internal();
  factory TelegramService() => _instance;
  TelegramService._internal();

  final StreamController<Map<String, dynamic>> _updateController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get updates => _updateController.stream;

  // FFI Functions
  late final ffi.DynamicLibrary _lib;
  late final TdJsonClientCreate _createClient;
  late final TdJsonClientSend _sendRequest;

  ffi.Pointer<ffi.Void>? _client;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // 1. Load Library
    _loadLibrary();

    // 2. Lookup Functions
    _createClient = _lib
        .lookupFunction<TdJsonClientCreateC, TdJsonClientCreate>(
          'td_json_client_create',
        );
    _sendRequest = _lib.lookupFunction<TdJsonClientSendC, TdJsonClientSend>(
      'td_json_client_send',
    );
    // We look up receive here just to fail early if missing, but it's used in Isolate mainly.
    // Actually, we pass the path or handle loading in Isolate.

    // 3. Create Client
    _client = _createClient();

    // 4. Spawn Receive Isolate
    // We pass the Client Address (int) because Pointer is not sendable?
    // Actually Pointer<Void> IS sendable.
    // Create the background isolate for receiving updates
    final receivePort = ReceivePort();

    // Set log verbosity to 1 (Errors only) to prevent console flooding and freeze
    send({'@type': 'setLogVerbosityLevel', 'new_verbosity_level': 1});

    await Isolate.spawn(
      _tdLibIsolateEntryPoint,
      _IsolateArgs(
        sendPort: receivePort.sendPort,
        clientAddress: _client!.address,
      ),
    );

    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        _updateController.add(message);
      }
    });

    _initialized = true;
  }

  void _loadLibrary() {
    try {
      if (Platform.isWindows) {
        _lib = ffi.DynamicLibrary.open('tdjson.dll');
      } else if (Platform.isLinux) {
        _lib = ffi.DynamicLibrary.open('libtdjson.so');
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      if (Platform.isLinux) {
        try {
          final executableDir = File(Platform.resolvedExecutable).parent;
          final libPath = p.join(executableDir.path, 'lib', 'libtdjson.so');
          _lib = ffi.DynamicLibrary.open(libPath);
        } catch (_) {
          throw e;
        }
      } else {
        rethrow;
      }
    }
  }

  void send(Map<String, dynamic> request) {
    if (_client == null) return;

    // ignore: avoid_print
    print('TDLib Send: $request');

    final requestJson = jsonEncode(request);
    final requestPtr = requestJson.toNativeUtf8().cast<ffi.Int8>();
    _sendRequest(_client!, requestPtr);
    calloc.free(requestPtr);
  }

  // Executes a synchronous request
  static Map<String, dynamic>? execute(Map<String, dynamic> request) {
    // This needs to be done in the main isolate or wherever called,
    // assuming library is loaded. But usually execute is for static stuff.
    // For now, allow simple usage through the isolate if needed, but 'execute'
    // in TDLib is strictly synchronous and usually for Log.
    // We will skip implementing sync execute for now unless needed for logging.
    return null;
  }

  static void _tdLibIsolateEntryPoint(_IsolateArgs args) {
    // Re-load library in Isolate to look up 'receive'
    ffi.DynamicLibrary lib;
    // ... Copy-paste logic or helper?
    // For simplicity and robustness, repeat the load logic succinctly or try common paths.
    // Since Isolate doesn't share static state, we must reload.
    try {
      if (Platform.isWindows) {
        lib = ffi.DynamicLibrary.open('tdjson.dll');
      } else if (Platform.isLinux) {
        lib = ffi.DynamicLibrary.open('libtdjson.so');
      } else {
        // Try fallback immediately for Linux
        final executableDir = File(Platform.resolvedExecutable).parent;
        final libPath = p.join(executableDir.path, 'lib', 'libtdjson.so');
        lib = ffi.DynamicLibrary.open(libPath);
      }
    } catch (e) {
      // Retry standard linux if fallback failed (unlikely flow but safe)
      try {
        lib = ffi.DynamicLibrary.open('libtdjson.so');
      } catch (_) {
        print('Isolate failed to load lib: $e');
        return;
      }
    }

    final receive = lib
        .lookupFunction<TdJsonClientReceiveC, TdJsonClientReceive>(
          'td_json_client_receive',
        );

    final client = ffi.Pointer<ffi.Void>.fromAddress(args.clientAddress);

    final ignoredTypes = <String>{
      'updateOption',
      'updateUserStatus',
      'updateChatReadInbox',
      'updateChatReadOutbox',
      'updateChatAction',
      'updateMessageInteractionInfo',
      'updateUser', // We usually fetch users on demand or they come with messages
    };

    while (true) {
      final resultPtr = receive(client, 1.0);
      if (resultPtr != ffi.nullptr) {
        final resultStr = resultPtr.cast<Utf8>().toDartString();
        try {
          final resultJson = jsonDecode(resultStr);
          // Only send relevant updates to Main Isolate to prevent flooding
          final type = resultJson['@type'];
          if (type != null && !ignoredTypes.contains(type)) {
            args.sendPort.send(resultJson);
          }
        } catch (e) {
          // ignore: avoid_print
          // print('Error decoding TDLib update: $e');
        }
      }
    }
  }
}

class _IsolateArgs {
  final SendPort sendPort;
  final int clientAddress;
  _IsolateArgs({required this.sendPort, required this.clientAddress});
}
