import 'dart:async';
import 'dart:io';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:window_manager/window_manager.dart';
import '../../domain/entities/video_entity.dart';
import '../../domain/repositories/video_repository.dart';
import '../../infrastructure/repositories/video_repository_impl.dart';
import '../../infrastructure/services/playback_storage_service.dart';
import '../../infrastructure/services/recent_videos_service.dart';
import 'player_state.dart';

part 'player_notifier.g.dart';

// Repository Provider
// Riverpod 3: Esta es una función "provider" generada.
// La anotación @riverpod le dice al generador que cree un provider (AutoDisposeProvider por defecto).
// 'Ref' es el objeto que nos permite interactuar con otros providers y el ciclo de vida.
@riverpod
VideoRepository videoRepository(Ref ref) {
  final repo = VideoRepositoryImpl();
  // ref.onDispose registra una función que se ejecuta cuando el provider es destruido.
  // Es crucial para limpiar recursos (streams, controladores, etc.).
  ref.onDispose(() => repo.dispose());
  return repo;
}

@riverpod
PlaybackStorageService playbackStorageService(Ref ref) {
  return PlaybackStorageService();
}

// Player Notifier
// Riverpod 3: @riverpod sobre una clase genera un NotifierProvider (o AsyncNotifierProvider si build devuelve Future).
// La clase debe extender de _$NombreDeLaClase (generated mixin).
@riverpod
class PlayerNotifier extends _$PlayerNotifier {
  late final VideoRepository _repository;
  late final PlaybackStorageService _storageService;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferingSub;
  Timer? _saveTimer;

  @override
  PlayerState build() {
    // Riverpod 3: El método build() reemplaza al constructor.
    // Aquí inicializamos el estado y las dependencias.
    // ref.watch lee el valor de otro provider y escucha sus cambios.
    // Si videoRepositoryProvider cambia, este provider se reconstruirá.
    _repository = ref.watch(videoRepositoryProvider);
    _storageService = ref.watch(playbackStorageServiceProvider);
    _initStreams();

    // Registramos la limpieza de recursos.
    // En Riverpod 3, esto reemplaza al método dispose() de los StateNotifier.
    ref.onDispose(() {
      _positionSub?.cancel();
      _durationSub?.cancel();
      _playingSub?.cancel();
      _playingSub?.cancel();
      _bufferingSub?.cancel();
      _saveTimer?.cancel();
      _savePosition();
    });

    // Retornamos el estado inicial.
    return const PlayerState();
  }

  void _initStreams() {
    _positionSub = _repository.positionStream.listen((pos) {
      // Riverpod 3: 'state' es la propiedad que mantiene el estado actual.
      // Es inmutable (en este caso), por lo que usamos copyWith para actualizarlo.
      // Al asignar un nuevo valor a 'state', se notifica a los listeners.
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

      if (!isNetwork) {
        final file = File(path);
        if (!await file.exists()) {
          throw const FileSystemException('File not found');
        }
      }

      final video = VideoEntity(path: path, isNetwork: isNetwork);
      await _repository.play(video);

      // Give player a moment to load tracks
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadTracks();

      // Save to recent videos history
      final recentVideosService = RecentVideosService();
      await recentVideosService.addVideo(path, isNetwork: isNetwork);

      final savedPositionMs = await _storageService.getPosition(path);
      if (savedPositionMs != null && savedPositionMs > 0) {
        final position = Duration(milliseconds: savedPositionMs);
        // Wait a bit to ensure player is ready to seek
        await Future.delayed(const Duration(milliseconds: 500));
        await seekTo(position);
      }

      _startSaveTimer();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await _repository.pause();
      await _savePosition();
      _saveTimer?.cancel();
    } else {
      await _repository.resume();
      _startSaveTimer();
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

  Future<void> toggleAlwaysOnTop() async {
    final newState = !state.isAlwaysOnTop;
    await windowManager.setAlwaysOnTop(newState);
    state = state.copyWith(isAlwaysOnTop: newState);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _repository.setPlaybackSpeed(speed);
    state = state.copyWith(playbackSpeed: speed);
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

  Future<void> _loadTracks() async {
    final audioTracks = await _repository.getAudioTracks();
    final subtitleTracks = await _repository.getSubtitleTracks();
    state = state.copyWith(
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      // Reset current selection or set default if needed
      currentAudioTrack: 0,
      currentSubtitleTrack: 0,
    );
  }

  Future<void> setAudioTrack(int trackId) async {
    await _repository.setAudioTrack(trackId);
    state = state.copyWith(currentAudioTrack: trackId);
  }

  Future<void> setSubtitleTrack(int trackId) async {
    await _repository.setSubtitleTrack(trackId);
    state = state.copyWith(currentSubtitleTrack: trackId);
  }

  Future<void> stop() async {
    _saveTimer?.cancel();
    await _savePosition();
    // We manually dispose the repo here to ensure resources are freed before window close
    await _repository.dispose();
  }

  void _startSaveTimer() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (state.isPlaying) {
        _savePosition();
      }
    });
  }
}
