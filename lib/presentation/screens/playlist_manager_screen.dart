import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';

import '../../config/router/routes.dart';
import '../../domain/entities/playlist_entity.dart';
import '../providers/playlist_notifier.dart';
import '../widgets/window_controls.dart';
import '../../l10n/l10n.dart';

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
  RepeatMode _repeatMode = RepeatMode.none;

  @override
  void initState() {
    super.initState();
    // Initialize with current playlist if any
    final playlist = ref.read(playlistProvider);
    if (playlist.items.isNotEmpty) {
      _items = List.from(playlist.items);
      _currentFilePath = playlist.sourcePath;
      _repeatMode = playlist.repeatMode;
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
          title: Text(AppLocalizations.of(context).playlistUnsavedChanges),
          content: Text(
            AppLocalizations.of(context).playlistUnsavedChangesMsg,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).playlistCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).playlistDiscard),
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
    final t = AppLocalizations.of(context);
    if (_isDirty && _items.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.playlistUnsavedChanges),
          content: Text(
            t.playlistUnsavedChangesLoadMsg,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.playlistCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.playlistDiscard),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u'],
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
          SnackBar(content: Text('${t.playlistErrorLoading}: $e')),
        );
      }
    }
  }

  Future<void> _savePlaylist({bool asNew = false}) async {
    String? targetPath = _currentFilePath;
    final messenger = ScaffoldMessenger.of(context);
    final t = AppLocalizations.of(context);

    if (asNew || targetPath == null) {
      targetPath = await FilePicker.platform.saveFile(
        dialogTitle: t.playlistSave,
        fileName: 'playlist.m3u',
        type: FileType.custom,
        allowedExtensions: ['m3u'],
      );
    }

    if (targetPath != null) {
      // Ensure .m3u extension
      if (!targetPath.endsWith('.m3u')) {
        targetPath += '.m3u';
      }

      final file = File(targetPath);

      // M3U format with metadata
      final buffer = StringBuffer('#EXTM3U\n');
      for (final item in _items) {
        final durationSecs = item.duration?.inSeconds ?? -1;
        final title = item.title ?? path.basename(item.path);
        buffer.writeln('#EXTINF:$durationSecs,$title');
        buffer.writeln(item.path);
      }
      final content = buffer.toString();

      try {
        await file.writeAsString(content);
        setState(() {
          _currentFilePath = targetPath;
          _isDirty = false;
        });
        messenger.showSnackBar(SnackBar(content: Text(t.playlistSaved)));
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('${t.playlistErrorSaving}: $e')),
        );
      }
    }
  }

  void _play() {
    if (_items.isEmpty) return;

    // Update global playlist state
    final notifier = ref.read(playlistProvider.notifier);
    notifier.setPlaylist(
      _items,
      sourcePath: _currentFilePath,
      startFromBeginning: _startFromBeginning,
    );
    // Set repeat mode
    notifier.setRepeatMode(_repeatMode);

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
            Text(AppLocalizations.of(context).playlistManagerTitle),
            if (_currentFilePath != null)
              Text(
                path.basename(_currentFilePath!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        flexibleSpace: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          behavior: HitTestBehavior.translucent,
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.filePlus),
            tooltip: AppLocalizations.of(context).playlistNew,
            onPressed: _newPlaylist,
          ),
          IconButton(
            icon: const Icon(LucideIcons.folderOpen),
            tooltip: AppLocalizations.of(context).playlistLoad,
            onPressed: _loadPlaylist,
          ),
          IconButton(
            icon: const Icon(LucideIcons.save),
            tooltip: AppLocalizations.of(context).playlistSave,
            onPressed: _items.isEmpty
                ? null
                : () => _savePlaylist(asNew: false),
          ),
          IconButton(
            icon: const Icon(LucideIcons.saveAll),
            tooltip: AppLocalizations.of(context).playlistSaveAs,
            onPressed: _items.isEmpty ? null : () => _savePlaylist(asNew: true),
          ),
          const WindowControls(),
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
                          AppLocalizations.of(context).playlistNoVideos,
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
                          label: Text(AppLocalizations.of(context).playlistAddVideos),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _items.length,
                    onReorderItem: _onReorder,
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
                    label: Text(AppLocalizations.of(context).playlistAdd),
                  ),
                  const SizedBox(width: 16),
                  // Loop playlist button
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: IconButton(
                      onPressed: () {
                        setState(() {
                          _repeatMode = switch (_repeatMode) {
                            RepeatMode.none => RepeatMode.all,
                            RepeatMode.all => RepeatMode.one,
                            RepeatMode.one => RepeatMode.none,
                          };
                        });
                      },
                      icon: Icon(
                        _repeatMode == RepeatMode.one
                            ? LucideIcons.repeat1
                            : LucideIcons.repeat,
                        color: _repeatMode != RepeatMode.none
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      tooltip: switch (_repeatMode) {
                        RepeatMode.none => AppLocalizations.of(context).controlRepeatOff,
                        RepeatMode.all => AppLocalizations.of(context).controlRepeatAll,
                        RepeatMode.one => AppLocalizations.of(context).controlRepeatOne,
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
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
                          AppLocalizations.of(context).playlistRestart,
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
                    label: Text(AppLocalizations.of(context).playlistPlayList),
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
