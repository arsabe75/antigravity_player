// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'player_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlayerState {

 bool get isPlaying; bool get isBuffering; Duration get position; Duration get duration; double get volume; double get playbackSpeed; bool get isFullscreen; bool get areControlsVisible; bool get isAlwaysOnTop; Map<int, String> get audioTracks; Map<int, String> get subtitleTracks; int? get currentAudioTrack; int? get currentSubtitleTrack; String? get currentVideoPath; String? get error; String get playerBackend;
/// Create a copy of PlayerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerStateCopyWith<PlayerState> get copyWith => _$PlayerStateCopyWithImpl<PlayerState>(this as PlayerState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerState&&(identical(other.isPlaying, isPlaying) || other.isPlaying == isPlaying)&&(identical(other.isBuffering, isBuffering) || other.isBuffering == isBuffering)&&(identical(other.position, position) || other.position == position)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.volume, volume) || other.volume == volume)&&(identical(other.playbackSpeed, playbackSpeed) || other.playbackSpeed == playbackSpeed)&&(identical(other.isFullscreen, isFullscreen) || other.isFullscreen == isFullscreen)&&(identical(other.areControlsVisible, areControlsVisible) || other.areControlsVisible == areControlsVisible)&&(identical(other.isAlwaysOnTop, isAlwaysOnTop) || other.isAlwaysOnTop == isAlwaysOnTop)&&const DeepCollectionEquality().equals(other.audioTracks, audioTracks)&&const DeepCollectionEquality().equals(other.subtitleTracks, subtitleTracks)&&(identical(other.currentAudioTrack, currentAudioTrack) || other.currentAudioTrack == currentAudioTrack)&&(identical(other.currentSubtitleTrack, currentSubtitleTrack) || other.currentSubtitleTrack == currentSubtitleTrack)&&(identical(other.currentVideoPath, currentVideoPath) || other.currentVideoPath == currentVideoPath)&&(identical(other.error, error) || other.error == error)&&(identical(other.playerBackend, playerBackend) || other.playerBackend == playerBackend));
}


@override
int get hashCode => Object.hash(runtimeType,isPlaying,isBuffering,position,duration,volume,playbackSpeed,isFullscreen,areControlsVisible,isAlwaysOnTop,const DeepCollectionEquality().hash(audioTracks),const DeepCollectionEquality().hash(subtitleTracks),currentAudioTrack,currentSubtitleTrack,currentVideoPath,error,playerBackend);

@override
String toString() {
  return 'PlayerState(isPlaying: $isPlaying, isBuffering: $isBuffering, position: $position, duration: $duration, volume: $volume, playbackSpeed: $playbackSpeed, isFullscreen: $isFullscreen, areControlsVisible: $areControlsVisible, isAlwaysOnTop: $isAlwaysOnTop, audioTracks: $audioTracks, subtitleTracks: $subtitleTracks, currentAudioTrack: $currentAudioTrack, currentSubtitleTrack: $currentSubtitleTrack, currentVideoPath: $currentVideoPath, error: $error, playerBackend: $playerBackend)';
}


}

