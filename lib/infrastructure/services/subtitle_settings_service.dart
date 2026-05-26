import 'secure_storage_service.dart';

class SubtitleSettingsService {
  static const String _fontSizeKey = 'subtitle_font_size';
  static const String _colorKey = 'subtitle_color';

  static const double defaultFontSize = 28.0;
  static const String defaultColor = 'white';

  static const double minFontSize = 22.0;
  static const double maxFontSize = 48.0;

  static const List<String> availableColors = [
    'white',
    'yellow',
    'grey',
    'cyan',
  ];

  double getFontSize() {
    final prefs = SecureStorageService.instance;
    final value = prefs.getString(_fontSizeKey);
    if (value == null) return defaultFontSize;
    final parsed = double.tryParse(value);
    if (parsed == null) return defaultFontSize;
    return parsed.clamp(minFontSize, maxFontSize);
  }

  Future<void> setFontSize(double size) async {
    final prefs = SecureStorageService.instance;
    await prefs.setString(
      _fontSizeKey,
      size.clamp(minFontSize, maxFontSize).toStringAsFixed(1),
    );
  }

  String getColor() {
    final prefs = SecureStorageService.instance;
    return prefs.getString(_colorKey) ?? defaultColor;
  }

  Future<void> setColor(String color) async {
    final prefs = SecureStorageService.instance;
    await prefs.setString(_colorKey, color);
  }

  /// Maps a color name to its mpv hex string (e.g. '#FFFFFF').
  static String colorNameToMpvHex(String name) {
    switch (name) {
      case 'white':
        return '#FFFFFF';
      case 'yellow':
        return '#FFFF00';
      case 'grey':
        return '#E0E0E0';
      case 'cyan':
        return '#18FFFF';
      default:
        return '#FFFFFF';
    }
  }

  /// Maps a color name to its Flutter Color for UI preview.
  static int colorNameToFlutterValue(String name) {
    switch (name) {
      case 'white':
        return 0xFFFFFFFF;
      case 'yellow':
        return 0xFFFFFF00;
      case 'grey':
        return 0xFFE0E0E0;
      case 'cyan':
        return 0xFF18FFFF;
      default:
        return 0xFFFFFFFF;
    }
  }

  /// Converts the user-facing pixel size to mpv's sub-font-size scale.
  /// mpv default is 55, which corresponds to our default of 28px.
  static double fontSizeToMpvScale(double userPx) {
    return (userPx / defaultFontSize) * 55.0;
  }
}
