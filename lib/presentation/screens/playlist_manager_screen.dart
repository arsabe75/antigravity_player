import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path/path.dart' as path;

import '../../config/router/routes.dart';
import '../../domain/entities/playlist_entity.dart';
import '../providers/playlist_notifier.dart';

class PlaylistManagerScreen extends ConsumerStatefulWidget {
  const PlaylistManagerScreen({super.key});

  @override
  ConsumerState<PlaylistManagerScreen> createState() =>
      _PlaylistManagerScreenState();
}

class _PlaylistManagerScreenState extends ConsumerState<PlaylistManagerScreen> {
  List<PlaylistItem> _items = [];
  String? _currentFilePath;
  bool _isDirty = false;
  bool _startFromBeginning = false;

  @override
  void initState() {
    super.initState();
    // Initialize with current playlist if any
    final playlist = ref.read(playlistProvider);
    if (playlist.items.isNotEmpty) {
      _items = List.from(playlist.items);
      _currentFilePath = playlist.sourcePath;
    }
  }

  void _addItems(List<String> paths) {
    setState(() {
      _items.addAll(
        paths.map(
          (p) =>
              PlaylistItem(path: p, isNetwork: false, title: path.basename(p)),
        ),
      );
      _isDirty = true;
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _isDirty = true;
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
      _isDirty = true;
    });
  }

  Future<void> _pickVideos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final paths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();
      _addItems(paths);
    }
  }

  Future<void> _newPlaylist() async {
    if (_isDirty && _items.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved Changes'),
          content: const Text(
            'You have unsaved changes. Are you sure you want to start a new playlist?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() {
      _items = [];
      _currentFilePath = null;
      _isDirty = false;
    });
  }

  Future<void> _loadPlaylist() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_isDirty && _items.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved Changes'),
          content: const Text(
            'You have unsaved changes. Are you sure you want to load a new playlist?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'm3u'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      try {
        final lines = await file.readAsLines();
        final newItems = <PlaylistItem>[];
        String? pendingTitle;
        int? pendingDurationSecs;

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          // Parse M3U EXTINF metadata line
          if (trimmed.startsWith('#EXTINF:')) {
            // Format: #EXTINF:duration,title
            final content = trimmed.substring(8); // Remove '#EXTINF:'
            final commaIndex = content.indexOf(',');
            if (commaIndex > 0) {
              pendingDurationSecs = int.tryParse(
                content.substring(0, commaIndex),
              );
              pendingTitle = content.substring(commaIndex + 1).trim();
            }
            continue;
          }

          // Skip other M3U directives
          if (trimmed.startsWith('#')) continue;

          // This is a path line
          newItems.add(
            PlaylistItem(
              path: trimmed,
              isNetwork: trimmed.startsWith('http'),
              title: pendingTitle ?? path.basename(trimmed),
              duration: pendingDurationSecs != null && pendingDurationSecs > 0
                  ? Duration(seconds: pendingDurationSecs)
                  : null,
            ),
          );
          // Reset pending metadata
          pendingTitle = null;
          pendingDurationSecs = null;
        }

        setState(() {
          _items = newItems;
          _currentFilePath = file.path;
          _isDirty = false;
        });
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error loading playlist: $e')),
        );
      }
    }
  }

  Future<void> _savePlaylist({bool asNew = false}) async {
    String? targetPath = _currentFilePath;
    final messenger = ScaffoldMessenger.of(context);

    if (asNew || targetPath == null) {
      targetPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Playlist',
        fileName: 'playlist.m3u',
        type: FileType.custom,
        allowedExtensions: ['m3u', 'txt'],
      );
    }

    if (targetPath != null) {
      // Ensure extension - default to M3U for better interoperability
      if (!targetPath.endsWith('.txt') && !targetPath.endsWith('.m3u')) {
        targetPath += '.m3u';
      }

      final file = File(targetPath);

      // Build content based on format
      String content;
      if (targetPath.endsWith('.m3u')) {
        // M3U format with metadata
        final buffer = StringBuffer('#EXTM3U\n');
        for (final item in _items) {
          final durationSecs = item.duration?.inSeconds ?? -1;
          final title = item.title ?? path.basename(item.path);
          buffer.writeln('#EXTINF:$durationSecs,$title');
          buffer.writeln(item.path);
        }
        content = buffer.toString();
      } else {
        // Simple TXT format (one path per line)
        content = _items.map((item) => item.path).join('\n');
      }

      try {
        await file.writeAsString(content);
        setState(() {
          _currentFilePath = targetPath;
          _isDirty = false;
        });
        messenger.showSnackBar(const SnackBar(content: Text('Playlist saved')));
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error saving playlist: $e')),
        );
      }
    }
  }

  void _play() {
    if (_items.isEmpty) return;

    // Update global playlist state
    ref
        .read(playlistProvider.notifier)
        .setPlaylist(
          _items,
          sourcePath: _currentFilePath,
          startFromBeginning: _startFromBeginning,
        );

    // Navigate to player
    PlayerRoute($extra: PlayerRouteExtra(url: _items.first.path)).go(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Playlist Manager'),
            if (_currentFilePath != null)
              Text(
                path.basename(_currentFilePath!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.filePlus),
            tooltip: 'New Playlist',
            onPressed: _newPlaylist,
          ),
          IconButton(
            icon: const Icon(LucideIcons.folderOpen),
            tooltip: 'Load Playlist',
            onPressed: _loadPlaylist,
          ),
          IconButton(
            icon: const Icon(LucideIcons.save),
            tooltip: 'Save Playlist',
            onPressed: _items.isEmpty
                ? null
                : () => _savePlaylist(asNew: false),
          ),
          IconButton(
            icon: const Icon(LucideIcons.saveAll),
            tooltip: 'Save As...',
            onPressed: _items.isEmpty ? null : () => _savePlaylist(asNew: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.list,
                          size: 64,
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No videos in playlist',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _pickVideos,
                          icon: const Icon(LucideIcons.plus),
                          label: const Text('Add Videos'),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _items.length,
                    onReorder: _onReorder,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return ListTile(
                        key: ValueKey(item), // Or unique ID if available
                        leading: const Icon(LucideIcons.gripVertical),
                        title: Text(
                          item.title ?? path.basename(item.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          item.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 18),
                          onPressed: () => _removeItem(index),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _items.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'add',
                    onPressed: _pickVideos,
                    icon: const Icon(LucideIcons.plus),
                    label: const Text('Add'),
                  ),
                  const SizedBox(width: 16),
                  // Restart checkbox
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _startFromBeginning,
                          onChanged: (v) =>
                              setState(() => _startFromBeginning = v ?? false),
                        ),
                        Text(
                          'Restart',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton.extended(
                    heroTag: 'play',
                    onPressed: _play,
                    icon: const Icon(LucideIcons.play),
                    label: const Text('Play List'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ],
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
