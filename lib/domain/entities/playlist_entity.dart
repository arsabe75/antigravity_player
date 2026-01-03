import 'package:freezed_annotation/freezed_annotation.dart';

part 'playlist_entity.freezed.dart';

/// Modo de repetición
enum RepeatMode {
  none, // No repetir
  one, // Repetir el video actual
  all, // Repetir toda la playlist
}

/// Representa un elemento de la playlist
@freezed
sealed class PlaylistItem with _$PlaylistItem {
  const factory PlaylistItem({
    required String path,
    required bool isNetwork,
    String? title,
    Duration? duration,
  }) = _PlaylistItem;
}

/// Representa una playlist de videos
@freezed
sealed class PlaylistEntity with _$PlaylistEntity {
  const PlaylistEntity._();

  const factory PlaylistEntity({
    @Default([]) List<PlaylistItem> items,
    @Default(0) int currentIndex,
    @Default(false) bool shuffle,
    @Default(RepeatMode.none) RepeatMode repeatMode,
    String? sourcePath,
    @Default(false) bool startFromBeginning,
  }) = _PlaylistEntity;

  /// Video actual
  PlaylistItem? get currentItem =>
      items.isNotEmpty && currentIndex >= 0 && currentIndex < items.length
      ? items[currentIndex]
      : null;

  /// Si hay video anterior
  bool get hasPrevious => currentIndex > 0;

  /// Si hay video siguiente
  bool get hasNext => currentIndex < items.length - 1;

  /// Número total de videos
  int get length => items.length;

  /// Si la playlist está vacía
  bool get isEmpty => items.isEmpty;

  /// Si la playlist no está vacía
  bool get isNotEmpty => items.isNotEmpty;
}
