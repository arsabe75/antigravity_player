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

String _$telegramAuthHash() => r'8b1d3bcf77e7726a03ec2e0265efb6bd051e37c6';

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
