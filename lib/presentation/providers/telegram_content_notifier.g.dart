// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'telegram_content_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TelegramContent)
const telegramContentProvider = TelegramContentProvider._();

final class TelegramContentProvider
    extends $NotifierProvider<TelegramContent, TelegramContentState> {
  const TelegramContentProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'telegramContentProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$telegramContentHash();

  @$internal
  @override
  TelegramContent create() => TelegramContent();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TelegramContentState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TelegramContentState>(value),
    );
  }
}

String _$telegramContentHash() => r'63570e40d52d280f106efb531e76abad15cf2656';

abstract class _$TelegramContent extends $Notifier<TelegramContentState> {
  TelegramContentState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<TelegramContentState, TelegramContentState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TelegramContentState, TelegramContentState>,
              TelegramContentState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
