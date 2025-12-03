import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/video_entity.dart';
import '../../domain/repositories/video_repository.dart';
import '../../infrastructure/repositories/video_repository_impl.dart';
import 'player_state.dart';

// Repository Provider
final videoRepositoryProvider = Provider.autoDispose<VideoRepository>((ref) {
  final repo = VideoRepositoryImpl();
  ref.onDispose(() => repo.dispose());
  return repo;
});

// Player Notifier
class PlayerNotifier extends Notifier<PlayerState> {
  late final VideoRepository _repository;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferingSub;

  @override
  PlayerState build() {
    _repository = ref.watch(videoRepositoryProvider);
    _initStreams();

    ref.onDispose(() {
      _positionSub?.cancel();
      _durationSub?.cancel();
      _playingSub?.cancel();
      _bufferingSub?.cancel();
    });

    return const PlayerState();
  }

  void _initStreams() {
    _positionSub = _repository.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
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
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await _repository.pause();
    } else {
      await _repository.resume();
    }
  }

  Future<void> seekTo(Duration position) async {
    await _repository.seekTo(position);
    state = state.copyWith(position: position);
  }

  Future<void> setVolume(double volume) async {
    await _repository.setVolume(volume);
    state = state.copyWith(volume: volume);
  }

  void toggleFullscreen() {
    state = state.copyWith(isFullscreen: !state.isFullscreen);
  }

  void setControlsVisibility(bool visible) {
    state = state.copyWith(areControlsVisible: visible);
  }
}

final playerProvider =
    NotifierProvider.autoDispose<PlayerNotifier, PlayerState>(
      PlayerNotifier.new,
    );
