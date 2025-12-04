import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/video_entity.dart';
import '../../domain/repositories/video_repository.dart';
import '../../infrastructure/repositories/video_repository_impl.dart';
import '../../infrastructure/services/playback_storage_service.dart';
import 'player_state.dart';

// Repository Provider
final videoRepositoryProvider = Provider.autoDispose<VideoRepository>((ref) {
  final repo = VideoRepositoryImpl();
  ref.onDispose(() => repo.dispose());
  return repo;
});

final playbackStorageServiceProvider = Provider<PlaybackStorageService>((ref) {
  return PlaybackStorageService();
});

// Player Notifier
class PlayerNotifier extends Notifier<PlayerState> {
  late final VideoRepository _repository;
  late final PlaybackStorageService _storageService;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferingSub;

  @override
  PlayerState build() {
    _repository = ref.watch(videoRepositoryProvider);
    _storageService = ref.watch(playbackStorageServiceProvider);
    _initStreams();

    ref.onDispose(() {
      _positionSub?.cancel();
      _durationSub?.cancel();
      _playingSub?.cancel();
      _bufferingSub?.cancel();
      _savePosition();
    });

    return const PlayerState();
  }

  void _initStreams() {
    _positionSub = _repository.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
      if (pos.inSeconds % 5 == 0) {
        _savePosition();
      }
    });
    _durationSub = _repository.durationStream.listen((dur) {
      state = state.copyWith(duration: dur);
    });
    _playingSub = _repository.isPlayingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });
    _bufferingSub = _repository.isBufferingStream.listen((buffering) {
      state = state.copyWith(isBuffering: buffering);
    });
  }

  Future<void> loadVideo(String path, {bool isNetwork = false}) async {
    try {
      state = state.copyWith(
        currentVideoPath: path,
        error: null,
        position: Duration.zero,
        duration: Duration.zero,
        isPlaying: false,
      );
      final video = VideoEntity(path: path, isNetwork: isNetwork);
      await _repository.play(video);

      final savedPositionMs = await _storageService.getPosition(path);
      if (savedPositionMs != null && savedPositionMs > 0) {
        final position = Duration(milliseconds: savedPositionMs);
        await seekTo(position);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await _repository.pause();
      await _savePosition();
    } else {
      await _repository.resume();
    }
  }

  Future<void> seekTo(Duration position) async {
    // Optimistic update
    state = state.copyWith(position: position);
    await _savePosition();
    await _repository.seekTo(position);
  }

  double _lastVolume = 1.0;

  Future<void> setVolume(double volume) async {
    await _repository.setVolume(volume);
    state = state.copyWith(volume: volume);
  }

  Future<void> toggleMute() async {
    if (state.volume > 0) {
      _lastVolume = state.volume;
      await setVolume(0);
    } else {
      await setVolume(_lastVolume > 0 ? _lastVolume : 1.0);
    }
  }

  void toggleFullscreen() {
    state = state.copyWith(isFullscreen: !state.isFullscreen);
  }

  void setControlsVisibility(bool visible) {
    state = state.copyWith(areControlsVisible: visible);
  }

  Future<void> _savePosition() async {
    try {
      if (state.currentVideoPath != null) {
        await _storageService.savePosition(
          state.currentVideoPath!,
          state.position.inMilliseconds,
        );
      }
    } catch (e) {
      // Ignore errors during save, especially during dispose
    }
  }

  Future<void> stop() async {
    await _savePosition();
    // We manually dispose the repo here to ensure resources are freed before window close
    await _repository.dispose();
  }
}

final playerProvider =
    NotifierProvider.autoDispose<PlayerNotifier, PlayerState>(
      PlayerNotifier.new,
    );
