import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/presentation/providers/theme_provider.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  group('ThemeNotifier', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // Wait for any async initialization if needed, though for individual tests we might need to handle it per test
      // or just ensure we wait after creating the container/notifier
    });

    test('initial state is dark mode', () async {
      final container = ProviderContainer();

      // Initial state is system while loading
      expect(container.read(themeProvider), ThemeMode.system);

      // Allow async load to complete
      await Future.delayed(const Duration(milliseconds: 50));

      // Should be dark (default)
      expect(container.read(themeProvider), ThemeMode.dark);

      container.dispose();
    });

    test('toggleTheme switches from dark to light', () async {
      final container = ProviderContainer();
      final notifier = container.read(themeProvider.notifier);

      // Wait for init
      await Future.delayed(const Duration(milliseconds: 50));

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
      await Future.delayed(const Duration(milliseconds: 50));

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
      await Future.delayed(const Duration(milliseconds: 50));

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
      await Future.delayed(const Duration(milliseconds: 50));

      expect(container.read(themeProvider) == ThemeMode.dark, true);

      await notifier.toggleTheme();
      expect(container.read(themeProvider) == ThemeMode.dark, false);

      container.dispose();
    });
  });
}
