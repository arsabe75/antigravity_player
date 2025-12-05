import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../infrastructure/services/recent_videos_service.dart';

/// Widget que muestra los videos recientes
class RecentVideosWidget extends StatefulWidget {
  final Function(String path, bool isNetwork) onVideoSelected;

  const RecentVideosWidget({super.key, required this.onVideoSelected});

  @override
  State<RecentVideosWidget> createState() => _RecentVideosWidgetState();
}

class _RecentVideosWidgetState extends State<RecentVideosWidget> {
  final _service = RecentVideosService();
  List<RecentVideo> _videos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    final videos = await _service.getRecentVideos();
    if (mounted) {
      setState(() {
        _videos = videos;
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
      await _service.clearAll();
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_videos.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                LucideIcons.history,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Recent Videos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearAll,
                icon: const Icon(LucideIcons.trash2, size: 14),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Videos List
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _videos.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final video = _videos[index];
                return _buildVideoCard(video, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCard(RecentVideo video, bool isDark) {
    return Material(
      color: isDark ? Colors.grey[850] : Colors.grey[100],
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => widget.onVideoSelected(video.path, video.isNetwork),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon and close button
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: video.isNetwork
                          ? Colors.blue.withValues(alpha: 0.2)
                          : Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      video.isNetwork ? LucideIcons.globe : LucideIcons.file,
                      size: 14,
                      color: video.isNetwork ? Colors.blue : Colors.green,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _removeVideo(video),
                    child: Icon(
                      LucideIcons.x,
                      size: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Title
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    video.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Time and position
              Row(
                children: [
                  Text(
                    _formatTimeAgo(video.playedAt),
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                  if (video.lastPosition != null &&
                      video.lastPosition!.inSeconds > 0) ...[
                    const Spacer(),
                    Icon(LucideIcons.clock, size: 10, color: Colors.grey[500]),
                    const SizedBox(width: 2),
                    Text(
                      _formatDuration(video.lastPosition!),
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
