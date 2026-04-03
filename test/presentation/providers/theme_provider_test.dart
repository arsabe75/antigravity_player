import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/presentation/providers/theme_provider.dart';
import 'package:riverpod/riverpod.dart';
import 'package:video_player_app/infrastructure/services/secure_storage_service.dart';
import 'package:video_player_app/infrastructure/database/app_database.dart';
import 'package:drift/native.dart';

void main() {
  group('ThemeNotifier', () {
    setUp(() async {
      SecureStorageService.reset();
      await SecureStorageService.initializeForTest(
          AppDatabase(e: NativeDatabase.memory()));
    });

    test('initial state is dark mode', () async {
      final container = ProviderContainer();

      // Initial state is system while loading
      expect(container.read(themeProvider), ThemeMode.system);

      // Allow async load to complete
      await Future.delayed(const Duration(milliseconds: 500));

      // Should be dark (default)
      expect(container.read(themeProvider), ThemeMode.dark);

      container.dispose();
    });

    test('toggleTheme switches from dark to light', () async {
      final container = ProviderContainer();
      final notifier = container.read(themeProvider.notifier);

      // Wait for init
      await Future.delayed(const Duration(milliseconds: 500));

      // Ensure we start at dark
      expect(container.read(themeProvider), ThemeMode.dark);

      await notifier.toggleTheme();
      final theme = container.read(themeProvider);

      expect(theme, ThemeMode.light);
      container.dispose();
    });

    test('toggleTheme switches from light to dark', () async {
      final container = ProviderContainer();
      final notifier = container.read(themeProvider.notifier);

      // Wait for init
      await Future.delayed(const Duration(milliseconds: 500));

      await notifier.toggleTheme(); // dark -> light
      await notifier.toggleTheme(); // light -> dark
      final theme = container.read(themeProvider);

      expect(theme, ThemeMode.dark);
      container.dispose();
    });

    test('setTheme sets specific theme', () async {
      final container = ProviderContainer();
      final notifier = container.read(themeProvider.notifier);

      // Wait for init
      await Future.delayed(const Duration(milliseconds: 500));

      await notifier.setTheme(ThemeMode.light);
      expect(container.read(themeProvider), ThemeMode.light);

      await notifier.setTheme(ThemeMode.dark);
      expect(container.read(themeProvider), ThemeMode.dark);

      container.dispose();
    });

    test('isDarkMode returns correct value', () async {
      final container = ProviderContainer();
      final notifier = container.read(themeProvider.notifier);

      // Wait for init
      await Future.delayed(const Duration(milliseconds: 500));

      expect(container.read(themeProvider) == ThemeMode.dark, true);

      await notifier.toggleTheme();
      expect(container.read(themeProvider) == ThemeMode.dark, false);

      container.dispose();
    });
  });
}
