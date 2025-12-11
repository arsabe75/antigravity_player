// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'telegram_chat_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TelegramChatNotifier)
const telegramChatProvider = TelegramChatNotifierFamily._();

final class TelegramChatNotifierProvider
    extends $NotifierProvider<TelegramChatNotifier, TelegramChatState> {
  const TelegramChatNotifierProvider._({
    required TelegramChatNotifierFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'telegramChatProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$telegramChatNotifierHash();

  @override
  String toString() {
    return r'telegramChatProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TelegramChatNotifier create() => TelegramChatNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TelegramChatState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TelegramChatState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TelegramChatNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$telegramChatNotifierHash() =>
    r'bc5875629407f439632401690420192b96185c13';

final class TelegramChatNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          TelegramChatNotifier,
          TelegramChatState,
          TelegramChatState,
          TelegramChatState,
          int
        > {
  const TelegramChatNotifierFamily._()
    : super(
        retry: null,
        name: r'telegramChatProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TelegramChatNotifierProvider call(int chatId) =>
      TelegramChatNotifierProvider._(argument: chatId, from: this);

  @override
  String toString() => r'telegramChatProvider';
}

abstract class _$TelegramChatNotifier extends $Notifier<TelegramChatState> {
  late final _$args = ref.$arg as int;
  int get chatId => _$args;

  TelegramChatState build(int chatId);
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
