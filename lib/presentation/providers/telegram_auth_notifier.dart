import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../infrastructure/services/telegram_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'state/telegram_auth_state.dart';
export 'state/telegram_auth_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../infrastructure/services/recent_videos_service.dart';
import '../../infrastructure/services/playback_storage_service.dart';
import '../../infrastructure/services/telegram_cache_service.dart';

part 'telegram_auth_notifier.g.dart';

@Riverpod(keepAlive: true)
class TelegramAuth extends _$TelegramAuth {
  late final TelegramService _service;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  // Read from environment variables
  late final int _apiId =
      int.tryParse(dotenv.env['TELEGRAM_API_ID'] ?? '') ?? 0;
  late final String _apiHash = dotenv.env['TELEGRAM_API_HASH'] ?? '';

  @override
  TelegramAuthState build() {
    debugPrint(
      'TelegramAuthNotifier: API_ID=$_apiId, API_HASH=$_apiHash',
    ); // DEBUG
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
      // if (!mounted) return; // Not available in simple Notifier, relay on Riverpod handling
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

        debugPrint(
          'Sending setTdlibParameters with API_ID=$_apiId, API_HASH=$_apiHash',
        ); // DEBUG

        _service.send({
          '@type': 'setTdlibParameters',
          'use_test_dc': false,
          'database_directory': tdlibPath,
          'files_directory': tdlibPath,
          'database_encryption_key': '',
          'use_file_database': true,
          'use_chat_info_database': true,
          'use_message_database': true,
          'use_secret_chats': false,
          'api_id': _apiId,
          'api_hash': _apiHash,
          'system_language_code': 'en',
          'device_model': 'Desktop',
          'system_version': Platform.operatingSystemVersion,
          'application_version':
              '1.0.0', // Reset to standard version now that we have new binary
          'enable_storage_optimizer': true,
        });
        break;

      case 'authorizationStateWaitEncryptionKey':
        // Check DB encryption key (empty for now)
        _service.send({
          '@type': 'checkDatabaseEncryptionKey',
          'encryption_key': '',
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
    debugPrint('Setting Phone Number: $phoneNumber');
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
      final prefs = await SharedPreferences.getInstance();
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
