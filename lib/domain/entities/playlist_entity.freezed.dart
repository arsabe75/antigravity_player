// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'playlist_entity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlaylistItem {

 String get path; bool get isNetwork; String? get title; Duration? get duration;
/// Create a copy of PlaylistItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaylistItemCopyWith<PlaylistItem> get copyWith => _$PlaylistItemCopyWithImpl<PlaylistItem>(this as PlaylistItem, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaylistItem&&(identical(other.path, path) || other.path == path)&&(identical(other.isNetwork, isNetwork) || other.isNetwork == isNetwork)&&(identical(other.title, title) || other.title == title)&&(identical(other.duration, duration) || other.duration == duration));
}


@override
int get hashCode => Object.hash(runtimeType,path,isNetwork,title,duration);

@override
String toString() {
  return 'PlaylistItem(path: $path, isNetwork: $isNetwork, title: $title, duration: $duration)';
}


}

/// @nodoc
abstract mixin class $PlaylistItemCopyWith<$Res>  {
  factory $PlaylistItemCopyWith(PlaylistItem value, $Res Function(PlaylistItem) _then) = _$PlaylistItemCopyWithImpl;
@useResult
$Res call({
 String path, bool isNetwork, String? title, Duration? duration
});




}
/// @nodoc
class _$PlaylistItemCopyWithImpl<$Res>
    implements $PlaylistItemCopyWith<$Res> {
  _$PlaylistItemCopyWithImpl(this._self, this._then);

  final PlaylistItem _self;
  final $Res Function(PlaylistItem) _then;

/// Create a copy of PlaylistItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? isNetwork = null,Object? title = freezed,Object? duration = freezed,}) {
  return _then(_self.copyWith(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,isNetwork: null == isNetwork ? _self.isNetwork : isNetwork // ignore: cast_nullable_to_non_nullable
as bool,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration?,
  ));
}

}


/// Adds pattern-matching-related methods to [PlaylistItem].
extension PlaylistItemPatterns on PlaylistItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlaylistItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlaylistItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlaylistItem value)  $default,){
final _that = this;
switch (_that) {
case _PlaylistItem():
return $default(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlaylistItem value)?  $default,){
final _that = this;
switch (_that) {
case _PlaylistItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  bool isNetwork,  String? title,  Duration? duration)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlaylistItem() when $default != null:
return $default(_that.path,_that.isNetwork,_that.title,_that.duration);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  bool isNetwork,  String? title,  Duration? duration)  $default,) {final _that = this;
switch (_that) {
case _PlaylistItem():
return $default(_that.path,_that.isNetwork,_that.title,_that.duration);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  bool isNetwork,  String? title,  Duration? duration)?  $default,) {final _that = this;
switch (_that) {
case _PlaylistItem() when $default != null:
return $default(_that.path,_that.isNetwork,_that.title,_that.duration);case _:
  return null;

}
}

}

/// @nodoc


class _PlaylistItem implements PlaylistItem {
  const _PlaylistItem({required this.path, required this.isNetwork, this.title, this.duration});
  

@override final  String path;
@override final  bool isNetwork;
@override final  String? title;
@override final  Duration? duration;

/// Create a copy of PlaylistItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlaylistItemCopyWith<_PlaylistItem> get copyWith => __$PlaylistItemCopyWithImpl<_PlaylistItem>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlaylistItem&&(identical(other.path, path) || other.path == path)&&(identical(other.isNetwork, isNetwork) || other.isNetwork == isNetwork)&&(identical(other.title, title) || other.title == title)&&(identical(other.duration, duration) || other.duration == duration));
}


@override
int get hashCode => Object.hash(runtimeType,path,isNetwork,title,duration);

@override
String toString() {
  return 'PlaylistItem(path: $path, isNetwork: $isNetwork, title: $title, duration: $duration)';
}


}

