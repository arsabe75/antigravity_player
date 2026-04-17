import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../domain/value_objects/streaming_error.dart';

/// Overlay que muestra un error de streaming al usuario.
/// Se muestra cuando el proxy no puede reproducir el video
/// (max retries, timeout, codec incompatible, archivo dañado, etc.)
class StreamingErrorOverlay extends StatelessWidget {
  final StreamingError error;
  final VoidCallback? onRetry;
  final VoidCallback onGoBack;

  const StreamingErrorOverlay({
    super.key,
    required this.error,
    this.onRetry,
    required this.onGoBack,
  });

  IconData _getIcon() {
    return switch (error.type) {
      StreamingErrorType.timeout => LucideIcons.clock,
      StreamingErrorType.networkError => LucideIcons.wifiOff,
      StreamingErrorType.corruptFile => LucideIcons.fileX,
      StreamingErrorType.unsupportedCodec => LucideIcons.fileWarning,
      StreamingErrorType.diskFull => LucideIcons.hardDrive,
      StreamingErrorType.fileNotFound => LucideIcons.searchX,
      StreamingErrorType.maxRetriesExceeded => LucideIcons.alertOctagon,
      StreamingErrorType.playbackStall => LucideIcons.alertTriangle,
      StreamingErrorType.unknown => LucideIcons.alertCircle,
    };
  }

  Color _getColor() {
    return switch (error.type) {
      StreamingErrorType.timeout => Colors.orange,
      StreamingErrorType.networkError => Colors.orange,
      StreamingErrorType.corruptFile => Colors.red,
      StreamingErrorType.unsupportedCodec => Colors.purple,
      StreamingErrorType.diskFull => Colors.red,
      StreamingErrorType.fileNotFound => Colors.red,
      StreamingErrorType.maxRetriesExceeded => Colors.amber,
      StreamingErrorType.playbackStall => Colors.deepOrange,
      StreamingErrorType.unknown => Colors.grey,
    };
  }

  String _getTitle() {
    return switch (error.type) {
      StreamingErrorType.timeout => 'Tiempo de espera agotado',
      StreamingErrorType.networkError => 'Error de conexión',
      StreamingErrorType.corruptFile => 'Video dañado',
      StreamingErrorType.unsupportedCodec => 'Formato no compatible',
      StreamingErrorType.diskFull => 'Disco lleno',
      StreamingErrorType.fileNotFound => 'Video no disponible',
      StreamingErrorType.maxRetriesExceeded => 'No se pudo reproducir el video',
      StreamingErrorType.playbackStall => 'Problema de reproducción',
      StreamingErrorType.unknown => 'Error de reproducción',
    };
  }

  String _getSubtitle() {
    return switch (error.type) {
      StreamingErrorType.timeout =>
        'El servidor tardó demasiado en responder. El video puede estar temporalmente inaccesible.',
      StreamingErrorType.networkError =>
        'No se pudo conectar al servidor. Verifica tu conexión a internet.',
      StreamingErrorType.corruptFile =>
        'El archivo de video parece estar dañado o tiene un formato inválido. No se puede reproducir.',
      StreamingErrorType.unsupportedCodec =>
        'El formato de este video no es compatible con el reproductor.',
      StreamingErrorType.diskFull =>
        'No hay suficiente espacio en disco para descargar el video. Libera espacio e intenta de nuevo.',
      StreamingErrorType.fileNotFound =>
        'El video ya no está disponible en Telegram. Puede haber sido eliminado.',
      StreamingErrorType.maxRetriesExceeded =>
        'Se agotaron los intentos de descarga. El video puede tener problemas de transmisión o estar temporalmente inaccesible.',
      StreamingErrorType.playbackStall =>
        'Este video presenta interrupciones persistentes que bloquean la interfaz. Puede estar dañado o tener un formato de transmisión incompatible.',
      StreamingErrorType.unknown =>
        'Ocurrió un error inesperado al reproducir el video.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return Container(
      color: Colors.black87,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(_getIcon(), size: 48, color: color),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                _getTitle(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Subtitle / description
              Text(
                _getSubtitle(),
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Go Back Button
                  OutlinedButton.icon(
                    onPressed: onGoBack,
                    icon: const Icon(LucideIcons.arrowLeft),
                    label: const Text('Volver'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),

                  // Retry Button (only for recoverable errors)
                  if (error.isRecoverable && onRetry != null) ...[
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(LucideIcons.refreshCw),
                      label: const Text('Reintentar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),

              // Technical Details (expandable)
              const SizedBox(height: 16),
              ExpansionTile(
                title: Text(
                  'Detalles técnicos',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                collapsedIconColor: Colors.grey[600],
                iconColor: Colors.grey[600],
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      'Tipo: ${error.type.name}\n'
                      'File ID: ${error.fileId}\n'
                      'Intentos: ${error.retryAttempts}\n'
                      'Recuperable: ${error.isRecoverable ? "Sí" : "No"}\n'
                      'Mensaje: ${error.message}',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
