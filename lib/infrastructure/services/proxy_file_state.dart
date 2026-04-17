import 'dart:async';

// ignore: unused_import
import '../../domain/value_objects/loading_progress.dart';
import '../../domain/value_objects/streaming_error.dart'; // Used in StreamingError

/// Consolidated state for a single file being proxied.
///
/// This class replaces the scattered Maps in [LocalStreamingProxy]
/// to improve code maintainability and make the per-file state explicit.
///
/// ## Usage
/// ```dart
/// final state = _getOrCreateState(fileId);
/// state.downloadStartTime = DateTime.now();
/// ```
class ProxyFileState {
  /// The file ID this state belongs to
  final int fileId;

  // ============================================================
  // TIMING
  // ============================================================

  /// When the video was first opened (for grace period calculation)
  DateTime? openTime;

  /// When the current download started (for stall cooldown protection)
  DateTime? downloadStartTime;

  /// Last time the download offset changed (for debouncing)
  DateTime? lastOffsetChangeTime;

  /// When user explicitly initiated a seek
  DateTime? lastExplicitSeekTime;

  /// Last time the primary playback offset was updated
  DateTime? lastPrimaryUpdateTime;

  /// Last seek time (for adaptive buffer after seek)
  DateTime? lastSeekTime;

  /// Timestamp del último seek debounced ejecutado.
  /// El stall timer lo usa para evitar reinicios redundantes.
  DateTime? lastDebouncedSeekTime;

  // ============================================================
  // DOWNLOAD TRACKING
  // ============================================================

  /// Last time downloadFile was called for this file (rate limiting).
  /// Prevents flooding TDLib with calls that generate event cascades.
  DateTime? lastDownloadFileCallTime;

  /// Current active download offset
  int? activeDownloadOffset;

  /// Primary playback position (lowest actively-requested offset)
  int? primaryPlaybackOffset;

  /// Last offset served to the player (for seek detection)
  int? lastServedOffset;

  /// Current active download priority (1-32)
  int activePriority = 0;

  /// Last download progress (for stall detection)
  int lastDownloadProgress = 0;

  /// Last explicit seek target offset
  int? lastExplicitSeekOffset;

  /// Número de secuencia de seek. Se incrementa con cada seek del usuario.
  /// Conexiones HTTP creadas antes del último seek no actualizan primaryPlaybackOffset.
  int seekSequenceNumber = 0;

  /// Pending seek offset after MOOV loads
  int? pendingSeekAfterMoov;

  /// Pending seek offset for debounced seek
  int? pendingSeekOffset;

  /// Seek debounce timer
  Timer? seekDebounceTimer;

  // ============================================================
  // MOOV DETECTION
  // ============================================================

  /// Whether MOOV atom is at the end of the file
  bool isMoovAtEnd = false;

  /// Detected MOOV position
  // ignore: unused_field
  MoovPosition? moovPosition;

  /// Exact byte offset where the MOOV atom starts, if known
  int? exactMoovOffset;

  /// Forced MOOV download offset (while downloading MOOV)
  int? forcedMoovOffset;

  /// FIX U: Timestamp when forced MOOV download started.
  /// Used to detect stuck MOOV downloads that never progress.
  DateTime? forcedMoovStartTime;

  /// FIX U: Last observed byte count for the forced MOOV download.
  /// Tracks progress to distinguish between slow-but-progressing and truly stuck.
  int forcedMoovLastProgress = 0;

  /// Whether early MOOV detection has been triggered
  bool earlyMoovDetectionTriggered = false;

  // ============================================================
  // STATE MACHINE
  // ============================================================

  /// Current file loading state
  FileLoadState loadState = FileLoadState.idle;

  /// Last streaming error
  StreamingError? lastError;

  /// Whether playback position is stale (after cache clear)
  bool hasStalePlaybackPosition = false;

  /// Whether user seek is currently in progress
  bool userSeekInProgress = false;

  /// The offset currently being waited for by the primary HTTP connection.
  /// Used by the per-file stall timer to know which offset to restart.
  int? waitingForOffset;

