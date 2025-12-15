import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../domain/entities/storage_statistics.dart';
import '../../infrastructure/services/telegram_cache_service.dart';
import '../providers/telegram_cache_notifier.dart';

/// Screen for viewing and managing Telegram cache storage.
///
/// Following Telegram Android pattern:
/// - Shows storage breakdown by file type
/// - "Keep Media" dropdown for auto-delete period
/// - "Clear Cache" button for manual cleanup
class TelegramStorageScreen extends ConsumerWidget {
  const TelegramStorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheState = ref.watch(telegramCacheProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Storage Usage'),
      ),
      body: cacheState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(telegramCacheProvider.notifier).loadStatistics(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Total size card
                    _buildTotalSizeCard(context, cacheState.statistics),

                    const SizedBox(height: 24),

                    // Storage breakdown
                    _buildStorageBreakdown(context, cacheState.statistics),

                    const SizedBox(height: 24),

                    // Keep Media setting
                    _buildKeepMediaSetting(context, ref, cacheState),

                    const SizedBox(height: 24),

                    // Clear cache button
                    _buildClearCacheButton(context, ref, cacheState),

                    // Error message
                    if (cacheState.error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        cacheState.error!,
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTotalSizeCard(BuildContext context, StorageStatistics? stats) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              LucideIcons.hardDrive,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Total Cache',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              stats?.formattedTotalSize ?? '0 B',
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${stats?.fileCount ?? 0} files',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageBreakdown(
    BuildContext context,
    StorageStatistics? stats,
  ) {
    final theme = Theme.of(context);

    final categories = [
      _StorageCategory(
        'Videos',
        stats?.videoSize ?? 0,
        stats?.formattedVideoSize ?? '0 B',
        LucideIcons.video,
        Colors.blue,
      ),
      _StorageCategory(
        'Photos',
        stats?.photoSize ?? 0,
        stats?.formattedPhotoSize ?? '0 B',
        LucideIcons.image,
        Colors.green,
      ),
      _StorageCategory(
        'Documents',
        stats?.documentSize ?? 0,
        stats?.formattedDocumentSize ?? '0 B',
        LucideIcons.fileText,
        Colors.orange,
      ),
      _StorageCategory(
        'Audio',
        stats?.audioSize ?? 0,
        stats?.formattedAudioSize ?? '0 B',
        LucideIcons.music,
        Colors.purple,
      ),
      _StorageCategory(
        'Other',
        stats?.otherSize ?? 0,
        stats?.formattedOtherSize ?? '0 B',
        LucideIcons.file,
        Colors.grey,
      ),
    ];

    final totalSize = stats?.totalSize ?? 1; // Avoid division by zero

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Breakdown',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...categories.map(
              (cat) => _buildCategoryRow(context, cat, totalSize),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow(
    BuildContext context,
    _StorageCategory category,
    int totalSize,
  ) {
    final theme = Theme.of(context);
    final percentage = totalSize > 0 ? category.size / totalSize : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(category.icon, size: 20, color: category.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(category.name),
                    Text(
                      category.formattedSize,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(category.color),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeepMediaSetting(
    BuildContext context,
    WidgetRef ref,
    TelegramCacheState cacheState,
  ) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Keep Media',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Auto-delete cached files after this period',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<KeepMediaDuration>(
                  value: cacheState.keepMediaDuration,
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(telegramCacheProvider.notifier)
                          .setKeepMediaDuration(value);
                    }
                  },
                  items: KeepMediaDuration.values
                      .map(
                        (duration) => DropdownMenuItem(
                          value: duration,
                          child: Text(duration.label),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClearCacheButton(
    BuildContext context,
    WidgetRef ref,
    TelegramCacheState cacheState,
  ) {
    return ElevatedButton.icon(
      onPressed: cacheState.isClearing
          ? null
          : () => _showClearCacheDialog(context, ref),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.error,
        foregroundColor: Theme.of(context).colorScheme.onError,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      icon: cacheState.isClearing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.trash2),
      label: Text(cacheState.isClearing ? 'Clearing...' : 'Clear Cache'),
    );
  }

  Future<void> _showClearCacheDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'This will delete all downloaded Telegram files. '
          'You can re-download them from the cloud if needed.\n\n'
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await ref
          .read(telegramCacheProvider.notifier)
          .clearCache();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Cache cleared successfully' : 'Failed to clear cache',
            ),
          ),
        );
      }
    }
  }
}

class _StorageCategory {
  final String name;
  final int size;
  final String formattedSize;
  final IconData icon;
  final Color color;

  _StorageCategory(
    this.name,
    this.size,
    this.formattedSize,
    this.icon,
    this.color,
  );
}
