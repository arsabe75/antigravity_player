// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'telegram_file_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TelegramFile)
const telegramFileProvider = TelegramFileFamily._();

final class TelegramFileProvider
    extends $NotifierProvider<TelegramFile, TelegramFileState> {
  const TelegramFileProvider._({
    required TelegramFileFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'telegramFileProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$telegramFileHash();

  @override
  String toString() {
    return r'telegramFileProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TelegramFile create() => TelegramFile();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TelegramFileState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TelegramFileState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TelegramFileProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$telegramFileHash() => r'b0c12d826045f30b7fd09dc8c94c6a3dc1a9f162';

final class TelegramFileFamily extends $Family
    with
        $ClassFamilyOverride<
          TelegramFile,
          TelegramFileState,
          TelegramFileState,
          TelegramFileState,
          int
        > {
  const TelegramFileFamily._()
    : super(
        retry: null,
        name: r'telegramFileProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  TelegramFileProvider call(int fileId) =>
      TelegramFileProvider._(argument: fileId, from: this);

  @override
  String toString() => r'telegramFileProvider';
}

abstract class _$TelegramFile extends $Notifier<TelegramFileState> {
  late final _$args = ref.$arg as int;
  int get fileId => _$args;

  TelegramFileState build(int fileId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<TelegramFileState, TelegramFileState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TelegramFileState, TelegramFileState>,
              TelegramFileState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
