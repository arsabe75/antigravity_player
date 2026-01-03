import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/entities/storage_statistics.dart';
import '../../infrastructure/services/telegram_cache_service.dart';
import '../../infrastructure/services/cache_settings.dart';
import '../../infrastructure/services/local_streaming_proxy.dart';

part 'telegram_cache_notifier.g.dart';

/// State for the Telegram cache management screen.
class TelegramCacheState {
  final StorageStatistics? statistics;
  final KeepMediaDuration keepMediaDuration;
  final CacheSizeLimit cacheSizeLimit;
  final int availableDiskSpace;
  final int totalDiskSpace;
  final bool isLoading;
  final bool isClearing;
  final bool isDiskCriticallyLow;
  final String? error;

  const TelegramCacheState({
    this.statistics,
    this.keepMediaDuration = KeepMediaDuration.forever,
    this.cacheSizeLimit = CacheSizeLimit.unlimited,
    this.availableDiskSpace = 0,
    this.totalDiskSpace = 0,
    this.isLoading = false,
    this.isClearing = false,
    this.isDiskCriticallyLow = false,
    this.error,
  });

  /// Returns true if video cache is approaching the limit (>80%).
  bool get isVideoNearLimit {
    if (cacheSizeLimit.isUnlimited) return false;
    final videoSize = statistics?.videoSize ?? 0;
    return videoSize > (cacheSizeLimit.sizeInBytes * 0.8);
  }

  /// Returns the video cache usage percentage (0.0 to 1.0).
  double get videoCacheUsagePercent {
    if (cacheSizeLimit.isUnlimited) return 0.0;
    final videoSize = statistics?.videoSize ?? 0;
    if (cacheSizeLimit.sizeInBytes <= 0) return 0.0;
    return (videoSize / cacheSizeLimit.sizeInBytes).clamp(0.0, 1.0);
  }

  TelegramCacheState copyWith({
    StorageStatistics? statistics,
    KeepMediaDuration? keepMediaDuration,
    CacheSizeLimit? cacheSizeLimit,
    int? availableDiskSpace,
    int? totalDiskSpace,
    bool? isLoading,
    bool? isClearing,
    bool? isDiskCriticallyLow,
    String? error,
    bool clearError = false,
  }) {
    return TelegramCacheState(
      statistics: statistics ?? this.statistics,
      keepMediaDuration: keepMediaDuration ?? this.keepMediaDuration,
      cacheSizeLimit: cacheSizeLimit ?? this.cacheSizeLimit,
      availableDiskSpace: availableDiskSpace ?? this.availableDiskSpace,
      totalDiskSpace: totalDiskSpace ?? this.totalDiskSpace,
      isLoading: isLoading ?? this.isLoading,
      isClearing: isClearing ?? this.isClearing,
      isDiskCriticallyLow: isDiskCriticallyLow ?? this.isDiskCriticallyLow,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

@Riverpod()
class TelegramCacheNotifier extends _$TelegramCacheNotifier {
  late final TelegramCacheService _service;

  @override
  TelegramCacheState build() {
    _service = TelegramCacheService();

    // Subscribe to disk safety stream
    final subscription = _service.onDiskCriticalState.listen((isCritical) {
      state = state.copyWith(isDiskCriticallyLow: isCritical);
    });
    ref.onDispose(subscription.cancel);

    // Load data on build
    Future.microtask(() => loadStatistics());
    return const TelegramCacheState(isLoading: true);
  }

  /// Load storage statistics and preferences.
  Future<void> loadStatistics() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final stats = await _service.getStorageStatistics();
      final keepDuration = await _service.getKeepMediaDuration();
      final sizeLimit = await _service.getCacheSizeLimit();
      final availableSpace = await _service.getAvailableDiskSpace();
      final totalSpace = await _service.getTotalDiskSpace();

      state = state.copyWith(
        statistics: stats,
        keepMediaDuration: keepDuration,
        cacheSizeLimit: sizeLimit,
        availableDiskSpace: availableSpace,
        totalDiskSpace: totalSpace,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load storage statistics: $e',
      );
    }
  }

  /// Clear all cached files.
  Future<bool> clearCache() async {
    state = state.copyWith(isClearing: true, clearError: true);

    try {
      final success = await _service.clearCache(forceAll: true);

      if (success) {
        // Invalidate streaming proxy cache to ensure fresh file info
        LocalStreamingProxy().invalidateAllFiles();

        // Reload statistics after clearing
        final stats = await _service.getStorageStatistics();
        final availableSpace = await _service.getAvailableDiskSpace();
        state = state.copyWith(
          statistics: stats,
          availableDiskSpace: availableSpace,
          isClearing: false,
        );
        return true;
      } else {
        state = state.copyWith(
          isClearing: false,
          error: 'Failed to clear cache',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isClearing: false,
        error: 'Error clearing cache: $e',
      );
      return false;
    }
  }

  /// Update the "Keep Media" duration preference.
  Future<void> setKeepMediaDuration(KeepMediaDuration duration) async {
    await _service.setKeepMediaDuration(duration);
    state = state.copyWith(keepMediaDuration: duration);

    // Run optimization with new setting if not "Forever"
    if (duration != KeepMediaDuration.forever) {
      await _service.runOptimization();
      await loadStatistics(); // Reload stats after optimization
    }
  }

  /// Update the video cache size limit.
  ///
  /// Triggers NVR-style cleanup if new limit is lower than current usage.
  Future<void> setCacheSizeLimit(CacheSizeLimit limit) async {
    await _service.setCacheSizeLimit(limit);
    state = state.copyWith(cacheSizeLimit: limit);

    // Enforce new limit immediately if not unlimited
    if (!limit.isUnlimited) {
      await _service.enforceVideoSizeLimit();
      await loadStatistics(); // Reload stats after enforcement
    }
  }
}
