import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/window_controls.dart';
import '../providers/telegram_forum_notifier.dart';
import '../widgets/custom_emoji_icon.dart';
import '../../config/router/routes.dart';

class TelegramTopicsScreen extends ConsumerWidget {
  final int chatId;
  final String title;

  const TelegramTopicsScreen({
    super.key,
    required this.chatId,
    required this.title,
  });

  /// Get topic icon color from topic info.
  /// Uses TDLib icon color, or falls back to theme-aware colors for contrast.
  Color _getTopicColor(Map<String, dynamic> topicInfo, BuildContext context) {
    // TDLib provides icon_color as an integer color value
    final iconColor = topicInfo['icon']?['color'] as int?;
    if (iconColor != null && iconColor != 0) {
      // TDLib uses RGB format
      return Color(iconColor | 0xFF000000); // Add alpha
    }
    // Theme-aware fallback for better contrast
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(telegramForumProvider(chatId));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            const Text(
              'Topics',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        flexibleSpace: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          behavior: HitTestBehavior.translucent,
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(telegramForumProvider(chatId).notifier).refreshTopics();
            },
          ),
          const SizedBox(width: 8),
          const WindowControls(),
          const SizedBox(width: 8),
        ],
      ),
      body: state.isLoading && state.topics.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading topics...'),
                ],
              ),
            )
          : state.topics.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    LucideIcons.messagesSquare,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No topics found',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      ref
                          .read(telegramForumProvider(chatId).notifier)
                          .refreshTopics();
                    },
                    icon: const Icon(LucideIcons.refreshCw),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                if (scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent - 200 &&
                    !state.isLoadingMore &&
                    state.hasMore) {
                  ref
                      .read(telegramForumProvider(chatId).notifier)
                      .loadMoreTopics();
                }
                return false;
              },
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: state.topics.length + (state.isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == state.topics.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final topic = state.topics[index];
                  final topicInfo =
                      topic['info'] as Map<String, dynamic>? ?? {};
                  final topicName =
                      topicInfo['name'] as String? ?? 'Unknown Topic';
                  // TDLib uses forum_topic_id as the thread identifier
                  final forumTopicId = topicInfo['forum_topic_id'] as int? ?? 0;
                  final isPinned = topic['is_pinned'] == true;
                  final isGeneral = topicInfo['is_general'] == true;

                  // Get last message preview
                  final lastMessage =
                      topic['last_message'] as Map<String, dynamic>?;
                  String? preview;
                  if (lastMessage != null) {
                    final content =
                        lastMessage['content'] as Map<String, dynamic>?;
                    if (content != null) {
                      final type = content['@type'] as String?;
                      if (type == 'messageText') {
                        final text = content['text'] as Map<String, dynamic>?;
                        preview = text?['text'] as String?;
                      } else if (type == 'messageVideo') {
                        preview = '🎬 Video';
                      } else if (type == 'messagePhoto') {
                        preview = '📷 Photo';
                      } else if (type == 'messageDocument') {
                        preview = '📎 Document';
                      } else {
                        preview = type?.replaceFirst('message', '') ?? '';
                      }
                    }
                  }

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: isGeneral
                              ? Icon(
                                  LucideIcons.hash,
                                  color: _getTopicColor(topicInfo, context),
                                  size: 28,
                                )
                              : CustomEmojiIcon(
                                  customEmojiId:
                                      topicInfo['icon']?['custom_emoji_id']
                                          is int
                                      ? topicInfo['icon']!['custom_emoji_id']
                                            as int
                                      : int.tryParse(
                                              topicInfo['icon']?['custom_emoji_id']
                                                      .toString() ??
                                                  '0',
                                            ) ??
                                            0,
                                  fallbackIcon: LucideIcons.messageSquare,
                                  color: _getTopicColor(topicInfo, context),
                                  size: 28,
                                ),
                        ),
                      ),
                      title: Row(
                        children: [
                          if (isPinned) ...[
                            Icon(
                              LucideIcons.pin,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              topicName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: preview != null
                          ? Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                      trailing: const Icon(LucideIcons.chevronRight, size: 20),
                      onTap: () {
                        TelegramChatRoute(
                          chatId: chatId,
                          title: topicName,
                          messageThreadId: forumTopicId,
                        ).push(context);
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
