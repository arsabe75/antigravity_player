import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/entities/playlist_entity.dart';

part 'playlist_notifier.g.dart';

// Riverpod 3: keepAlive: true evita que el estado se destruya cuando no hay listeners.
// Por defecto (sin keepAlive), Riverpod destruye el estado si nadie lo está "viendo" (watching).
@Riverpod(keepAlive: true)
class PlaylistNotifier extends _$PlaylistNotifier {
  @override
  PlaylistEntity build() {
    // Retornamos el estado inicial de la playlist (vacía).
    return const PlaylistEntity();
  }

  /// Añade un video a la playlist
  void addItem(String path, {bool isNetwork = false, String? title}) {
    final item = PlaylistItem(
      path: path,
      isNetwork: isNetwork,
      title: title ?? path.split('/').last,
    );
    // Actualizamos el estado creando una nueva copia con el nuevo item añadido.
    // Nunca mutamos el estado directamente (ej. state.items.add(item) NO funcionaría si la lista fuera mutable,
    // pero aquí usamos listas inmutables y copyWith).
    state = state.copyWith(items: [...state.items, item]);
  }

  /// Añade múltiples videos a la playlist
  void addItems(List<PlaylistItem> items) {
    state = state.copyWith(items: [...state.items, ...items]);
  }

  /// Establece la playlist completa
  void setPlaylist(List<PlaylistItem> items, {int startIndex = 0}) {
    state = state.copyWith(
      items: items,
      currentIndex: startIndex.clamp(0, items.isEmpty ? 0 : items.length - 1),
    );
  }

  /// Limpia la playlist
  void clear() {
    state = const PlaylistEntity();
  }

  /// Elimina un item de la playlist
  void removeItem(int index) {
    if (index < 0 || index >= state.items.length) return;

    final newItems = [...state.items]..removeAt(index);
    var newIndex = state.currentIndex;

    if (index < state.currentIndex) {
      newIndex--;
    } else if (index == state.currentIndex && newIndex >= newItems.length) {
      newIndex = newItems.isEmpty ? 0 : newItems.length - 1;
    }

    state = state.copyWith(items: newItems, currentIndex: newIndex);
  }

  /// Mueve un item en la playlist
  void moveItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.items.length) return;
    if (newIndex < 0 || newIndex >= state.items.length) return;

    final items = [...state.items];
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    var currentIndex = state.currentIndex;
    if (oldIndex == currentIndex) {
      currentIndex = newIndex;
    } else if (oldIndex < currentIndex && newIndex >= currentIndex) {
      currentIndex--;
    } else if (oldIndex > currentIndex && newIndex <= currentIndex) {
      currentIndex++;
    }

    state = state.copyWith(items: items, currentIndex: currentIndex);
  }

  /// Va al video en el índice especificado
  void goToIndex(int index) {
    if (index < 0 || index >= state.items.length) return;
    state = state.copyWith(currentIndex: index);
  }

  /// Va al siguiente video
  bool next() {
    if (state.repeatMode == RepeatMode.one) {
      // En modo repetir uno, no cambiamos de video
      return true;
    }

    if (state.hasNext) {
      state = state.copyWith(currentIndex: state.currentIndex + 1);
      return true;
    } else if (state.repeatMode == RepeatMode.all && state.items.isNotEmpty) {
      // En modo repetir todo, volvemos al inicio
      state = state.copyWith(currentIndex: 0);
      return true;
    }
    return false;
  }

  /// Va al video anterior
  bool previous() {
    if (state.hasPrevious) {
      state = state.copyWith(currentIndex: state.currentIndex - 1);
      return true;
    } else if (state.repeatMode == RepeatMode.all && state.items.isNotEmpty) {
      // En modo repetir todo, vamos al final
      state = state.copyWith(currentIndex: state.items.length - 1);
      return true;
    }
    return false;
  }

  /// Alterna el modo shuffle
  void toggleShuffle() {
    if (!state.shuffle) {
      // Activar shuffle: mezclar los items
      final items = [...state.items];
      final currentItem = state.currentItem;
      items.shuffle(Random());

      // Mover el item actual al principio
      if (currentItem != null) {
        items.remove(currentItem);
        items.insert(0, currentItem);
      }

      state = state.copyWith(items: items, currentIndex: 0, shuffle: true);
    } else {
      // Desactivar shuffle (no restauramos el orden original por simplicidad)
      state = state.copyWith(shuffle: false);
    }
  }

  /// Cambia el modo de repetición
  void toggleRepeat() {
    final newMode = switch (state.repeatMode) {
      RepeatMode.none => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.none,
    };
    state = state.copyWith(repeatMode: newMode);
  }

  /// Establece el modo de repetición
  void setRepeatMode(RepeatMode mode) {
    state = state.copyWith(repeatMode: mode);
  }
}
