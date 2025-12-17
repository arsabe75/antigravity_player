import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/entities/storage_statistics.dart';
import '../../infrastructure/services/telegram_cache_service.dart';
import '../../infrastructure/services/local_streaming_proxy.dart';

part 'telegram_cache_notifier.g.dart';

/// State for the Telegram cache management screen.
class TelegramCacheState {
  final StorageStatistics? statistics;
  final KeepMediaDuration keepMediaDuration;
  final bool isLoading;
  final bool isClearing;
  final String? error;

  const TelegramCacheState({
    this.statistics,
    this.keepMediaDuration = KeepMediaDuration.forever,
    this.isLoading = false,
    this.isClearing = false,
    this.error,
  });

  TelegramCacheState copyWith({
    StorageStatistics? statistics,
    KeepMediaDuration? keepMediaDuration,
    bool? isLoading,
    bool? isClearing,
    String? error,
    bool clearError = false,
  }) {
    return TelegramCacheState(
      statistics: statistics ?? this.statistics,
      keepMediaDuration: keepMediaDuration ?? this.keepMediaDuration,
      isLoading: isLoading ?? this.isLoading,
      isClearing: isClearing ?? this.isClearing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

@riverpod
class TelegramCacheNotifier extends _$TelegramCacheNotifier {
  late final TelegramCacheService _service;

  @override
  TelegramCacheState build() {
    _service = TelegramCacheService();
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

      state = state.copyWith(
        statistics: stats,
        keepMediaDuration: keepDuration,
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
        state = state.copyWith(statistics: stats, isClearing: false);
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
}
