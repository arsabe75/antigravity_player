import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:window_manager/window_manager.dart';

import '../widgets/window_controls.dart';
import '../widgets/home/recent_videos_widget.dart';
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
  final _recentVideosKey = GlobalKey<RecentVideosWidgetState>();

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
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate 30% of screen width with min/max bounds
          final panelWidth = (constraints.maxWidth * 0.30).clamp(250.0, 450.0);

          return Row(
            children: [
              // Left side - Favorites list
              Expanded(
                child: _favorites.isEmpty
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
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer
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
                                    const Icon(
                                      LucideIcons.messagesSquare,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Topics',
                                      style: TextStyle(fontSize: 12),
                                    ),
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
              ),
              // Right side - Recent Telegram Videos Panel (only shows when not empty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16, right: 16),
                child: RecentVideosWidget(
                  panelWidth: panelWidth,
                  key: _recentVideosKey,
                  showTelegramVideos: true,
                  onVideoSelected: (video) async {
                    // Wait for TDLib to be ready before playing
                    final authState = ref.read(telegramAuthProvider);

                    // Show loading dialog - always wait a bit for TDLib file system to initialize
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => const AlertDialog(
                        content: Row(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(width: 16),
                            Text('Connecting to Telegram...'),
                          ],
                        ),
                      ),
                    );

                    // Wait for authorization if not ready
                    if (authState.list != AuthState.ready) {
                      debugPrint('TelegramScreen: Not ready, waiting for auth');
                      int attempts = 0;
                      while (attempts < 100) {
                        await Future.delayed(const Duration(milliseconds: 100));
                        final currentState = ref.read(telegramAuthProvider);
                        if (currentState.list == AuthState.ready) {
                          break;
                        }
                        if (currentState.list == AuthState.waitPhoneNumber ||
                            currentState.list == AuthState.error ||
                            currentState.list == AuthState.closed) {
                          if (context.mounted) Navigator.of(context).pop();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Telegram not authorized. Please log in first.',
                                ),
                              ),
                            );
                          }
                          return;
                        }
                        attempts++;
                      }

                      final finalState = ref.read(telegramAuthProvider);
                      if (finalState.list != AuthState.ready) {
                        if (context.mounted) Navigator.of(context).pop();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Telegram connection timed out. Please try again.',
                              ),
                            ),
                          );
                        }
                        return;
                      }
                    }

                    // Hydrate the chat to ensure TDLib knows about the file
                    // TDLib file IDs only become valid after the chat is loaded
                    if (video.telegramChatId != null) {
                      debugPrint(
                        'TelegramScreen: Hydrating chat ${video.telegramChatId} for file access...',
                      );
                      try {
                        // First, open the chat to ensure TDLib loads it
                        await TelegramService().sendWithResult({
                          '@type': 'getChat',
                          'chat_id': video.telegramChatId,
                        });

                        // Load some chat history to hydrate file information
                        await TelegramService().sendWithResult({
                          '@type': 'getChatHistory',
                          'chat_id': video.telegramChatId,
                          'from_message_id': 0,
                          'offset': 0,
                          'limit': 50,
                          'only_local': false,
                        });

                        debugPrint('TelegramScreen: Chat hydration complete');
                      } catch (e) {
                        debugPrint('TelegramScreen: Chat hydration error: $e');
                      }

                      // Small delay to let TDLib process the loaded messages
                      await Future.delayed(const Duration(milliseconds: 500));
                    } else {
                      debugPrint(
                        'TelegramScreen: No chatId available, using 2s delay fallback...',
                      );
                      await Future.delayed(const Duration(seconds: 2));
                    }

                    if (context.mounted) Navigator.of(context).pop();

                    // Get fresh file info from the message (file_ids can become stale)
                    final proxy = LocalStreamingProxy();
                    String url = video.path;

                    if (video.telegramChatId != null &&
                        video.telegramMessageId != null) {
                      try {
                        debugPrint(
                          'TelegramScreen: Getting fresh file info from message ${video.telegramMessageId}',
                        );
                        final messageResult = await TelegramService()
                            .sendWithResult({
                              '@type': 'getMessage',
                              'chat_id': video.telegramChatId,
                              'message_id': video.telegramMessageId,
                            });

                        // Extract video file from message content
                        final content =
                            messageResult['content'] as Map<String, dynamic>?;
                        if (content != null) {
                          final videoContent =
                              content['video'] as Map<String, dynamic>?;
                          if (videoContent != null) {
                            final videoFile =
                                videoContent['video'] as Map<String, dynamic>?;
                            if (videoFile != null) {
                              final freshFileId = videoFile['id'] as int?;
                              final size =
                                  videoFile['size'] as int? ??
                                  video.telegramFileSize ??
                                  0;
                              if (freshFileId != null) {
                                url = proxy.getUrl(freshFileId, size);
                                debugPrint(
                                  'TelegramScreen: Got fresh file_id: $freshFileId, size: $size',
                                );
                              }
                            }
                          }
                        }
                      } catch (e) {
                        debugPrint(
                          'TelegramScreen: Failed to get message, using stored URL: $e',
                        );
                      }
                    }

                    // Fallback to stored URL if fresh fetch failed
                    if (url == video.path &&
                        video.path.contains('/stream?file_id=')) {
                      try {
                        final uri = Uri.parse(video.path);
                        final fileIdStr = uri.queryParameters['file_id'];
                        final sizeStr = uri.queryParameters['size'];
                        if (fileIdStr != null && sizeStr != null) {
                          final fileId = int.parse(fileIdStr);
                          final size = int.parse(sizeStr);
                          url = proxy.getUrl(fileId, size);
                        }
                      } catch (_) {}
                    }

                    if (!context.mounted) return;

                    context
                        .push(
                          '/player',
                          extra: {
                            'url': url,
                            'title': video.title,
                            'telegramChatId': video.telegramChatId,
                            'telegramMessageId': video.telegramMessageId,
                            'telegramFileSize': video.telegramFileSize,
                          },
                        )
                        .then((_) {
                          // Refresh recent videos when returning from player
                          _recentVideosKey.currentState?.refresh();
                        });
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
