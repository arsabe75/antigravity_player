import 'dart:async';
import 'dart:io';

import 'package:flutter_media_session/flutter_media_session.dart';
import 'package:mpris_service/mpris_service.dart';

class MediaControlService {
  MPRIS? _mpris;
  StreamSubscription<MediaAction>? _smTcSubscription;

  // Callbacks
  void Function()? onPlay;
  void Function()? onPause;
  void Function()? onPlayPause;
  void Function()? onNext;
  void Function()? onPrevious;
  void Function(Duration)? onSeek;

  // Pending state (MPRIS)
  MPRISPlaybackStatus? _pendingStatus;
  Duration? _pendingPosition;
  double? _pendingRate;
  MPRISMetadata? _pendingMetadata;

  Future<void> init() async {
    if (Platform.isLinux) {
      await _initMpris();
    } else if (Platform.isWindows) {
      await _initSmTc();
    }
  }

  Future<void> _initMpris() async {
    try {
      _mpris = await MPRIS.create(
        busName: 'org.mpris.MediaPlayer2.antigravity_player',
        identity: 'Antigravity Player',
        desktopEntry: 'antigravity_player',
      );

      _mpris!.setEventHandler(
        MPRISEventHandler(
          play: () async => onPlay?.call(),
          pause: () async => onPause?.call(),
          playPause: () async => onPlayPause?.call(),
          next: () async => onNext?.call(),
          previous: () async => onPrevious?.call(),
          seek: (offset) async => onSeek?.call(offset),
        ),
      );

      // Apply pending state
      if (_pendingStatus != null) {
        _mpris!.playbackStatus = _pendingStatus!;
      }
      if (_pendingPosition != null) {
        _mpris!.position = _pendingPosition!;
      }
      if (_pendingRate != null) {
        _mpris!.rate = _pendingRate!;
      }
      if (_pendingMetadata != null) {
        _mpris!.metadata = _pendingMetadata!;
      }
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _initSmTc() async {
    try {
      final session = FlutterMediaSession();

      // Enable only transport buttons we support
      await session.updateAvailableActions({
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      });

      _smTcSubscription = session.onMediaAction.listen((action) {
        if (action == MediaAction.play) {
          onPlay?.call();
        } else if (action == MediaAction.pause) {
          onPause?.call();
        } else if (action == MediaAction.skipToNext) {
          onNext?.call();
        } else if (action == MediaAction.skipToPrevious) {
          onPrevious?.call();
        } else if (action == MediaAction.stop) {
          onPause?.call();
        }
      });

      await session.activate();
    } catch (e) {
      // Ignore errors
    }
  }

  void updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    required double speed,
  }) {
    if (Platform.isLinux) {
      _updateMprisPlaybackState(isPlaying, position, speed);
    } else if (Platform.isWindows) {
      _updateSmTcPlaybackState(isPlaying, position, speed);
    }
  }

  void _updateMprisPlaybackState(
    bool isPlaying,
    Duration position,
    double speed,
  ) {
    final status =
        isPlaying ? MPRISPlaybackStatus.playing : MPRISPlaybackStatus.paused;

    if (_mpris == null) {
      _pendingStatus = status;
      _pendingPosition = position;
      _pendingRate = speed;
      return;
    }

    _mpris!.playbackStatus = status;
    _mpris!.position = position;
    _mpris!.rate = speed;
  }

  void _updateSmTcPlaybackState(
    bool isPlaying,
    Duration position,
    double speed,
  ) {
    final session = FlutterMediaSession();
    final status = isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused;

    session.updatePlaybackState(PlaybackState(
      status: status,
      position: position,
      speed: speed,
    ));
  }

  void updateMetaData({
    required String title,
    required Duration duration,
    String? artist,
    String? thumbUrl,
  }) {
    if (Platform.isLinux) {
      _updateMprisMetaData(title, duration, artist, thumbUrl);
    } else if (Platform.isWindows) {
      _updateSmTcMetaData(title, duration, artist, thumbUrl);
    }
  }

  void _updateMprisMetaData(
    String title,
    Duration duration,
    String? artist,
    String? thumbUrl,
  ) {
    final metadata = MPRISMetadata(
      Uri.parse('app://antigravity/video'),
      title: title,
      artist: artist != null ? [artist] : [],
      artUrl: thumbUrl != null ? Uri.tryParse(thumbUrl) : null,
      length: duration,
    );

    if (_mpris == null) {
      _pendingMetadata = metadata;
      return;
    }

    _mpris!.metadata = metadata;
  }

  void _updateSmTcMetaData(
    String title,
    Duration duration,
    String? artist,
    String? thumbUrl,
  ) {
    final session = FlutterMediaSession();

    session.updateMetadata(MediaMetadata(
      title: title,
      artist: artist,
      artworkUri: thumbUrl,
      duration: duration,
    ));
  }

  void dispose() {
    _mpris?.dispose();
    _mpris = null;
    _smTcSubscription?.cancel();
    _smTcSubscription = null;
  }
}
