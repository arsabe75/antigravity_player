// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'telegram_content_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TelegramContentState {

 List<Map<String, dynamic>> get chats; bool get isLoading; String? get error;
/// Create a copy of TelegramContentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TelegramContentStateCopyWith<TelegramContentState> get copyWith => _$TelegramContentStateCopyWithImpl<TelegramContentState>(this as TelegramContentState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TelegramContentState&&const DeepCollectionEquality().equals(other.chats, chats)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(chats),isLoading,error);

@override
String toString() {
  return 'TelegramContentState(chats: $chats, isLoading: $isLoading, error: $error)';
}


}

/// @nodoc
abstract mixin class $TelegramContentStateCopyWith<$Res>  {
  factory $TelegramContentStateCopyWith(TelegramContentState value, $Res Function(TelegramContentState) _then) = _$TelegramContentStateCopyWithImpl;
@useResult
$Res call({
 List<Map<String, dynamic>> chats, bool isLoading, String? error
});




}
/// @nodoc
class _$TelegramContentStateCopyWithImpl<$Res>
    implements $TelegramContentStateCopyWith<$Res> {
  _$TelegramContentStateCopyWithImpl(this._self, this._then);

  final TelegramContentState _self;
  final $Res Function(TelegramContentState) _then;

/// Create a copy of TelegramContentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? chats = null,Object? isLoading = null,Object? error = freezed,}) {
  return _then(_self.copyWith(
chats: null == chats ? _self.chats : chats // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [TelegramContentState].
extension TelegramContentStatePatterns on TelegramContentState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TelegramContentState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TelegramContentState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TelegramContentState value)  $default,){
final _that = this;
switch (_that) {
case _TelegramContentState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TelegramContentState value)?  $default,){
final _that = this;
switch (_that) {
case _TelegramContentState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Map<String, dynamic>> chats,  bool isLoading,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TelegramContentState() when $default != null:
return $default(_that.chats,_that.isLoading,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Map<String, dynamic>> chats,  bool isLoading,  String? error)  $default,) {final _that = this;
switch (_that) {
case _TelegramContentState():
return $default(_that.chats,_that.isLoading,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Map<String, dynamic>> chats,  bool isLoading,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _TelegramContentState() when $default != null:
return $default(_that.chats,_that.isLoading,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _TelegramContentState implements TelegramContentState {
  const _TelegramContentState({final  List<Map<String, dynamic>> chats = const [], this.isLoading = false, this.error}): _chats = chats;
  

 final  List<Map<String, dynamic>> _chats;
@override@JsonKey() List<Map<String, dynamic>> get chats {
  if (_chats is EqualUnmodifiableListView) return _chats;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_chats);
}

@override@JsonKey() final  bool isLoading;
@override final  String? error;

/// Create a copy of TelegramContentState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TelegramContentStateCopyWith<_TelegramContentState> get copyWith => __$TelegramContentStateCopyWithImpl<_TelegramContentState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TelegramContentState&&const DeepCollectionEquality().equals(other._chats, _chats)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_chats),isLoading,error);

@override
String toString() {
  return 'TelegramContentState(chats: $chats, isLoading: $isLoading, error: $error)';
}


}

/// @nodoc
abstract mixin class _$TelegramContentStateCopyWith<$Res> implements $TelegramContentStateCopyWith<$Res> {
  factory _$TelegramContentStateCopyWith(_TelegramContentState value, $Res Function(_TelegramContentState) _then) = __$TelegramContentStateCopyWithImpl;
@override @useResult
$Res call({
 List<Map<String, dynamic>> chats, bool isLoading, String? error
});




}
/// @nodoc
class __$TelegramContentStateCopyWithImpl<$Res>
    implements _$TelegramContentStateCopyWith<$Res> {
  __$TelegramContentStateCopyWithImpl(this._self, this._then);

  final _TelegramContentState _self;
  final $Res Function(_TelegramContentState) _then;

/// Create a copy of TelegramContentState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? chats = null,Object? isLoading = null,Object? error = freezed,}) {
  return _then(_TelegramContentState(
chats: null == chats ? _self._chats : chats // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
