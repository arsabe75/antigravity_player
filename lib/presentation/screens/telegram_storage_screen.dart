import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../domain/entities/storage_statistics.dart';
import '../../infrastructure/services/telegram_cache_service.dart';
import '../../infrastructure/services/cache_settings.dart';
import '../providers/telegram_cache_notifier.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/window_controls.dart';
import '../../l10n/l10n.dart';

/// Screen for viewing and managing Telegram cache storage.
///
/// Following Telegram Android pattern:
/// - Shows storage breakdown by file type
/// - "Keep Media" dropdown for auto-delete period
/// - Video cache size limit (NVR-style)
/// - Disk space information
/// - "Clear Cache" button for manual cleanup
class TelegramStorageScreen extends ConsumerWidget {
  const TelegramStorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheState = ref.watch(telegramCacheProvider);
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: t.storageBack,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(t.storageUsage),
        flexibleSpace: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          behavior: HitTestBehavior.translucent,
        ),
        actions: const [
          SizedBox(width: 8),
          WindowControls(),
          SizedBox(width: 8),
        ],
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
                    // Disk space info
                    _buildDiskSpaceCard(context, cacheState),

                    const SizedBox(height: 24),

                    // Total size card
                    _buildTotalSizeCard(context, cacheState.statistics),

                    const SizedBox(height: 24),

                    // Storage breakdown
                    _buildStorageBreakdown(context, cacheState.statistics),

                    const SizedBox(height: 24),

                    // Video cache limit (NVR-style)
                    _buildVideoCacheLimitSetting(context, ref, cacheState),

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

  Widget _buildDiskSpaceCard(BuildContext context, TelegramCacheState state) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final availableSpace = state.availableDiskSpace;
    final totalSpace = state.totalDiskSpace;
    final usedPercent = totalSpace > 0
        ? ((totalSpace - availableSpace) / totalSpace).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              LucideIcons.hardDrive,
              size: 32,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        t.storageDiskSpace,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${StorageStatistics.formatBytes(availableSpace)} ${t.storageFree}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usedPercent,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        usedPercent > 0.9
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${StorageStatistics.formatBytes(totalSpace - availableSpace)} ${t.storageUsedOf} ${StorageStatistics.formatBytes(totalSpace)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalSizeCard(BuildContext context, StorageStatistics? stats) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              LucideIcons.database,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              t.storageTotalCache,
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
              '${stats?.fileCount ?? 0} ${t.storageFiles}',
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
    final t = AppLocalizations.of(context);

    final categories = [
      _StorageCategory(
        t.storageVideos,
        stats?.videoSize ?? 0,
        stats?.formattedVideoSize ?? '0 B',
        LucideIcons.video,
        Colors.blue,
      ),
      _StorageCategory(
        t.storagePhotos,
        stats?.photoSize ?? 0,
        stats?.formattedPhotoSize ?? '0 B',
        LucideIcons.image,
        Colors.green,
      ),
      _StorageCategory(
        t.storageDocuments,
        stats?.documentSize ?? 0,
        stats?.formattedDocumentSize ?? '0 B',
        LucideIcons.fileText,
        Colors.orange,
      ),
      _StorageCategory(
        t.storageAudio,
        stats?.audioSize ?? 0,
        stats?.formattedAudioSize ?? '0 B',
        LucideIcons.music,
        Colors.purple,
      ),
      _StorageCategory(
        t.storageOther,
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
              t.storageBreakdown,
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

  Widget _buildVideoCacheLimitSetting(
    BuildContext context,
    WidgetRef ref,
    TelegramCacheState cacheState,
  ) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final videoSize = cacheState.statistics?.videoSize ?? 0;
    final isNearLimit = cacheState.isVideoNearLimit;
    final usagePercent = cacheState.videoCacheUsagePercent;

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
                      Row(
                        children: [
                          Icon(
                            LucideIcons.video,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t.storageVideoCacheLimit,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.storageCacheLimitDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<CacheSizeLimit>(
                  value: cacheState.cacheSizeLimit,
                  onChanged: (value) {
                    if (value != null) {
                      // Validate if user has enough space
                      // Max Safe = Current Video Usage + Free Space - Safety Buffer (500MB)
                      final currentVideoSize =
                          cacheState.statistics?.videoSize ?? 0;
                      final safetyBuffer = 500 * 1024 * 1024; // 500 MB
                      final maxSafeSpace =
                          currentVideoSize +
                          cacheState.availableDiskSpace -
                          safetyBuffer;

                      if (value.sizeInBytes > maxSafeSpace) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              t.storageNotEnoughSpace(value.label, StorageStatistics.formatBytes(maxSafeSpace)),
                            ),
                            backgroundColor: theme.colorScheme.error,
                          ),
                        );
                        return;
                      }

                      ref
                          .read(telegramCacheProvider.notifier)
                          .setCacheSizeLimit(value);
                    }
                  },
                  items: CacheSizeLimit.values
                      .map(
                        (limit) => DropdownMenuItem(
                          value: limit,
                          child: Text(limit.label),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
            // Show usage progress bar
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  StorageStatistics.formatBytes(videoSize),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isNearLimit
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: isNearLimit ? FontWeight.bold : null,
                  ),
                ),
                Text(
                  cacheState.cacheSizeLimit.label,
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
                value: usagePercent,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                  isNearLimit ? theme.colorScheme.error : Colors.blue,
                ),
                minHeight: 8,
              ),
            ),
            if (isNearLimit) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    LucideIcons.alertTriangle,
                    size: 14,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    t.storageApproachingLimit,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKeepMediaSetting(
    BuildContext context,
    WidgetRef ref,
    TelegramCacheState cacheState,
  ) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

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
                        t.storageKeepMedia,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.storageKeepMediaDesc,
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
    final t = AppLocalizations.of(context);
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
      label: Text(cacheState.isClearing ? t.storageClearing : t.storageClearCache),
    );
  }

  Future<void> _showClearCacheDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.storageClearConfirmTitle),
        content: Text(
          t.storageClearConfirmMsg,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.storageClearConfirmCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.storageClearConfirmClear),
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
              success ? t.storageCacheCleared : t.storageCacheClearFailed,
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
