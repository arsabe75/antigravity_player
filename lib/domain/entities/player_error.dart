/// Representa los diferentes tipos de errores que pueden ocurrir durante la reproducción
sealed class PlayerError {
  /// Mensaje técnico del error
  String get message;

  /// Mensaje amigable para el usuario
  String get userFriendlyMessage;

  /// Si el error permite reintentar
  bool get canRetry;
}

/// Error de red (conexión, timeout, etc.)
class NetworkError extends PlayerError {
  @override
  final String message;

  NetworkError(this.message);

  @override
  String get userFriendlyMessage =>
      'Unable to connect to the video source.\nPlease check your internet connection.';

  @override
  bool get canRetry => true;
}

/// Error cuando el archivo no se encuentra
class FileNotFoundError extends PlayerError {
  @override
  final String message;
  final String? filePath;

  FileNotFoundError(this.message, {this.filePath});

  @override
  String get userFriendlyMessage =>
      'The video file could not be found.\nIt may have been moved or deleted.';

  @override
  bool get canRetry => false;
}

/// Error de formato no soportado
class UnsupportedFormatError extends PlayerError {
  @override
  final String message;
  final String? format;

  UnsupportedFormatError(this.message, {this.format});

  @override
  String get userFriendlyMessage {
    if (format != null) {
      return 'The video format ".$format" is not supported.\nTry converting to MP4.';
    }
    return 'This video format is not supported.\nTry converting to MP4.';
  }

  @override
  bool get canRetry => false;
}

/// Error durante la reproducción
class PlaybackError extends PlayerError {
  @override
  final String message;

  PlaybackError(this.message);

  @override
  String get userFriendlyMessage =>
      'An error occurred during playback.\nTry reopening the video.';

  @override
  bool get canRetry => true;
}

/// Error de permisos
class PermissionError extends PlayerError {
  @override
  final String message;

  PermissionError(this.message);

  @override
  String get userFriendlyMessage =>
      'Permission denied to access this file.\nCheck your file permissions.';

  @override
  bool get canRetry => false;
}

/// Error desconocido
class UnknownError extends PlayerError {
  @override
  final String message;

  UnknownError(this.message);

  @override
  String get userFriendlyMessage =>
      'An unexpected error occurred.\nPlease try again.';

  @override
  bool get canRetry => true;
}

/// Factory para crear el tipo de error apropiado basado en el mensaje
class PlayerErrorFactory {
  static PlayerError fromException(dynamic exception) {
    final message = exception.toString();

    if (_isNetworkError(message)) {
      return NetworkError(message);
    }

    if (_isFileNotFoundError(message)) {
      return FileNotFoundError(message);
    }

    if (_isFormatError(message)) {
      return UnsupportedFormatError(message);
    }

    if (_isPermissionError(message)) {
      return PermissionError(message);
    }

    return UnknownError(message);
  }

  static bool _isNetworkError(String message) {
    final lowerMessage = message.toLowerCase();
    return lowerMessage.contains('socket') ||
        lowerMessage.contains('connection') ||
        lowerMessage.contains('timeout') ||
        lowerMessage.contains('network') ||
        lowerMessage.contains('host');
  }

  static bool _isFileNotFoundError(String message) {
    final lowerMessage = message.toLowerCase();
    return lowerMessage.contains('not found') ||
        lowerMessage.contains('no such file') ||
        lowerMessage.contains('does not exist') ||
        lowerMessage.contains('enoent');
  }

  static bool _isFormatError(String message) {
    final lowerMessage = message.toLowerCase();
    return lowerMessage.contains('codec') ||
        lowerMessage.contains('format') ||
        lowerMessage.contains('unsupported') ||
        lowerMessage.contains('invalid');
  }

  static bool _isPermissionError(String message) {
    final lowerMessage = message.toLowerCase();
    return lowerMessage.contains('permission') ||
        lowerMessage.contains('denied') ||
        lowerMessage.contains('access');
  }
}
