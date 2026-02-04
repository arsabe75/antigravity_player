import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/telegram_content_notifier.dart';
import '../widgets/chat_icon.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/window_controls.dart';

class TelegramSelectionScreen extends ConsumerStatefulWidget {
  const TelegramSelectionScreen({super.key});

  @override
  ConsumerState<TelegramSelectionScreen> createState() =>
      _TelegramSelectionScreenState();
}

class _TelegramSelectionScreenState
    extends ConsumerState<TelegramSelectionScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    debugPrint('TelegramSelectionScreen: initState');

    _scrollController.addListener(_onScroll);

    // Load chats on init, deferred to avoid navigation jank or race conditions
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        debugPrint('TelegramSelectionScreen: Calling loadChats()');
        ref.read(telegramContentProvider.notifier).loadChats();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(telegramContentProvider.notifier).loadMoreChats();
    }
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

  /// Get icon for chat type
  IconData _getChatIcon(Map<String, dynamic> chat) {
    final chatType = chat['type'];
    if (chatType != null) {
      final type = chatType['@type'];
      if (type == 'chatTypeSupergroup') {
        if (chatType['is_channel'] == true) {
          return LucideIcons.radio; // Channel icon
        }
        if (_isForum(chat)) {
          return LucideIcons.messagesSquare; // Forum/topics icon
        }
        return LucideIcons.users; // Regular supergroup
      } else if (type == 'chatTypeBasicGroup') {
        return LucideIcons.users;
      } else if (type == 'chatTypePrivate') {
        return LucideIcons.user;
      }
    }
    return LucideIcons.messageCircle;
  }

  /// Get subtitle based on chat type
  String _getChatSubtitle(Map<String, dynamic> chat) {
    String typeStr = 'Chat';
    final chatType = chat['type'];
    if (chatType != null) {
      final type = chatType['@type'];
      if (type == 'chatTypeSupergroup') {
        if (chatType['is_channel'] == true) {
          typeStr = 'Canal';
        } else if (_isForum(chat)) {
          typeStr = 'Grupo con temas';
        } else {
          typeStr = 'Supergrupo';
        }
      } else if (type == 'chatTypeBasicGroup') {
        typeStr = 'Grupo';
      } else if (type == 'chatTypePrivate') {
        typeStr = 'Chat privado';
      }
    }

    // Check if archived
    bool isArchived = false;
    final positions = chat['positions'] as List<dynamic>? ?? [];
    for (final pos in positions) {
      if (pos['list'] != null && pos['list']['@type'] == 'chatListArchive') {
        isArchived = true;
        break;
      }
    }

    if (isArchived) {
      return '$typeStr (Archivado)';
    }
    return typeStr;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(telegramContentProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Chats'),
        flexibleSpace: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          behavior: HitTestBehavior.translucent,
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(telegramContentProvider.notifier).reloadChats();
            },
          ),
          const SizedBox(width: 8),
          const WindowControls(),
          const SizedBox(width: 8),
        ],
      ),
      body: state.isLoading && state.chats.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading chats...'),
                ],
              ),
            )
          : state.chats.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.inbox, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No chats found',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      ref.read(telegramContentProvider.notifier).reloadChats();
                    },
                    icon: const Icon(LucideIcons.refreshCw),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              itemCount: state.chats.length + (state.isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == state.chats.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final chat = state.chats[index];
                final title = chat['title'] ?? 'Unknown Chat';
                final isForum = _isForum(chat);

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isForum
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: ChatIcon(
                      chat: chat,
                      fallbackIcon: _getChatIcon(chat),
                      size: 40,
                    ),
                  ),
                  title: Text(title),
                  subtitle: Text(_getChatSubtitle(chat)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isForum)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Chip(
                            label: Text(
                              'Topics',
                              style: TextStyle(fontSize: 10),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      IconButton(
                        icon: const Icon(LucideIcons.plus),
                        tooltip: 'Select',
                        onPressed: () {
                          Navigator.of(context).pop(chat);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