/// @nodoc
abstract mixin class _$PlaylistItemCopyWith<$Res> implements $PlaylistItemCopyWith<$Res> {
  factory _$PlaylistItemCopyWith(_PlaylistItem value, $Res Function(_PlaylistItem) _then) = __$PlaylistItemCopyWithImpl;
@override @useResult
$Res call({
 String path, bool isNetwork, String? title, Duration? duration
});




}
/// @nodoc
class __$PlaylistItemCopyWithImpl<$Res>
    implements _$PlaylistItemCopyWith<$Res> {
  __$PlaylistItemCopyWithImpl(this._self, this._then);

  final _PlaylistItem _self;
  final $Res Function(_PlaylistItem) _then;

/// Create a copy of PlaylistItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? isNetwork = null,Object? title = freezed,Object? duration = freezed,}) {
  return _then(_PlaylistItem(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,isNetwork: null == isNetwork ? _self.isNetwork : isNetwork // ignore: cast_nullable_to_non_nullable
as bool,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration?,
  ));
}


}

/// @nodoc
mixin _$PlaylistEntity {

 List<PlaylistItem> get items; int get currentIndex; bool get shuffle; RepeatMode get repeatMode; String? get sourcePath; bool get startFromBeginning;
/// Create a copy of PlaylistEntity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaylistEntityCopyWith<PlaylistEntity> get copyWith => _$PlaylistEntityCopyWithImpl<PlaylistEntity>(this as PlaylistEntity, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaylistEntity&&const DeepCollectionEquality().equals(other.items, items)&&(identical(other.currentIndex, currentIndex) || other.currentIndex == currentIndex)&&(identical(other.shuffle, shuffle) || other.shuffle == shuffle)&&(identical(other.repeatMode, repeatMode) || other.repeatMode == repeatMode)&&(identical(other.sourcePath, sourcePath) || other.sourcePath == sourcePath)&&(identical(other.startFromBeginning, startFromBeginning) || other.startFromBeginning == startFromBeginning));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items),currentIndex,shuffle,repeatMode,sourcePath,startFromBeginning);

@override
String toString() {
  return 'PlaylistEntity(items: $items, currentIndex: $currentIndex, shuffle: $shuffle, repeatMode: $repeatMode, sourcePath: $sourcePath, startFromBeginning: $startFromBeginning)';
}


}

/// @nodoc
abstract mixin class $PlaylistEntityCopyWith<$Res>  {
  factory $PlaylistEntityCopyWith(PlaylistEntity value, $Res Function(PlaylistEntity) _then) = _$PlaylistEntityCopyWithImpl;
@useResult
$Res call({
 List<PlaylistItem> items, int currentIndex, bool shuffle, RepeatMode repeatMode, String? sourcePath, bool startFromBeginning
});




}
/// @nodoc
class _$PlaylistEntityCopyWithImpl<$Res>
    implements $PlaylistEntityCopyWith<$Res> {
  _$PlaylistEntityCopyWithImpl(this._self, this._then);

  final PlaylistEntity _self;
  final $Res Function(PlaylistEntity) _then;

/// Create a copy of PlaylistEntity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,Object? currentIndex = null,Object? shuffle = null,Object? repeatMode = null,Object? sourcePath = freezed,Object? startFromBeginning = null,}) {
  return _then(_self.copyWith(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<PlaylistItem>,currentIndex: null == currentIndex ? _self.currentIndex : currentIndex // ignore: cast_nullable_to_non_nullable
as int,shuffle: null == shuffle ? _self.shuffle : shuffle // ignore: cast_nullable_to_non_nullable
as bool,repeatMode: null == repeatMode ? _self.repeatMode : repeatMode // ignore: cast_nullable_to_non_nullable
as RepeatMode,sourcePath: freezed == sourcePath ? _self.sourcePath : sourcePath // ignore: cast_nullable_to_non_nullable
as String?,startFromBeginning: null == startFromBeginning ? _self.startFromBeginning : startFromBeginning // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [PlaylistEntity].
extension PlaylistEntityPatterns on PlaylistEntity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlaylistEntity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlaylistEntity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlaylistEntity value)  $default,){
final _that = this;
switch (_that) {
case _PlaylistEntity():
return $default(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlaylistEntity value)?  $default,){
final _that = this;
switch (_that) {
case _PlaylistEntity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<PlaylistItem> items,  int currentIndex,  bool shuffle,  RepeatMode repeatMode,  String? sourcePath,  bool startFromBeginning)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlaylistEntity() when $default != null:
return $default(_that.items,_that.currentIndex,_that.shuffle,_that.repeatMode,_that.sourcePath,_that.startFromBeginning);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<PlaylistItem> items,  int currentIndex,  bool shuffle,  RepeatMode repeatMode,  String? sourcePath,  bool startFromBeginning)  $default,) {final _that = this;
switch (_that) {
case _PlaylistEntity():
return $default(_that.items,_that.currentIndex,_that.shuffle,_that.repeatMode,_that.sourcePath,_that.startFromBeginning);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<PlaylistItem> items,  int currentIndex,  bool shuffle,  RepeatMode repeatMode,  String? sourcePath,  bool startFromBeginning)?  $default,) {final _that = this;
switch (_that) {
case _PlaylistEntity() when $default != null:
return $default(_that.items,_that.currentIndex,_that.shuffle,_that.repeatMode,_that.sourcePath,_that.startFromBeginning);case _:
  return null;

}
}

}

