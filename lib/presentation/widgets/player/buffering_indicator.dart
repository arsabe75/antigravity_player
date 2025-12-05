import 'package:flutter/material.dart';

/// Indicador de buffering que se muestra sobre el video
class BufferingIndicator extends StatelessWidget {
  final bool isBuffering;
  final Color? color;
  final double size;

  const BufferingIndicator({
    super.key,
    required this.isBuffering,
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
        child: SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            color: color ?? Colors.white,
            strokeWidth: 3,
          ),
        ),
      ),
    );
  }
}
