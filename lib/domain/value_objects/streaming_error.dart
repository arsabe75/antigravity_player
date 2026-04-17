/// Types of errors that can occur during video streaming.
/// Used to provide specific feedback to users and determine recovery strategies.
enum StreamingErrorType {
  /// Timeout waiting for data from server
  timeout,

  /// Network connectivity error
  networkError,

  /// File appears to be corrupt or invalid
  corruptFile,

  /// Video codec not supported by player
  unsupportedCodec,

  /// Not enough disk space to continue downloading
  diskFull,

  /// File no longer available on Telegram servers
  fileNotFound,

  /// Maximum retry attempts exceeded
  maxRetriesExceeded,

  /// Playback stall: video causes repeated connection thrashing
  playbackStall,

  /// Unknown/unspecified error
  unknown,
}

/// Represents a streaming error with context for UI and recovery.
class StreamingError {
  /// Type of error that occurred
  final StreamingErrorType type;

  /// Human-readable error message
  final String message;

  /// File ID that encountered the error
  final int fileId;

  /// Whether the error might be resolved by retrying
  final bool isRecoverable;

  /// Number of retry attempts made before this error
  final int retryAttempts;

  const StreamingError({
    required this.type,
    required this.message,
    required this.fileId,
    this.isRecoverable = true,
    this.retryAttempts = 0,
  });

  /// Create a timeout error
  factory StreamingError.timeout(int fileId, {int retryAttempts = 0}) {
    return StreamingError(
      type: StreamingErrorType.timeout,
      message: 'Tiempo de espera agotado al cargar el video',
      fileId: fileId,
      isRecoverable: true,
      retryAttempts: retryAttempts,
    );
  }

  /// Create a max retries exceeded error.
  /// Marked as recoverable so the proxy uses FileLoadState.error (not unsupported).
  /// This allows the user to retry manually instead of permanently blocking the file.
  factory StreamingError.maxRetries(int fileId, int attempts) {
    return StreamingError(
      type: StreamingErrorType.maxRetriesExceeded,
      message: 'No se pudo cargar el video después de $attempts intentos',
      fileId: fileId,
      isRecoverable: true,
      retryAttempts: attempts,
    );
  }

  /// Create a file not found error
  factory StreamingError.fileNotFound(int fileId) {
    return StreamingError(
      type: StreamingErrorType.fileNotFound,
      message: 'El video ya no está disponible',
      fileId: fileId,
      isRecoverable: false,
    );
  }

  /// Create a disk full error
  factory StreamingError.diskFull(int fileId) {
    return StreamingError(
      type: StreamingErrorType.diskFull,
      message: 'No hay suficiente espacio en disco',
      fileId: fileId,
      isRecoverable: false,
    );
  }

  /// Create an unsupported codec error (video format not supported by player)
  factory StreamingError.unsupportedCodec(int fileId) {
    return StreamingError(
      type: StreamingErrorType.unsupportedCodec,
      message: 'El formato de video no es compatible con el reproductor',
      fileId: fileId,
      isRecoverable: false,
    );
  }

  /// Create a corrupt file error (invalid or damaged data)
  factory StreamingError.corruptFile(int fileId) {
    return StreamingError(
      type: StreamingErrorType.corruptFile,
      message: 'El archivo de video parece estar dañado o es inválido',
      fileId: fileId,
      isRecoverable: false,
    );
  }

  /// Create a playback stall error (video causes repeated UI-blocking thrashing)
  factory StreamingError.playbackStall(int fileId, int earlyExits) {
    return StreamingError(
      type: StreamingErrorType.playbackStall,
      message: 'El video presenta problemas de reproducción persistentes '
          '($earlyExits interrupciones detectadas)',
      fileId: fileId,
      isRecoverable: false,
      retryAttempts: earlyExits,
    );
  }

  /// Create from an exception
  factory StreamingError.fromException(int fileId, Object exception) {
    return StreamingError(
      type: StreamingErrorType.unknown,
      message: exception.toString(),
      fileId: fileId,
      isRecoverable: true,
    );
  }

  @override
  String toString() =>
      'StreamingError(type: $type, fileId: $fileId, recoverable: $isRecoverable)';
}