  // ============================================================
  // CONNECTION THRASHING DETECTION
  // ============================================================

  /// Number of consecutive early exits from the streaming loop.
  /// When this exceeds the threshold within the time window,
  /// the video is marked as problematic.
  int earlyExitCount = 0;

  /// Timestamp of the first early exit in the current detection window.
  DateTime? firstEarlyExitTime;

  /// Read offset of the last early exit.
  /// Used to detect if exits are stuck at the same point.
  int? lastEarlyExitReadOffset;

  // ============================================================
  // PREFETCH BUFFER
  // ============================================================

  /// Whether a prefetch download is currently in progress
  /// (as opposed to a player-demanded download).
  bool prefetchActive = false;

  /// Last time prefetch was evaluated (for debounce).
  DateTime? lastPrefetchEvalTime;

  // ============================================================
  // CONSTRUCTOR AND METHODS
  // ============================================================

  ProxyFileState(this.fileId);

  /// Reset all state to initial values.
  /// Call this when switching away from a video.
  void reset() {
    // Timing
    openTime = null;
    downloadStartTime = null;
    lastOffsetChangeTime = null;
    lastExplicitSeekTime = null;
    lastPrimaryUpdateTime = null;
    lastSeekTime = null;
    lastDebouncedSeekTime = null;

    // Download tracking
    lastDownloadFileCallTime = null;
    activeDownloadOffset = null;
    primaryPlaybackOffset = null;
    lastServedOffset = null;
    activePriority = 0;
    lastDownloadProgress = 0;
    lastExplicitSeekOffset = null;
    seekSequenceNumber = 0;
    pendingSeekAfterMoov = null;
    pendingSeekOffset = null;
    seekDebounceTimer?.cancel();
    seekDebounceTimer = null;

    // MOOV detection
    isMoovAtEnd = false;
    moovPosition = null;
    exactMoovOffset = null;
    forcedMoovOffset = null;
    forcedMoovStartTime = null;
    forcedMoovLastProgress = 0;
    earlyMoovDetectionTriggered = false;

    // State machine
    loadState = FileLoadState.idle;
    lastError = null;
    hasStalePlaybackPosition = false;
    userSeekInProgress = false;
    waitingForOffset = null;

    // Connection thrashing detection
    earlyExitCount = 0;
    firstEarlyExitTime = null;
    lastEarlyExitReadOffset = null;

    // Prefetch
    prefetchActive = false;
    lastPrefetchEvalTime = null;
  }

  /// Reset only the active download state.
  /// Use this when the underlying file is deleted/re-created but the session continues.
  void resetDownloadState() {
    activeDownloadOffset = null;
    activePriority = 0;
    lastDownloadProgress = 0;
    waitingForOffset = null;

    // Also reset timing for download flow
    downloadStartTime = null;
    lastOffsetChangeTime = null;
    lastDownloadFileCallTime = null;

    // We assume the new file might need new MOOV detection
    // but keep isMoovAtEnd flag if we already knew it to avoid re-work?
    // Safer to reset if the file was fully deleted.
    // earlyMoovDetectionTriggered = false; // Keep this true to avoid spamming?

    // Prefetch
    prefetchActive = false;
    lastPrefetchEvalTime = null;
  }

  /// Check if this file is within the initialization grace period.
  bool isWithinGracePeriod(Duration gracePeriod) {
    if (openTime == null) return false;
    return DateTime.now().difference(openTime!) < gracePeriod;
  }

  /// Check if a download was started recently (for stall cooldown).
  bool isRecentDownload(Duration cooldown) {
    if (downloadStartTime == null) return false;
    return DateTime.now().difference(downloadStartTime!) < cooldown;
  }

  /// Check if a recent seek happened (for adaptive buffer).
  bool isRecentSeek(Duration window) {
    if (lastSeekTime == null) return false;
    return DateTime.now().difference(lastSeekTime!) < window;
  }

  @override
  String toString() {
    return 'ProxyFileState($fileId, loadState: $loadState, '
        'activeOffset: $activeDownloadOffset, priority: $activePriority)';
  }
}
