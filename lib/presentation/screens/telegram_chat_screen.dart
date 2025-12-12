import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/telegram_chat_notifier.dart';
import '../providers/telegram_content_notifier.dart'; // For getStreamUrl helper if needed

class TelegramChatScreen extends ConsumerStatefulWidget {
  final int chatId;
  final String title;

  const TelegramChatScreen({
    super.key,
    required this.chatId,
    required this.title,
  });

  @override
  ConsumerState<TelegramChatScreen> createState() => _TelegramChatScreenState();
}

class _TelegramChatScreenState extends ConsumerState<TelegramChatScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(telegramChatProvider(widget.chatId));

    // Filter for video or video note messages
    final videoMessages = state.messages.where((m) {
      final content = m['content'];
      return content != null && (content['@type'] == 'messageVideo');
    }).toList();

    // Auto-load more if we have very few videos and there's more history
    // We check !state.isLoadingMore to prevent spamming
    // And !state.isLoading to ensure initial load is done

    // DEBUG: Print status
    // print('ChatScreen check: isLoading=${state.isLoading}, isLoadingMore=${state.isLoadingMore}, hasMore=${state.hasMore}, videos=${videoMessages.length}, total=${state.messages.length}');

    if (!state.isLoading &&
        !state.isLoadingMore &&
        state.hasMore &&
        videoMessages.length < 20) {
      debugPrint(
        'TelegramChatScreen: Auto-loading more messages (Current videos: ${videoMessages.length})',
      );
      Future.microtask(() {
        if (mounted) {
          ref
              .read(telegramChatProvider(widget.chatId).notifier)
              .loadMoreMessages();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        flexibleSpace: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          behavior: HitTestBehavior.translucent,
        ),
      ),
      body: state.isLoading && state.messages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : videoMessages.isEmpty && !state.isLoading
          ? Center(
              child: state.isLoadingMore
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Searching chat history for videos...'),
                      ],
                    )
                  : const Text('No videos found in this chat.'),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                if (scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent - 500 &&
                    !state.isLoadingMore &&
                    state.hasMore) {
                  ref
                      .read(telegramChatProvider(widget.chatId).notifier)
                      .loadMoreMessages();
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 16 / 9,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final msg = videoMessages[index];
                        final video = msg['content']['video'];
                        final fileId = video['video']['id'];
                        final size = video['video']['size'];
                        // final thumbnail = ... (handle thumbnail later)

                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () async {
                              // Get Stream URL
                              final url = await ref
                                  .read(telegramContentProvider.notifier)
                                  .getStreamUrl(fileId, size);

                              if (context.mounted) {
                                context.push('/player', extra: url);
                              }
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(color: Colors.black12), // Placeholder
                                const Center(
                                  child: Icon(
                                    LucideIcons.playCircle,
                                    size: 48,
                                    color: Colors.white70,
                                  ),
                                ),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _formatDuration(video['duration'] ?? 0),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }, childCount: videoMessages.length),
                    ),
                  ),
                  if (state.isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}
