// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'telegram_forum_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TelegramForum)
const telegramForumProvider = TelegramForumFamily._();

final class TelegramForumProvider
    extends $NotifierProvider<TelegramForum, TelegramForumState> {
  const TelegramForumProvider._({
    required TelegramForumFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'telegramForumProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$telegramForumHash();

  @override
  String toString() {
    return r'telegramForumProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TelegramForum create() => TelegramForum();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TelegramForumState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TelegramForumState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TelegramForumProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$telegramForumHash() => r'8bbb430f24a851628c549f754e9a1430272918d4';

final class TelegramForumFamily extends $Family
    with
        $ClassFamilyOverride<
          TelegramForum,
          TelegramForumState,
          TelegramForumState,
          TelegramForumState,
          int
        > {
  const TelegramForumFamily._()
    : super(
        retry: null,
        name: r'telegramForumProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  TelegramForumProvider call(int chatId) =>
      TelegramForumProvider._(argument: chatId, from: this);

  @override
  String toString() => r'telegramForumProvider';
}

abstract class _$TelegramForum extends $Notifier<TelegramForumState> {
  late final _$args = ref.$arg as int;
  int get chatId => _$args;

  TelegramForumState build(int chatId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<TelegramForumState, TelegramForumState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TelegramForumState, TelegramForumState>,
              TelegramForumState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
