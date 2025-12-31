// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'telegram_auth_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TelegramAuthState {

 AuthState get list; String? get error; bool get isLoading;
/// Create a copy of TelegramAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TelegramAuthStateCopyWith<TelegramAuthState> get copyWith => _$TelegramAuthStateCopyWithImpl<TelegramAuthState>(this as TelegramAuthState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TelegramAuthState&&(identical(other.list, list) || other.list == list)&&(identical(other.error, error) || other.error == error)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading));
}


@override
int get hashCode => Object.hash(runtimeType,list,error,isLoading);

@override
String toString() {
  return 'TelegramAuthState(list: $list, error: $error, isLoading: $isLoading)';
}


}

/// @nodoc
abstract mixin class $TelegramAuthStateCopyWith<$Res>  {
  factory $TelegramAuthStateCopyWith(TelegramAuthState value, $Res Function(TelegramAuthState) _then) = _$TelegramAuthStateCopyWithImpl;
@useResult
$Res call({
 AuthState list, String? error, bool isLoading
});




}
/// @nodoc
class _$TelegramAuthStateCopyWithImpl<$Res>
    implements $TelegramAuthStateCopyWith<$Res> {
  _$TelegramAuthStateCopyWithImpl(this._self, this._then);

  final TelegramAuthState _self;
  final $Res Function(TelegramAuthState) _then;

/// Create a copy of TelegramAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? list = null,Object? error = freezed,Object? isLoading = null,}) {
  return _then(_self.copyWith(
list: null == list ? _self.list : list // ignore: cast_nullable_to_non_nullable
as AuthState,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [TelegramAuthState].
extension TelegramAuthStatePatterns on TelegramAuthState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TelegramAuthState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TelegramAuthState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TelegramAuthState value)  $default,){
final _that = this;
switch (_that) {
case _TelegramAuthState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TelegramAuthState value)?  $default,){
final _that = this;
switch (_that) {
case _TelegramAuthState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AuthState list,  String? error,  bool isLoading)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TelegramAuthState() when $default != null:
return $default(_that.list,_that.error,_that.isLoading);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AuthState list,  String? error,  bool isLoading)  $default,) {final _that = this;
switch (_that) {
case _TelegramAuthState():
return $default(_that.list,_that.error,_that.isLoading);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AuthState list,  String? error,  bool isLoading)?  $default,) {final _that = this;
switch (_that) {
case _TelegramAuthState() when $default != null:
return $default(_that.list,_that.error,_that.isLoading);case _:
  return null;

}
}

}

/// @nodoc


class _TelegramAuthState implements TelegramAuthState {
  const _TelegramAuthState({this.list = AuthState.initial, this.error, this.isLoading = false});
  

@override@JsonKey() final  AuthState list;
@override final  String? error;
@override@JsonKey() final  bool isLoading;

/// Create a copy of TelegramAuthState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TelegramAuthStateCopyWith<_TelegramAuthState> get copyWith => __$TelegramAuthStateCopyWithImpl<_TelegramAuthState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TelegramAuthState&&(identical(other.list, list) || other.list == list)&&(identical(other.error, error) || other.error == error)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading));
}


@override
int get hashCode => Object.hash(runtimeType,list,error,isLoading);

@override
String toString() {
  return 'TelegramAuthState(list: $list, error: $error, isLoading: $isLoading)';
}


}

/// @nodoc
abstract mixin class _$TelegramAuthStateCopyWith<$Res> implements $TelegramAuthStateCopyWith<$Res> {
  factory _$TelegramAuthStateCopyWith(_TelegramAuthState value, $Res Function(_TelegramAuthState) _then) = __$TelegramAuthStateCopyWithImpl;
@override @useResult
$Res call({
 AuthState list, String? error, bool isLoading
});




}
/// @nodoc
class __$TelegramAuthStateCopyWithImpl<$Res>
    implements _$TelegramAuthStateCopyWith<$Res> {
  __$TelegramAuthStateCopyWithImpl(this._self, this._then);

  final _TelegramAuthState _self;
  final $Res Function(_TelegramAuthState) _then;

/// Create a copy of TelegramAuthState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? list = null,Object? error = freezed,Object? isLoading = null,}) {
  return _then(_TelegramAuthState(
list: null == list ? _self.list : list // ignore: cast_nullable_to_non_nullable
as AuthState,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
