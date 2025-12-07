import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../infrastructure/services/theme_storage_service.dart';

part 'theme_provider.g.dart';

@Riverpod(keepAlive: true)
class ThemeNotifier extends _$ThemeNotifier {
  late final ThemeStorageService _storageService;

  @override
  ThemeMode build() {
    _storageService = ThemeStorageService();
    // Iniciamos la carga asíncrona, pero retornamos un valor initial síncrono inmediatamente.
    // Si quisiéramos que el estado fuera asíncrono desde el principio, usaríamos AsyncNotifier<ThemeMode>
    // y retornaríamos un Future<ThemeMode>.
    _loadTheme();
    return ThemeMode.system; // Estado inicial por defecto mientras carga
  }

  Future<void> _loadTheme() async {
    final isDarkMode = await _storageService.loadThemeMode();
    if (isDarkMode != null) {
      state = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    } else {
      state = ThemeMode.dark;
      await _storageService.saveThemeMode(true);
    }
  }

  Future<void> toggleTheme() async {
    if (state == ThemeMode.dark) {
      // Cambio de estado simple. Al no ser una clase compleja con copyWith,
      // simplemente asignamos el nuevo valor.
      state = ThemeMode.light;
      await _storageService.saveThemeMode(false);
    } else {
      state = ThemeMode.dark;
      await _storageService.saveThemeMode(true);
    }
  }

  // Explicitly set theme
  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    if (mode == ThemeMode.dark) {
      await _storageService.saveThemeMode(true);
    } else if (mode == ThemeMode.light) {
      await _storageService.saveThemeMode(false);
    }
  }
}
