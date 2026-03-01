import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/value_objects/streaming_error.dart';

part 'player_state.freezed.dart';

@freezed
abstract class PlayerState with _$PlayerState {
  const factory PlayerState({
    @Default(false) bool isPlaying,
    @Default(false) bool isBuffering,
    @Default(false)
    bool
    isInitialLoading, // New: True when loading network video before playback starts
    @Default(Duration.zero) Duration position,
    @Default(Duration.zero) Duration duration,
    @Default(1.0) double volume,
    @Default(1.0) double playbackSpeed,
    @Default(false) bool isFullscreen,
    @Default(true) bool areControlsVisible,
    @Default(false) bool isAlwaysOnTop,
    @Default({}) Map<int, String> audioTracks,
    @Default({}) Map<int, String> subtitleTracks,
    int? currentAudioTrack,
    int? currentSubtitleTrack,
    String? currentVideoPath,
    String? currentVideoTitle,
    String? error,
    @Default(false) bool isMirrored,
    @Default('media_kit') String playerBackend,
    // Video not optimized for streaming (moov atom at end of file)
    @Default(false) bool isVideoNotOptimizedForStreaming,
    // Streaming proxy error (max retries, timeout, etc.)
    StreamingError? streamingError,
    // Contador de reintentos automáticos de seek (recuperación de buffering atascado)
    @Default(0) int seekRetryCount,
  }) = _PlayerState;
}
