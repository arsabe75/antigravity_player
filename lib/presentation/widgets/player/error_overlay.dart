import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../domain/entities/player_error.dart';

/// Widget que muestra un overlay de error sobre el video
class ErrorOverlay extends StatelessWidget {
  final PlayerError error;
  final VoidCallback? onRetry;
  final VoidCallback onGoHome;

  const ErrorOverlay({
    super.key,
    required this.error,
    this.onRetry,
    required this.onGoHome,
  });

  IconData _getErrorIcon() {
    return switch (error) {
      NetworkError() => LucideIcons.wifiOff,
      FileNotFoundError() => LucideIcons.fileX,
      UnsupportedFormatError() => LucideIcons.fileWarning,
      PlaybackError() => LucideIcons.alertTriangle,
      PermissionError() => LucideIcons.lock,
      UnknownError() => LucideIcons.alertCircle,
    };
  }

  Color _getErrorColor() {
    return switch (error) {
      NetworkError() => Colors.orange,
      FileNotFoundError() => Colors.red,
      UnsupportedFormatError() => Colors.purple,
      PlaybackError() => Colors.yellow,
      PermissionError() => Colors.red,
      UnknownError() => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _getErrorColor().withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _getErrorColor().withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(_getErrorIcon(), size: 48, color: _getErrorColor()),
              ),
              const SizedBox(height: 24),

              // Error Title
              Text(
                _getErrorTitle(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Error Message
              Text(
                error.userFriendlyMessage,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Go Home Button
                  OutlinedButton.icon(
                    onPressed: onGoHome,
                    icon: const Icon(LucideIcons.home),
                    label: const Text('Go Home'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),

                  // Retry Button (if applicable)
                  if (error.canRetry && onRetry != null) ...[
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(LucideIcons.refreshCw),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _getErrorColor(),
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
                  'Technical Details',
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
                      error.message,
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

  String _getErrorTitle() {
    return switch (error) {
      NetworkError() => 'Connection Error',
      FileNotFoundError() => 'File Not Found',
      UnsupportedFormatError() => 'Unsupported Format',
      PlaybackError() => 'Playback Error',
      PermissionError() => 'Permission Denied',
      UnknownError() => 'Error',
    };
  }
}
