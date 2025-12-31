// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'routes.dart';

// **************************************************************************
// GoRouterGenerator
// **************************************************************************

List<RouteBase> get $appRoutes => [
  $homeRoute,
  $playerRoute,
  $telegramRoute,
  $telegramSelectionRoute,
  $telegramStorageRoute,
  $telegramTopicsRoute,
  $telegramChatRoute,
];

RouteBase get $homeRoute =>
    GoRouteData.$route(path: '/', factory: $HomeRoute._fromState);

mixin $HomeRoute on GoRouteData {
  static HomeRoute _fromState(GoRouterState state) => const HomeRoute();

  @override
  String get location => GoRouteData.$location('/');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $playerRoute =>
    GoRouteData.$route(path: '/player', factory: $PlayerRoute._fromState);

mixin $PlayerRoute on GoRouteData {
  static PlayerRoute _fromState(GoRouterState state) =>
      PlayerRoute($extra: state.extra as PlayerRouteExtra?);

  PlayerRoute get _self => this as PlayerRoute;

  @override
  String get location => GoRouteData.$location('/player');

  @override
  void go(BuildContext context) => context.go(location, extra: _self.$extra);

  @override
  Future<T?> push<T>(BuildContext context) =>
      context.push<T>(location, extra: _self.$extra);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location, extra: _self.$extra);

  @override
  void replace(BuildContext context) =>
      context.replace(location, extra: _self.$extra);
}

RouteBase get $telegramRoute =>
    GoRouteData.$route(path: '/telegram', factory: $TelegramRoute._fromState);

mixin $TelegramRoute on GoRouteData {
  static TelegramRoute _fromState(GoRouterState state) => const TelegramRoute();

  @override
  String get location => GoRouteData.$location('/telegram');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $telegramSelectionRoute => GoRouteData.$route(
  path: '/telegram/selection',
  factory: $TelegramSelectionRoute._fromState,
);

mixin $TelegramSelectionRoute on GoRouteData {
  static TelegramSelectionRoute _fromState(GoRouterState state) =>
      const TelegramSelectionRoute();

  @override
  String get location => GoRouteData.$location('/telegram/selection');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $telegramStorageRoute => GoRouteData.$route(
  path: '/telegram/storage',
  factory: $TelegramStorageRoute._fromState,
);

mixin $TelegramStorageRoute on GoRouteData {
  static TelegramStorageRoute _fromState(GoRouterState state) =>
      const TelegramStorageRoute();

  @override
  String get location => GoRouteData.$location('/telegram/storage');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $telegramTopicsRoute => GoRouteData.$route(
  path: '/telegram/topics/:chatId',
  factory: $TelegramTopicsRoute._fromState,
);

mixin $TelegramTopicsRoute on GoRouteData {
  static TelegramTopicsRoute _fromState(GoRouterState state) =>
      TelegramTopicsRoute(
        chatId: int.parse(state.pathParameters['chatId']!),
        title: state.uri.queryParameters['title'],
      );

  TelegramTopicsRoute get _self => this as TelegramTopicsRoute;

  @override
  String get location => GoRouteData.$location(
    '/telegram/topics/${Uri.encodeComponent(_self.chatId.toString())}',
    queryParams: {if (_self.title != null) 'title': _self.title},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $telegramChatRoute => GoRouteData.$route(
  path: '/telegram/chat/:chatId',
  factory: $TelegramChatRoute._fromState,
);

mixin $TelegramChatRoute on GoRouteData {
  static TelegramChatRoute _fromState(GoRouterState state) => TelegramChatRoute(
    chatId: int.parse(state.pathParameters['chatId']!),
    title: state.uri.queryParameters['title'],
    messageThreadId: _$convertMapValue(
      'message-thread-id',
      state.uri.queryParameters,
      int.tryParse,
    ),
  );

  TelegramChatRoute get _self => this as TelegramChatRoute;

  @override
  String get location => GoRouteData.$location(
    '/telegram/chat/${Uri.encodeComponent(_self.chatId.toString())}',
    queryParams: {
      if (_self.title != null) 'title': _self.title,
      if (_self.messageThreadId != null)
        'message-thread-id': _self.messageThreadId!.toString(),
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

T? _$convertMapValue<T>(
  String key,
  Map<String, String> map,
  T? Function(String) converter,
) {
  final value = map[key];
  return value == null ? null : converter(value);
}
