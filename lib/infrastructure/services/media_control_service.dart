import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_media_session/flutter_media_session.dart';

class MediaControlService {
  // Linux MPRIS
  DBusClient? _mprisClient;
  _MprisObject? _mprisObject;
  StreamSubscription<String>? _nameLostSub;
  int _mprisRetryCount = 0;
  static const _maxRetries = 5;
  static const _busName = 'org.mpris.MediaPlayer2.video_player_app';
  static const _desktopEntry = 'video_player_app';
  static const _identity = 'Video Player App';
  int _trackCounter = 0;
  String? _lastMetaTitle;

  // Windows SMTC
  StreamSubscription<MediaAction>? _smTcSubscription;

  // Callbacks
  void Function()? onPlay;
  void Function()? onPause;
  void Function()? onPlayPause;
  void Function()? onNext;
  void Function()? onPrevious;
  void Function(Duration)? onSeek;

  Future<void> init() async {
    if (Platform.isLinux) {
      await _initMpris();
    } else if (Platform.isWindows) {
      await _initSmTc();
    }
  }

  // ── Linux MPRIS ──────────────────────────────────────────────────────

  Future<void> _ensureDesktopEntry() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return;

      final xdgDataHome = Platform.environment['XDG_DATA_HOME'] ??
          '$home/.local/share';

      // Copy icon from bundle to user's XDG icons directory so KDE/GNOME
      // can find it via the Icon= key in the desktop entry.
      await _installRuntimeIcon(xdgDataHome);

      final appsDir = Directory('$xdgDataHome/applications');
      if (!await appsDir.exists()) {
        await appsDir.create(recursive: true);
      }

      final desktopFile = File('${appsDir.path}/$_desktopEntry.desktop');

      // Use the real executable path so KDE can launch the app even when
      // the bundle is not in PATH (e.g. manual copy to an arbitrary folder).
      final content = '''
[Desktop Entry]
Version=1.0
Name=Video Player App
Comment=Futuristic Video Player
Exec=${Platform.resolvedExecutable}
Icon=$_desktopEntry
Terminal=false
Type=Application
Categories=AudioVideo;Player;Video;
Keywords=video;movie;player;
StartupNotify=true
StartupWMClass=com.arsabe75.videoplayerapp.video_player_app
''';

