import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../domain/entities/playlist_entity.dart';
import '../../providers/playlist_notifier.dart';

/// Sidebar que muestra la playlist actual
class PlaylistSidebar extends ConsumerWidget {
  final VoidCallback onVideoSelected;
  final VoidCallback onClose;

  const PlaylistSidebar({
    super.key,
    required this.onVideoSelected,
    required this.onClose,
  });

  Future<void> _addFiles(PlaylistNotifier notifier) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true, // Allow selecting multiple files
    );

    if (result != null) {
      for (final file in result.files) {
        if (file.path != null) {
          notifier.addItem(file.path!, isNetwork: false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistProvider);
    final notifier = ref.read(playlistProvider.notifier);

    return Container(
      width: 300,
      color: Colors.black87,
      child: Column(
        children: [
          // Header
          _buildHeader(context, playlist, notifier),

          // Playlist items
          Expanded(
            child: playlist.isEmpty
                ? _buildEmptyState(notifier)
                : _buildPlaylistItems(playlist, notifier),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    PlaylistEntity playlist,
    PlaylistNotifier notifier,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        children: [
          // Title row
          Row(
            children: [
              const Icon(LucideIcons.listVideo, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Playlist',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Text(
                playlist.isEmpty
                    ? '0'
                    : '${playlist.currentIndex + 1}/${playlist.length}',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 18),
                color: Colors.white,
                onPressed: onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Add files button
              IconButton(
                icon: const Icon(
                  LucideIcons.folderPlus,
                  color: Colors.white54,
                  size: 18,
                ),
                onPressed: () => _addFiles(notifier),
                tooltip: 'Add files',
              ),
              // Shuffle
              IconButton(
                icon: Icon(
                  LucideIcons.shuffle,
                  color: playlist.shuffle ? Colors.blue : Colors.white54,
                  size: 18,
                ),
                onPressed: notifier.toggleShuffle,
                tooltip: 'Shuffle',
              ),
              // Repeat
              IconButton(
                icon: Icon(
                  _getRepeatIcon(playlist.repeatMode),
                  color: playlist.repeatMode != RepeatMode.none
                      ? Colors.blue
                      : Colors.white54,
                  size: 18,
                ),
                onPressed: notifier.toggleRepeat,
                tooltip: _getRepeatTooltip(playlist.repeatMode),
              ),
              // Clear
              IconButton(
                icon: const Icon(
                  LucideIcons.trash2,
                  color: Colors.white54,
                  size: 18,
                ),
                onPressed: playlist.isEmpty ? null : notifier.clear,
                tooltip: 'Clear playlist',
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getRepeatIcon(RepeatMode mode) {
    return switch (mode) {
      RepeatMode.none => LucideIcons.repeat,
      RepeatMode.all => LucideIcons.repeat,
      RepeatMode.one => LucideIcons.repeat1,
    };
  }

  String _getRepeatTooltip(RepeatMode mode) {
    return switch (mode) {
      RepeatMode.none => 'Repeat: Off',
      RepeatMode.all => 'Repeat: All',
      RepeatMode.one => 'Repeat: One',
    };
  }

  Widget _buildEmptyState(PlaylistNotifier notifier) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.listVideo, size: 48, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text('Playlist is empty', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 8),
          Text(
            'Add videos to your playlist',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _addFiles(notifier),
            icon: const Icon(LucideIcons.folderPlus, size: 16),
            label: const Text('Add Files'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistItems(
    PlaylistEntity playlist,
    PlaylistNotifier notifier,
  ) {
    return ReorderableListView.builder(
      itemCount: playlist.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        notifier.moveItem(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final item = playlist.items[index];
        final isCurrent = index == playlist.currentIndex;

        return _PlaylistItemTile(
          key: ValueKey('${item.path}_$index'),
          item: item,
          index: index,
          isCurrent: isCurrent,
          onTap: () {
            notifier.goToIndex(index);
            onVideoSelected();
          },
          onRemove: () => notifier.removeItem(index),
        );
      },
    );
  }
}

class _PlaylistItemTile extends StatelessWidget {
  final PlaylistItem item;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PlaylistItemTile({
    super.key,
    required this.item,
    required this.index,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCurrent
          ? Colors.blue.withValues(alpha: 0.2)
          : Colors.transparent,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: isCurrent
              ? const Icon(LucideIcons.play, color: Colors.blue, size: 16)
              : Text(
                  '${index + 1}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
        ),
        title: Text(
          item.title ?? item.path.split('/').last,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isCurrent ? Colors.blue : Colors.white,
            fontSize: 13,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(
              item.isNetwork ? LucideIcons.globe : LucideIcons.file,
              size: 12,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              item.isNetwork ? 'Network' : 'Local',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(LucideIcons.x, size: 14),
              color: Colors.grey[500],
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            const Icon(LucideIcons.gripVertical, color: Colors.grey, size: 16),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
