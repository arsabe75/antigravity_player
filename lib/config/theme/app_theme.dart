import 'dart:io';
import 'package:flutter/material.dart';

class AppTheme {
  static final lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1A6DAF),
      brightness: Brightness.light,
    ).copyWith(
      surface: const Color(0xFFF8F6F1),
      onSurface: const Color(0xFF1C1B18),
      surfaceContainerHighest: const Color(0xFFE8E4DA),
      surfaceContainerHigh: const Color(0xFFEDE9E0),
      surfaceContainer: const Color(0xFFF0EDE5),
      surfaceContainerLow: const Color(0xFFF5F2EB),
      surfaceContainerLowest: const Color(0xFFF8F6F1),
    ),
    scaffoldBackgroundColor: const Color(0xFFF0EDE5),
    fontFamilyFallback: Platform.isWindows ? const ['Noto Color Emoji'] : null,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF0EDE5),
      foregroundColor: Color(0xFF1C1B18),
      elevation: 0,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
  );

  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    fontFamilyFallback: Platform.isWindows ? const ['Noto Color Emoji'] : null,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF121212),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
  );
}
