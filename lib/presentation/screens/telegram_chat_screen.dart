import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/window_controls.dart';
import '../providers/telegram_chat_notifier.dart';
import '../providers/telegram_content_notifier.dart'; // For getStreamUrl helper if needed
import '../../config/router/routes.dart';
import '../../domain/entities/playlist_entity.dart';
import '../providers/playlist_notifier.dart';

class TelegramChatScreen extends ConsumerStatefulWidget {
  final int chatId;
  final String title;
  final int? messageThreadId; // For forum topics

  const TelegramChatScreen({
    super.key,
    required this.chatId,
    required this.title,
    this.messageThreadId,
  });

  @override
  ConsumerState<TelegramChatScreen> createState() => _TelegramChatScreenState();
}

class _TelegramChatScreenState extends ConsumerState<TelegramChatScreen> {
  TelegramChatParams get _params => TelegramChatParams(
    chatId: widget.chatId,
    messageThreadId: widget.messageThreadId,
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(telegramChatProvider(_params));

    // Filter for video or video note messages, including MKV documents
    final videoMessages = state.messages.where((m) {
      final content = m['content'];
      if (content == null) return false;

      // Standard mp4/mov videos
      if (content['@type'] == 'messageVideo') return true;

      // MKV and other video formats sent as documents
      if (content['@type'] == 'messageDocument') {
        final document = content['document'];
        final mimeType = (document['mime_type'] as String? ?? '').toLowerCase();
        final fileName = (document['file_name'] as String? ?? '').toLowerCase();

        if (mimeType.startsWith('video/')) return true;

        const videoExtensions = [
          '.mkv',
          '.avi',
          '.mp4',
          '.mov',
          '.webm',
          '.flv',
        ];
        for (final ext in videoExtensions) {
          if (fileName.endsWith(ext)) return true;
        }
      }
      return false;
    }).toList();

    // Auto-load more if we have very few videos and there's more history
    // We check !state.isLoadingMore to prevent spamming
    // And !state.isLoading to ensure initial load is done

    if (!state.isLoading &&
        !state.isLoadingMore &&
        state.hasMore &&
        videoMessages.length < 20) {
      debugPrint(
        'TelegramChatScreen: Auto-loading more messages (Current videos: ${videoMessages.length})',
      );
      // Use addPostFrameCallback to avoid modifying provider during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(telegramChatProvider(_params).notifier).loadMoreMessages();
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
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: 'Refresh',
            onPressed: () => ref
                .read(telegramChatProvider(_params).notifier)
                .refreshMessages(),
          ),
          const SizedBox(width: 8),
          const WindowControls(),
          const SizedBox(width: 8),
        ],
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
                  // Use addPostFrameCallback to avoid modifying provider during build
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      ref
                          .read(telegramChatProvider(_params).notifier)
                          .loadMoreMessages();
                    }
                  });
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 250,
                            childAspectRatio:
                                1.3, // Cinema-like landscape ratio
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final msg = videoMessages[index];
                        final content = msg['content'];
                        final messageId = msg['id'] as int;

                        int fileId;
                        int? size;
                        int duration = 0;
                        String? rawFileName;

                        if (content['@type'] == 'messageVideo') {
                          final video = content['video'];
                          fileId = video['video']['id'];
                          size = video['video']['size'];
                          duration = video['duration'] ?? 0;
                          rawFileName = video['file_name'];
                        } else if (content['@type'] == 'messageDocument') {
                          final doc = content['document'];
                          fileId = doc['document']['id'];
                          size = doc['document']['size'];
                          rawFileName = doc['file_name'];
                          // Documents don't provide duration in the message object
                          duration = 0;
                        } else {
                          return const SizedBox.shrink();
                        }

                        // Note: preloadVideoStart was removed - it was a no-op
                        // TDLib handles download on-demand when video is played

                        // Get video title with multiple fallbacks:
                        // 1. caption text from message (priority)
                        // 2. file_name from video metadata
                        // 3. Default fallback
                        String? captionText;
                        final caption = content['caption'];
                        if (caption != null && caption['text'] != null) {
                          final text = caption['text'].toString().trim();
                          if (text.isNotEmpty) {
                            // Take first line of caption as title
                            captionText = text.split('\n').first;
                            if (captionText.length > 100) {
                              captionText =
                                  '${captionText.substring(0, 97)}...';
                            }
                          }
                        }

                        // Use rawFileName extracted above instead of getting it from video['file_name']
                        String? effectiveFileName = rawFileName;
                        if (effectiveFileName != null &&
                            effectiveFileName.trim().isEmpty) {
                          effectiveFileName = null;
                        }

                        final fileName =
                            captionText ??
                            effectiveFileName ??
                            'Video sin título';

                        final isSelected = _selectedMessages.contains(
                          messageId,
                        );

                        return Card(
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: isSelected
                                ? const BorderSide(color: Colors.blue, width: 3)
                                : BorderSide.none,
                          ),
                          child: InkWell(
                            onTap: () async {
                              if (_selectedMessages.isNotEmpty) {
                                _toggleSelection(messageId);
                                return;
                              }
                              _playVideo(msg, fileId, size, fileName);
                            },
                            onSecondaryTap: () {
                              _toggleSelection(messageId);
                            },
                            child: Stack(
                              children: [
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Container(
                                            decoration: const BoxDecoration(
                                              color: Colors.transparent,
                                            ),
                                          ),
                                          Center(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.5,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                LucideIcons.play,
                                                color: Colors.white,
                                                size: 32,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 8,
                                            right: 8,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: duration > 0
                                                  ? Text(
                                                      _formatDuration(duration),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                      ),
                                                    )
                                                  : const Text(
                                                      'MKV', // Badge for files without duration (likely MKV)
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      color: isSelected
                                          ? Theme.of(context).primaryColor
                                                .withValues(alpha: 0.1)
                                          : Theme.of(context).cardColor,
                                      child: Text(
                                        fileName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: isSelected
                                              ? Colors.blue
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (isSelected)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).primaryColor,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: const Icon(
                                        LucideIcons.check,
                                        size: 16,
                                        color: Colors.white,
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
      floatingActionButton: _selectedMessages.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _playSelectedVideos(videoMessages),
              icon: const Icon(LucideIcons.play),
              label: Text('Play (${_selectedMessages.length})'),
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  // Set of selected message IDs (ordered by insertion if we used a LinkedHashSet, but here List is easier to maintain order if needed)
  // Actually, Set doesn't guarantee order. We want to play in the order selected OR chronological.
  // User request: "ir seleccionando videos... comenzar a reproducir la PlayList"
  // Implies order of selection matters? Or easier -> just play those selected in chronological order?
  // Usually "Add to playlist" appends. "Play selected" usually plays them in list order.
  // Let's use a List to preserve selection order which gives the user maximum control.
  final List<int> _selectedMessages = [];

  void _toggleSelection(int messageId) {
    setState(() {
      if (_selectedMessages.contains(messageId)) {
        _selectedMessages.remove(messageId);
      } else {
        _selectedMessages.add(messageId);
      }
    });
  }

  Future<void> _playVideo(
    Map<String, dynamic> msg,
    int fileId,
    int? size,
    String title,
  ) async {
    // Get Stream URL
    final url = await ref
        .read(telegramContentProvider.notifier)
        .getStreamUrl(fileId, size ?? 0);

    // Get message ID for stable progress persistence
    final messageId = msg['id'] as int?;

    // Create playlist item
    final playlistItem = PlaylistItem(
      path: url,
      isNetwork: true,
      title: title,
      extras: {
        'telegramChatId': widget.chatId,
        'telegramMessageId': messageId,
        'telegramFileSize': size,
        'telegramTopicId': widget.messageThreadId,
        'telegramTopicName': widget.messageThreadId != null
            ? widget.title
            : null,
      },
    );

    // Set playlist with single item
    ref.read(playlistProvider.notifier).setPlaylist([
      playlistItem,
    ], startIndex: 0);

    if (mounted) {
      PlayerRoute(
        $extra: PlayerRouteExtra(
          url: url,
          title: title,
          telegramChatId: widget.chatId,
          telegramMessageId: messageId,
          telegramFileSize: size,
          telegramTopicId: widget.messageThreadId,
          telegramTopicName: widget.messageThreadId != null
              ? widget.title
              : null,
        ),
      ).push(context);
    }
  }

  Future<void> _playSelectedVideos(List<Map<String, dynamic>> allVideos) async {
    if (_selectedMessages.isEmpty) return;

    final playlistNotifier = ref.read(playlistProvider.notifier);
    final playlistItems = <PlaylistItem>[];
    final telegramContent = ref.read(telegramContentProvider.notifier);

    // Map message ID to video info for O(1) lookup
    final videoMap = {for (var v in allVideos) v['id'] as int: v};

    for (final msgId in _selectedMessages) {
      final msg = videoMap[msgId];
      if (msg == null) continue;

      final content = msg['content'];
      int fileId = 0;
      int? size;
      String? rawFileName;

      if (content['@type'] == 'messageVideo') {
        final video = content['video'];
        fileId = video['video']['id'];
        size = video['video']['size'];
        rawFileName = video['file_name'];
      } else if (content['@type'] == 'messageDocument') {
        final doc = content['document'];
        fileId = doc['document']['id'];
        size = doc['document']['size'];
        rawFileName = doc['file_name'];
      } else {
        continue;
      }

      // Calculate title (same logic as builder)
      String? captionText;
      final caption = content['caption'];
      if (caption != null && caption['text'] != null) {
        final text = caption['text'].toString().trim();
        if (text.isNotEmpty) {
          captionText = text.split('\n').first;
          if (captionText.length > 100) {
            captionText = '${captionText.substring(0, 97)}...';
          }
        }
      }
      String? effectiveFileName = rawFileName;
      if (effectiveFileName != null && effectiveFileName.trim().isEmpty) {
        effectiveFileName = null;
      }
      final title = captionText ?? effectiveFileName ?? 'Video sin título';

      // Get URL (can be async, but for playlist we might need it now OR just store fileId and let player handle it?)
      // The current Player expects a path/URL.
      // We'll generate the proxy URL here.
      final url = await telegramContent.getStreamUrl(fileId, size ?? 0);

      playlistItems.add(
        PlaylistItem(
          path: url,
          isNetwork: true,
          title: title,
          extras: {
            'telegramChatId': widget.chatId,
            'telegramMessageId': msgId,
            'telegramFileSize': size,
            'telegramTopicId': widget.messageThreadId,
            'telegramTopicName': widget.messageThreadId != null
                ? widget.title
                : null,
          },
        ),
      );
    }

    // Set Playlist
    playlistNotifier.setPlaylist(playlistItems, startIndex: 0);

    // Get first item to start player
    if (playlistItems.isNotEmpty) {
      final firstItem = playlistItems.first;

      if (!mounted) return;

      await PlayerRoute(
        $extra: PlayerRouteExtra(
          url: firstItem.path,
          title: firstItem.title,
          telegramChatId: widget.chatId,
          telegramMessageId: firstItem.extras?['telegramMessageId'] as int?,
          telegramFileSize: firstItem.extras?['telegramFileSize'] as int?,
          telegramTopicId: widget.messageThreadId,
          telegramTopicName: widget.messageThreadId != null
              ? widget.title
              : null,
        ),
      ).push(context);

      if (mounted) {
        setState(() {
          _selectedMessages.clear();
        });
      }
    }
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}