/// @nodoc
abstract mixin class $PlayerStateCopyWith<$Res>  {
  factory $PlayerStateCopyWith(PlayerState value, $Res Function(PlayerState) _then) = _$PlayerStateCopyWithImpl;
@useResult
$Res call({
 bool isPlaying, bool isBuffering, Duration position, Duration duration, double volume, double playbackSpeed, bool isFullscreen, bool areControlsVisible, bool isAlwaysOnTop, Map<int, String> audioTracks, Map<int, String> subtitleTracks, int? currentAudioTrack, int? currentSubtitleTrack, String? currentVideoPath, String? error, String playerBackend
});




}
/// @nodoc
class _$PlayerStateCopyWithImpl<$Res>
    implements $PlayerStateCopyWith<$Res> {
  _$PlayerStateCopyWithImpl(this._self, this._then);

  final PlayerState _self;
  final $Res Function(PlayerState) _then;

/// Create a copy of PlayerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? isPlaying = null,Object? isBuffering = null,Object? position = null,Object? duration = null,Object? volume = null,Object? playbackSpeed = null,Object? isFullscreen = null,Object? areControlsVisible = null,Object? isAlwaysOnTop = null,Object? audioTracks = null,Object? subtitleTracks = null,Object? currentAudioTrack = freezed,Object? currentSubtitleTrack = freezed,Object? currentVideoPath = freezed,Object? error = freezed,Object? playerBackend = null,}) {
  return _then(_self.copyWith(
isPlaying: null == isPlaying ? _self.isPlaying : isPlaying // ignore: cast_nullable_to_non_nullable
as bool,isBuffering: null == isBuffering ? _self.isBuffering : isBuffering // ignore: cast_nullable_to_non_nullable
as bool,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as Duration,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,playbackSpeed: null == playbackSpeed ? _self.playbackSpeed : playbackSpeed // ignore: cast_nullable_to_non_nullable
as double,isFullscreen: null == isFullscreen ? _self.isFullscreen : isFullscreen // ignore: cast_nullable_to_non_nullable
as bool,areControlsVisible: null == areControlsVisible ? _self.areControlsVisible : areControlsVisible // ignore: cast_nullable_to_non_nullable
as bool,isAlwaysOnTop: null == isAlwaysOnTop ? _self.isAlwaysOnTop : isAlwaysOnTop // ignore: cast_nullable_to_non_nullable
as bool,audioTracks: null == audioTracks ? _self.audioTracks : audioTracks // ignore: cast_nullable_to_non_nullable
as Map<int, String>,subtitleTracks: null == subtitleTracks ? _self.subtitleTracks : subtitleTracks // ignore: cast_nullable_to_non_nullable
as Map<int, String>,currentAudioTrack: freezed == currentAudioTrack ? _self.currentAudioTrack : currentAudioTrack // ignore: cast_nullable_to_non_nullable
as int?,currentSubtitleTrack: freezed == currentSubtitleTrack ? _self.currentSubtitleTrack : currentSubtitleTrack // ignore: cast_nullable_to_non_nullable
as int?,currentVideoPath: freezed == currentVideoPath ? _self.currentVideoPath : currentVideoPath // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,playerBackend: null == playerBackend ? _self.playerBackend : playerBackend // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PlayerState].
extension PlayerStatePatterns on PlayerState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlayerState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlayerState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlayerState value)  $default,){
final _that = this;
switch (_that) {
case _PlayerState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlayerState value)?  $default,){
final _that = this;
switch (_that) {
case _PlayerState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool isPlaying,  bool isBuffering,  Duration position,  Duration duration,  double volume,  double playbackSpeed,  bool isFullscreen,  bool areControlsVisible,  bool isAlwaysOnTop,  Map<int, String> audioTracks,  Map<int, String> subtitleTracks,  int? currentAudioTrack,  int? currentSubtitleTrack,  String? currentVideoPath,  String? error,  String playerBackend)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlayerState() when $default != null:
return $default(_that.isPlaying,_that.isBuffering,_that.position,_that.duration,_that.volume,_that.playbackSpeed,_that.isFullscreen,_that.areControlsVisible,_that.isAlwaysOnTop,_that.audioTracks,_that.subtitleTracks,_that.currentAudioTrack,_that.currentSubtitleTrack,_that.currentVideoPath,_that.error,_that.playerBackend);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool isPlaying,  bool isBuffering,  Duration position,  Duration duration,  double volume,  double playbackSpeed,  bool isFullscreen,  bool areControlsVisible,  bool isAlwaysOnTop,  Map<int, String> audioTracks,  Map<int, String> subtitleTracks,  int? currentAudioTrack,  int? currentSubtitleTrack,  String? currentVideoPath,  String? error,  String playerBackend)  $default,) {final _that = this;
switch (_that) {
case _PlayerState():
return $default(_that.isPlaying,_that.isBuffering,_that.position,_that.duration,_that.volume,_that.playbackSpeed,_that.isFullscreen,_that.areControlsVisible,_that.isAlwaysOnTop,_that.audioTracks,_that.subtitleTracks,_that.currentAudioTrack,_that.currentSubtitleTrack,_that.currentVideoPath,_that.error,_that.playerBackend);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool isPlaying,  bool isBuffering,  Duration position,  Duration duration,  double volume,  double playbackSpeed,  bool isFullscreen,  bool areControlsVisible,  bool isAlwaysOnTop,  Map<int, String> audioTracks,  Map<int, String> subtitleTracks,  int? currentAudioTrack,  int? currentSubtitleTrack,  String? currentVideoPath,  String? error,  String playerBackend)?  $default,) {final _that = this;
switch (_that) {
case _PlayerState() when $default != null:
return $default(_that.isPlaying,_that.isBuffering,_that.position,_that.duration,_that.volume,_that.playbackSpeed,_that.isFullscreen,_that.areControlsVisible,_that.isAlwaysOnTop,_that.audioTracks,_that.subtitleTracks,_that.currentAudioTrack,_that.currentSubtitleTrack,_that.currentVideoPath,_that.error,_that.playerBackend);case _:
  return null;

}
}

}

