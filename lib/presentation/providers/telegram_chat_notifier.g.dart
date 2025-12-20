// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'telegram_chat_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TelegramChat)
const telegramChatProvider = TelegramChatFamily._();

final class TelegramChatProvider
    extends $NotifierProvider<TelegramChat, TelegramChatState> {
  const TelegramChatProvider._({
    required TelegramChatFamily super.from,
    required TelegramChatParams super.argument,
  }) : super(
         retry: null,
         name: r'telegramChatProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$telegramChatHash();

  @override
  String toString() {
    return r'telegramChatProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TelegramChat create() => TelegramChat();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TelegramChatState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TelegramChatState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TelegramChatProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$telegramChatHash() => r'c864d0672f7d7ae7578c15a54165e8ec3e7edce6';

final class TelegramChatFamily extends $Family
    with
        $ClassFamilyOverride<
          TelegramChat,
          TelegramChatState,
          TelegramChatState,
          TelegramChatState,
          TelegramChatParams
        > {
  const TelegramChatFamily._()
    : super(
        retry: null,
        name: r'telegramChatProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  TelegramChatProvider call(TelegramChatParams params) =>
      TelegramChatProvider._(argument: params, from: this);

  @override
  String toString() => r'telegramChatProvider';
}

abstract class _$TelegramChat extends $Notifier<TelegramChatState> {
  late final _$args = ref.$arg as TelegramChatParams;
  TelegramChatParams get params => _$args;

  TelegramChatState build(TelegramChatParams params);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<TelegramChatState, TelegramChatState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TelegramChatState, TelegramChatState>,
              TelegramChatState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
