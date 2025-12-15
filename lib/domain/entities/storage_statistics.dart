/// Statistics about storage usage from TDLib cache.
class StorageStatistics {
  /// Total size of all cached files in bytes.
  final int totalSize;

  /// Total number of cached files.
  final int fileCount;

  /// Size of video files in bytes.
  final int videoSize;

  /// Size of photo files in bytes.
  final int photoSize;

  /// Size of document files in bytes.
  final int documentSize;

  /// Size of audio files in bytes.
  final int audioSize;

  /// Size of other files (stickers, etc.) in bytes.
  final int otherSize;

  const StorageStatistics({
    this.totalSize = 0,
    this.fileCount = 0,
    this.videoSize = 0,
    this.photoSize = 0,
    this.documentSize = 0,
    this.audioSize = 0,
    this.otherSize = 0,
  });

  /// Creates a StorageStatistics from TDLib storageStatistics response.
  ///
  /// TDLib structure:
  /// - storageStatistics { size, count, by_chat[] }
  /// - Each by_chat entry: storageStatisticsByChat { chat_id, size, count, by_file_type[] }
  /// - Each by_file_type entry: storageStatisticsByFileType { file_type, size, count }
  factory StorageStatistics.fromTdLib(Map<String, dynamic> json) {
    int total = 0;
    int count = 0;
    int videos = 0;
    int photos = 0;
    int documents = 0;
    int audio = 0;
    int other = 0;

    total = json['size'] as int? ?? 0;
    count = json['count'] as int? ?? 0;

    // Parse by_chat array - each chat contains its own by_file_type breakdown
    final byChat = json['by_chat'] as List<dynamic>? ?? [];

    for (final chatEntry in byChat) {
      if (chatEntry is! Map<String, dynamic>) continue;

      // Each chat has a by_file_type array
      final byFileType = chatEntry['by_file_type'] as List<dynamic>? ?? [];

      for (final entry in byFileType) {
        if (entry is! Map<String, dynamic>) continue;

        final fileType = entry['file_type'] as Map<String, dynamic>?;
        final size = entry['size'] as int? ?? 0;

        if (fileType == null) continue;

        final type = fileType['@type'] as String? ?? '';

        switch (type) {
          case 'fileTypeVideo':
          case 'fileTypeVideoNote':
            videos += size;
            break;
          case 'fileTypePhoto':
          case 'fileTypeProfilePhoto':
          case 'fileTypeThumbnail':
            photos += size;
            break;
          case 'fileTypeDocument':
            documents += size;
            break;
          case 'fileTypeAudio':
          case 'fileTypeVoiceNote':
            audio += size;
            break;
          default:
            other += size;
        }
      }
    }

    return StorageStatistics(
      totalSize: total,
      fileCount: count,
      videoSize: videos,
      photoSize: photos,
      documentSize: documents,
      audioSize: audio,
      otherSize: other,
    );
  }

  /// Formats bytes into human-readable string (KB, MB, GB).
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Returns formatted total size string.
  String get formattedTotalSize => formatBytes(totalSize);

  /// Returns formatted video size string.
  String get formattedVideoSize => formatBytes(videoSize);

  /// Returns formatted photo size string.
  String get formattedPhotoSize => formatBytes(photoSize);

  /// Returns formatted document size string.
  String get formattedDocumentSize => formatBytes(documentSize);

  /// Returns formatted audio size string.
  String get formattedAudioSize => formatBytes(audioSize);

  /// Returns formatted other size string.
  String get formattedOtherSize => formatBytes(otherSize);
}
