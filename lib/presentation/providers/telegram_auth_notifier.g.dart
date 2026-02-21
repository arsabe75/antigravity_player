// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'telegram_auth_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TelegramAuth)
const telegramAuthProvider = TelegramAuthProvider._();

final class TelegramAuthProvider
    extends $NotifierProvider<TelegramAuth, TelegramAuthState> {
  const TelegramAuthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'telegramAuthProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$telegramAuthHash();

  @$internal
  @override
  TelegramAuth create() => TelegramAuth();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TelegramAuthState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TelegramAuthState>(value),
    );
  }
}

String _$telegramAuthHash() => r'56d74236ae06a05ee99bd3765e2555169b6c1ae0';

abstract class _$TelegramAuth extends $Notifier<TelegramAuthState> {
  TelegramAuthState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<TelegramAuthState, TelegramAuthState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TelegramAuthState, TelegramAuthState>,
              TelegramAuthState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
