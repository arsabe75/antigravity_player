import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../infrastructure/services/theme_storage_service.dart';

class ThemeNotifier extends Notifier<ThemeMode> {
  late final ThemeStorageService _storageService;

  @override
  ThemeMode build() {
    _storageService = ThemeStorageService();
    _loadTheme();
    return ThemeMode.system; // Default state while loading
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

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(() {
  return ThemeNotifier();
});
