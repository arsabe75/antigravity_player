/// Cache size limit options for Telegram video cache.
///
/// Implements NVR-style cache management where oldest files are
/// deleted when the limit is reached.
enum CacheSizeLimit {
  /// 2 GB - Minimal cache for limited storage devices
  gb2(2 * 1024 * 1024 * 1024, '2 GB'),

  /// 4 GB - Light usage
  gb4(4 * 1024 * 1024 * 1024, '4 GB'),

  /// 6 GB - Moderate usage
  gb6(6 * 1024 * 1024 * 1024, '6 GB'),

  /// 8 GB - Heavy usage
  gb8(8 * 1024 * 1024 * 1024, '8 GB'),

  /// 10 GB - Maximum recommended
  gb10(10 * 1024 * 1024 * 1024, '10 GB'),

  /// No limit - cache can grow indefinitely (current behavior)
  unlimited(-1, 'Unlimited');

  /// Size in bytes, -1 for unlimited
  final int sizeInBytes;

  /// Human-readable label for UI
  final String label;

  const CacheSizeLimit(this.sizeInBytes, this.label);

  /// Returns true if this limit has no cap.
  bool get isUnlimited => sizeInBytes < 0;
}
