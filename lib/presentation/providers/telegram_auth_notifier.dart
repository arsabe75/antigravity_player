import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../infrastructure/services/telegram_service.dart';
import '../../infrastructure/services/config_obfuscator.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'state/telegram_auth_state.dart';
export 'state/telegram_auth_state.dart';
import '../../infrastructure/services/secure_storage_service.dart';
import '../../infrastructure/services/recent_videos_service.dart';
import '../../infrastructure/services/playback_storage_service.dart';
import '../../infrastructure/services/telegram_cache_service.dart';
import '../../infrastructure/services/tdlib_encryption_service.dart';

part 'telegram_auth_notifier.g.dart';

@Riverpod(keepAlive: true)
class TelegramAuth extends _$TelegramAuth {
  late final TelegramService _service;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  // Read and decode obfuscated credentials from environment variables
  late final int _apiId = ConfigObfuscator.decodeInt(
    dotenv.env['TELEGRAM_API_ID'] ?? '',
  );
  late final String _apiHash = ConfigObfuscator.decode(
    dotenv.env['TELEGRAM_API_HASH'] ?? '',
  );

  @override
  TelegramAuthState build() {
    // Security: Don't log credentials in production
    if (kDebugMode) {
      debugPrint('TelegramAuthNotifier: Credentials loaded (hidden)');
    }
    _service = TelegramService();
    // Defer initialization to avoid modifying provider during build
    Future.microtask(() => _init());

    // Ensure we clean up the subscription when the notifier is disposed
    ref.onDispose(() {
      _subscription?.cancel();
    });

    return TelegramAuthState();
  }

  void _init() {
    // Cancel existing subscription if re-initializing (e.g. after logout)
    _subscription?.cancel();

    _service.initialize();
    _subscription = _service.updates.listen(_handleUpdate);

    // Request current auth state
    _service.send({'@type': 'getAuthorizationState'});
  }

  void _handleUpdate(Map<String, dynamic> update) {
    // Wrap in microtask to ensure we never update state during a build frame,
    // regardless of when the stream emits.
    Future.microtask(() {
      // Guard against disposed provider
      if (!ref.mounted) return;
      if (update['@type'] == 'updateAuthorizationState') {
        final stateUpdate = update['authorization_state'];
        _processAuthState(stateUpdate);
      } else if (update['@type'] == 'error') {
        state = state.copyWith(error: update['message'], isLoading: false);
      }
    });
  }

  Future<void> _processAuthState(Map<String, dynamic> authState) async {
    final type = authState['@type'];

    switch (type) {
      case 'authorizationStateWaitTdlibParameters':
        final appDir = await getApplicationDocumentsDirectory();
        final tdlibPath = p.join(appDir.path, 'antigravity_tdlib');
        await Directory(tdlibPath).create(recursive: true);

        // Get or create secure encryption key for TDLib database
        final encryptionKey =
            await TDLibEncryptionService.getOrCreateEncryptionKey();

        // Security: Don't log credentials
        if (kDebugMode) {
          debugPrint('Sending setTdlibParameters (database encrypted)...');
        }

        _service.send({
          '@type': 'setTdlibParameters',
          'use_test_dc': false,
          'database_directory': tdlibPath,
          'files_directory': tdlibPath,
          'database_encryption_key': encryptionKey,
          'use_file_database': true,
          'use_chat_info_database': true,
          'use_message_database': true,
          'use_secret_chats': false,
          'api_id': _apiId,
          'api_hash': _apiHash,
          'system_language_code': 'en',
          'device_model': 'Desktop',
          'system_version': Platform.operatingSystemVersion,
          'application_version': '1.0.0',
          'enable_storage_optimizer': true,
        });
        break;

      case 'authorizationStateWaitEncryptionKey':
        // Provide the same encryption key used in setTdlibParameters
        final encryptionKey =
            await TDLibEncryptionService.getOrCreateEncryptionKey();
        _service.send({
          '@type': 'checkDatabaseEncryptionKey',
          'encryption_key': encryptionKey,
        });
        break;

      case 'authorizationStateWaitPhoneNumber':
        state = state.copyWith(
          list: AuthState.waitPhoneNumber,
          isLoading: false,
        );
        break;

      case 'authorizationStateWaitCode':
        state = state.copyWith(list: AuthState.waitCode, isLoading: false);
        break;

      case 'authorizationStateWaitPassword':
        state = state.copyWith(list: AuthState.waitPassword, isLoading: false);
        break;

      case 'authorizationStateReady':
        state = state.copyWith(list: AuthState.ready, isLoading: false);
        break;

      case 'authorizationStateClosed':
        state = state.copyWith(list: AuthState.closed, isLoading: false);

        // When TDLib closes (after logout), we need to reset the service
        // and restart the auth flow for the next user.
        debugPrint('TelegramAuthNotifier: Auth closed. Resetting service...');
        _service.reset();

        // Small delay to ensure cleanup
        await Future.delayed(const Duration(milliseconds: 500));

        // Restart flow
        _init();
        break;
    }
  }

  void setPhoneNumber(String phoneNumber) {
    // Security: Don't log phone numbers
    if (kDebugMode) {
      debugPrint('Setting Phone Number: ***hidden***');
    }
    state = state.copyWith(isLoading: true, error: null);
    _service.send({
      '@type': 'setAuthenticationPhoneNumber',
      'phone_number': phoneNumber,
    });
  }

  void checkCode(String code) {
    state = state.copyWith(isLoading: true, error: null);
    _service.send({'@type': 'checkAuthenticationCode', 'code': code});
  }

  void checkPassword(String password) {
    state = state.copyWith(isLoading: true, error: null);
    _service.send({
      '@type': 'checkAuthenticationPassword',
      'password': password,
    });
  }

  Future<void> logout() async {
    debugPrint('TelegramAuthNotifier: Logging out and clearing data...');

    try {
      // 1. Clear Favorites and Settings
      final prefs = SecureStorageService.instance;
      await prefs.remove('telegram_favorites');

      // 2. Clear Recent Videos (Telegram only)
      await RecentVideosService().clearTelegramVideos();

      // 3. Clear Playback Progress
      await PlaybackStorageService().clearAllPositions();

      // 4. Clear Cache (Force all, including avatars/headers)
      // Note: This uses optimizeStorage which deletes files.
      await TelegramCacheService().clearCache(forceAll: true);
    } catch (e) {
      debugPrint('TelegramAuthNotifier: Error during cleanup: $e');
    }

    // 5. Send logout command to TDLib
    _service.send({'@type': 'logOut'});
  }
}
