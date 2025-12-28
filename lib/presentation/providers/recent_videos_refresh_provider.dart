import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifier that holds a counter to trigger refreshes of recent videos.
/// Increment this value to trigger a refresh in any widget watching it.
class RecentVideosRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void trigger() {
    state++;
  }
}

final recentVideosRefreshProvider =
    NotifierProvider<RecentVideosRefreshNotifier, int>(
      RecentVideosRefreshNotifier.new,
    );

/// Helper to trigger a refresh of recent videos from anywhere
void triggerRecentVideosRefresh(WidgetRef ref) {
  ref.read(recentVideosRefreshProvider.notifier).trigger();
}
