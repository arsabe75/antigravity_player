import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Log levels for ProxyLogger, from most to least verbose.
enum ProxyLogLevel {
  /// Detailed trace logs for debugging specific issues
  trace,

  /// Debug information for development
  debug,

  /// General informational messages
  info,

  /// Warning conditions that might need attention
  warning,

  /// Error conditions that affect functionality
  error,

  /// No logging
  none,
}

/// Structured logger for LocalStreamingProxy with configurable levels
/// and a ring buffer for capturing recent logs during debugging.
///
/// Usage:
/// ```dart
/// final logger = ProxyLogger.instance;
/// logger.setLevel(ProxyLogLevel.debug);
/// logger.info('Proxy started', fileId: 123);
/// logger.error('Download failed', fileId: 123, data: {'offset': 1000});
/// ```
class ProxyLogger {
  // Singleton instance
  static final ProxyLogger instance = ProxyLogger._();

  ProxyLogger._();

  /// Current log level - messages below this level are ignored
  ProxyLogLevel _level = kDebugMode
      ? ProxyLogLevel.debug
      : ProxyLogLevel.warning;

  /// Ring buffer for recent log entries (for debugging)
  final Queue<ProxyLogEntry> _logBuffer = Queue();

  /// Maximum number of log entries to keep in buffer
  static const int _maxBufferSize = 500;

  /// Whether to also print to console (via debugPrint)
  bool _printToConsole = true;

  // ============================================================
  // CONFIGURATION
  // ============================================================

  /// Set the minimum log level. Messages below this level are ignored.
  void setLevel(ProxyLogLevel level) {
    _level = level;
  }

  /// Get the current log level.
  ProxyLogLevel get level => _level;

  /// Enable or disable console output.
  void setPrintToConsole(bool enabled) {
    _printToConsole = enabled;
  }

  /// Clear the log buffer.
  void clearBuffer() {
    _logBuffer.clear();
  }

  /// Get all buffered log entries.
  List<ProxyLogEntry> getBufferedLogs() {
    return _logBuffer.toList();
  }

  /// Get buffered logs filtered by level.
  List<ProxyLogEntry> getLogsAtLevel(ProxyLogLevel minLevel) {
    return _logBuffer
        .where((entry) => entry.level.index >= minLevel.index)
        .toList();
  }

  /// Get buffered logs for a specific file.
  List<ProxyLogEntry> getLogsForFile(int fileId) {
    return _logBuffer.where((entry) => entry.fileId == fileId).toList();
  }

  // ============================================================
  // LOGGING METHODS
  // ============================================================

  /// Log a trace message (most verbose).
  void trace(String message, {int? fileId, Map<String, dynamic>? data}) {
    _log(ProxyLogLevel.trace, message, fileId: fileId, data: data);
  }

  /// Log a debug message.
  void debug(String message, {int? fileId, Map<String, dynamic>? data}) {
    _log(ProxyLogLevel.debug, message, fileId: fileId, data: data);
  }

  /// Log an info message.
  void info(String message, {int? fileId, Map<String, dynamic>? data}) {
    _log(ProxyLogLevel.info, message, fileId: fileId, data: data);
  }

  /// Log a warning message.
  void warning(String message, {int? fileId, Map<String, dynamic>? data}) {
    _log(ProxyLogLevel.warning, message, fileId: fileId, data: data);
  }

  /// Log an error message.
  void error(
    String message, {
    int? fileId,
    Map<String, dynamic>? data,
    Object? exception,
    StackTrace? stackTrace,
  }) {
    _log(
      ProxyLogLevel.error,
      message,
      fileId: fileId,
      data: data,
      exception: exception,
      stackTrace: stackTrace,
    );
  }

  // ============================================================
  // INTERNAL
  // ============================================================

  void _log(
    ProxyLogLevel level,
    String message, {
    int? fileId,
    Map<String, dynamic>? data,
    Object? exception,
    StackTrace? stackTrace,
  }) {
    // Skip if below current log level
    if (level.index < _level.index) return;

    final entry = ProxyLogEntry(
      level: level,
      message: message,
      fileId: fileId,
      data: data,
      exception: exception,
      stackTrace: stackTrace,
      timestamp: DateTime.now(),
    );

    // Add to ring buffer
    _logBuffer.add(entry);
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeFirst();
    }

    // Print to console if enabled
    if (_printToConsole) {
      debugPrint(entry.formatted);
    }
  }
}

/// A single log entry with metadata.
class ProxyLogEntry {
  final ProxyLogLevel level;
  final String message;
  final int? fileId;
  final Map<String, dynamic>? data;
  final Object? exception;
  final StackTrace? stackTrace;
  final DateTime timestamp;

  const ProxyLogEntry({
    required this.level,
    required this.message,
    this.fileId,
    this.data,
    this.exception,
    this.stackTrace,
    required this.timestamp,
  });

  /// Format as a human-readable string for console output.
  String get formatted {
    final buffer = StringBuffer();

    // Level prefix
    buffer.write(_levelPrefix);
    buffer.write(' ');

    // Timestamp (HH:mm:ss.SSS)
    buffer.write(_formatTime(timestamp));
    buffer.write(' ');

    // File ID if present
    if (fileId != null) {
      buffer.write('[F:$fileId] ');
    }

    // Message
    buffer.write(message);

    // Data if present
    if (data != null && data!.isNotEmpty) {
      buffer.write(' ');
      buffer.write(_formatData(data!));
    }

    // Exception if present
    if (exception != null) {
      buffer.write(' | Exception: $exception');
    }

    return buffer.toString();
  }

  String get _levelPrefix {
    switch (level) {
      case ProxyLogLevel.trace:
        return 'Proxy[T]';
      case ProxyLogLevel.debug:
        return 'Proxy[D]';
      case ProxyLogLevel.info:
        return 'Proxy[I]';
      case ProxyLogLevel.warning:
        return 'Proxy[W]';
      case ProxyLogLevel.error:
        return 'Proxy[E]';
      case ProxyLogLevel.none:
        return 'Proxy[-]';
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }

  String _formatData(Map<String, dynamic> data) {
    final parts = data.entries.map((e) {
      final value = e.value;
      if (value is int && value > 1024 * 1024) {
        // Format large byte values as MB
        return '${e.key}=${(value / (1024 * 1024)).toStringAsFixed(1)}MB';
      } else if (value is int && value > 1024) {
        // Format medium byte values as KB
        return '${e.key}=${(value / 1024).toStringAsFixed(0)}KB';
      }
      return '${e.key}=$value';
    });
    return '{${parts.join(', ')}}';
  }

  @override
  String toString() => formatted;
}
