import 'dart:io';

import 'package:mpris_service/mpris_service.dart';

class MediaControlService {
  MPRIS? _mpris;

  // Callbacks
  void Function()? onPlay;
  void Function()? onPause;
  void Function()? onPlayPause;
  void Function()? onNext;
  void Function()? onPrevious;
  void Function(Duration)? onSeek;

  // Pending state
  MPRISPlaybackStatus? _pendingStatus;
  Duration? _pendingPosition;
  double? _pendingRate;
  MPRISMetadata? _pendingMetadata;

  Future<void> init() async {
    if (!Platform.isLinux) return;

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

  void updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    required double speed,
  }) {
    final status = isPlaying
        ? MPRISPlaybackStatus.playing
        : MPRISPlaybackStatus.paused;

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

  void updateMetaData({
    required String title,
    required Duration duration,
    String? artist,
    String? thumbUrl,
  }) {
    final metadata = MPRISMetadata(
      // Track ID is required, can be dummy
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

  void dispose() {
    _mpris?.dispose();
    _mpris = null;
  }
}
