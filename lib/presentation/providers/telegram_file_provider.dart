import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../infrastructure/services/telegram_service.dart';

part 'telegram_file_provider.g.dart';

class TelegramFileState {
  final String? localPath;
  final bool isDownloading;
  final bool isCompleted;

  const TelegramFileState({
    this.localPath,
    this.isDownloading = false,
    this.isCompleted = false,
  });
}

@Riverpod(keepAlive: true)
class TelegramFile extends _$TelegramFile {
  late final TelegramService _service;

  @override
  TelegramFileState build(int fileId) {
    _service = TelegramService();

    final sub = _service.updates.listen((update) {
      if (update['@type'] == 'updateFile') {
        final file = update['file'];
        if (file['id'] == fileId) {
          final local = file['local'];
          state = TelegramFileState(
            localPath: local['path'],
            isDownloading: local['is_downloading_active'] ?? false,
            isCompleted: local['is_downloading_completed'] ?? false,
          );
        }
      }
    });

    ref.onDispose(() {
      sub.cancel();
    });

    // Trigger download
    _downloadFile(fileId);

    return const TelegramFileState(isDownloading: true);
  }

  Future<void> _downloadFile(int fileId, {int attempt = 1}) async {
    const maxRetries = 8; // More retries for initialization race condition

    // Small delay on first attempt to give TDLib time to initialize
    if (attempt == 1) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // 1. Request Download
    try {
      final result = await _service.sendWithResult({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 32,
        'synchronous': false,
      });

      // Handle error response - TDLib not ready yet, retry after delay
      if (result['@type'] == 'error') {
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          return _downloadFile(fileId, attempt: attempt + 1);
        }
        return;
      }

      // Check if download completed immediately (file already cached)
      if (result['@type'] == 'file') {
        final local = result['local'];
        if (local != null && local['is_downloading_completed'] == true) {
          state = TelegramFileState(
            localPath: local['path'],
            isDownloading: false,
            isCompleted: true,
          );
          return;
        }
      }
    } catch (e) {
      if (attempt < maxRetries) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
        return _downloadFile(fileId, attempt: attempt + 1);
      }
      return;
    }

    // 2. Check Status
    try {
      await Future.delayed(const Duration(milliseconds: 500));

      final result = await _service.sendWithResult({
        '@type': 'getFile',
        'file_id': fileId,
      });

      if (result['@type'] == 'file') {
        final local = result['local'];
        if (local != null) {
          final isCompleted = local['is_downloading_completed'] == true;
          final isActive = local['is_downloading_active'] == true;
          final path = local['path'] as String?;

          if (isCompleted || (path != null && path.isNotEmpty)) {
            state = TelegramFileState(
              localPath: path,
              isDownloading: isActive,
              isCompleted: isCompleted,
            );
            return;
          }

          // If still downloading, wait and check again
          if (isActive && attempt < maxRetries) {
            await Future.delayed(Duration(seconds: 1));
            return _downloadFile(fileId, attempt: attempt + 1);
          }
        }
      }
    } catch (_) {
      if (attempt < maxRetries) {
        await Future.delayed(Duration(seconds: attempt));
        return _downloadFile(fileId, attempt: attempt + 1);
      }
    }
  }
}
