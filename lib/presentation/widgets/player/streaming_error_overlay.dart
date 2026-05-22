import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../domain/value_objects/streaming_error.dart';

/// Overlay que muestra un error de streaming al usuario.
/// Se muestra cuando el proxy no puede reproducir el video
/// (max retries, timeout, codec incompatible, archivo dañado, etc.)
class StreamingErrorOverlay extends StatelessWidget {
  final StreamingError error;
  final VoidCallback? onRetry;
  final VoidCallback? onForceRetry;
  final VoidCallback onGoBack;

  const StreamingErrorOverlay({
    super.key,
    required this.error,
    this.onRetry,
    this.onForceRetry,
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
      StreamingErrorType.degraded => LucideIcons.info,
      StreamingErrorType.metadataUnavailable => LucideIcons.fileSearch,
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
      StreamingErrorType.degraded => Colors.blue,
      StreamingErrorType.metadataUnavailable => Colors.amber,
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
      StreamingErrorType.degraded => 'Advertencia de rendimiento',
      StreamingErrorType.metadataUnavailable => 'Metadatos no disponibles',
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
        'El reproductor no puede procesar este video. Puede estar dañado, tener un formato no compatible, o presentar problemas temporales de transmisión.',
      StreamingErrorType.unsupportedCodec =>
        'El formato de este video no es compatible con el reproductor.',
      StreamingErrorType.diskFull =>
        'No hay suficiente espacio en disco para descargar el video. Libera espacio e intenta de nuevo.',
      StreamingErrorType.fileNotFound =>
        'El video ya no está disponible en Telegram. Puede haber sido eliminado.',
      StreamingErrorType.maxRetriesExceeded =>
        'Se agotaron los intentos de descarga. El video puede tener problemas de transmisión o estar temporalmente inaccesible.',
      StreamingErrorType.degraded =>
        'Este video muestra signos de transmisión inestable. Puede continuar viéndolo pero es posible que experimente pausas breves.',
      StreamingErrorType.metadataUnavailable =>
        'Los metadatos del video no están disponibles temporalmente. '
        'El video puede reproducirse una vez que se cargue la información necesaria.',
      StreamingErrorType.playbackStall =>
        'Este video presenta interrupciones persistentes que bloquean la interfaz. Puede estar dañado o tener un formato de transmisión incompatible.',
      StreamingErrorType.unknown =>
        'Ocurrió un error inesperado al reproducir el video.',
    };
  }

  bool get _isWarning => error.type == StreamingErrorType.degraded;

  String _getSuggestion() {
    return switch (error.type) {
      StreamingErrorType.timeout =>
        'Verifica tu conexión a internet e intenta de nuevo.',
      StreamingErrorType.networkError =>
        'Verifica tu conexión e intenta en unos minutos.',
      StreamingErrorType.corruptFile =>
        'Usa "Forzar reproducción" para un reintento más agresivo, o vuelve más tarde.',
      StreamingErrorType.unsupportedCodec =>
        'Convierte el video a un formato compatible (H.264/AAC).',
      StreamingErrorType.diskFull =>
        'Libera espacio en disco y vuelve a intentar.',
      StreamingErrorType.fileNotFound =>
        'El video fue eliminado de Telegram.',
      StreamingErrorType.maxRetriesExceeded =>
        'Puedes reintentar normalmente o usar "Forzar" para un '
            'reintento más agresivo.',
      StreamingErrorType.degraded =>
        'El video puede seguir viéndose con algunas pausas.',
      StreamingErrorType.metadataUnavailable =>
        'Espera unos segundos y vuelve a intentar. Si el problema persiste, '
        'usa "Forzar" para un reintento más agresivo.',
      StreamingErrorType.playbackStall =>
        'Este video tiene problemas persistentes. Puede estar mal codificado.',
      StreamingErrorType.unknown =>
        'Contacta al soporte si el problema persiste.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return Container(
      // For warnings, use a more transparent background so the video
      // (which is still playing) remains partially visible.
      color: _isWarning ? Colors.black54 : Colors.black87,
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

                  // "Forzar reproducción": disponible para todos los errores
                  // como vía de escape incluso cuando la clasificación falla.
                  if (!_isWarning && onForceRetry != null) ...[
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: onForceRetry,
                      icon: const Icon(LucideIcons.zap),
                      label: const Text('Forzar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // Reintentar/Entendido: solo para errores recuperables
                  if (error.isRecoverable && onRetry != null)
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: Icon(
                        _isWarning ? LucideIcons.x : LucideIcons.refreshCw,
                      ),
                      label: Text(_isWarning ? 'Entendido' : 'Reintentar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                      ),
                    ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SelectableText(
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
                        const SizedBox(height: 8),
                        Text(
                          'Sugerencia: ${_getSuggestion()}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
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
