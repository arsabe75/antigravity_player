// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'telegram_cache_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TelegramCacheNotifier)
const telegramCacheProvider = TelegramCacheNotifierProvider._();

final class TelegramCacheNotifierProvider
    extends $NotifierProvider<TelegramCacheNotifier, TelegramCacheState> {
  const TelegramCacheNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'telegramCacheProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$telegramCacheNotifierHash();

  @$internal
  @override
  TelegramCacheNotifier create() => TelegramCacheNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TelegramCacheState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TelegramCacheState>(value),
    );
  }
}

String _$telegramCacheNotifierHash() =>
    r'e824714b59e4ec8ec09d4c47d6a3648f75499a8d';

abstract class _$TelegramCacheNotifier extends $Notifier<TelegramCacheState> {
  TelegramCacheState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<TelegramCacheState, TelegramCacheState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TelegramCacheState, TelegramCacheState>,
              TelegramCacheState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
