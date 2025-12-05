/// Validador de URLs y rutas de video
class UrlValidator {
  UrlValidator._();

  /// Extensiones de video soportadas
  static const supportedExtensions = [
    'mp4',
    'mkv',
    'avi',
    'webm',
    'mov',
    'wmv',
    'flv',
    'm4v',
    'ts',
    'm3u8', // HLS
    'mpd', // DASH
  ];

  /// Valida si una URL es válida para video
  static ValidationResult validateVideoUrl(String url) {
    if (url.isEmpty) {
      return ValidationResult.invalid('URL cannot be empty');
    }

    // Check if it's a valid URL format
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return ValidationResult.invalid('Invalid URL format');
    }

    // Check if it has http or https scheme
    if (!['http', 'https'].contains(uri.scheme.toLowerCase())) {
      return ValidationResult.invalid(
        'URL must start with http:// or https://',
      );
    }

    // Check if it has a host
    if (uri.host.isEmpty) {
      return ValidationResult.invalid('URL must have a valid host');
    }

    // Check extension if present
    final extension = getVideoExtension(url);
    if (extension != null &&
        !supportedExtensions.contains(extension.toLowerCase())) {
      return ValidationResult.invalid(
        'Unsupported format: .$extension\nSupported: ${supportedExtensions.join(", ")}',
      );
    }

    return ValidationResult.valid();
  }

  /// Valida si una ruta de archivo es válida para video
  static ValidationResult validateFilePath(String path) {
    if (path.isEmpty) {
      return ValidationResult.invalid('Path cannot be empty');
    }

    final extension = getVideoExtension(path);
    if (extension == null) {
      return ValidationResult.invalid('File must have a video extension');
    }

    if (!supportedExtensions.contains(extension.toLowerCase())) {
      return ValidationResult.invalid(
        'Unsupported format: .$extension\nSupported: ${supportedExtensions.join(", ")}',
      );
    }

    return ValidationResult.valid();
  }

  /// Obtiene la extensión del video de una URL o ruta
  static String? getVideoExtension(String urlOrPath) {
    try {
      // Remove query parameters and fragments
      final cleanPath = urlOrPath.split('?').first.split('#').first;
      final lastDot = cleanPath.lastIndexOf('.');
      if (lastDot == -1 || lastDot == cleanPath.length - 1) {
        return null;
      }
      return cleanPath.substring(lastDot + 1).toLowerCase();
    } catch (_) {
      return null;
    }
  }

  /// Verifica si una cadena parece ser una URL de red
  static bool isNetworkUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  /// Obtiene el dominio de una URL
  static String? getDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      return null;
    }
  }
}

/// Resultado de la validación
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult._({required this.isValid, this.errorMessage});

  factory ValidationResult.valid() => const ValidationResult._(isValid: true);

  factory ValidationResult.invalid(String message) =>
      ValidationResult._(isValid: false, errorMessage: message);
}
