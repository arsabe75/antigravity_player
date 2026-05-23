import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../infrastructure/services/recent_videos_service.dart';
import '../../../infrastructure/services/telegram_service.dart';
import '../../providers/recent_videos_refresh_provider.dart';

/// Widget que muestra los videos recientes
/// Use [showTelegramVideos] to filter:
/// - false: Shows only local/network videos (for Home screen)
/// - true: Shows only Telegram videos (for Telegram screen)
///
/// Set [panelWidth] to constrain the widget width (used when placed in a Row)
class RecentVideosWidget extends ConsumerStatefulWidget {
  final Function(RecentVideo video) onVideoSelected;
  final bool showTelegramVideos;
  final double panelWidth;

  const RecentVideosWidget({
    super.key,
    required this.onVideoSelected,
    this.showTelegramVideos = false,
    this.panelWidth = 280,
  });

  @override
  ConsumerState<RecentVideosWidget> createState() => RecentVideosWidgetState();
}

/// Public state class so parent can call refresh() via GlobalKey
class RecentVideosWidgetState extends ConsumerState<RecentVideosWidget> {
  final _service = RecentVideosService();
  List<RecentVideo> _videos = [];
  bool _isLoading = true;
  final Map<int, String> _chatNames = {};
  final Set<int> _pendingChatIds = {};

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload videos when dependencies change
    _loadVideos();
  }

  /// Public method to refresh the list (call via GlobalKey)
  void refresh() {
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    final allVideos = await _service.getRecentVideos();
    // Filter based on showTelegramVideos parameter
    final filteredVideos = allVideos.where((v) {
      if (widget.showTelegramVideos) {
        return v.isTelegramVideo;
      } else {
        return !v.isTelegramVideo;
      }
    }).toList();

    if (mounted) {
      setState(() {
        _videos = filteredVideos;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeVideo(RecentVideo video) async {
    await _service.removeVideo(video.path);
    await _loadVideos();
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text(
          'Are you sure you want to clear all recent videos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Clear only the appropriate type of videos
      if (widget.showTelegramVideos) {
        await _service.clearTelegramVideos();
      } else {
        await _service.clearLocalVideos();
      }
      await _loadVideos();
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  void _resolveChatName(int chatId) {
    if (_chatNames.containsKey(chatId) || _pendingChatIds.contains(chatId)) {
      return;
    }
    final service = TelegramService();
    if (!service.isClientReady) return;

    _pendingChatIds.add(chatId);
    service.sendWithResult({
      '@type': 'getChat',
      'chat_id': chatId,
    }).then((result) {
      if (result['@type'] == 'chat') {
        final title = result['title'] as String?;
        if (title != null && mounted) {
          setState(() {
            _chatNames[chatId] = title;
          });
        }
      }
    }).catchError((e) {
      debugPrint('Error getting chat name for recent video: $e');
    }).whenComplete(() {
      _pendingChatIds.remove(chatId);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen for refresh trigger from anywhere in the app
    ref.listen<int>(recentVideosRefreshProvider, (previous, next) {
      _loadVideos();
    });

    // While loading, reserve the panel width so the Row layout doesn't shift
    // when videos appear. On cold boot the DB query can take long enough that
    // the initial collapsed state becomes visible and then jumps.
    if (_isLoading) {
      return SizedBox(
        width: widget.panelWidth,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_videos.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: widget.panelWidth,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.grey[900]?.withValues(alpha: 0.5)
            : const Color(0xFFEAE6DC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : const Color(0xFFD5CFC3),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  LucideIcons.history,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Recent',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _clearAll,
                  icon: Icon(
                    LucideIcons.trash2,
                    size: 14,
                    color: Colors.grey[500],
                  ),
                  tooltip: 'Clear all',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Videos List - Vertical scrollable
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: _videos.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final video = _videos[index];
                return _buildVerticalVideoCard(video, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalVideoCard(RecentVideo video, bool isDark) {
    if (video.isTelegramVideo && video.telegramChatId != null) {
      final chatId = video.telegramChatId!;
      if (!_chatNames.containsKey(chatId) && !_pendingChatIds.contains(chatId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _resolveChatName(chatId);
        });
      }
    }

    return Material(
      color: isDark ? Colors.grey[850] : const Color(0xFFF5F2EB),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => widget.onVideoSelected(video),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: video.isTelegramVideo
                      ? Colors.blue.withValues(alpha: 0.2)
                      : video.isNetwork
                          ? Colors.blue.withValues(alpha: 0.2)
                          : Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  video.isTelegramVideo
                      ? LucideIcons.send
                      : video.isNetwork ? LucideIcons.globe : LucideIcons.file,
                  size: 14,
                  color: video.isTelegramVideo
                      ? Colors.blue
                      : video.isNetwork ? Colors.blue : Colors.green,
                ),
              ),
              const SizedBox(width: 10),
              // Title and metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (video.isTelegramVideo && video.telegramChatId != null) ...[
                      if (video.telegramTopicName != null) ...[
                        // Topic name
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.hash,
                                size: 10,
                                color: Colors.orange[400],
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  video.telegramTopicName!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.orange[400],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Group name
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.users,
                                size: 10,
                                color: Colors.blue[400],
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _chatNames[video.telegramChatId] ?? 'Loading group...',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.blue[400],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Channel name
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.radio,
                                size: 10,
                                color: Colors.blue[400],
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _chatNames[video.telegramChatId] ?? 'Loading channel...',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.blue[400],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _formatTimeAgo(video.playedAt),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                        if (video.lastPosition != null &&
                            video.lastPosition!.inSeconds > 0) ...[
                          const SizedBox(width: 8),
                          Icon(
                            LucideIcons.clock,
                            size: 10,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _formatDuration(video.lastPosition!),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Delete button
              Tooltip(
                message: 'Remove video',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _removeVideo(video),
                    child: Icon(
                      LucideIcons.x,
                      size: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