/// @nodoc


class _PlaylistEntity extends PlaylistEntity {
  const _PlaylistEntity({final  List<PlaylistItem> items = const [], this.currentIndex = 0, this.shuffle = false, this.repeatMode = RepeatMode.none, this.sourcePath, this.startFromBeginning = false}): _items = items,super._();
  

 final  List<PlaylistItem> _items;
@override@JsonKey() List<PlaylistItem> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override@JsonKey() final  int currentIndex;
@override@JsonKey() final  bool shuffle;
@override@JsonKey() final  RepeatMode repeatMode;
@override final  String? sourcePath;
@override@JsonKey() final  bool startFromBeginning;

/// Create a copy of PlaylistEntity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlaylistEntityCopyWith<_PlaylistEntity> get copyWith => __$PlaylistEntityCopyWithImpl<_PlaylistEntity>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlaylistEntity&&const DeepCollectionEquality().equals(other._items, _items)&&(identical(other.currentIndex, currentIndex) || other.currentIndex == currentIndex)&&(identical(other.shuffle, shuffle) || other.shuffle == shuffle)&&(identical(other.repeatMode, repeatMode) || other.repeatMode == repeatMode)&&(identical(other.sourcePath, sourcePath) || other.sourcePath == sourcePath)&&(identical(other.startFromBeginning, startFromBeginning) || other.startFromBeginning == startFromBeginning));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_items),currentIndex,shuffle,repeatMode,sourcePath,startFromBeginning);

@override
String toString() {
  return 'PlaylistEntity(items: $items, currentIndex: $currentIndex, shuffle: $shuffle, repeatMode: $repeatMode, sourcePath: $sourcePath, startFromBeginning: $startFromBeginning)';
}


}

/// @nodoc
abstract mixin class _$PlaylistEntityCopyWith<$Res> implements $PlaylistEntityCopyWith<$Res> {
  factory _$PlaylistEntityCopyWith(_PlaylistEntity value, $Res Function(_PlaylistEntity) _then) = __$PlaylistEntityCopyWithImpl;
@override @useResult
$Res call({
 List<PlaylistItem> items, int currentIndex, bool shuffle, RepeatMode repeatMode, String? sourcePath, bool startFromBeginning
});




}
/// @nodoc
class __$PlaylistEntityCopyWithImpl<$Res>
    implements _$PlaylistEntityCopyWith<$Res> {
  __$PlaylistEntityCopyWithImpl(this._self, this._then);

  final _PlaylistEntity _self;
  final $Res Function(_PlaylistEntity) _then;

/// Create a copy of PlaylistEntity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? items = null,Object? currentIndex = null,Object? shuffle = null,Object? repeatMode = null,Object? sourcePath = freezed,Object? startFromBeginning = null,}) {
  return _then(_PlaylistEntity(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<PlaylistItem>,currentIndex: null == currentIndex ? _self.currentIndex : currentIndex // ignore: cast_nullable_to_non_nullable
as int,shuffle: null == shuffle ? _self.shuffle : shuffle // ignore: cast_nullable_to_non_nullable
as bool,repeatMode: null == repeatMode ? _self.repeatMode : repeatMode // ignore: cast_nullable_to_non_nullable
as RepeatMode,sourcePath: freezed == sourcePath ? _self.sourcePath : sourcePath // ignore: cast_nullable_to_non_nullable
as String?,startFromBeginning: null == startFromBeginning ? _self.startFromBeginning : startFromBeginning // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
