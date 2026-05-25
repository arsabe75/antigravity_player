import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';

/// Indicador de buffering que se muestra sobre el video.
///
/// Incluye tracking del tiempo transcurrido para mostrar mensajes
/// progresivos cuando la carga del video toma más de lo esperado
/// (ej. videos con MOOV atom al final del archivo).
class BufferingIndicator extends StatefulWidget {
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
  State<BufferingIndicator> createState() => _BufferingIndicatorState();
}

class _BufferingIndicatorState extends State<BufferingIndicator> {
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  @override
  void didUpdateWidget(covariant BufferingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBuffering && !oldWidget.isBuffering) {
      _startTimer();
    } else if (!widget.isBuffering && oldWidget.isBuffering) {
      _stopTimer();
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _startTimer() {
    _stopTimer();
    _elapsedSeconds = 0;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  void _stopTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  String _getMessage(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!widget.isVideoNotOptimizedForStreaming) {
      if (_elapsedSeconds < 5) return t.bufferingLoading;
      if (_elapsedSeconds < 15) return t.bufferingStillDownloading;
      return t.bufferingCheckConnection;
    }
    if (_elapsedSeconds < 10) {
      return t.bufferingPreparingVideo;
    }
    if (_elapsedSeconds < 20) {
      return t.bufferingNotOptimized;
    }
    if (_elapsedSeconds < 35) {
      return t.bufferingSlowMetadata;
    }
    return t.bufferingTooLong;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isBuffering) return const SizedBox.shrink();

    final t = AppLocalizations.of(context);
    final msg = _getMessage(context);
    final lines = msg.split('\n');

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
              width: widget.size,
              height: widget.size,
              child: CircularProgressIndicator(
                color: widget.color ?? Colors.white,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 12),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  style: TextStyle(
                    color: _elapsedSeconds > 20
                        ? Colors.orange[200]
                        : Colors.white,
                    fontSize: 14,
                    fontWeight:
                        _elapsedSeconds > 15 ? FontWeight.w500 : FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (_elapsedSeconds >= 5) ...[
              const SizedBox(height: 4),
              Text(
                '$_elapsedSeconds${t.bufferingSecondsElapsed}',
                style: TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