/// @nodoc


class _PlayerState implements PlayerState {
  const _PlayerState({this.isPlaying = false, this.isBuffering = false, this.position = Duration.zero, this.duration = Duration.zero, this.volume = 1.0, this.playbackSpeed = 1.0, this.isFullscreen = false, this.areControlsVisible = true, this.isAlwaysOnTop = false, final  Map<int, String> audioTracks = const {}, final  Map<int, String> subtitleTracks = const {}, this.currentAudioTrack, this.currentSubtitleTrack, this.currentVideoPath, this.error, this.playerBackend = 'media_kit'}): _audioTracks = audioTracks,_subtitleTracks = subtitleTracks;
  

@override@JsonKey() final  bool isPlaying;
@override@JsonKey() final  bool isBuffering;
@override@JsonKey() final  Duration position;
@override@JsonKey() final  Duration duration;
@override@JsonKey() final  double volume;
@override@JsonKey() final  double playbackSpeed;
@override@JsonKey() final  bool isFullscreen;
@override@JsonKey() final  bool areControlsVisible;
@override@JsonKey() final  bool isAlwaysOnTop;
 final  Map<int, String> _audioTracks;
@override@JsonKey() Map<int, String> get audioTracks {
  if (_audioTracks is EqualUnmodifiableMapView) return _audioTracks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_audioTracks);
}

 final  Map<int, String> _subtitleTracks;
@override@JsonKey() Map<int, String> get subtitleTracks {
  if (_subtitleTracks is EqualUnmodifiableMapView) return _subtitleTracks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_subtitleTracks);
}

@override final  int? currentAudioTrack;
@override final  int? currentSubtitleTrack;
@override final  String? currentVideoPath;
@override final  String? error;
@override@JsonKey() final  String playerBackend;

/// Create a copy of PlayerState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlayerStateCopyWith<_PlayerState> get copyWith => __$PlayerStateCopyWithImpl<_PlayerState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlayerState&&(identical(other.isPlaying, isPlaying) || other.isPlaying == isPlaying)&&(identical(other.isBuffering, isBuffering) || other.isBuffering == isBuffering)&&(identical(other.position, position) || other.position == position)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.volume, volume) || other.volume == volume)&&(identical(other.playbackSpeed, playbackSpeed) || other.playbackSpeed == playbackSpeed)&&(identical(other.isFullscreen, isFullscreen) || other.isFullscreen == isFullscreen)&&(identical(other.areControlsVisible, areControlsVisible) || other.areControlsVisible == areControlsVisible)&&(identical(other.isAlwaysOnTop, isAlwaysOnTop) || other.isAlwaysOnTop == isAlwaysOnTop)&&const DeepCollectionEquality().equals(other._audioTracks, _audioTracks)&&const DeepCollectionEquality().equals(other._subtitleTracks, _subtitleTracks)&&(identical(other.currentAudioTrack, currentAudioTrack) || other.currentAudioTrack == currentAudioTrack)&&(identical(other.currentSubtitleTrack, currentSubtitleTrack) || other.currentSubtitleTrack == currentSubtitleTrack)&&(identical(other.currentVideoPath, currentVideoPath) || other.currentVideoPath == currentVideoPath)&&(identical(other.error, error) || other.error == error)&&(identical(other.playerBackend, playerBackend) || other.playerBackend == playerBackend));
}