      // Overwrite if missing or stale — catches bundle relocation and
      // upgrades from the old relative-path version.
      final current = await desktopFile.exists()
          ? await desktopFile.readAsString().catchError((_) => '')
          : null;
      if (current != content) {
        await desktopFile.writeAsString(content);
      }
    } catch (_) {
      // Non-critical — media keys may not route if this fails
    }
  }

  /// Copies the application icon from the release bundle (data/icons/...)
  /// into the user's XDG icons directory so the desktop entry Icon= key
  /// resolves. In dev builds the bundle icon may not exist; silently skipped.
  Future<void> _installRuntimeIcon(String xdgDataHome) async {
    try {
      final destDir = Directory(
        '$xdgDataHome/icons/hicolor/256x256/apps',
      );
      final destIcon = File('${destDir.path}/$_desktopEntry.png');
      if (await destIcon.exists()) return;

      // Icon is installed by CMake next to the binary at:
      //   $bundleRoot/data/icons/hicolor/256x256/apps/<name>.png
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final srcIcon = File(
        '$exeDir/data/icons/hicolor/256x256/apps/$_desktopEntry.png',
      );

      if (await srcIcon.exists()) {
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }
        await srcIcon.copy(destIcon.path);
      }
    } catch (_) {
      // Best-effort — icon is cosmetic, not having it doesn't break MPRIS
    }
  }

  Future<void> _initMpris() async {
    try {
      // Ensure the .desktop file is installed in the XDG applications
      // directory so KDE/GNOME can find it via the MPRIS DesktopEntry property
      // and route physical media keys to our window.
      await _ensureDesktopEntry();

      _mprisClient = DBusClient.session();

      final reply = await _mprisClient!.requestName(
        _busName,
        flags: {DBusRequestNameFlag.replaceExisting, DBusRequestNameFlag.doNotQueue},
      );

      if (reply != DBusRequestNameReply.primaryOwner) {
        await _mprisClient!.close();
        _mprisClient = null;
        return;
      }

      _mprisRetryCount = 0;

      _mprisObject = _MprisObject(
        DBusObjectPath('/org/mpris/MediaPlayer2'),
        _identity,
        _desktopEntry,
        () => onPlay?.call(),
        () => onPause?.call(),
        () => onPlayPause?.call(),
        () => onNext?.call(),
        () => onPrevious?.call(),
        (offset) => onSeek?.call(offset),
      );

      await _mprisClient!.registerObject(_mprisObject!);

      _nameLostSub = _mprisClient!.nameLost.listen((_) => _onNameLost());
    } catch (e) {
      // Ignore errors
    }
  }

  void _onNameLost() {
    _nameLostSub?.cancel();
    _nameLostSub = null;
    _mprisObject = null;
    _mprisClient?.close();
    _mprisClient = null;

    if (_mprisRetryCount < _maxRetries) {
      _mprisRetryCount++;
      final delay = Duration(seconds: 1 << (_mprisRetryCount - 1)); // 1, 2, 4, 8, 16 s
      Future.delayed(delay, _initMpris);
    }
  }

  void _updateMprisPlaybackState(
    bool isPlaying,
    Duration position,
    double speed,
  ) {
    if (_mprisObject == null) return;

    final newStatus = isPlaying
        ? _MprisPlaybackStatus.playing
        : _MprisPlaybackStatus.paused;

    final changed = <String, DBusValue>{};
    if (_mprisObject!.playbackStatus != newStatus) {
      _mprisObject!.playbackStatus = newStatus;
      changed['PlaybackStatus'] = DBusString(newStatus.value);
    }
    if (_mprisObject!.position != position) {
      final oldPos = _mprisObject!.position;
      _mprisObject!.position = position;

      // MPRIS spec: do NOT emit PropertiesChanged for Position.
      // Only emit Seeked if the jump is significant (>1s delta).
      if (oldPos != null &&
          (position - oldPos).inMicroseconds.abs() > 1000000) {
        _mprisObject!.emitSignal(
          'org.mpris.MediaPlayer2.Player',
          'Seeked',
          [DBusInt64(position.inMicroseconds)],
        );
      }
    }
    if (_mprisObject!.rate != speed) {
      _mprisObject!.rate = speed;
      changed['Rate'] = DBusDouble(speed);
    }

    if (changed.isNotEmpty) {
      _mprisObject!.emitPropertiesChanged(
        'org.mpris.MediaPlayer2.Player',
        changedProperties: changed,
      );
    }
  }

  void _updateMprisMetaData(
    String title,
    Duration duration,
    String? artist,
    String? thumbUrl,
  ) {
    if (_mprisObject == null) return;

    // Increment track counter when the title changes (new video loaded)
    if (title != _lastMetaTitle) {
      _lastMetaTitle = title;
      _trackCounter++;
    }

    final metadata = _buildMprisMetadata(title, duration, artist, thumbUrl);
    _mprisObject!.metadata = metadata;

    _mprisObject!.emitPropertiesChanged(
      'org.mpris.MediaPlayer2.Player',
      changedProperties: {'Metadata': DBusVariant(metadata)},
    );
  }

  DBusDict _buildMprisMetadata(
    String title,
    Duration duration,
    String? artist,
    String? thumbUrl,
  ) {
    final map = <String, DBusValue>{
      'mpris:trackid': DBusObjectPath('/org/mpris/MediaPlayer2/video_player_app/track/$_trackCounter'),
      'mpris:length': DBusInt64(duration.inMicroseconds),
      'xesam:title': DBusString(title),
    };
    if (artist != null && artist.isNotEmpty) {
      map['xesam:artist'] = DBusArray.string([artist]);
    }
    if (thumbUrl != null) {
      map['mpris:artUrl'] = DBusString(thumbUrl);
    }
    return DBusDict.stringVariant(map);
  }

  // ── Windows SMTC ─────────────────────────────────────────────────────

  Future<void> _initSmTc() async {
    try {
      final session = FlutterMediaSession();

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

  // ── Public API ───────────────────────────────────────────────────────

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

  void dispose() {
    _nameLostSub?.cancel();
    _nameLostSub = null;
    _mprisObject = null;
    _mprisClient?.close();
    _mprisClient = null;
    _smTcSubscription?.cancel();
    _smTcSubscription = null;
  }
}

// ── MPRIS PlaybackStatus enum ──────────────────────────────────────────

enum _MprisPlaybackStatus {
  playing('Playing'),
  paused('Paused'),
  stopped('Stopped');

  final String value;
  const _MprisPlaybackStatus(this.value);
}

// ── MPRIS D-Bus Object ─────────────────────────────────────────────────

typedef _MprisMethodCallback = void Function();
typedef _MprisSeekCallback = void Function(Duration offset);

class _MprisObject extends DBusObject {
  final String identity;
  final String desktopEntry;
  final _MprisMethodCallback onPlay;
  final _MprisMethodCallback onPause;
  final _MprisMethodCallback onPlayPause;
  final _MprisMethodCallback onNext;
  final _MprisMethodCallback onPrevious;
  final _MprisSeekCallback onSeek;

  _MprisPlaybackStatus playbackStatus = _MprisPlaybackStatus.stopped;
  Duration? position;
  double rate = 1.0;
  DBusDict metadata = DBusDict.stringVariant({});

  _MprisObject(
    super.path,
    this.identity,
    this.desktopEntry,
    this.onPlay,
    this.onPause,
    this.onPlayPause,
    this.onNext,
    this.onPrevious,
    this.onSeek,
  );

  // ── Introspection ──────────────────────────────────────────────────

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface('org.mpris.MediaPlayer2', methods: [
        DBusIntrospectMethod('Raise'),
        DBusIntrospectMethod('Quit'),
      ], properties: [
        DBusIntrospectProperty('CanQuit', DBusSignature('b'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanRaise', DBusSignature('b'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanSetFullscreen', DBusSignature('b'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('DesktopEntry', DBusSignature('s'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('HasTrackList', DBusSignature('b'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('Identity', DBusSignature('s'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('SupportedMimeTypes', DBusSignature('as'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('SupportedUriSchemes', DBusSignature('as'),
            access: DBusPropertyAccess.read),
      ]),
      DBusIntrospectInterface('org.mpris.MediaPlayer2.Player', methods: [
        DBusIntrospectMethod('Next'),
        DBusIntrospectMethod('Previous'),
        DBusIntrospectMethod('Pause'),
        DBusIntrospectMethod('PlayPause'),
        DBusIntrospectMethod('Stop'),
        DBusIntrospectMethod('Play'),
        DBusIntrospectMethod('Seek', args: [
          DBusIntrospectArgument(DBusSignature('x'),
              DBusArgumentDirection.in_, name: 'Offset'),
        ]),
        DBusIntrospectMethod('SetPosition', args: [
          DBusIntrospectArgument(DBusSignature('o'),
              DBusArgumentDirection.in_, name: 'TrackId'),
          DBusIntrospectArgument(DBusSignature('x'),
              DBusArgumentDirection.in_, name: 'Position'),
        ]),
      ], signals: [
        DBusIntrospectSignal('Seeked', args: [
          DBusIntrospectArgument(DBusSignature('x'),
              DBusArgumentDirection.out, name: 'Position'),
        ]),
      ], properties: [
        DBusIntrospectProperty('CanControl', DBusSignature('b'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanGoNext', DBusSignature('b'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanGoPrevious', DBusSignature('b'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanPause', DBusSignature('b'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanPlay', DBusSignature('b'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanSeek', DBusSignature('b'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('LoopStatus', DBusSignature('s'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('MaximumRate', DBusSignature('d'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('Metadata', DBusSignature('a{sv}'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('MinimumRate', DBusSignature('d'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('PlaybackStatus', DBusSignature('s'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('Position', DBusSignature('x'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('Rate', DBusSignature('d'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('Shuffle', DBusSignature('b'),
            access: DBusPropertyAccess.read),
        DBusIntrospectProperty('Volume', DBusSignature('d'),
            access: DBusPropertyAccess.read),
      ]),
    ];
  }

  // ── Method calls ───────────────────────────────────────────────────

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == 'org.mpris.MediaPlayer2') {
      return _handleMediaPlayer2Method(call);
    }
    if (call.interface == 'org.mpris.MediaPlayer2.Player') {
      return _handlePlayerMethod(call);
    }
    return DBusMethodErrorResponse.unknownInterface();
  }

  Future<DBusMethodResponse> _handleMediaPlayer2Method(
      DBusMethodCall call) async {
    switch (call.name) {
      case 'Raise':
      case 'Quit':
        return DBusMethodSuccessResponse([]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  Future<DBusMethodResponse> _handlePlayerMethod(DBusMethodCall call) async {
    switch (call.name) {
      case 'Play':
        onPlay();
        playbackStatus = _MprisPlaybackStatus.playing;
        emitPropertiesChanged('org.mpris.MediaPlayer2.Player',
            changedProperties: {
              'PlaybackStatus': DBusString(playbackStatus.value),
            });
        return DBusMethodSuccessResponse([]);
      case 'Pause':
        onPause();
        playbackStatus = _MprisPlaybackStatus.paused;
        emitPropertiesChanged('org.mpris.MediaPlayer2.Player',
            changedProperties: {
              'PlaybackStatus': DBusString(playbackStatus.value),
            });
        return DBusMethodSuccessResponse([]);
      case 'PlayPause':
        onPlayPause();
        return DBusMethodSuccessResponse([]);
      case 'Stop':
        onPause();
        playbackStatus = _MprisPlaybackStatus.stopped;
        emitPropertiesChanged('org.mpris.MediaPlayer2.Player',
            changedProperties: {
              'PlaybackStatus': DBusString(playbackStatus.value),
            });
        return DBusMethodSuccessResponse([]);
      case 'Next':
        onNext();
        return DBusMethodSuccessResponse([]);
      case 'Previous':
        onPrevious();
        return DBusMethodSuccessResponse([]);
      case 'Seek':
        if (call.signature != DBusSignature('x')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final offset = Duration(microseconds: (call.values[0] as DBusInt64).value);
        onSeek(offset);
        return DBusMethodSuccessResponse([]);
      case 'SetPosition':
        if (call.signature != DBusSignature('ox')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final targetPos =
            Duration(microseconds: (call.values[1] as DBusInt64).value);
        final currentPos = position ?? Duration.zero;
        onSeek(targetPos - currentPos);
        return DBusMethodSuccessResponse([]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  // ── Properties ─────────────────────────────────────────────────────

  @override
  Future<DBusMethodResponse> getProperty(
      String interface, String name) async {
    if (interface == 'org.mpris.MediaPlayer2') {
      return _getMediaPlayer2Property(name);
    }
    if (interface == 'org.mpris.MediaPlayer2.Player') {
      return _getPlayerProperty(name);
    }
    return DBusMethodErrorResponse.unknownInterface();
  }

  DBusMethodResponse _getMediaPlayer2Property(String name) {
    switch (name) {
      case 'CanQuit':
        return DBusGetPropertyResponse(DBusBoolean(false));
      case 'CanRaise':
        return DBusGetPropertyResponse(DBusBoolean(true));
      case 'CanSetFullscreen':
        return DBusGetPropertyResponse(DBusBoolean(false));
      case 'DesktopEntry':
        return DBusGetPropertyResponse(DBusString(desktopEntry));
      case 'HasTrackList':
        return DBusGetPropertyResponse(DBusBoolean(false));
      case 'Identity':
        return DBusGetPropertyResponse(DBusString(identity));
      case 'SupportedMimeTypes':
        return DBusGetPropertyResponse(DBusArray.string([]));
      case 'SupportedUriSchemes':
        return DBusGetPropertyResponse(DBusArray.string([]));
      default:
        return DBusMethodErrorResponse.unknownProperty();
    }
  }

  DBusMethodResponse _getPlayerProperty(String name) {
    switch (name) {
      case 'CanControl':
        return DBusGetPropertyResponse(DBusBoolean(true));
      case 'CanGoNext':
        return DBusGetPropertyResponse(DBusBoolean(true));
      case 'CanGoPrevious':
        return DBusGetPropertyResponse(DBusBoolean(true));
      case 'CanPause':
        return DBusGetPropertyResponse(DBusBoolean(true));
      case 'CanPlay':
        return DBusGetPropertyResponse(DBusBoolean(true));
      case 'CanSeek':
        return DBusGetPropertyResponse(DBusBoolean(true));
      case 'LoopStatus':
        return DBusGetPropertyResponse(DBusString('None'));
      case 'MaximumRate':
        return DBusGetPropertyResponse(DBusDouble(1.0));
      case 'Metadata':
        return DBusGetPropertyResponse(metadata);
      case 'MinimumRate':
        return DBusGetPropertyResponse(DBusDouble(1.0));
      case 'PlaybackStatus':
        return DBusGetPropertyResponse(DBusString(playbackStatus.value));
      case 'Position':
        return DBusGetPropertyResponse(
            DBusInt64(position?.inMicroseconds ?? 0));
      case 'Rate':
        return DBusGetPropertyResponse(DBusDouble(rate));
      case 'Shuffle':
        return DBusGetPropertyResponse(DBusBoolean(false));
      case 'Volume':
        return DBusGetPropertyResponse(DBusDouble(1.0));
      default:
        return DBusMethodErrorResponse.unknownProperty();
    }
  }

  @override
  Future<DBusMethodResponse> setProperty(
      String interface, String name, DBusValue value) async {
    // All our properties are read-only for now
    return DBusMethodErrorResponse.propertyReadOnly();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface == 'org.mpris.MediaPlayer2') {
      return DBusGetAllPropertiesResponse({
        'CanQuit': DBusBoolean(false),
        'CanRaise': DBusBoolean(true),
        'CanSetFullscreen': DBusBoolean(false),
        'DesktopEntry': DBusString(desktopEntry),
        'HasTrackList': DBusBoolean(false),
        'Identity': DBusString(identity),
        'SupportedMimeTypes': DBusArray.string([]),
        'SupportedUriSchemes': DBusArray.string([]),
      });
    }
    if (interface == 'org.mpris.MediaPlayer2.Player') {
      return DBusGetAllPropertiesResponse({
        'CanControl': DBusBoolean(true),
        'CanGoNext': DBusBoolean(true),
        'CanGoPrevious': DBusBoolean(true),
        'CanPause': DBusBoolean(true),
        'CanPlay': DBusBoolean(true),
        'CanSeek': DBusBoolean(true),
        'LoopStatus': DBusString('None'),
        'MaximumRate': DBusDouble(1.0),
        'Metadata': metadata,
        'MinimumRate': DBusDouble(1.0),
        'PlaybackStatus': DBusString(playbackStatus.value),
        'Position': DBusInt64(position?.inMicroseconds ?? 0),
        'Rate': DBusDouble(rate),
        'Shuffle': DBusBoolean(false),
        'Volume': DBusDouble(1.0),
      });
    }
    return DBusMethodErrorResponse.unknownInterface();
  }
}
