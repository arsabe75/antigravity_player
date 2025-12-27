import 'package:flutter/material.dart';

/// Indicador de buffering que se muestra sobre el video
class BufferingIndicator extends StatelessWidget {
  final bool isBuffering;
  final bool isVideoNotOptimizedForStreaming;
  final Color? color;
  final double size;

  const BufferingIndicator({
    super.key,
    required this.isBuffering,
    this.isVideoNotOptimizedForStreaming = false,
    this.color,
    this.size = 48.0,
  });

  @override
  Widget build(BuildContext context) {
    if (!isBuffering) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                color: color ?? Colors.white,
                strokeWidth: 3,
              ),
            ),
            // Show message when video is not optimized for streaming
            if (isVideoNotOptimizedForStreaming) ...[
              const SizedBox(height: 12),
              const Text(
                'Video not optimized for streaming',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'Loading may take a moment...',
                style: TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