@override
int get hashCode => Object.hash(runtimeType,isPlaying,isBuffering,position,duration,volume,playbackSpeed,isFullscreen,areControlsVisible,isAlwaysOnTop,const DeepCollectionEquality().hash(_audioTracks),const DeepCollectionEquality().hash(_subtitleTracks),currentAudioTrack,currentSubtitleTrack,currentVideoPath,error,playerBackend);

@override
String toString() {
  return 'PlayerState(isPlaying: $isPlaying, isBuffering: $isBuffering, position: $position, duration: $duration, volume: $volume, playbackSpeed: $playbackSpeed, isFullscreen: $isFullscreen, areControlsVisible: $areControlsVisible, isAlwaysOnTop: $isAlwaysOnTop, audioTracks: $audioTracks, subtitleTracks: $subtitleTracks, currentAudioTrack: $currentAudioTrack, currentSubtitleTrack: $currentSubtitleTrack, currentVideoPath: $currentVideoPath, error: $error, playerBackend: $playerBackend)';
}


}

/// @nodoc
abstract mixin class _$PlayerStateCopyWith<$Res> implements $PlayerStateCopyWith<$Res> {
  factory _$PlayerStateCopyWith(_PlayerState value, $Res Function(_PlayerState) _then) = __$PlayerStateCopyWithImpl;
@override @useResult
$Res call({
 bool isPlaying, bool isBuffering, Duration position, Duration duration, double volume, double playbackSpeed, bool isFullscreen, bool areControlsVisible, bool isAlwaysOnTop, Map<int, String> audioTracks, Map<int, String> subtitleTracks, int? currentAudioTrack, int? currentSubtitleTrack, String? currentVideoPath, String? error, String playerBackend
});




}
/// @nodoc
class __$PlayerStateCopyWithImpl<$Res>
    implements _$PlayerStateCopyWith<$Res> {
  __$PlayerStateCopyWithImpl(this._self, this._then);

  final _PlayerState _self;
  final $Res Function(_PlayerState) _then;

/// Create a copy of PlayerState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? isPlaying = null,Object? isBuffering = null,Object? position = null,Object? duration = null,Object? volume = null,Object? playbackSpeed = null,Object? isFullscreen = null,Object? areControlsVisible = null,Object? isAlwaysOnTop = null,Object? audioTracks = null,Object? subtitleTracks = null,Object? currentAudioTrack = freezed,Object? currentSubtitleTrack = freezed,Object? currentVideoPath = freezed,Object? error = freezed,Object? playerBackend = null,}) {
  return _then(_PlayerState(
isPlaying: null == isPlaying ? _self.isPlaying : isPlaying // ignore: cast_nullable_to_non_nullable
as bool,isBuffering: null == isBuffering ? _self.isBuffering : isBuffering // ignore: cast_nullable_to_non_nullable
as bool,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as Duration,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,playbackSpeed: null == playbackSpeed ? _self.playbackSpeed : playbackSpeed // ignore: cast_nullable_to_non_nullable
as double,isFullscreen: null == isFullscreen ? _self.isFullscreen : isFullscreen // ignore: cast_nullable_to_non_nullable
as bool,areControlsVisible: null == areControlsVisible ? _self.areControlsVisible : areControlsVisible // ignore: cast_nullable_to_non_nullable
as bool,isAlwaysOnTop: null == isAlwaysOnTop ? _self.isAlwaysOnTop : isAlwaysOnTop // ignore: cast_nullable_to_non_nullable
as bool,audioTracks: null == audioTracks ? _self._audioTracks : audioTracks // ignore: cast_nullable_to_non_nullable
as Map<int, String>,subtitleTracks: null == subtitleTracks ? _self._subtitleTracks : subtitleTracks // ignore: cast_nullable_to_non_nullable
as Map<int, String>,currentAudioTrack: freezed == currentAudioTrack ? _self.currentAudioTrack : currentAudioTrack // ignore: cast_nullable_to_non_nullable
as int?,currentSubtitleTrack: freezed == currentSubtitleTrack ? _self.currentSubtitleTrack : currentSubtitleTrack // ignore: cast_nullable_to_non_nullable
as int?,currentVideoPath: freezed == currentVideoPath ? _self.currentVideoPath : currentVideoPath // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,playerBackend: null == playerBackend ? _self.playerBackend : playerBackend // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
