/// Cache size limit options for Telegram video cache.
///
/// Implements NVR-style cache management where oldest files are
/// deleted when the limit is reached.
enum CacheSizeLimit {
  /// 2 GB - Minimal cache for limited storage devices
  gb2(2147483648, '2 GB'), // 2 * 1024^3

  /// 4 GB - Light usage
  gb4(4294967296, '4 GB'), // 4 * 1024^3

  /// 6 GB - Moderate usage
  gb6(6442450944, '6 GB'), // 6 * 1024^3

  /// 8 GB - Heavy usage
  gb8(8589934592, '8 GB'), // 8 * 1024^3

  /// 10 GB - Maximum recommended
  gb10(10737418240, '10 GB'), // 10 * 1024^3

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
