import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:window_manager/window_manager.dart';

import '../widgets/window_controls.dart';
import '../providers/telegram_auth_notifier.dart';
import '../../infrastructure/services/local_streaming_proxy.dart';
import '../../infrastructure/services/telegram_service.dart';
import 'telegram_login_screen.dart';
import '../widgets/chat_icon.dart';

class TelegramScreen extends ConsumerStatefulWidget {
  const TelegramScreen({super.key});

  @override
  ConsumerState<TelegramScreen> createState() => _TelegramScreenState();
}

class _TelegramScreenState extends ConsumerState<TelegramScreen> {
  List<Map<String, dynamic>> _favorites = []; // No longer final

  @override
  void initState() {
    super.initState();
    // Start Proxy
    LocalStreamingProxy().start();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final String? favoritesJson = prefs.getString('telegram_favorites');
    if (favoritesJson != null) {
      final cachedFavorites = List<Map<String, dynamic>>.from(
        jsonDecode(favoritesJson),
      );

      // Set cached data immediately for fast display
      setState(() {
        _favorites = cachedFavorites;
      });

      // Refresh from TDLib to get fresh file IDs
      _refreshFavoritesFromTdlib(cachedFavorites);
    }
  }

  /// Refresh favorites data from TDLib to get updated file IDs
  Future<void> _refreshFavoritesFromTdlib(
    List<Map<String, dynamic>> cachedFavorites,
  ) async {
    final service = TelegramService();

    final refreshedFavorites = <Map<String, dynamic>>[];

    for (final cached in cachedFavorites) {
      final chatId = cached['id'];
      if (chatId == null) continue;

      try {
        final result = await service.sendWithResult({
          '@type': 'getChat',
          'chat_id': chatId,
        });

        if (result['@type'] == 'chat') {
          refreshedFavorites.add(result);
        } else {
          // Keep cached version if refresh fails
          refreshedFavorites.add(cached);
        }
      } catch (e) {
        debugPrint('Failed to refresh chat $chatId: $e');
        refreshedFavorites.add(cached);
      }
    }

    if (refreshedFavorites.isNotEmpty && mounted) {
      setState(() {
        _favorites = refreshedFavorites;
      });
      // Save refreshed data
      _saveFavorites();
    }
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('telegram_favorites', jsonEncode(_favorites));
  }

  /// Check if a chat is a forum (supergroup with topics enabled)
  bool _isForum(Map<String, dynamic> chat) {
    // TDLib uses 'view_as_topics' field in chat object to indicate forums
    if (chat['view_as_topics'] == true) {
      return true;
    }
    // Fallback: check is_forum field (may be present in some responses)
    final chatType = chat['type'];
    if (chatType != null && chatType['@type'] == 'chatTypeSupergroup') {
      return chat['is_forum'] == true;
    }
    return false;
  }

  /// Check if a chat is a channel
  bool _isChannel(Map<String, dynamic> chat) {
    final chatType = chat['type'];
    if (chatType != null && chatType['@type'] == 'chatTypeSupergroup') {
      return chatType['is_channel'] == true;
    }
    return false;
  }

  /// Get icon for chat type
  IconData _getChatIcon(Map<String, dynamic> chat) {
    if (_isChannel(chat)) {
      return LucideIcons.radio;
    }
    if (_isForum(chat)) {
      return LucideIcons.messagesSquare;
    }
    final chatType = chat['type'];
    if (chatType != null) {
      final type = chatType['@type'];
      if (type == 'chatTypeSupergroup' || type == 'chatTypeBasicGroup') {
        return LucideIcons.users;
      }
    }
    return LucideIcons.tv;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(telegramAuthProvider);

    // If checking auth state, show loading
    if (authState.list == AuthState.initial) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // If not authenticated, show login
    if (authState.list != AuthState.ready) {
      return const TelegramLoginScreen();
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Telegram Channels'),
        flexibleSpace: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          behavior: HitTestBehavior.translucent,
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () async {
              final result = await context.push<Map<String, dynamic>>(
                '/telegram/selection',
              );

              if (result != null) {
                setState(() {
                  if (!_favorites.any((c) => c['id'] == result['id'])) {
                    _favorites.add(result);
                    _saveFavorites();
                  }
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.hardDrive),
            tooltip: 'Storage',
            onPressed: () {
              context.push('/telegram/storage');
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.logOut),
            onPressed: () {
              ref.read(telegramAuthProvider.notifier).logout();
            },
          ),
          const SizedBox(width: 8),
          const WindowControls(),
          const SizedBox(width: 8),
        ],
      ),
      body: _favorites.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    LucideIcons.messageSquare,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No favorites yet.\nClick + to add channels.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _favorites.length,
              itemBuilder: (context, index) {
                final chat = _favorites[index];
                final title = chat['title'] ?? 'Unknown';
                final isForum = _isForum(chat);

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          ChatIcon.getAccentColor(chat) ??
                          (isForum
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null),
                      child: ChatIcon(
                        chat: chat,
                        fallbackIcon: _getChatIcon(chat),
                        size: 40,
                      ),
                    ),
                    title: Text(title),
                    subtitle: Row(
                      children: [
                        if (isForum) ...[
                          const Icon(LucideIcons.messagesSquare, size: 12),
                          const SizedBox(width: 4),
                          const Text('Topics', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          'ID: ${chat['id']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    onTap: () {
                      if (isForum) {
                        // Navigate to topics screen for forum groups
                        context.push(
                          '/telegram/topics/${chat['id']}',
                          extra: title,
                        );
                      } else {
                        // Navigate directly to chat screen for channels/regular groups
                        context.push(
                          '/telegram/chat/${chat['id']}',
                          extra: {'title': title},
                        );
                      }
                    },
                    trailing: IconButton(
                      icon: const Icon(LucideIcons.trash2, size: 20),
                      onPressed: () {
                        setState(() {
                          _favorites.removeAt(index);
                          _saveFavorites();
                        });
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
