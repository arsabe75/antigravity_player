// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'telegram_chat_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TelegramChatState {

 List<Map<String, dynamic>> get messages; bool get isLoading; bool get isLoadingMore; bool get hasMore; String? get error;
/// Create a copy of TelegramChatState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TelegramChatStateCopyWith<TelegramChatState> get copyWith => _$TelegramChatStateCopyWithImpl<TelegramChatState>(this as TelegramChatState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TelegramChatState&&const DeepCollectionEquality().equals(other.messages, messages)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isLoadingMore, isLoadingMore) || other.isLoadingMore == isLoadingMore)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(messages),isLoading,isLoadingMore,hasMore,error);

@override
String toString() {
  return 'TelegramChatState(messages: $messages, isLoading: $isLoading, isLoadingMore: $isLoadingMore, hasMore: $hasMore, error: $error)';
}


}

/// @nodoc
abstract mixin class $TelegramChatStateCopyWith<$Res>  {
  factory $TelegramChatStateCopyWith(TelegramChatState value, $Res Function(TelegramChatState) _then) = _$TelegramChatStateCopyWithImpl;
@useResult
$Res call({
 List<Map<String, dynamic>> messages, bool isLoading, bool isLoadingMore, bool hasMore, String? error
});




}
/// @nodoc
class _$TelegramChatStateCopyWithImpl<$Res>
    implements $TelegramChatStateCopyWith<$Res> {
  _$TelegramChatStateCopyWithImpl(this._self, this._then);

  final TelegramChatState _self;
  final $Res Function(TelegramChatState) _then;

/// Create a copy of TelegramChatState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? messages = null,Object? isLoading = null,Object? isLoadingMore = null,Object? hasMore = null,Object? error = freezed,}) {
  return _then(_self.copyWith(
messages: null == messages ? _self.messages : messages // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isLoadingMore: null == isLoadingMore ? _self.isLoadingMore : isLoadingMore // ignore: cast_nullable_to_non_nullable
as bool,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [TelegramChatState].
extension TelegramChatStatePatterns on TelegramChatState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TelegramChatState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TelegramChatState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TelegramChatState value)  $default,){
final _that = this;
switch (_that) {
case _TelegramChatState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TelegramChatState value)?  $default,){
final _that = this;
switch (_that) {
case _TelegramChatState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Map<String, dynamic>> messages,  bool isLoading,  bool isLoadingMore,  bool hasMore,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TelegramChatState() when $default != null:
return $default(_that.messages,_that.isLoading,_that.isLoadingMore,_that.hasMore,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Map<String, dynamic>> messages,  bool isLoading,  bool isLoadingMore,  bool hasMore,  String? error)  $default,) {final _that = this;
switch (_that) {
case _TelegramChatState():
return $default(_that.messages,_that.isLoading,_that.isLoadingMore,_that.hasMore,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Map<String, dynamic>> messages,  bool isLoading,  bool isLoadingMore,  bool hasMore,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _TelegramChatState() when $default != null:
return $default(_that.messages,_that.isLoading,_that.isLoadingMore,_that.hasMore,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _TelegramChatState implements TelegramChatState {
  const _TelegramChatState({final  List<Map<String, dynamic>> messages = const [], this.isLoading = false, this.isLoadingMore = false, this.hasMore = true, this.error}): _messages = messages;
  

 final  List<Map<String, dynamic>> _messages;
@override@JsonKey() List<Map<String, dynamic>> get messages {
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_messages);
}

@override@JsonKey() final  bool isLoading;
@override@JsonKey() final  bool isLoadingMore;
@override@JsonKey() final  bool hasMore;
@override final  String? error;

/// Create a copy of TelegramChatState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TelegramChatStateCopyWith<_TelegramChatState> get copyWith => __$TelegramChatStateCopyWithImpl<_TelegramChatState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TelegramChatState&&const DeepCollectionEquality().equals(other._messages, _messages)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isLoadingMore, isLoadingMore) || other.isLoadingMore == isLoadingMore)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_messages),isLoading,isLoadingMore,hasMore,error);

@override
String toString() {
  return 'TelegramChatState(messages: $messages, isLoading: $isLoading, isLoadingMore: $isLoadingMore, hasMore: $hasMore, error: $error)';
}


}

/// @nodoc
abstract mixin class _$TelegramChatStateCopyWith<$Res> implements $TelegramChatStateCopyWith<$Res> {
  factory _$TelegramChatStateCopyWith(_TelegramChatState value, $Res Function(_TelegramChatState) _then) = __$TelegramChatStateCopyWithImpl;
@override @useResult
$Res call({
 List<Map<String, dynamic>> messages, bool isLoading, bool isLoadingMore, bool hasMore, String? error
});




}
/// @nodoc
class __$TelegramChatStateCopyWithImpl<$Res>
    implements _$TelegramChatStateCopyWith<$Res> {
  __$TelegramChatStateCopyWithImpl(this._self, this._then);

  final _TelegramChatState _self;
  final $Res Function(_TelegramChatState) _then;

/// Create a copy of TelegramChatState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? messages = null,Object? isLoading = null,Object? isLoadingMore = null,Object? hasMore = null,Object? error = freezed,}) {
  return _then(_TelegramChatState(
messages: null == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isLoadingMore: null == isLoadingMore ? _self.isLoadingMore : isLoadingMore // ignore: cast_nullable_to_non_nullable
as bool,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$TelegramChatParams {

 int get chatId; int? get messageThreadId;
/// Create a copy of TelegramChatParams
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TelegramChatParamsCopyWith<TelegramChatParams> get copyWith => _$TelegramChatParamsCopyWithImpl<TelegramChatParams>(this as TelegramChatParams, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TelegramChatParams&&(identical(other.chatId, chatId) || other.chatId == chatId)&&(identical(other.messageThreadId, messageThreadId) || other.messageThreadId == messageThreadId));
}


@override
int get hashCode => Object.hash(runtimeType,chatId,messageThreadId);

@override
String toString() {
  return 'TelegramChatParams(chatId: $chatId, messageThreadId: $messageThreadId)';
}


}

/// @nodoc
abstract mixin class $TelegramChatParamsCopyWith<$Res>  {
  factory $TelegramChatParamsCopyWith(TelegramChatParams value, $Res Function(TelegramChatParams) _then) = _$TelegramChatParamsCopyWithImpl;
@useResult
$Res call({
 int chatId, int? messageThreadId
});




}
/// @nodoc
class _$TelegramChatParamsCopyWithImpl<$Res>
    implements $TelegramChatParamsCopyWith<$Res> {
  _$TelegramChatParamsCopyWithImpl(this._self, this._then);

  final TelegramChatParams _self;
  final $Res Function(TelegramChatParams) _then;

/// Create a copy of TelegramChatParams
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? chatId = null,Object? messageThreadId = freezed,}) {
  return _then(_self.copyWith(
chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as int,messageThreadId: freezed == messageThreadId ? _self.messageThreadId : messageThreadId // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [TelegramChatParams].
extension TelegramChatParamsPatterns on TelegramChatParams {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TelegramChatParams value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TelegramChatParams() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TelegramChatParams value)  $default,){
final _that = this;
switch (_that) {
case _TelegramChatParams():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TelegramChatParams value)?  $default,){
final _that = this;
switch (_that) {
case _TelegramChatParams() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int chatId,  int? messageThreadId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TelegramChatParams() when $default != null:
return $default(_that.chatId,_that.messageThreadId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int chatId,  int? messageThreadId)  $default,) {final _that = this;
switch (_that) {
case _TelegramChatParams():
return $default(_that.chatId,_that.messageThreadId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int chatId,  int? messageThreadId)?  $default,) {final _that = this;
switch (_that) {
case _TelegramChatParams() when $default != null:
return $default(_that.chatId,_that.messageThreadId);case _:
  return null;

}
}

}

/// @nodoc


class _TelegramChatParams implements TelegramChatParams {
  const _TelegramChatParams({required this.chatId, this.messageThreadId});
  

@override final  int chatId;
@override final  int? messageThreadId;

/// Create a copy of TelegramChatParams
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TelegramChatParamsCopyWith<_TelegramChatParams> get copyWith => __$TelegramChatParamsCopyWithImpl<_TelegramChatParams>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TelegramChatParams&&(identical(other.chatId, chatId) || other.chatId == chatId)&&(identical(other.messageThreadId, messageThreadId) || other.messageThreadId == messageThreadId));
}


@override
int get hashCode => Object.hash(runtimeType,chatId,messageThreadId);

@override
String toString() {
  return 'TelegramChatParams(chatId: $chatId, messageThreadId: $messageThreadId)';
}


}

/// @nodoc
abstract mixin class _$TelegramChatParamsCopyWith<$Res> implements $TelegramChatParamsCopyWith<$Res> {
  factory _$TelegramChatParamsCopyWith(_TelegramChatParams value, $Res Function(_TelegramChatParams) _then) = __$TelegramChatParamsCopyWithImpl;
@override @useResult
$Res call({
 int chatId, int? messageThreadId
});




}
/// @nodoc
class __$TelegramChatParamsCopyWithImpl<$Res>
    implements _$TelegramChatParamsCopyWith<$Res> {
  __$TelegramChatParamsCopyWithImpl(this._self, this._then);

  final _TelegramChatParams _self;
  final $Res Function(_TelegramChatParams) _then;

/// Create a copy of TelegramChatParams
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? chatId = null,Object? messageThreadId = freezed,}) {
  return _then(_TelegramChatParams(
chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as int,messageThreadId: freezed == messageThreadId ? _self.messageThreadId : messageThreadId // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
