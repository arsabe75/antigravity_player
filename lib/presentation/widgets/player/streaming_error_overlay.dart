import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../domain/value_objects/streaming_error.dart';
import '../../../../l10n/l10n.dart';

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

  String _getTitle(BuildContext context) {
    final t = AppLocalizations.of(context);
    return switch (error.type) {
      StreamingErrorType.timeout => t.streamingTimeout,
      StreamingErrorType.networkError => t.streamingNetworkError,
      StreamingErrorType.corruptFile => t.streamingCorruptFile,
      StreamingErrorType.unsupportedCodec => t.streamingUnsupportedCodec,
      StreamingErrorType.diskFull => t.streamingDiskFull,
      StreamingErrorType.fileNotFound => t.streamingFileNotFound,
      StreamingErrorType.maxRetriesExceeded => t.streamingMaxRetries,
      StreamingErrorType.degraded => t.streamingDegraded,
      StreamingErrorType.metadataUnavailable => t.streamingMetadataUnavailable,
      StreamingErrorType.playbackStall => t.streamingPlaybackStall,
      StreamingErrorType.unknown => t.streamingUnknown,
    };
  }

  String _getSubtitle(BuildContext context) {
    final t = AppLocalizations.of(context);
    return switch (error.type) {
      StreamingErrorType.timeout => t.streamingTimeoutSubtitle,
      StreamingErrorType.networkError => t.streamingNetworkSubtitle,
      StreamingErrorType.corruptFile => t.streamingCorruptSubtitle,
      StreamingErrorType.unsupportedCodec => t.streamingUnsupportedSubtitle,
      StreamingErrorType.diskFull => t.streamingDiskFullSubtitle,
      StreamingErrorType.fileNotFound => t.streamingNotFoundSubtitle,
      StreamingErrorType.maxRetriesExceeded => t.streamingMaxRetriesSubtitle,
      StreamingErrorType.degraded => t.streamingDegradedSubtitle,
      StreamingErrorType.metadataUnavailable => t.streamingMetadataSubtitle,
      StreamingErrorType.playbackStall => t.streamingStallSubtitle,
      StreamingErrorType.unknown => t.streamingUnknownSubtitle,
    };
  }

  bool get _isWarning => error.type == StreamingErrorType.degraded;

  String _getSuggestion(BuildContext context) {
    final t = AppLocalizations.of(context);
    return switch (error.type) {
      StreamingErrorType.timeout => t.streamingSuggestionTimeout,
      StreamingErrorType.networkError => t.streamingSuggestionNetwork,
      StreamingErrorType.corruptFile => t.streamingSuggestionCorrupt,
      StreamingErrorType.unsupportedCodec => t.streamingSuggestionUnsupported,
      StreamingErrorType.diskFull => t.streamingSuggestionDiskFull,
      StreamingErrorType.fileNotFound => t.streamingSuggestionNotFound,
      StreamingErrorType.maxRetriesExceeded => t.streamingSuggestionMaxRetries,
      StreamingErrorType.degraded => t.streamingSuggestionDegraded,
      StreamingErrorType.metadataUnavailable => t.streamingSuggestionMetadata,
      StreamingErrorType.playbackStall => t.streamingSuggestionStall,
      StreamingErrorType.unknown => t.streamingSuggestionUnknown,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final t = AppLocalizations.of(context);

    return Container(
      // For warnings, use a more transparent background so the video
      // (which is still playing) remains partially visible.
      color: _isWarning ? Colors.black54 : Colors.black87,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
            ),
            child: SingleChildScrollView(
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
                _getTitle(context),
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
                _getSubtitle(context),
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Action Buttons
              // Usamos Wrap en lugar de Row para evitar overflow horizontal
              // cuando hay 3 botones ("Volver", "Forzar", "Reintentar") con
              // texto en español en el espacio limitado (maxWidth: 480).
              Wrap(
                spacing: 16,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  // Go Back Button
                  OutlinedButton.icon(
                    onPressed: onGoBack,
                    icon: const Icon(LucideIcons.arrowLeft),
                    label: Text(AppLocalizations.of(context).streamingGoBack),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),

                  // "Forzar reproducción": disponible para todos los errores
                  // como vía de escape incluso cuando la clasificación falla.
                  if (!_isWarning && onForceRetry != null)
                    OutlinedButton.icon(
                      onPressed: onForceRetry,
                      icon: const Icon(LucideIcons.zap),
                      label: Text(AppLocalizations.of(context).streamingForceRetry),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                      ),
                    ),
                  // Reintentar/Entendido: solo para errores recuperables
                  if (error.isRecoverable && onRetry != null)
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: Icon(
                        _isWarning ? LucideIcons.x : LucideIcons.refreshCw,
                      ),
                      label: Text(_isWarning ? AppLocalizations.of(context).streamingGotIt : AppLocalizations.of(context).streamingRetry),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),

              // Technical Details (expandable)
              const SizedBox(height: 16),
              Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  title: Text(
                    AppLocalizations.of(context).streamingTechnicalDetails,
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
                          '${t.streamingSuggestion}: ${_getSuggestion(context)}',
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
              ),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }
}
